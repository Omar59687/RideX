import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/providers/driver_tracking_providers.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/driver_location_repository.dart';
import 'package:ridex/core/repositories/location_repository.dart';
import 'package:ridex/core/services/driver_location/driver_gps_stream_service.dart';
import 'package:ridex/core/services/driver_location/driver_tracking_connection.dart';
import 'package:ridex/features/driver_home/presentation/screens/driver_home_screen.dart';

void main() {
  late FakeLocationRepository location;
  late FakeDriverRepository driver;
  late FakeGpsService gps;
  late FakeLifecycle lifecycle;
  late FakeConnection connection;
  late DriverTrackingState trackingState;

  Widget buildSubject() => ProviderScope(
        overrides: [
          locationRepositoryProvider.overrideWithValue(location),
          driverLocationRepositoryProvider.overrideWithValue(driver),
          driverGpsStreamServiceProvider.overrideWithValue(gps),
          driverTrackingLifecycleProvider.overrideWithValue(lifecycle),
          driverTrackingConnectionProvider.overrideWithValue(connection),
          driverOnlineProvider.overrideWith((_) => true),
        ],
        observers: [
          _TrackingObserver((state) => trackingState = state),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DriverHomeScreen(),
        ),
      );

  Future<void> pumpSubject(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(buildSubject());
    await tester.pump();
  }

  setUp(() {
    location = FakeLocationRepository();
    driver = FakeDriverRepository();
    gps = FakeGpsService();
    lifecycle = FakeLifecycle();
    connection = FakeConnection();
    trackingState = const DriverTrackingState.initial();
  });

  Future<void> tapButton(WidgetTester tester, String label) async {
    final finder = find.byKey(
      ValueKey(label == 'Start sharing'
          ? 'driver-location-start'
          : 'driver-location-stop'),
    );
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition,
  ) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail(
        'Condition did not become true. Current state: ${trackingState.status}.');
  }

  testWidgets('does not request permission until Start sharing is tapped',
      (tester) async {
    await pumpSubject(tester);

    expect(location.requestCount, 0);
    expect(find.text('Start sharing'), findsOneWidget);

    await tapButton(tester, 'Start sharing');

    expect(location.requestCount, 1);
    expect(find.text('Sharing'), findsOneWidget);
  });

  testWidgets('Stop sharing stops tracking without changing demo presence',
      (tester) async {
    await pumpSubject(tester);
    await tapButton(tester, 'Start sharing');

    expect(find.text('Stop sharing'), findsOneWidget);
    await tapButton(tester, 'Stop sharing');
    await pumpUntil(
      tester,
      () => trackingState.status == DriverTrackingStatus.stopped,
    );

    expect(trackingState.status, DriverTrackingStatus.stopped);
    expect(find.text('You are online'), findsOneWidget);
    expect(find.text('Mock presence only for this phase.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('backgrounding pauses requested location sharing',
      (tester) async {
    await pumpSubject(tester);
    await tapButton(tester, 'Start sharing');

    lifecycle.emit(DriverTrackingLifecycleState.background);
    await pumpUntil(
      tester,
      () => trackingState.status == DriverTrackingStatus.paused,
    );

    expect(trackingState.status, DriverTrackingStatus.paused);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Stop sharing'), findsOneWidget);
  });

  testWidgets('shows safe permission failure text', (tester) async {
    location.result = const CurrentLocationState(
      status: CurrentLocationStatus.unavailable,
      permission: LocationPermissionStatus.permanentlyDenied,
      failure: LocationFailure.permissionPermanentlyDenied,
    );
    await pumpSubject(tester);
    await tapButton(tester, 'Start sharing');

    expect(
      find.text(
        'Location permission is blocked. Enable it in Settings to share your location.',
      ),
      findsOneWidget,
    );
    expect(find.text('Start sharing'), findsOneWidget);
  });

  testWidgets('shows age of the last server-confirmed location',
      (tester) async {
    final now = DateTime.now().toUtc();
    driver.latest = SavedDriverLocation(
      point: LocationPoint(
        latitude: 31.9,
        longitude: 35.9,
        accuracyMeters: 5,
      ),
      sequence: 1,
      recordedAt: now,
      receivedAt: now.subtract(const Duration(minutes: 2)),
    );
    await pumpSubject(tester);
    await tapButton(tester, 'Start sharing');

    expect(find.textContaining('Last server-confirmed location: 2m ago'),
        findsOneWidget);
  });

  testWidgets('shows a recoverable network failure without losing metadata',
      (tester) async {
    final now = DateTime.now().toUtc();
    driver
      ..latest = SavedDriverLocation(
        point: LocationPoint(
          latitude: 31.9,
          longitude: 35.9,
          accuracyMeters: 5,
        ),
        sequence: 1,
        recordedAt: now.subtract(const Duration(minutes: 1)),
        receivedAt: now.subtract(const Duration(seconds: 10)),
      )
      ..publishError = const DriverLocationException(
        DriverLocationFailure.networkFailure,
      );
    await pumpSubject(tester);
    await tapButton(tester, 'Start sharing');

    gps.add(DriverLocationFix(
      point: LocationPoint(
        latitude: 31.91,
        longitude: 35.91,
        accuracyMeters: 5,
      ),
      recordedAt: now,
    ));
    await pumpUntil(
      tester,
      () => trackingState.failure == DriverLocationFailure.networkFailure,
    );

    expect(find.textContaining('Network connection was lost'), findsOneWidget);
    expect(
        find.textContaining('Last server-confirmed location:'), findsOneWidget);
    expect(find.text('Start sharing'), findsOneWidget);
  });
}

class _TrackingObserver extends ProviderObserver {
  _TrackingObserver(this.onState);

  final void Function(DriverTrackingState state) onState;

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    if (provider == driverTrackingControllerProvider &&
        newValue is DriverTrackingState) {
      onState(newValue);
    }
  }
}

class FakeLocationRepository implements LocationRepository {
  int requestCount = 0;
  CurrentLocationState result = CurrentLocationState(
    status: CurrentLocationStatus.available,
    permission: LocationPermissionStatus.granted,
    point: LocationPoint(latitude: 31.9, longitude: 35.9),
  );

  @override
  Future<CurrentLocationState> inspectCurrentLocation() async => result;

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;

  @override
  Future<CurrentLocationState> requestPermissionAndLocate() async {
    requestCount++;
    return result;
  }
}

class FakeDriverRepository implements DriverLocationRepository {
  DriverAvailability? availability = const DriverAvailability(
    state: DriverAvailabilityState.available,
  );
  SavedDriverLocation? latest;
  Object? publishError;

  @override
  Future<DriverAvailability?> fetchAvailability() async => availability;

  @override
  Future<SavedDriverLocation?> fetchLatestLocation() async => latest;

  @override
  Future<SavedDriverLocation> publish(DriverLocationSample sample) async {
    if (publishError case final error?) throw error;
    return SavedDriverLocation(
      point: sample.point,
      sequence: sample.sequence,
      recordedAt: sample.recordedAt,
      receivedAt: DateTime.now().toUtc(),
    );
  }
}

class FakeGpsService implements DriverGpsStreamService {
  final _controller = StreamController<DriverLocationFix>.broadcast();

  @override
  Stream<DriverLocationFix> foregroundFixes(DriverGpsTrackingConfig config) =>
      _controller.stream;

  void add(DriverLocationFix fix) => _controller.add(fix);
}

class FakeLifecycle implements DriverTrackingLifecycle {
  final _controller =
      StreamController<DriverTrackingLifecycleState>.broadcast();

  @override
  Stream<DriverTrackingLifecycleState> get changes => _controller.stream;

  void emit(DriverTrackingLifecycleState state) => _controller.add(state);

  @override
  Future<void> dispose() => _controller.close();
}

class FakeConnection implements DriverTrackingConnection {
  final _controller =
      StreamController<DriverTrackingConnectionEvent>.broadcast();

  @override
  Stream<DriverTrackingConnectionEvent> get events => _controller.stream;

  @override
  Future<int> connect() async => 1;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() => _controller.close();
}
