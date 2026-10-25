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
  final Set<String> _verifiedReceipts = {};
  final Map<String, DriverCompleteTripCommand> _commands = {};
  final Map<String, DriverCashRecoveryState> _outcomes = {};
  static const maxCommandsPerRun = 10;
  int _nextCommandOffset = 0;
  DriverCashRecoveryState _state =
      DriverCashRecoveryState.checkingCanonicalTrip;
  Future<void>? _running;
  bool _disposed = false;
  int _generation = 0;

  DriverCashRecoveryState get state =>
      source.isCurrent ? _state : DriverCashRecoveryState.authorizationRevoked;

  // Retained canonical facts are distinct from the latest reconciliation result.
  // Neither a later failed read nor a different Trip can replace these facts.
  Map<String, CanonicalTripEvidence> get canonicalEvidence =>
      !_disposed && source.isCurrent ? Map.unmodifiable(_strongest) : const {};
  Set<String> get receiptVerifiedTrips => !_disposed && source.isCurrent
      ? Set.unmodifiable(_verifiedReceipts)
      : const {};

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
            _publish(
                generation,
                _commands.isEmpty
                    ? DriverCashRecoveryState.noPendingRecovery
                    : DriverCashRecoveryState.outcomeUnknown);
            return;
          }
          final visible = <String>{};
          for (final command in commands) {
            final key = command.tripId.toLowerCase();
            final previous = _commands[key];
            if (previous != null && previous != command) {
              _publish(generation,
                  DriverCashRecoveryState.journalCorruptedOrUnavailable);
              return;
            }
            _commands[key] = command;
            visible.add(key);
          }
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
            final key = command.tripId.toLowerCase();
            final observed = outcome.observedTrip;
            if (observed != null && !_retainStrongest(observed)) {
              _outcomes[key] = DriverCashRecoveryState.outcomeUnknown;
              continue;
            }
            switch (outcome.disposition) {
              case DriverReadOnlyRecoveryDisposition.completedTrip:
                final trip = outcome.observedTrip;
                if (trip == null) {
                  _outcomes[key] = DriverCashRecoveryState.outcomeUnknown;
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
                if (receipt.status == DriverReceiptReadStatus.verified) {
                  _verifiedReceipts.add(key);
                }
                _outcomes[key] = receipt.status ==
                        DriverReceiptReadStatus.verified
                    ? DriverCashRecoveryState.completionVerifiedReceiptVerified
                    : DriverCashRecoveryState
                        .completionVerifiedReceiptUnverified;
              case DriverReadOnlyRecoveryDisposition.notVisible:
              case DriverReadOnlyRecoveryDisposition.terminalNonCompletedTrip:
              case DriverReadOnlyRecoveryDisposition.nonterminalTrip:
                _outcomes[key] = DriverCashRecoveryState.completionNotVisible;
              case DriverReadOnlyRecoveryDisposition.journalBlocked:
              case DriverReadOnlyRecoveryDisposition.conflictingEvidence:
                _outcomes[key] =
                    DriverCashRecoveryState.journalCorruptedOrUnavailable;
              case DriverReadOnlyRecoveryDisposition.readFailed:
                _outcomes[key] = DriverCashRecoveryState.networkReadFailure;
              case DriverReadOnlyRecoveryDisposition.invalidated:
                _publish(
                  generation,
                  DriverCashRecoveryState.authorizationRevoked,
                );
                return;
              case DriverReadOnlyRecoveryDisposition.noJournalEvidence:
                _outcomes[key] = DriverCashRecoveryState.outcomeUnknown;
            }
          }
          _nextCommandOffset = (start + count) % commands.length;
          _publish(generation, _aggregate(visible));
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
    _state = value;
    notifyListeners();
  }

  DriverCashRecoveryState _aggregate(Set<String> visible) {
    // A missing previously discovered command is not evidence of retirement.
    if (_commands.keys.any((key) => !visible.contains(key))) {
      return DriverCashRecoveryState.outcomeUnknown;
    }
    final outcomes = visible.map((key) => _outcomes[key]).toSet();
    for (final unresolved in [
      DriverCashRecoveryState.journalCorruptedOrUnavailable,
      DriverCashRecoveryState.networkReadFailure,
      DriverCashRecoveryState.outcomeUnknown,
    ]) {
      if (outcomes.contains(unresolved)) return unresolved;
    }
    if (outcomes.contains(null)) {
      return DriverCashRecoveryState.additionalPendingRecovery;
    }
    if (outcomes.contains(DriverCashRecoveryState.completionNotVisible)) {
      return DriverCashRecoveryState.completionNotVisible;
    }
    if (outcomes.contains(
        DriverCashRecoveryState.completionVerifiedReceiptUnverified)) {
      return DriverCashRecoveryState.completionVerifiedReceiptUnverified;
    }
    return DriverCashRecoveryState.completionVerifiedReceiptVerified;
  }

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
