import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/services/driver_location/driver_gps_stream_service.dart';
import 'package:ridex/core/services/driver_location/geolocator_driver_gps_stream_service.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';

import 'helpers/recording_error_reporter.dart';

void main() {
  final timestamp = DateTime.utc(2026, 9, 17, 10);

  Position position({
    double latitude = 31.963158,
    double longitude = 35.930359,
    double accuracy = 6,
    double heading = 90,
    double speed = 4.5,
  }) {
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: heading,
      headingAccuracy: 1,
      speed: speed,
      speedAccuracy: 1,
      floor: null,
      isMocked: false,
    );
  }

  test('maps a provider position to a provider-neutral fix', () async {
    final stream = Stream.value(position());
    final service = GeolocatorDriverGpsStreamService(
      errorReporter: const NoopAppErrorReporter(),
      positionStream: (_) => stream,
    );

    final fix = await service
        .foregroundFixes(DriverGpsTrackingConfig.activeTrip)
        .single;

    expect(fix, isA<DriverLocationFix>());
    expect(fix.point.latitude, 31.963158);
    expect(fix.point.longitude, 35.930359);
    expect(fix.point.accuracyMeters, 6);
    expect(fix.recordedAt, timestamp);
    expect(fix.headingDegrees, 90);
    expect(fix.speedMetersPerSecond, 4.5);
  });

  test('maps canonical availability to centralized tracking configurations',
      () {
    expect(
      DriverGpsTrackingConfig.forAvailability(
        DriverAvailabilityState.available,
      ),
      same(DriverGpsTrackingConfig.available),
    );
    expect(
      DriverGpsTrackingConfig.forAvailability(
        DriverAvailabilityState.reserved,
      ),
      same(DriverGpsTrackingConfig.reserved),
    );
    expect(
      DriverGpsTrackingConfig.forAvailability(DriverAvailabilityState.onTrip),
      same(DriverGpsTrackingConfig.activeTrip),
    );
    expect(
      DriverGpsTrackingConfig.forAvailability(DriverAvailabilityState.offline),
      isNull,
    );
  });

  test('maps active-trip configuration to high-frequency provider settings',
      () async {
    LocationSettings? requestedSettings;
    final service = GeolocatorDriverGpsStreamService(
      errorReporter: const NoopAppErrorReporter(),
      positionStream: (settings) {
        requestedSettings = settings;
        return Stream.value(position());
      },
    );

    await service
        .foregroundFixes(DriverGpsTrackingConfig.activeTrip)
        .drain<void>();

    expect(requestedSettings?.accuracy, LocationAccuracy.high);
    expect(requestedSettings?.distanceFilter, 10);
  });

  test('maps available configuration to low-power provider settings', () async {
    LocationSettings? requestedSettings;
    final service = GeolocatorDriverGpsStreamService(
      errorReporter: const NoopAppErrorReporter(),
      positionStream: (settings) {
        requestedSettings = settings;
        return Stream.value(position());
      },
    );

    await service
        .foregroundFixes(DriverGpsTrackingConfig.available)
        .drain<void>();

    expect(requestedSettings?.accuracy, LocationAccuracy.low);
    expect(requestedSettings?.distanceFilter, 50);
  });

  test('maps reserved configuration to balanced provider settings', () async {
    LocationSettings? requestedSettings;
    final service = GeolocatorDriverGpsStreamService(
      errorReporter: const NoopAppErrorReporter(),
      positionStream: (settings) {
        requestedSettings = settings;
        return Stream.value(position());
      },
    );

    await service
        .foregroundFixes(DriverGpsTrackingConfig.reserved)
        .drain<void>();

    expect(requestedSettings?.accuracy, LocationAccuracy.medium);
    expect(requestedSettings?.distanceFilter, 25);
  });

  test('centralizes state-specific write and heartbeat thresholds', () {
    expect(DriverGpsTrackingConfig.available.minimumUpdateInterval,
        const Duration(seconds: 30));
    expect(DriverGpsTrackingConfig.available.minimumPublishDistanceMeters, 50);
    expect(DriverGpsTrackingConfig.available.maximumPublishInterval,
        const Duration(minutes: 2));
    expect(DriverGpsTrackingConfig.reserved.minimumPublishDistanceMeters, 25);
    expect(DriverGpsTrackingConfig.reserved.maximumPublishInterval,
        const Duration(minutes: 1));
    expect(DriverGpsTrackingConfig.activeTrip.minimumPublishDistanceMeters, 10);
    expect(DriverGpsTrackingConfig.activeTrip.maximumPublishInterval,
        const Duration(seconds: 15));
  });

  test('drops invalid coordinates and omits invalid optional measurements',
      () async {
    final controller = StreamController<Position>();
    final service = GeolocatorDriverGpsStreamService(
      errorReporter: const NoopAppErrorReporter(),
      positionStream: (_) => controller.stream,
    );
    final fixes = <DriverLocationFix>[];
    final subscription = service
        .foregroundFixes(DriverGpsTrackingConfig.activeTrip)
        .listen(fixes.add);
    final completed = subscription.asFuture<void>();

    controller.add(position(latitude: 91));
    controller.add(position(accuracy: -1, heading: 360, speed: -1));
    await controller.close();
    await completed;

    expect(fixes, hasLength(1));
    expect(fixes.single.point.accuracyMeters, isNull);
    expect(fixes.single.headingDegrees, isNull);
    expect(fixes.single.speedMetersPerSecond, isNull);
  });

  test('sanitizes provider stream errors', () async {
    final error = StateError(rawErrorCanary);
    final reporter = RecordingAppErrorReporter();
    final service = GeolocatorDriverGpsStreamService(
      errorReporter: reporter,
      positionStream: (_) => Stream<Position>.error(error),
    );

    await expectLater(
      service.foregroundFixes(DriverGpsTrackingConfig.activeTrip),
      emitsError(
        isA<DriverLocationException>().having(
          (error) => error.failure,
          'failure',
          DriverLocationFailure.gpsUnavailable,
        ),
      ),
    );
    expect(reporter.reports.single.error, same(error));
  });

  test('cancelling the foreground stream cancels the provider stream',
      () async {
    var cancelled = false;
    final controller = StreamController<Position>(
      onCancel: () {
        cancelled = true;
      },
    );
    final service = GeolocatorDriverGpsStreamService(
      errorReporter: const NoopAppErrorReporter(),
      positionStream: (_) => controller.stream,
    );
    final subscription = service
        .foregroundFixes(DriverGpsTrackingConfig.activeTrip)
        .listen((_) {});

    await subscription.cancel();

    expect(cancelled, isTrue);
    await controller.close();
  });
}
