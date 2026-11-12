import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/services/driver_location/driver_gps_stream_service.dart';

class GeolocatorDriverGpsStreamService implements DriverGpsStreamService {
  GeolocatorDriverGpsStreamService({
    required AppErrorReporter errorReporter,
    Stream<Position> Function(LocationSettings settings)? positionStream,
    Future<Position> Function(LocationSettings settings)? currentPosition,
    DateTime Function()? clock,
  })  : _errorReporter = errorReporter,
        _positionStream = positionStream ?? _deviceStream,
        _currentPosition = currentPosition ?? _devicePosition,
        _clock = clock ?? DateTime.now;

  final Stream<Position> Function(LocationSettings settings) _positionStream;
  final AppErrorReporter _errorReporter;
  final Future<Position> Function(LocationSettings settings) _currentPosition;
  final DateTime Function() _clock;
  static const refreshInterval = Duration(seconds: 20);
  static const observationTimeout = Duration(seconds: 10);

  static LocationSettings _settings({
    required LocationAccuracy accuracy,
    required int distanceFilter,
    Duration? timeLimit,
  }) {
    // FusedLocationClient can launch a settings-resolution dialog even after
    // an access check succeeds (or settings change during that check). Android's
    // LocationManager returns an unavailable/error result without that UI.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        forceLocationManager: true,
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        timeLimit: timeLimit,
      );
    }
    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      timeLimit: timeLimit,
    );
  }

  // Automatic observation must never trigger location/permission dialogs.
  // The explicit Home Start sharing flow owns permission/settings requests.
  static Future<void> _requireDeviceAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DriverLocationException(DriverLocationFailure.gpsUnavailable);
    }
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const DriverLocationException(DriverLocationFailure.gpsUnavailable);
    }
  }

  static Stream<Position> _deviceStream(LocationSettings settings) async* {
    await _requireDeviceAccess();
    yield* Geolocator.getPositionStream(locationSettings: settings);
  }

  static Future<Position> _devicePosition(LocationSettings settings) async {
    await _requireDeviceAccess();
    return Geolocator.getCurrentPosition(locationSettings: settings);
  }

  @override
  Stream<DriverLocationFix> foregroundFixes(DriverGpsTrackingConfig config) {
    // Collection only: both sources feed the ONE existing publisher/sequence
    // queue. A snapshot requests device evidence; it never reuses/retimestamps
    // the last fix. The controller cancels this owner on background/auth/Stop.
    final settings = _settings(
      accuracy: switch (config.accuracy) {
        DriverGpsAccuracy.low => LocationAccuracy.low,
        DriverGpsAccuracy.medium => LocationAccuracy.medium,
        DriverGpsAccuracy.high => LocationAccuracy.high,
      },
      distanceFilter: config.distanceFilterMeters,
    );
    late final StreamController<DriverLocationFix> output;
    StreamSubscription<Position>? subscription;
    Timer? timer;
    var closed = false, paused = false, observing = false;
    var epoch = 0;
    void emit(Position position) {
      if (closed || paused) return;
      final fix = _mapPosition(position);
      if (fix != null) output.add(fix);
    }

    Future<void> refresh() async {
      if (closed || paused || observing) return;
      observing = true;
      final captured = epoch;
      try {
        final position = await _currentPosition(_settings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          timeLimit: observationTimeout,
        )).timeout(observationTimeout);
        if (closed || paused || captured != epoch) return;
        final age = _clock().toUtc().difference(position.timestamp.toUtc());
        if (age > const Duration(seconds: 30) ||
            age < const Duration(seconds: -5) ||
            !position.accuracy.isFinite ||
            position.accuracy <= 0 ||
            position.accuracy > 50) {
          return;
        }
        emit(position);
      } on Object catch (error, stackTrace) {
        if (!closed && !paused && captured == epoch) {
          // A failed refresh grants no freshness. Keep bounded retries alive;
          // the view ages canonical evidence to STALE instead of inventing data.
          _errorReporter.report(
              operation: 'refreshing foreground driver GPS',
              error: error,
              stackTrace: stackTrace);
        }
      } finally {
        observing = false;
      }
    }

    void schedule() {
      timer?.cancel();
      timer = Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
    }

    output = StreamController<DriverLocationFix>(
      onListen: () {
        try {
          subscription = _positionStream(settings).listen(emit,
              onError: (Object error, StackTrace stackTrace) {
            if (closed) return;
            _errorReporter.report(
                operation: 'reading the driver GPS stream',
                error: error,
                stackTrace: stackTrace);
            output.addError(const DriverLocationException(
                DriverLocationFailure.gpsUnavailable));
          }, onDone: () {
            closed = true;
            epoch++;
            timer?.cancel();
            unawaited(output.close());
          });
          schedule();
        } on Object catch (error, stackTrace) {
          closed = true;
          _errorReporter.report(
              operation: 'starting the driver GPS stream',
              error: error,
              stackTrace: stackTrace);
          output.addError(const DriverLocationException(
              DriverLocationFailure.gpsUnavailable));
          unawaited(output.close());
        }
      },
      onPause: () {
        paused = true;
        epoch++;
        timer?.cancel();
        subscription?.pause();
      },
      onResume: () {
        paused = false;
        subscription?.resume();
        if (!closed) schedule();
      },
      onCancel: () async {
        closed = true;
        epoch++;
        timer?.cancel();
        await subscription?.cancel();
      },
    );
    return output.stream;
  }

  DriverLocationFix? _mapPosition(Position position) {
    try {
      final point = LocationPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: _validNonnegative(position.accuracy),
      );
      return DriverLocationFix(
        point: point,
        recordedAt: position.timestamp,
        headingDegrees: _validHeading(position.heading),
        speedMetersPerSecond: _validNonnegative(position.speed),
      );
    } on ArgumentError {
      return null;
    }
  }

  double? _validNonnegative(double value) =>
      value.isFinite && value >= 0 ? value : null;

  double? _validHeading(double value) =>
      value.isFinite && value >= 0 && value < 360 ? value : null;
}
