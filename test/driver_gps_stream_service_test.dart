import 'dart:async';
import 'package:fake_async/fake_async.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/services/driver_location/driver_gps_stream_service.dart';
import 'package:ridex/core/services/driver_location/geolocator_driver_gps_stream_service.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';

import 'helpers/recording_error_reporter.dart';

class _UnavailableDevice extends GeolocatorPlatform {
  bool serviceEnabled = false;
  LocationPermission permission = LocationPermission.denied;
  int reads = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    reads++;
    throw StateError('Native stream must not be requested without access');
  }

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    reads++;
    throw StateError('Native snapshot must not be requested without access');
  }
}

class _AvailableDevice extends GeolocatorPlatform {
  _AvailableDevice(this.position);
  final Position position;
  final source = StreamController<Position>();
  final requestedSettings = <LocationSettings?>[];
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    requestedSettings.add(locationSettings);
    return source.stream;
  }

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    requestedSettings.add(locationSettings);
    return position;
  }
}

void main() {
  final timestamp = DateTime.utc(2026, 9, 17, 10);

  Position position({
    double latitude = 31.963158,
    double longitude = 35.930359,
    double accuracy = 6,
    double heading = 90,
    double speed = 4.5,
    DateTime? observedAt,
  }) {
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: observedAt ?? timestamp,
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

  test('maps available configuration to stationary-capable provider settings',
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
        .foregroundFixes(DriverGpsTrackingConfig.available)
        .drain<void>();

    expect(requestedSettings?.accuracy, LocationAccuracy.high);
    expect(requestedSettings?.distanceFilter, 0);
  });

  test('maps reserved configuration to stationary-capable provider settings',
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
        .foregroundFixes(DriverGpsTrackingConfig.reserved)
        .drain<void>();

    expect(requestedSettings?.accuracy, LocationAccuracy.high);
    expect(requestedSettings?.distanceFilter, 0);
  });

  test('centralizes state-specific write and heartbeat thresholds', () {
    expect(DriverGpsTrackingConfig.available.minimumUpdateInterval,
        const Duration(seconds: 10));
    expect(DriverGpsTrackingConfig.available.minimumPublishDistanceMeters, 50);
    expect(DriverGpsTrackingConfig.available.maximumPublishInterval,
        const Duration(seconds: 15));
    expect(DriverGpsTrackingConfig.reserved.minimumPublishDistanceMeters, 25);
    expect(DriverGpsTrackingConfig.reserved.maximumPublishInterval,
        const Duration(seconds: 15));
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
  test('silent stationary stream refreshes for three minutes then cancels', () {
    fakeAsync((time) {
      var now = timestamp;
      var calls = 0;
      final source = StreamController<Position>();
      final fixes = <DriverLocationFix>[];
      final service = GeolocatorDriverGpsStreamService(
          errorReporter: const NoopAppErrorReporter(),
          positionStream: (_) => source.stream,
          clock: () => now,
          currentPosition: (settings) async {
            calls++;
            expect(settings.accuracy, LocationAccuracy.high);
            expect(settings.timeLimit, const Duration(seconds: 10));
            return position(observedAt: now);
          });
      final sub = service
          .foregroundFixes(DriverGpsTrackingConfig.available)
          .listen(fixes.add);
      for (var tick = 1; tick <= 9; tick++) {
        now = timestamp.add(Duration(seconds: tick * 20));
        time.elapse(const Duration(seconds: 20));
        expect(fixes.length, tick);
        expect(fixes.last.recordedAt, now);
      }
      expect(fixes.map((f) => f.point.latitude).toSet().length, 1);
      sub.cancel();
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 40));
      expect(calls, 9);
      source.close();
      time.flushMicrotasks();
      expect(time.pendingTimers, isEmpty);
    });
  });

  test(
      'cached/inaccurate snapshots and refresh errors grant no freshness; retries recover',
      () {
    fakeAsync((time) {
      var now = timestamp;
      var calls = 0;
      final source = StreamController<Position>();
      final reporter = RecordingAppErrorReporter();
      final fixes = <DriverLocationFix>[];
      final service = GeolocatorDriverGpsStreamService(
          errorReporter: reporter,
          positionStream: (_) => source.stream,
          clock: () => now,
          currentPosition: (_) async {
            calls++;
            if (calls == 1) {
              return position(
                  observedAt: now.subtract(const Duration(minutes: 2)));
            }
            if (calls == 2) return position(observedAt: now, accuracy: 100);
            if (calls == 3) throw StateError('temporary failure');
            return position(observedAt: now);
          });
      final sub = service
          .foregroundFixes(DriverGpsTrackingConfig.available)
          .listen(fixes.add);
      for (var tick = 1; tick <= 4; tick++) {
        now = timestamp.add(Duration(seconds: tick * 20));
        time.elapse(const Duration(seconds: 20));
        expect(fixes.length, tick == 4 ? 1 : 0);
      }
      expect(reporter.reports.length, 1);
      sub.cancel();
      time.flushMicrotasks();
      source.close();
      time.flushMicrotasks();
      expect(time.pendingTimers, isEmpty);
    });
  });

  test(
      'one bounded observation, timeout retry and cancellation suppress late fixes',
      () {
    fakeAsync((time) {
      var calls = 0;
      final pending = <Completer<Position>>[];
      final source = StreamController<Position>();
      final fixes = <DriverLocationFix>[];
      final service = GeolocatorDriverGpsStreamService(
          errorReporter: const NoopAppErrorReporter(),
          positionStream: (_) => source.stream,
          clock: () => timestamp,
          currentPosition: (_) {
            calls++;
            final request = Completer<Position>();
            pending.add(request);
            return request.future;
          });
      final sub = service
          .foregroundFixes(DriverGpsTrackingConfig.available)
          .listen(fixes.add);
      time.elapse(const Duration(seconds: 20));
      expect(calls, 1);
      time.elapse(const Duration(seconds: 5));
      expect(calls, 1);
      time.elapse(const Duration(seconds: 15));
      expect(calls, 2);
      sub.cancel();
      time.flushMicrotasks();
      for (final request in pending) {
        request.complete(position());
      }
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 60));
      expect(fixes, isEmpty);
      expect(calls, 2);
      source.close();
      time.flushMicrotasks();
      expect(time.pendingTimers, isEmpty);
    });
  });
  test(
      'paused collection cancels its refresh timer and ignores an old observation on resume',
      () {
    fakeAsync((time) {
      var now = timestamp;
      var calls = 0;
      final first = Completer<Position>();
      final source = StreamController<Position>();
      final fixes = <DriverLocationFix>[];
      final service = GeolocatorDriverGpsStreamService(
          errorReporter: const NoopAppErrorReporter(),
          positionStream: (_) => source.stream,
          clock: () => now,
          currentPosition: (_) {
            calls++;
            return calls == 1
                ? first.future
                : Future.value(position(observedAt: now));
          });
      final sub = service
          .foregroundFixes(DriverGpsTrackingConfig.available)
          .listen(fixes.add);
      time.elapse(const Duration(seconds: 20));
      sub.pause();
      first.complete(position(observedAt: now));
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 60));
      expect(calls, 1);
      expect(fixes, isEmpty);
      now = timestamp.add(const Duration(seconds: 100));
      sub.resume();
      time.elapse(const Duration(seconds: 20));
      expect(calls, 2);
      expect(fixes.length, 1);
      sub.cancel();
      time.flushMicrotasks();
      source.close();
      time.flushMicrotasks();
      expect(time.pendingTimers, isEmpty);
    });
  });
  test(
      'automatic stream never requests native location while service off or permission denied',
      () async {
    final original = GeolocatorPlatform.instance;
    final platform = _UnavailableDevice();
    GeolocatorPlatform.instance = platform;
    addTearDown(() => GeolocatorPlatform.instance = original);
    for (final enabled in [false, true]) {
      platform.serviceEnabled = enabled;
      final service = GeolocatorDriverGpsStreamService(
          errorReporter: const NoopAppErrorReporter());
      await expectLater(
          service.foregroundFixes(DriverGpsTrackingConfig.available),
          emitsError(isA<DriverLocationException>()));
      expect(platform.reads, 0);
    }
  });

  test('Android automatic stream and refresh use the nonprompting native path',
      () {
    final original = GeolocatorPlatform.instance;
    final platform = _AvailableDevice(position());
    GeolocatorPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      GeolocatorPlatform.instance = original;
      debugDefaultTargetPlatformOverride = null;
    });
    fakeAsync((time) {
      final fixes = <DriverLocationFix>[];
      final service = GeolocatorDriverGpsStreamService(
          errorReporter: const NoopAppErrorReporter(), clock: () => timestamp);
      final sub = service
          .foregroundFixes(DriverGpsTrackingConfig.available)
          .listen(fixes.add);
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 20));
      expect(platform.requestedSettings.length, 2);
      for (final settings in platform.requestedSettings) {
        expect(settings, isA<AndroidSettings>());
        expect((settings! as AndroidSettings).forceLocationManager, isTrue);
        expect(settings.accuracy, LocationAccuracy.high);
        expect(settings.distanceFilter, 0);
      }
      expect(platform.requestedSettings.last?.timeLimit,
          GeolocatorDriverGpsStreamService.observationTimeout);
      expect(fixes.single.recordedAt, timestamp);
      sub.cancel();
      time.flushMicrotasks();
      platform.source.close();
      time.flushMicrotasks();
      expect(time.pendingTimers, isEmpty);
    });
  });

  test(
      'automatic refresh does not request a settings dialog after services are disabled',
      () {
    final original = GeolocatorPlatform.instance;
    final platform = _UnavailableDevice();
    GeolocatorPlatform.instance = platform;
    addTearDown(() => GeolocatorPlatform.instance = original);
    fakeAsync((time) {
      final source = StreamController<Position>();
      final fixes = <DriverLocationFix>[];
      final service = GeolocatorDriverGpsStreamService(
          errorReporter: const NoopAppErrorReporter(),
          positionStream: (_) => source.stream);
      final sub = service
          .foregroundFixes(DriverGpsTrackingConfig.available)
          .listen(fixes.add);
      time.elapse(const Duration(seconds: 60));
      expect(platform.reads, 0);
      expect(fixes, isEmpty);
      sub.cancel();
      time.flushMicrotasks();
      source.close();
      time.flushMicrotasks();
    });
  });
}
