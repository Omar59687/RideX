import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/services/driver_location/driver_gps_stream_service.dart';
import 'package:ridex/core/services/driver_location/geolocator_driver_gps_stream_service.dart';
import 'package:ridex/core/providers/repositories_providers.dart';

enum DriverTrackingStatus {
  stopped,
  starting,
  sharing,
  unavailable,
}

enum DriverTrackingLifecycleState { foreground, background }

abstract interface class DriverTrackingLifecycle {
  Stream<DriverTrackingLifecycleState> get changes;

  void dispose();
}

class WidgetsDriverTrackingLifecycle
    with WidgetsBindingObserver
    implements DriverTrackingLifecycle {
  WidgetsDriverTrackingLifecycle() {
    WidgetsBinding.instance.addObserver(this);
  }

  final _changes = StreamController<DriverTrackingLifecycleState>.broadcast();

  @override
  Stream<DriverTrackingLifecycleState> get changes => _changes.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _changes.add(
      state == AppLifecycleState.resumed
          ? DriverTrackingLifecycleState.foreground
          : DriverTrackingLifecycleState.background,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes.close();
  }
}

class DriverTrackingState extends Equatable {
  const DriverTrackingState({
    required this.status,
    this.failure,
    this.nextSequence,
  });

  const DriverTrackingState.initial()
      : status = DriverTrackingStatus.stopped,
        failure = null,
        nextSequence = null;

  final DriverTrackingStatus status;
  final DriverLocationFailure? failure;
  final int? nextSequence;

  @override
  List<Object?> get props => [status, failure, nextSequence];
}

final driverGpsStreamServiceProvider = Provider<DriverGpsStreamService>(
  (ref) => GeolocatorDriverGpsStreamService(),
);

final driverTrackingLifecycleProvider = Provider<DriverTrackingLifecycle>(
  (ref) {
    final lifecycle = WidgetsDriverTrackingLifecycle();
    ref.onDispose(lifecycle.dispose);
    return lifecycle;
  },
);

final driverTrackingControllerProvider =
    NotifierProvider.autoDispose<DriverTrackingController, DriverTrackingState>(
  DriverTrackingController.new,
);

