import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:ridex/core/models/canonical_trip_reconciliation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/supabase_driver_cash_completion_composition.dart';
import 'package:ridex/core/repositories/supabase_driver_completion_source.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/features/trips/application/driver_completion_recovery_coordinator.dart';

enum DriverCashRecoveryState {
  noPendingRecovery,
  checkingCanonicalTrip,
  completionVerifiedReceiptVerified,
  completionVerifiedReceiptUnverified,
  completionNotVisible,
  additionalPendingRecovery,
  outcomeUnknown,
  authorizationRevoked,
  journalCorruptedOrUnavailable,
  networkReadFailure,
}

final class DriverCashRecoveryController extends ChangeNotifier
    with WidgetsBindingObserver {
  DriverCashRecoveryController({
    required this.source,
    required this.authority,
    required this.repository,
    required this.openJournal,
  }) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(reconcile());
  }

  final SupabaseDriverCompletionSource source;
  final SupabaseDriverAuthorityBinding authority;
  final SupabaseDriverCashCompletionComposition repository;
  final Future<DriverCompletionCommandStore> Function() openJournal;
  final Map<String, CanonicalTripEvidence> _strongest = {};
  static const maxCommandsPerRun = 10;
  int _nextCommandOffset = 0;
  DriverCashRecoveryState _state =
      DriverCashRecoveryState.checkingCanonicalTrip;
  Future<void>? _running;
  bool _disposed = false;
  int _generation = 0;
  DriverCashRecoveryState? _strongestState;

  DriverCashRecoveryState get state =>
      source.isCurrent ? _state : DriverCashRecoveryState.authorizationRevoked;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(reconcile());
  }

  Future<void> reconcile() {
    if (_disposed) return Future<void>.value();
    return _running ??= _run(++_generation).whenComplete(() => _running = null);
  }

  Future<void> _run(int generation) async {
    _publish(generation, DriverCashRecoveryState.checkingCanonicalTrip);
    try {
      await source.readSession();
      if (!_owns(generation)) return;
      final owner = authority.currentOwner;
      final journal = await openJournal();
      if (!_owns(generation)) return;
      final snapshot = await journal.inspectDriver(
        backendNamespace: owner.backend.namespace,
        driverId: owner.driverId!,
      );
      if (!_owns(generation)) return;
      switch (snapshot) {
        case CompletionDriverUnavailable():
          _publish(
            generation,
            DriverCashRecoveryState.journalCorruptedOrUnavailable,
          );
          return;
        case CompletionDriverCommands(commands: final commands):
          if (commands.isEmpty) {
            _publish(generation, DriverCashRecoveryState.noPendingRecovery);
            return;
          }
          var result = DriverCashRecoveryState.completionNotVisible;
          final count = commands.length < maxCommandsPerRun
              ? commands.length
              : maxCommandsPerRun;
          final start = _nextCommandOffset % commands.length;
          for (var index = 0; index < count; index++) {
            final command = commands[(start + index) % commands.length];
            if (!_owns(generation)) return;
            final readOwner = CanonicalTripReadSession(
              driverId: owner.driverId,
              backendNamespace: owner.backend.namespace,
              epoch: owner.epoch,
              isApprovedDriver: true,
            );
            final coordinator = DriverCompletionRecoveryCoordinator(
              tripId: command.tripId,
              owner: readOwner,
              journal: journal,
              repository: repository,
              sessionReader: () => _readOwner(),
            );
            final outcome = await coordinator.recover();
            coordinator.dispose();
            await source.readSession();
            if (!_owns(generation)) return;
            switch (outcome.disposition) {
              case DriverReadOnlyRecoveryDisposition.completedTrip:
                final trip = outcome.observedTrip;
                if (trip == null || !_retainStrongest(trip)) {
                  result = DriverCashRecoveryState.outcomeUnknown;
                  continue;
                }
                // Revalidate eligibility after the canonical read, before the
                // receipt call and again after its response.
                await source.readSession();
                if (!_owns(generation)) return;
                final receipt = await repository.readReceipt(
                  tripId: command.tripId,
                  capturedDriverId: owner.driverId!,
                  capturedBackendNamespace: owner.backend.namespace,
                );
                await source.readSession();
                if (!_owns(generation)) return;
                if (receipt.status == DriverReceiptReadStatus.unauthorized) {
                  _publish(
                    generation,
                    DriverCashRecoveryState.authorizationRevoked,
                  );
                  return;
                }
                result = receipt.status == DriverReceiptReadStatus.verified
                    ? DriverCashRecoveryState.completionVerifiedReceiptVerified
                    : DriverCashRecoveryState
                        .completionVerifiedReceiptUnverified;
              case DriverReadOnlyRecoveryDisposition.notVisible:
              case DriverReadOnlyRecoveryDisposition.terminalNonCompletedTrip:
              case DriverReadOnlyRecoveryDisposition.nonterminalTrip:
                result = DriverCashRecoveryState.completionNotVisible;
              case DriverReadOnlyRecoveryDisposition.journalBlocked:
              case DriverReadOnlyRecoveryDisposition.conflictingEvidence:
                result = DriverCashRecoveryState.journalCorruptedOrUnavailable;
              case DriverReadOnlyRecoveryDisposition.readFailed:
                result = DriverCashRecoveryState.networkReadFailure;
              case DriverReadOnlyRecoveryDisposition.invalidated:
                _publish(
                  generation,
                  DriverCashRecoveryState.authorizationRevoked,
                );
                return;
              case DriverReadOnlyRecoveryDisposition.noJournalEvidence:
                result = DriverCashRecoveryState.outcomeUnknown;
            }
          }
          _nextCommandOffset = (start + count) % commands.length;
          if (commands.length > count) {
            result = DriverCashRecoveryState.additionalPendingRecovery;
          }
          _publish(generation, result);
      }
    } on DriverCashContextException catch (error) {
      _publish(
        generation,
        error.failure == DriverCashContextFailure.unavailable
            ? DriverCashRecoveryState.networkReadFailure
            : DriverCashRecoveryState.authorizationRevoked,
      );
    } on Object {
      _publish(
        generation,
        source.isCurrent
            ? DriverCashRecoveryState.networkReadFailure
            : DriverCashRecoveryState.authorizationRevoked,
      );
    }
  }

  CanonicalTripReadSession _readOwner() {
    final owner = authority.currentOwner;
    return CanonicalTripReadSession(
      driverId: owner.driverId,
      backendNamespace: owner.backend.namespace,
      epoch: owner.epoch,
      isApprovedDriver: source.isCurrent,
    );
  }

  bool _retainStrongest(CanonicalTripEvidence next) {
    final key = next.tripId.toLowerCase();
    final previous = _strongest[key];
    if (previous != null &&
        (next.backendVersion < previous.backendVersion ||
            (previous.status == DriverTripLifecycleStatus.completed &&
                next.status != DriverTripLifecycleStatus.completed) ||
            (next.backendVersion == previous.backendVersion &&
                next.status != previous.status))) {
      return false;
    }
    _strongest[key] = next;
    return true;
  }

  bool _owns(int generation) =>
      !_disposed && generation == _generation && source.isCurrent;

  void _publish(int generation, DriverCashRecoveryState value) {
    if (!_owns(generation)) return;
    if (value != DriverCashRecoveryState.authorizationRevoked &&
        value != DriverCashRecoveryState.checkingCanonicalTrip) {
      final previous = _strongestState;
      if (previous != null && _rank(value) < _rank(previous)) value = previous;
      if (_strongestState == null || _rank(value) >= _rank(_strongestState!)) {
        _strongestState = value;
      }
    }
    if (value == DriverCashRecoveryState.authorizationRevoked) {
      _strongestState = value;
    }
    _state = value;
    notifyListeners();
  }

  int _rank(DriverCashRecoveryState state) => switch (state) {
        DriverCashRecoveryState.noPendingRecovery => 0,
        DriverCashRecoveryState.checkingCanonicalTrip => 0,
        DriverCashRecoveryState.completionNotVisible => 1,
        DriverCashRecoveryState.additionalPendingRecovery => 4,
        DriverCashRecoveryState.networkReadFailure => 2,
        DriverCashRecoveryState.journalCorruptedOrUnavailable => 3,
        DriverCashRecoveryState.outcomeUnknown => 4,
        DriverCashRecoveryState.completionVerifiedReceiptUnverified => 5,
        DriverCashRecoveryState.completionVerifiedReceiptVerified => 6,
        DriverCashRecoveryState.authorizationRevoked => 7,
      };

  void observeAuthority() {
    if (!source.isCurrent) {
      _generation++;
      _publish(_generation, DriverCashRecoveryState.authorizationRevoked);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
