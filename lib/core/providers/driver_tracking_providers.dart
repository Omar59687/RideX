import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final driverTrackingControllerProvider =
    NotifierProvider.autoDispose<DriverTrackingController, DriverTrackingState>(
  DriverTrackingController.new,
);

class DriverTrackingController
    extends AutoDisposeNotifier<DriverTrackingState> {
  StreamSubscription<DriverLocationFix>? _subscription;
  Future<void> _publishQueue = Future<void>.value();
  DateTime? _latestRecordedAt;
  String? _activeTripId;
  int _nextSequence = 1;
  bool _startInProgress = false;
  int _generation = 0;
  bool _disposed = false;

  @override
  DriverTrackingState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _subscription?.cancel();
      _subscription = null;
    });
    return const DriverTrackingState.initial();
  }

  Future<void> start() async {
    if (_startInProgress || _subscription != null) return;

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