class DriverTrackingController
    extends AutoDisposeNotifier<DriverTrackingState> {
  StreamSubscription<DriverLocationFix>? _subscription;
  StreamSubscription<DriverTrackingLifecycleState>? _lifecycleSubscription;
  Future<void> _publishQueue = Future<void>.value();
  Future<void> _lifecycleQueue = Future<void>.value();
  DateTime? _latestRecordedAt;
  String? _activeTripId;
  int _nextSequence = 1;
  bool _startInProgress = false;
  bool _recoveryInProgress = false;
  bool _trackingRequested = false;
  bool _backgrounded = false;
  int _generation = 0;
  bool _disposed = false;

  @override
  DriverTrackingState build() {
    _lifecycleSubscription = ref
        .read(driverTrackingLifecycleProvider)
        .changes
        .listen(_handleLifecycleChange);
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _subscription?.cancel();
      _subscription = null;
      _lifecycleSubscription?.cancel();
      _lifecycleSubscription = null;
    });
    return const DriverTrackingState.initial();
  }

  Future<void> start() async {
    _trackingRequested = true;
    if (_backgrounded) return;
    await _startSession();
  }

  Future<void> _startSession() async {
    if (_backgrounded || _startInProgress || _subscription != null) return;

    final generation = ++_generation;
    _startInProgress = true;
    state = const DriverTrackingState(status: DriverTrackingStatus.starting);
    try {
      final repository = ref.read(driverLocationRepositoryProvider);
      final availability = await repository.fetchAvailability();
      if (!_isCurrent(generation)) return;
      if (availability == null || !availability.canShareLocation) {
        _setUnavailable(DriverLocationFailure.ineligible);
        return;
      }

      final latest = await repository.fetchLatestLocation();
      if (!_isCurrent(generation)) return;
      _latestRecordedAt = latest?.recordedAt;
      _activeTripId = availability.state == DriverAvailabilityState.onTrip
          ? availability.activeTripId
          : null;
      _nextSequence = (latest?.sequence ?? 0) + 1;
      state = DriverTrackingState(
        status: DriverTrackingStatus.sharing,
        nextSequence: _nextSequence,
      );
      final subscription =
          ref.read(driverGpsStreamServiceProvider).foregroundFixes().listen(
                (fix) => _handleFix(fix, generation),
                onError: (error, stackTrace) =>
                    _handleStreamError(error, stackTrace, generation),
              );
      if (!_isCurrent(generation)) {
        await subscription.cancel();
      } else {
        _subscription = subscription;
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        _setUnavailable(_failureFromError(error));
      }
    } finally {
      if (_generation == generation) _startInProgress = false;
    }
  }

  Future<void> stop() async {
    _trackingRequested = false;
    await _stopSession();
  }

  Future<void> _stopSession() async {
    _generation++;
    _startInProgress = false;
    _activeTripId = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    if (!_disposed) {
      state = const DriverTrackingState(status: DriverTrackingStatus.stopped);
    }
  }

  Future<void> stopForSignOut() => stop();

  Future<void> recoverAfterConnectivity() async {
    if (!_trackingRequested ||
        _backgrounded ||
        _disposed ||
        _recoveryInProgress ||
        _startInProgress) {
      return;
    }
    _recoveryInProgress = true;
    try {
      await _stopSession();
      if (_trackingRequested && !_backgrounded && !_disposed) {
        await _startSession();
      }
    } finally {
      _recoveryInProgress = false;
    }
  }

  void _handleLifecycleChange(DriverTrackingLifecycleState lifecycleState) {
    _lifecycleQueue = _lifecycleQueue.then((_) async {
      if (lifecycleState == DriverTrackingLifecycleState.background) {
        _backgrounded = true;
        if (_trackingRequested) await _stopSession();
      } else if (_trackingRequested) {
        _backgrounded = false;
        await _startSession();
      } else {
        _backgrounded = false;
      }
    });
  }

  void _handleFix(DriverLocationFix fix, int generation) {
    if (!_isCurrent(generation) ||
        state.status != DriverTrackingStatus.sharing ||
        fix.point.accuracyMeters == null ||
        (_latestRecordedAt != null &&
            fix.recordedAt.isBefore(_latestRecordedAt!))) {
      return;
    }

    final sequence = _nextSequence++;
    _latestRecordedAt = fix.recordedAt;
    state = DriverTrackingState(
      status: DriverTrackingStatus.sharing,
      nextSequence: _nextSequence,
    );
    _publishQueue = _publishQueue.then((_) async {
      if (!_isCurrent(generation) ||
          state.status != DriverTrackingStatus.sharing) {
        return;
      }
      try {
        await ref.read(driverLocationRepositoryProvider).publish(
              DriverLocationSample(
                point: fix.point,
                sequence: sequence,
                recordedAt: fix.recordedAt,
                tripId: _activeTripId,
                headingDegrees: fix.headingDegrees,
                speedMetersPerSecond: fix.speedMetersPerSecond,
              ),
            );
      } catch (error) {
        if (_isCurrent(generation)) {
          _setUnavailable(_failureFromError(error));
          await _cancelSubscription(generation);
        }
      }
    });
  }

  void _handleStreamError(Object error, StackTrace stackTrace, int generation) {
    if (!_isCurrent(generation)) return;
    _setUnavailable(_failureFromError(error));
    unawaited(_cancelSubscription(generation));
  }

  Future<void> _cancelSubscription(int generation) async {
    if (!_isCurrent(generation)) {
      return;
    }
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setUnavailable(DriverLocationFailure failure) {
    state = DriverTrackingState(
      status: DriverTrackingStatus.unavailable,
      failure: failure,
    );
  }

  DriverLocationFailure _failureFromError(Object error) =>
      error is DriverLocationException
          ? error.failure
          : DriverLocationFailure.unavailable;
}
