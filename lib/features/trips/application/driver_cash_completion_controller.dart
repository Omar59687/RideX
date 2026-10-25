import 'package:flutter/foundation.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';

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
      required this.prepareContext,
      required this.isCurrent,
      required this.failureState,
      required this.release});
  final DriverCompletionCoordinator coordinator;
  final Future<bool> Function() prepareContext;
  final bool Function() isCurrent;
  final DriverCashCompletionState Function() failureState;
  final VoidCallback release;
  DriverCashCompletionState _state = DriverCashCompletionState.unavailable;
  bool _disposed = false;
  Future<void>? _pending;
  bool _attempted = false;
  bool _preparing = false;

  DriverCashCompletionState get state =>
      isCurrent() ? _state : DriverCashCompletionState.authorizationLost;

  void _publish(DriverCashCompletionState value) {
    if (_disposed) return;
    _state = isCurrent() ? value : DriverCashCompletionState.authorizationLost;
    notifyListeners();
  }

  Future<void> prepare() async {
    if (_disposed || _attempted || _pending != null || _preparing) return;
    _preparing = true;
    _publish(DriverCashCompletionState.processing);
    try {
      _publish(await prepareContext()
          ? DriverCashCompletionState.ready
          : DriverCashCompletionState.unavailable);
    } on Object {
      _publish(failureState());
    } finally {
      _preparing = false;
    }
  }

  Future<void> complete() {
    if (_disposed || _attempted || state != DriverCashCompletionState.ready) {
      return _pending ?? Future<void>.value();
    }
    _attempted = true;
    return _pending = _complete();
  }

  Future<void> _complete() async {
    _publish(DriverCashCompletionState.processing);
    final outcome = await coordinator.complete();
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
  }

  void observeAuthority() {
    if (!_disposed && !isCurrent()) {
      coordinator.invalidate();
      _publish(DriverCashCompletionState.authorizationLost);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    coordinator.dispose();
    release();
    super.dispose();
  }
}
