import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/services/driver_location/geolocator_driver_gps_stream_service.dart';

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
      positionStream: (_) => stream,
    );

    final fix = await service.foregroundFixes().single;

    expect(fix, isA<DriverLocationFix>());
    expect(fix.point.latitude, 31.963158);
    expect(fix.point.longitude, 35.930359);
    expect(fix.point.accuracyMeters, 6);
    expect(fix.recordedAt, timestamp);
    expect(fix.headingDegrees, 90);
    expect(fix.speedMetersPerSecond, 4.5);
  });

  test('uses a movement filter for foreground position requests', () async {
    LocationSettings? requestedSettings;
    final service = GeolocatorDriverGpsStreamService(
      positionStream: (settings) {
        requestedSettings = settings;
        return Stream.value(position());
      },
    );

    await service.foregroundFixes().drain<void>();

    expect(requestedSettings?.accuracy, LocationAccuracy.high);
    expect(requestedSettings?.distanceFilter, 10);
  });

  test('drops invalid coordinates and omits invalid optional measurements',
      () async {
    final controller = StreamController<Position>();
    final service = GeolocatorDriverGpsStreamService(
      positionStream: (_) => controller.stream,
    );
    final fixes = <DriverLocationFix>[];
    final subscription = service.foregroundFixes().listen(fixes.add);
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
    final service = GeolocatorDriverGpsStreamService(
      positionStream: (_) => Stream<Position>.error(StateError('provider')),
    );

    await expectLater(
      service.foregroundFixes(),
      emitsError(
        isA<DriverLocationException>().having(
          (error) => error.failure,
          'failure',
          DriverLocationFailure.unavailable,
        ),
      ),
    );
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
      positionStream: (_) => controller.stream,
    );
    final subscription = service.foregroundFixes().listen((_) {});

    await subscription.cancel();

    expect(cancelled, isTrue);
    await controller.close();
  });
}
