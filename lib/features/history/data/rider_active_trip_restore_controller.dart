import 'package:ridex/features/history/data/rider_active_trip_restoration.dart';

enum RiderActiveRestoreStage {
  idle,
  loading,
  noActiveTrip,
  restored,
  unavailable,
}

/// One session-scoped UI state. Never stores a Trip after invalidation.
final class RiderActiveRestoreState {
  const RiderActiveRestoreState(this.stage, {this.snapshot});
  final RiderActiveRestoreStage stage;
  final RiderActiveTripSnapshot? snapshot;

  static const idle = RiderActiveRestoreState(RiderActiveRestoreStage.idle);
  static const loading = RiderActiveRestoreState(RiderActiveRestoreStage.loading);
  static const unavailable =
      RiderActiveRestoreState(RiderActiveRestoreStage.unavailable);
  static const empty =
      RiderActiveRestoreState(RiderActiveRestoreStage.noActiveTrip);
}

/// Feature-local coordinator; Omar may inject this into app routing later.
/// No navigation, persistence or speculative trip selection occurs here.
final class RiderActiveTripRestoreController {
  RiderActiveTripRestoreController(this.restorer);

  final RiderActiveTripRestorer restorer;
  int _generation = 0;
  bool _disposed = false;
  RiderActiveRestoreState _state = RiderActiveRestoreState.idle;

  RiderActiveRestoreState get state => _state;

  /// Invoked on logout, role change, SDK session/epoch replacement, blocked
  /// profile, or changing the active Rider. Invalidate *before* any UI action.
  void invalidate() {
    _generation++;
    _state = RiderActiveRestoreState.idle;
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }

  /// Starts a new read on first login, restart, resume or reconnect.
  /// Old completions from an overlapping attempt cannot publish.
  Future<RiderActiveRestoreState> refresh(String riderId) async {
    if (_disposed) return RiderActiveRestoreState.idle;
    final generation = ++_generation;
    _state = RiderActiveRestoreState.loading;
    try {
      final result = await restorer.restore(riderId);
      if (_disposed || generation != _generation) return _state;
      _state = result == null
          ? RiderActiveRestoreState.empty
          : RiderActiveRestoreState(
              RiderActiveRestoreStage.restored,
              snapshot: result,
            );
    } on RiderActiveRestoreException {
      if (_disposed || generation != _generation) return _state;
      _state = RiderActiveRestoreState.unavailable;
    } on Object {
      if (_disposed || generation != _generation) return _state;
      _state = RiderActiveRestoreState.unavailable;
    }
    return _state;
  }
}
