import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_selection_state.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/services/maps/ride_map_service.dart';
import 'package:ridex/core/widgets/ride_location_selection_map.dart';

import 'helpers/fake_places.dart';

void main() {
  testWidgets(
      'passes independent pickup and destination markers to map boundary',
      (tester) async {
    final pickup = testLocation(latitude: 31.95, longitude: 35.91);
    final destination = testLocation(latitude: 31.96, longitude: 35.92);
    LocationPoint? tappedPoint;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rideMapServiceProvider.overrideWithValue(
            const MockRideMapService(configured: true),
          ),
          mapPlatformSupportedProvider.overrideWithValue(true),
          locationSelectionMapBuilderProvider.overrideWithValue((
            context, {
            required activeEndpoint,
            required pickup,
            required destination,
            required currentLocation,
            required onPointSelected,
          }) {
            return TextButton(
              key: const ValueKey('fake-selection-map'),
              onPressed: () => onPointSelected(
                LocationPoint(latitude: 32, longitude: 36),
              ),
              child: Text(
                '${activeEndpoint.name}:${pickup?.point.latitude}:'
                '${destination?.point.latitude}',
              ),
            );
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: RideLocationSelectionMap(
              activeEndpoint: LocationEndpoint.pickup,
              pickup: pickup,
              destination: destination,
              currentLocation: null,
              onPointSelected: (point) => tappedPoint = point,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('pickup:31.95:31.96'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fake-selection-map')));
    expect(tappedPoint, LocationPoint(latitude: 32, longitude: 36));
  });

  testWidgets('map unavailable keeps search fallback message visible',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rideMapServiceProvider.overrideWithValue(
            const MockRideMapService(configured: false),
          ),
          mapPlatformSupportedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: RideLocationSelectionMap(
              activeEndpoint: LocationEndpoint.destination,
              pickup: null,
              destination: null,
              currentLocation: null,
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Map selection is unavailable. Search still works.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
