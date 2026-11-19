import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ridex/features/driver_flow/application/driver_completion_interaction.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'package:ridex/features/trips/application/driver_cash_recovery_controller.dart';

enum DriverCashCompletionState {
  unavailable,
  ready,
  processing,
  completedReceiptVerified,
  completedReceiptUnverified,
  unresolved,
  authorizationLost,
  storageFailure,
  networkFailure,
}

/// Presentation owner only; SDK identity/epochs remain application-owned.
/// No automatic load, dispatch, recovery, retry or journal cleanup.
final class DriverCashCompletionController extends ChangeNotifier {
  DriverCashCompletionController(
      {required this.coordinator,
      required this.recovery,
      required this.prepareContext,
      required this.isCurrent,
      required this.failureState,
      required this.release});
  final DriverCompletionCoordinator coordinator;
  final DriverCashRecoveryController recovery;
  final Future<bool> Function() prepareContext;
  final bool Function() isCurrent;
  final DriverCashCompletionState Function() failureState;
  final VoidCallback release;
  DriverCashCompletionState _state = DriverCashCompletionState.unavailable;
  bool _disposed = false;
  Future<void>? _pending;
  bool _attempted = false;
  bool _preparing = false;
  bool _interactionRetired = false;
  DriverCompletionInteraction? _interaction;

  /// Bind exactly once before preparation. Shared providers remain unchanged;
  /// only reviewed Driver-owned composition supplies this default-off gate.
  void bindInteraction(DriverCompletionInteraction interaction) {
    if (_disposed ||
        _interactionRetired ||
        _interaction != null ||
        _attempted ||
        _preparing ||
        _pending != null) {
      return;
    }
    _interaction = interaction;
    interaction.addListener(observeInteraction);
  }

  bool get canComplete =>
      !_disposed &&
      !_interactionRetired &&
      !_attempted &&
      _interaction?.isCurrent == true &&
      state == DriverCashCompletionState.ready;

  void observeInteraction() {
    if (_disposed) return;
    if (_interaction?.isCurrent != true) invalidateInteraction();
  }

  /// Loss of connectivity/navigation/config never revives an armed owner.
  /// Durable evidence remains untouched; a new route may only recover it.
  void invalidateInteraction({bool deferNotification = false}) {
    if (_disposed || _interactionRetired) return;
    _interactionRetired = true;
    coordinator.invalidate();
    if (deferNotification) {
      // Revoke synchronously even during route build, but Riverpod listeners
      // must not be notified until the current widget build is finished.
      _state = DriverCashCompletionState.networkFailure;
      scheduleMicrotask(
          () => _publish(DriverCashCompletionState.networkFailure));
    } else {
      _publish(DriverCashCompletionState.networkFailure);
    }
  }

  DriverCashCompletionState get state =>
      isCurrent() ? _state : DriverCashCompletionState.authorizationLost;

  void _publish(DriverCashCompletionState value) {
    if (_disposed) return;
    _state = isCurrent() ? value : DriverCashCompletionState.authorizationLost;
    notifyListeners();
  }

  Future<void> prepare() async {
    if (_disposed || _attempted || _pending != null || _preparing) return;
    final interaction = _interaction;
    if (_interactionRetired || interaction?.isCurrent != true) return;
    _preparing = true;
    _publish(DriverCashCompletionState.processing);
    try {
      final prepared = await prepareContext();
      final verified = prepared &&
          !_disposed &&
          !_interactionRetired &&
          await interaction!.verify();
      _publish(verified && !_interactionRetired && interaction.isCurrent
          ? DriverCashCompletionState.ready
          : DriverCashCompletionState.unavailable);
    } on Object {
      _publish(failureState());
    } finally {
      _preparing = false;
    }
  }

  Future<void> complete() {
    if (!canComplete) {
      return _pending ?? Future<void>.value();
    }
    _attempted = true;
    return _pending = _complete();
  }

  Future<void> _complete() async {
    _publish(DriverCashCompletionState.processing);
    final interaction = _interaction!;
    try {
      if (!await interaction.verify() ||
          _disposed ||
          _interactionRetired ||
          !interaction.isCurrent) {
        _publish(DriverCashCompletionState.unresolved);
        return;
      }
      final outcome = await coordinator.complete(
        beforeDispatch: (context) =>
            interaction.verify(expected: context.command),
      );
      final command = switch (outcome) {
        CoordinatorCompleted(:final stagedCommand) => stagedCommand,
        CoordinatorUnresolved(:final stagedCommand, :final attempt)
            when attempt?.confirmedTrip?.isCompleted == true =>
          stagedCommand,
        _ => null,
      };
      if (command != null &&
          (!await interaction.confirmCompleted(command) ||
              _disposed ||
              _interactionRetired ||
              !interaction.isCurrent)) {
        _publish(DriverCashCompletionState.unresolved);
        return;
      }
      _publish(switch (outcome) {
        CoordinatorCompleted(:final result) => result.receiptVerified
            ? DriverCashCompletionState.completedReceiptVerified
            : DriverCashCompletionState.completedReceiptUnverified,
        CoordinatorBlocked() => DriverCashCompletionState.storageFailure,
        CoordinatorInvalidated() => failureState(),
        CoordinatorSessionInvalid() => failureState(),
        CoordinatorUnresolved(:final attempt)
            when attempt?.confirmedTrip?.isCompleted == true =>
          DriverCashCompletionState.completedReceiptUnverified,
        CoordinatorNoContext() => DriverCashCompletionState.unavailable,
        _ => DriverCashCompletionState.unresolved,
      });
    } on Object {
      _publish(DriverCashCompletionState.unresolved);
    }
  }

  void observeAuthority() {
    if (!_disposed && !isCurrent()) {
      coordinator.invalidate();
      recovery.observeAuthority();
      _publish(DriverCashCompletionState.authorizationLost);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _interaction?.removeListener(observeInteraction);
    coordinator.dispose();
    recovery.dispose();
    release();
    super.dispose();
  }
}
