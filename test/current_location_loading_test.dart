import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/services/maps/ride_map_service.dart';
import 'package:ridex/core/widgets/ride_current_location_map.dart';

import 'helpers/fake_location.dart';

void main() {
  testWidgets('shows current-location loading while the repository is pending',
      (tester) async {
    final inspection = Completer<CurrentLocationState>();
    final repository = FakeLocationRepository()
      ..inspectResult = inspection.future;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rideMapServiceProvider.overrideWithValue(
            const MockRideMapService(configured: true),
          ),
          mapPlatformSupportedProvider.overrideWithValue(true),
          locationRepositoryProvider.overrideWithValue(repository),
          currentLocationMapBuilderProvider.overrideWithValue(
            (context, point) => const SizedBox(key: ValueKey('fake-map')),
          ),
        ],
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

    expect(repository.inspectCount, 1);
    expect(
        find.byKey(const ValueKey('current-location-loading')), findsOneWidget);
    expect(find.text('Finding your current location...'), findsOneWidget);

    inspection.complete(const CurrentLocationState.initial());
    await tester.pump();
  });
}
