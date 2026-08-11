import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/services/maps/ride_map_service.dart';
import 'package:ridex/core/widgets/ride_current_location_map.dart';
import 'package:ridex/features/driver_home/presentation/screens/driver_home_screen.dart';
import 'package:ridex/features/rider_home/presentation/widgets/home_map_header.dart';

import 'helpers/fake_location.dart';

void main() {
  testWidgets('keeps the map surface usable without configuration',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: RideCurrentLocationMap(
              height: 220,
              semanticLabel: 'Test map',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('map-configuration-fallback')),
        findsOneWidget);
    expect(find.textContaining('continue using RideX'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows permanent denial without exposing provider errors',
      (tester) async {
    final repository = FakeLocationRepository(
      inspectedState: const CurrentLocationState(
        status: CurrentLocationStatus.unavailable,
        permission: LocationPermissionStatus.permanentlyDenied,
        failure: LocationFailure.permissionPermanentlyDenied,
      ),
    );

    await tester.pumpWidget(_testMapApp(repository));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('fake-google-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('location-permanently-denied')),
        findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);
    expect(find.textContaining('raw'), findsNothing);

    await tester.tap(find.text('App settings'));
    await tester.pump();
    expect(repository.appSettingsCount, 1);
  });

  final fallbackCases = <(
    String,
    CurrentLocationState,
    Key,
  )>[
    (
      'initial permission',
      const CurrentLocationState.initial(),
      const ValueKey('location-permission-initial'),
    ),
    (
      'denied permission',
      const CurrentLocationState(
        status: CurrentLocationStatus.unavailable,
        permission: LocationPermissionStatus.denied,
        failure: LocationFailure.permissionDenied,
      ),
      const ValueKey('location-permission-denied'),
    ),
    (
      'disabled location service',
      const CurrentLocationState(
        status: CurrentLocationStatus.serviceDisabled,
        permission: LocationPermissionStatus.granted,
        failure: LocationFailure.serviceDisabled,
      ),
      const ValueKey('location-service-disabled'),
    ),
    (
      'temporary location failure',
      const CurrentLocationState(
        status: CurrentLocationStatus.unavailable,
        permission: LocationPermissionStatus.granted,
        failure: LocationFailure.unavailable,
      ),
      const ValueKey('current-location-unavailable'),
    ),
  ];

  for (final fallbackCase in fallbackCases) {
    testWidgets('shows safe ${fallbackCase.$1} state', (tester) async {
      final repository = FakeLocationRepository(
        inspectedState: fallbackCase.$2,
      );

      await tester.pumpWidget(_testMapApp(repository));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(fallbackCase.$3), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-google-map')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Rider and Driver home use the shared current-location map',
      (tester) async {
    final point = LocationPoint(latitude: 31.95, longitude: 35.91);
    final repository = FakeLocationRepository(
      inspectedState: CurrentLocationState(
        status: CurrentLocationStatus.available,
        permission: LocationPermissionStatus.granted,
        point: point,
      ),
    );
    final overrides = _mapOverrides(repository);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HomeMapHeader(
              firstName: 'Rider',
              pickup: const RideLocation(
                label: 'Current location',
                address: 'Location pending',
              ),
              unreadCount: 0,
              onNotifications: _doNothing,
              onPlanRide: _doNothing,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-google-map')), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _mapOverrides(repository),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DriverHomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-google-map')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _testMapApp(FakeLocationRepository repository) {
  return ProviderScope(
    overrides: _mapOverrides(repository),
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: RideCurrentLocationMap(
          height: 220,
          semanticLabel: 'Test map',
        ),
      ),
    ),
  );
}

List<Override> _mapOverrides(FakeLocationRepository repository) {
  return [
    rideMapServiceProvider.overrideWithValue(
      const MockRideMapService(configured: true),
    ),
    mapPlatformSupportedProvider.overrideWithValue(true),
    locationRepositoryProvider.overrideWithValue(repository),
    currentLocationMapBuilderProvider.overrideWithValue(
      (context, point) => ColoredBox(
        key: const ValueKey('fake-google-map'),
        color: Colors.blueGrey,
        child: Text(point == null ? 'Map ready' : 'Current point ready'),
      ),
    ),
  ];
}

void _doNothing() {}
