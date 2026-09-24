import 'dart:async';

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
  })  : _errorReporter = errorReporter,
        _positionStream = positionStream ??
            ((settings) =>
                Geolocator.getPositionStream(locationSettings: settings));

  final Stream<Position> Function(LocationSettings settings) _positionStream;
  final AppErrorReporter _errorReporter;

  @override
  Stream<DriverLocationFix> foregroundFixes(DriverGpsTrackingConfig config) {
    try {
      return _positionStream(
        LocationSettings(
          accuracy: switch (config.accuracy) {
            DriverGpsAccuracy.low => LocationAccuracy.low,
            DriverGpsAccuracy.medium => LocationAccuracy.medium,
            DriverGpsAccuracy.high => LocationAccuracy.high,
          },
          distanceFilter: config.distanceFilterMeters,
        ),
      ).transform(
        StreamTransformer<Position, DriverLocationFix>.fromHandlers(
          handleData: (position, sink) {
            final fix = _mapPosition(position);
            if (fix != null) sink.add(fix);
          },
          handleError: (error, stackTrace, sink) {
            _errorReporter.report(
              operation: 'reading the driver GPS stream',
              error: error,
              stackTrace: stackTrace,
            );
            sink.addError(
              const DriverLocationException(
                DriverLocationFailure.gpsUnavailable,
              ),
            );
          },
        ),
      );
    } on Object catch (error, stackTrace) {
      _errorReporter.report(
        operation: 'starting the driver GPS stream',
        error: error,
        stackTrace: stackTrace,
      );
      return Stream<DriverLocationFix>.error(
        const DriverLocationException(DriverLocationFailure.gpsUnavailable),
      );
    }
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
