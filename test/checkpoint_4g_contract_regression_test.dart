import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/models/vehicle_type.dart';

void main() {
  final pickup = RideLocation(
    point: LocationPoint(latitude: 31.95, longitude: 35.91),
    label: 'Pickup',
    address: 'Pickup address',
    source: LocationSelectionSource.map,
  );
  final destination = RideLocation(
    point: LocationPoint(latitude: 31.96, longitude: 35.92),
    label: 'Destination',
    address: 'Destination address',
    source: LocationSelectionSource.search,
  );

  test(
      'BookingDraft copy preserves canonical endpoints during transient updates',
      () {
    final draft = BookingDraft(
      pickup: pickup,
      destination: destination,
      vehicleType: const VehicleType(
        id: 'standard',
        name: 'Standard',
        description: 'Everyday rides',
        baseFare: 5.8,
        arrivalMinutes: 5,
        capacity: 4,
      ),
      distanceKm: 4.2,
      etaMinutes: 12,
      estimatedFare: 7.35,
    );

    final updated = draft.copyWith(distanceKm: 4.5, etaMinutes: 13);

    expect(updated.pickup, pickup);
    expect(updated.destination, destination);
    expect(updated.vehicleType, draft.vehicleType);
    expect(updated.estimatedFare, draft.estimatedFare);
    expect(updated.isRoutingReady, isTrue);
  });

  test('MockTrip copy preserves booking and driver state while changing status',
      () {
    const driver = DriverSummary(
      name: 'Nadia',
      rating: 4.8,
      vehicleName: 'Kia K5',
      plate: '12-ABC',
      etaMinutes: 4,
    );
    final trip = MockTrip(
      id: 'trip-1',
      booking: BookingDraft(pickup: pickup, destination: destination),
      status: TripStatus.accepted,
      driver: driver,
      finalFare: 7.35,
    );

    final updated = trip.copyWith(status: TripStatus.driverArriving);

    expect(updated.id, trip.id);
    expect(updated.booking, trip.booking);
    expect(updated.driver, driver);
    expect(updated.finalFare, trip.finalFare);
    expect(updated.status, TripStatus.driverArriving);
  });

  test(
      'DriverLocation contracts normalize timestamps and reject invalid samples',
      () {
    final localTime = DateTime(2026, 9, 27, 10);
    final fix = DriverLocationFix(
      point: LocationPoint(
        latitude: 31.95,
        longitude: 35.91,
        accuracyMeters: 6,
      ),
      recordedAt: localTime,
      headingDegrees: 90,
      speedMetersPerSecond: 4.5,
    );
    final sample = DriverLocationSample(
      point: fix.point,
      sequence: 3,
      recordedAt: localTime,
      tripId: 'trip-1',
      headingDegrees: fix.headingDegrees,
      speedMetersPerSecond: fix.speedMetersPerSecond,
    );
    final saved = SavedDriverLocation(
      point: sample.point,
      sequence: sample.sequence,
      recordedAt: sample.recordedAt,
      receivedAt: localTime.add(const Duration(seconds: 2)),
      tripId: sample.tripId,
    );

    expect(fix.recordedAt.isUtc, isTrue);
    expect(sample.recordedAt.isUtc, isTrue);
    expect(saved.receivedAt.isUtc, isTrue);
    expect(saved.sequence, 3);
    expect(saved.tripId, 'trip-1');
    expect(
      () => DriverLocationFix(
        point: fix.point,
        recordedAt: localTime,
        headingDegrees: 360,
      ),
      throwsArgumentError,
    );
    expect(
      () => DriverLocationSample(
        point: LocationPoint(latitude: 31.95, longitude: 35.91),
        sequence: 0,
        recordedAt: localTime,
      ),
      throwsArgumentError,
    );
  });
}
