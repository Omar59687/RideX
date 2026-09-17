import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
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
  int _nextSequence = 1;
  bool _startInProgress = false;

  @override
  DriverTrackingState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    return const DriverTrackingState.initial();
  }

  Future<void> start() async {
    if (_startInProgress || _subscription != null) return;

    _startInProgress = true;
    state = const DriverTrackingState(status: DriverTrackingStatus.starting);
    try {
      final repository = ref.read(driverLocationRepositoryProvider);
      final availability = await repository.fetchAvailability();
      if (availability == null || !availability.canShareLocation) {
        _setUnavailable(DriverLocationFailure.ineligible);
        return;
      }

      final latest = await repository.fetchLatestLocation();
      _latestRecordedAt = latest?.recordedAt;
      _nextSequence = (latest?.sequence ?? 0) + 1;
      state = DriverTrackingState(
        status: DriverTrackingStatus.sharing,
        nextSequence: _nextSequence,
      );
      _subscription = ref
          .read(driverGpsStreamServiceProvider)
          .foregroundFixes()
          .listen(_handleFix, onError: _handleStreamError);
    } catch (error) {
      _setUnavailable(_failureFromError(error));
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> stop() async {
    _startInProgress = false;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    state = const DriverTrackingState(status: DriverTrackingStatus.stopped);
  }

  void _handleFix(DriverLocationFix fix) {
    if (state.status != DriverTrackingStatus.sharing ||
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
      if (state.status != DriverTrackingStatus.sharing) return;
      try {
        await ref.read(driverLocationRepositoryProvider).publish(
              DriverLocationSample(
                point: fix.point,
                sequence: sequence,
                recordedAt: fix.recordedAt,
                headingDegrees: fix.headingDegrees,
                speedMetersPerSecond: fix.speedMetersPerSecond,
              ),
            );
      } catch (error) {
        _setUnavailable(_failureFromError(error));
        await _cancelSubscription();
      }
    });
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    _setUnavailable(_failureFromError(error));
    unawaited(_cancelSubscription());
  }

  Future<void> _cancelSubscription() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

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
