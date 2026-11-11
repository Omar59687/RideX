import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_trip_location.dart';
import 'package:ridex/core/widgets/google_canonical_driver_map.dart';

const tripId = 'c1000000-0000-4000-8000-000000000001';
const driverId = 'b1000000-0000-4000-8000-000000000001';

void main() {
  testWidgets('expired canonical GPS never creates a Google Map or marker',
      (tester) async {
    final now = DateTime.utc(2026, 11, 11, 10);
    final location = RiderTripLocation(
      tripId: tripId,
      driverId: driverId,
      sequence: 1,
      point: LocationPoint(latitude: 31.95, longitude: 35.91),
      recordedAt: now.subtract(const Duration(minutes: 2)),
      receivedAt: now.subtract(const Duration(minutes: 2)),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GoogleCanonicalDriverMap(
          location: location,
          clock: () => now,
        ),
      ),
    ));
    expect(find.byType(GoogleMap), findsNothing);
    expect(find.byKey(const ValueKey('canonical-driver-location-unavailable')),
        findsOneWidget);
    expect(find.text('Waiting for a fresh verified Driver location.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('future-dated GPS never creates a Google Map', (tester) async {
    final now = DateTime.utc(2026, 11, 11, 10);
    final location = RiderTripLocation(
      tripId: tripId,
      driverId: driverId,
      sequence: 1,
      point: LocationPoint(latitude: 31.95, longitude: 35.91),
      recordedAt: now.add(const Duration(minutes: 1)),
      receivedAt: now,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GoogleCanonicalDriverMap(
          location: location,
          clock: () => now,
        ),
      ),
    ));
    expect(find.byType(GoogleMap), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
