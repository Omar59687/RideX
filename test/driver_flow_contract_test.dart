import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'helpers/fake_driver_flow_repository.dart';

void main() {
  test('session identity and generation reject invalid values', () {
    expect(() => DriverFlowSession(' ', 1), throwsArgumentError);
    expect(() => DriverFlowSession('driver', -1), throwsArgumentError);
    expect(
      DriverFlowSession('A', 1).sameSession(DriverFlowSession('A', 3)),
      isFalse,
    );
  });

  for (final state in DriverAvailabilityState.values) {
    test('availability represents ${state.name} with independent version', () {
      final value = DriverFlowAvailability(
        state: state,
        version: 7,
        vehicleId: state == DriverAvailabilityState.offline ? null : 'vehicle',
        bookingId: state == DriverAvailabilityState.reserved ? 'booking' : null,
        tripId: state == DriverAvailabilityState.onTrip ? 'trip' : null,
      );
      expect(value.version, 7);
    });
  }
  test('availability rejects missing linkage and invalid version', () {
    for (final state in [
      DriverAvailabilityState.available,
      DriverAvailabilityState.reserved,
      DriverAvailabilityState.onTrip,
    ]) {
      expect(
        () => DriverFlowAvailability(state: state, version: 1),
        throwsArgumentError,
      );
    }
    expect(
      () => DriverFlowAvailability(
        state: DriverAvailabilityState.offline,
        version: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => DriverFlowAvailability(
        state: DriverAvailabilityState.available,
        version: 1,
        vehicleId: 'vehicle',
        tripId: 'trip',
      ),
      throwsArgumentError,
    );
  });
  test(
    'offer retains distinct IDs, version, integer fare and exact expiry',
    () {
      final offer = driverFlowOffer();
      expect({
        offer.id,
        offer.bookingId,
        offer.quoteId,
        offer.journey.vehicleId,
      }, hasLength(4));
      expect(offer.version, 3);
      expect(offer.journey.lockedFareFils, 1990);
      expect(
        offer.isExpiredAt(
          offer.expiresAt.subtract(const Duration(microseconds: 1)),
        ),
        isFalse,
      );
      expect(offer.isExpiredAt(offer.expiresAt), isTrue);
      expect(
        offer.isExpiredAt(offer.expiresAt.add(const Duration(seconds: 1))),
        isTrue,
      );
      expect(() => driverFlowOffer(id: ''), throwsArgumentError);
      expect(() => driverFlowOffer(version: 0), throwsArgumentError);
    },
  );
  test('journey rejects Card and keeps stops immutable', () {
    final journey = driverFlowJourney();
    expect(
      () => DriverFlowJourney(
        pickup: journey.pickup,
        destination: journey.destination,
        vehicleId: 'vehicle',
        vehicleLabel: 'Taxi',
        lockedFareFils: 1990,
        distanceMeters: 5000,
        durationSeconds: 600,
        paymentMethod: PaymentMethod.card,
      ),
      throwsArgumentError,
    );
    expect(() => journey.stops.add(journey.pickup), throwsUnsupportedError);
  });
  test('journey defensively copies caller-owned stops', () {
    final original = driverFlowJourney();
    final stops = [original.pickup];
    final journey = DriverFlowJourney(
      pickup: original.pickup,
      destination: original.destination,
      vehicleId: original.vehicleId,
      vehicleLabel: original.vehicleLabel,
      lockedFareFils: original.lockedFareFils,
      distanceMeters: original.distanceMeters,
      durationSeconds: original.durationSeconds,
      stops: stops,
    );
    final snapshot = driverFlowSnapshot(
        trip: DriverFlowTrip(
      id: 'trip',
      version: 9,
      status: DriverTripLifecycleStatus.accepted,
      journey: journey,
    ));
    stops[0] = original.destination;
    stops.clear();
    expect(snapshot.trip!.journey.stops, [original.pickup]);
    expect(() => snapshot.trip!.journey.stops.clear(), throwsUnsupportedError);
  });
  for (final status in DriverTripLifecycleStatus.values) {
    test('Trip presentation retains ${status.name} independently', () {
      final trip = DriverFlowTrip(
        id: 'trip',
        version: 9,
        status: status,
        journey: driverFlowJourney(),
      );
      expect(trip.status, status);
      expect(trip.id, 'trip');
      expect(trip.version, 9);
    });
  }
  test('commands reject completion and preserve token verbatim', () {
    final session = DriverFlowSession('driver', 1);
    expect(
      () => DriverFlowProgressTrip(
        session: session,
        targetId: 'trip',
        expectedVersion: 1,
        idempotencyToken: 'original',
        status: DriverTripLifecycleStatus.completed,
      ),
      throwsArgumentError,
    );
    expect(
      () => DriverFlowSetAvailability(
        session: session,
        targetId: 'driver',
        expectedVersion: 1,
        idempotencyToken: 'original',
        state: DriverAvailabilityState.reserved,
      ),
      throwsArgumentError,
    );
    final command = DriverFlowDecideOffer(
      session: session,
      targetId: 'offer',
      expectedVersion: 3,
      idempotencyToken: ' original-token ',
      decision: DriverFlowOfferDecision.accept,
    );
    expect(command.idempotencyToken, ' original-token ');
  });
  test('unconfigured source cannot carry fake journey data', () {
    expect(
      () => DriverFlowSnapshot(
        session: DriverFlowSession('driver', 1),
        revision: 1,
        phase: DriverFlowPhase.ready,
        source: DriverFlowSource.unconfigured,
        offer: driverFlowOffer(),
      ),
      throwsArgumentError,
    );
  });
}
