import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

void main() {
  group('RiderAssignedTrip', () {
    test('preserves exact canonical identities and values', () {
      final trip = riderAssignedTripFixture(driverDisplayName: 'Test Driver');

      expect(trip.tripId, riderTripIdFixture);
      expect(trip.bookingRequestId, riderBookingIdFixture);
      expect(trip.riderId, riderIdFixture);
      expect(trip.driver.driverId, riderDriverIdFixture);
      expect(trip.vehicle.vehicleId, riderVehicleIdFixture);
      expect(trip.version, 3);
      expect(trip.status, DriverTripLifecycleStatus.accepted);
      expect(trip.paymentMethod, PaymentMethod.cash);
      expect(trip.driver.displayName, 'Test Driver');
      expect(trip.vehicle.registrationPlate, 'TEST 123');
      expect(trip.currency, 'JOD');
      expect(trip.stops, isEmpty);
      expect(trip.acceptedAt, DateTime.utc(2026, 11, 4, 8));
      expect(trip.updatedAt, DateTime.utc(2026, 11, 4, 8, 5));
    });

    test('rejects non-canonical identities', () {
      final builders = [
        () => riderAssignedTripFixture(tripId: 'trip-1'),
        () => riderAssignedTripFixture(bookingRequestId: 'booking-1'),
        () => riderAssignedTripFixture(riderId: 'rider-1'),
        () => riderAssignedTripFixture(driverId: 'driver-1'),
        () => riderAssignedTripFixture(vehicleId: 'vehicle-1'),
      ];

      for (final build in builders) {
        expect(build, throwsArgumentError);
      }
    });

    test('rejects non-positive versions and Card payment', () {
      expect(() => riderAssignedTripFixture(version: 0), throwsArgumentError);
      expect(() => riderAssignedTripFixture(version: -1), throwsArgumentError);
      expect(
        () => riderAssignedTripFixture(paymentMethod: PaymentMethod.card),
        throwsArgumentError,
      );
    });

    test('rejects invalid fare, route, and currency values', () {
      expect(
        () => riderAssignedTripFixture(routeDistanceMeters: -1),
        throwsArgumentError,
      );
      expect(
        () => riderAssignedTripFixture(routeDurationSeconds: -1),
        throwsArgumentError,
      );
      expect(
        () => riderAssignedTripFixture(originalFareFils: -1),
        throwsArgumentError,
      );
      expect(
        () => riderAssignedTripFixture(currentFareFils: -1),
        throwsArgumentError,
      );
      expect(
        () => riderAssignedTripFixture(currency: 'USD'),
        throwsArgumentError,
      );
    });

    test('keeps stops immutable and bounded', () {
      final trip = riderAssignedTripFixture();
      expect(
        () => trip.stops.add(RiderTripPlace(point: _point())),
        throwsUnsupportedError,
      );

      final fourStops = List.generate(
        4,
        (index) => RiderTripPlace(
          point: _point(latitude: 31.95 + index / 1000),
          label: 'Stop $index',
        ),
      );
      expect(
        () => riderAssignedTripFixture(stops: fourStops),
        throwsArgumentError,
      );
    });

    test('rejects identical pickup and destination coordinates', () {
      final samePoint = _point();
      expect(
        () => riderAssignedTripFixture(
          pickup: RiderTripPlace(point: samePoint, label: 'Pickup'),
          destination: RiderTripPlace(point: samePoint, label: 'Destination'),
        ),
        throwsArgumentError,
      );
    });

    test('reports terminal canonical statuses', () {
      for (final status in [
        DriverTripLifecycleStatus.completed,
        DriverTripLifecycleStatus.cancelledByRider,
        DriverTripLifecycleStatus.cancelledByDriver,
        DriverTripLifecycleStatus.cancelledByAdmin,
        DriverTripLifecycleStatus.failed,
      ]) {
        expect(riderAssignedTripFixture(status: status).isTerminal, isTrue);
      }
      for (final status in [
        DriverTripLifecycleStatus.accepted,
        DriverTripLifecycleStatus.driverArriving,
        DriverTripLifecycleStatus.driverArrived,
        DriverTripLifecycleStatus.inProgress,
      ]) {
        expect(riderAssignedTripFixture(status: status).isTerminal, isFalse);
      }
    });

    test('validates Driver and vehicle summary ranges', () {
      expect(
        () => RiderDriverSummary(
          driverId: riderDriverIdFixture,
          ratingAverage: 5.1,
          ratingCount: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => RiderDriverSummary(
          driverId: riderDriverIdFixture,
          ratingAverage: double.nan,
          ratingCount: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => RiderDriverSummary(
          driverId: riderDriverIdFixture,
          ratingAverage: 4.5,
          ratingCount: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => RiderVehicleSummary(
          vehicleId: riderVehicleIdFixture,
          seatCapacity: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => RiderVehicleSummary(
          vehicleId: riderVehicleIdFixture,
          registrationPlate: 'ab',
        ),
        throwsArgumentError,
      );
    });

    test('keeps optional Driver rating values paired', () {
      expect(
        () => RiderDriverSummary(
          driverId: riderDriverIdFixture,
          ratingAverage: 4.5,
        ),
        throwsArgumentError,
      );
      expect(
        () => RiderDriverSummary(
          driverId: riderDriverIdFixture,
          ratingCount: 10,
        ),
        throwsArgumentError,
      );
      final driver = RiderDriverSummary(
        driverId: riderDriverIdFixture,
        ratingAverage: 4.5,
        ratingCount: 10,
      );
      expect(driver.ratingAverage, 4.5);
      expect(driver.ratingCount, 10);
    });

    test(
      'allows unknown Driver and vehicle details without inventing them',
      () {
        final trip = riderAssignedTripFixture(includeVehicleDetails: false);

        expect(trip.driver.displayName, isNull);
        expect(trip.driver.ratingAverage, isNull);
        expect(trip.driver.ratingCount, isNull);
        expect(trip.vehicle.vehicleId, riderVehicleIdFixture);
        expect(trip.vehicle.make, isNull);
        expect(trip.vehicle.model, isNull);
        expect(trip.vehicle.color, isNull);
        expect(trip.vehicle.registrationPlate, isNull);
        expect(trip.vehicle.seatCapacity, isNull);
      },
    );

    test('validates optional place text', () {
      expect(
        () => RiderTripPlace(point: _point(), label: '   '),
        throwsArgumentError,
      );
      expect(
        () => RiderTripPlace(point: _point(), label: 'x' * 201),
        throwsArgumentError,
      );
      expect(RiderTripPlace(point: _point(), label: '  Home  ').label, 'Home');
      expect(RiderTripPlace(point: _point()).label, isNull);
    });

    test('validates optional route geometry reference', () {
      expect(
        riderAssignedTripFixture(routeGeometryReference: null)
            .routeGeometryReference,
        isNull,
      );
      expect(
        riderAssignedTripFixture(routeGeometryReference: '  route  ')
            .routeGeometryReference,
        'route',
      );
      expect(
        () => riderAssignedTripFixture(routeGeometryReference: '   '),
        throwsArgumentError,
      );
    });
  });

  group('Rider canonical status contract', () {
    test('strictly maps backend status values', () {
      for (final status in DriverTripLifecycleStatus.values) {
        expect(
          DriverTripLifecycleStatus.fromBackendValue(status.backendValue),
          status,
        );
      }
      expect(
        () => DriverTripLifecycleStatus.fromBackendValue('searching'),
        throwsArgumentError,
      );
      expect(
        () => DriverTripLifecycleStatus.fromBackendValue('driver_arriving'),
        throwsArgumentError,
      );
    });
  });

  group('Rider trip tracking events', () {
    test('keeps Trip version and event sequence separate', () {
      final statusEvent = RiderTripStatusChanged(
        tripId: riderTripIdFixture,
        tripVersion: 4,
        eventSequence: 9,
        status: DriverTripLifecycleStatus.inProgress,
        occurredAt: DateTime.utc(2026, 11, 4, 8, 10),
      );
      final locationEvent = RiderTripLocationChanged(
        tripId: riderTripIdFixture,
        sample: DriverLocationSample(
          point: _point(),
          sequence: 2,
          recordedAt: DateTime.utc(2026, 11, 4, 8, 11),
          tripId: riderTripIdFixture,
        ),
        receivedAt: DateTime.utc(2026, 11, 4, 8, 11, 1),
      );

      expect(statusEvent.tripVersion, 4);
      expect(statusEvent.eventSequence, 9);
      expect(locationEvent.locationSequence, 2);
      expect(locationEvent.sample.sequence, 2);
      expect(locationEvent.tripId, riderTripIdFixture);
      expect(statusEvent.tripId, riderTripIdFixture);
    });

    test('rejects invalid status event ordering values', () {
      expect(
        () => RiderTripStatusChanged(
          tripId: riderTripIdFixture,
          tripVersion: 0,
          eventSequence: 1,
          status: DriverTripLifecycleStatus.accepted,
          occurredAt: DateTime.utc(2026, 11, 4),
        ),
        throwsArgumentError,
      );
      expect(
        () => RiderTripStatusChanged(
          tripId: riderTripIdFixture,
          tripVersion: 1,
          eventSequence: 0,
          status: DriverTripLifecycleStatus.accepted,
          occurredAt: DateTime.utc(2026, 11, 4),
        ),
        throwsArgumentError,
      );
      expect(
        () => RiderTripStatusChanged(
          tripId: 'trip-1',
          tripVersion: 1,
          eventSequence: 1,
          status: DriverTripLifecycleStatus.accepted,
          occurredAt: DateTime.utc(2026, 11, 4),
        ),
        throwsArgumentError,
      );
    });

    test('matches location Trip identity case-insensitively', () {
      final upperTripId = riderTripIdFixture.toUpperCase();
      expect(upperTripId, isNot(riderTripIdFixture));
      final event = RiderTripLocationChanged(
        tripId: upperTripId,
        sample: DriverLocationSample(
          point: _point(),
          sequence: 1,
          recordedAt: DateTime.utc(2026, 11, 4),
          tripId: riderTripIdFixture,
        ),
        receivedAt: DateTime.utc(2026, 11, 4),
      );

      expect(event.tripId, upperTripId);
      expect(event.sample.tripId, riderTripIdFixture);
    });

    test('rejects mismatched location Trip identity', () {
      expect(
        () => RiderTripLocationChanged(
          tripId: riderTripIdFixture,
          sample: DriverLocationSample(
            point: _point(),
            sequence: 1,
            recordedAt: DateTime.utc(2026, 11, 4),
            tripId: '99999999-9999-4999-8999-999999999999',
          ),
          receivedAt: DateTime.utc(2026, 11, 4),
        ),
        throwsArgumentError,
      );
      expect(
        () => RiderTripLocationChanged(
          tripId: riderTripIdFixture,
          sample: DriverLocationSample(
            point: _point(),
            sequence: 1,
            recordedAt: DateTime.utc(2026, 11, 4),
          ),
          receivedAt: DateTime.utc(2026, 11, 4),
        ),
        throwsArgumentError,
      );
    });

    test('validates disconnect evidence and snapshot identity', () {
      final trip = riderAssignedTripFixture();
      final snapshot = RiderTripSnapshot(trip);
      final disconnected = RiderTripTrackingDisconnected(
        tripId: riderTripIdFixture,
        disconnectedAt: DateTime.utc(2026, 11, 4, 8, 20),
        reason: '  network down  ',
      );

      expect(snapshot.tripId, trip.tripId);
      expect(snapshot.trip, same(trip));
      expect(disconnected.reason, 'network down');
      expect(disconnected.tripId, riderTripIdFixture);
      expect(
        () => RiderTripTrackingDisconnected(
          tripId: riderTripIdFixture,
          disconnectedAt: DateTime.utc(2026, 11, 4),
          reason: '   ',
        ),
        throwsArgumentError,
      );
      expect(
        () => RiderTripTrackingDisconnected(
          tripId: 'trip-1',
          disconnectedAt: DateTime.utc(2026, 11, 4),
        ),
        throwsArgumentError,
      );
      expect(
        () => RiderTripTrackingDisconnected(
          tripId: riderTripIdFixture,
          disconnectedAt: DateTime.utc(2026, 11, 4),
          reason: 'x' * 201,
        ),
        throwsArgumentError,
      );
    });
  });
}

LocationPoint _point({double latitude = 31.9539}) {
  return LocationPoint(
    latitude: latitude,
    longitude: 35.9106,
    accuracyMeters: 8,
  );
}
