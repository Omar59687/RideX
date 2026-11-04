import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

void main() {
  group('FakeRiderTripTrackingRepository lookups', () {
    test(
      'returns the exact seeded Trip by booking and Trip identity',
      () async {
        final trip = riderAssignedTripFixture();
        final repository = FakeRiderTripTrackingRepository(trip: trip);

        final byBooking = await repository.findByBooking(
          bookingRequestId: riderBookingIdFixture,
        );
        final byTrip = await repository.findByTrip(tripId: riderTripIdFixture);

        expect(byBooking, same(trip));
        expect(byTrip, same(trip));
        expect(repository.bookingLoadCount, 1);
        expect(repository.tripLoadCount, 1);
        expect(repository.requestedBookingIds, [riderBookingIdFixture]);
        expect(repository.requestedTripIds, [riderTripIdFixture]);
        await repository.close();
      },
    );

    test('matches canonical UUID identities case-insensitively', () async {
      final trip = riderAssignedTripFixture();
      final repository = FakeRiderTripTrackingRepository(trip: trip);

      expect(riderBookingIdFixture.toUpperCase(), isNot(riderBookingIdFixture));
      expect(riderTripIdFixture.toUpperCase(), isNot(riderTripIdFixture));

      expect(
        await repository.findByBooking(
          bookingRequestId: riderBookingIdFixture.toUpperCase(),
        ),
        same(trip),
      );
      expect(
        await repository.findByTrip(tripId: riderTripIdFixture.toUpperCase()),
        same(trip),
      );
      await repository.close();
    });

    test('returns null for absent or mismatched identities', () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );

      expect(
        await repository.findByBooking(
          bookingRequestId: '99999999-9999-4999-8999-999999999999',
        ),
        isNull,
      );
      expect(
        await repository.findByTrip(
          tripId: '99999999-9999-4999-8999-999999999999',
        ),
        isNull,
      );
      await repository.close();
    });

    test('does not hide typed lookup failures', () async {
      final bookingError = StateError('booking read failed');
      final tripError = StateError('trip read failed');
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      repository.bookingLoadError = bookingError;
      repository.tripLoadError = tripError;

      await expectLater(
        repository.findByBooking(bookingRequestId: riderBookingIdFixture),
        throwsA(same(bookingError)),
      );
      await expectLater(
        repository.findByTrip(tripId: riderTripIdFixture),
        throwsA(same(tripError)),
      );
      await repository.close();
    });

    test('rejects non-canonical lookup, watch, and session IDs', () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );

      await expectLater(
        repository.findByBooking(bookingRequestId: 'booking-1'),
        throwsArgumentError,
      );
      await expectLater(
        repository.findByTrip(tripId: 'trip-1'),
        throwsArgumentError,
      );
      expect(() => repository.watch(tripId: 'trip-1'), throwsArgumentError);
      expect(
        () => FakeRiderTripTrackingRepository(
          authenticatedRiderId: 'rider-1',
        ),
        throwsArgumentError,
      );
      await repository.close();
    });

    test('scopes reads and watches to the authenticated Rider', () async {
      final ownTrip = riderAssignedTripFixture();
      final otherTrip = riderAssignedTripFixture(
        tripId: secondaryRiderTripIdFixture,
        bookingRequestId: secondaryRiderBookingIdFixture,
        riderId: unrelatedRiderIdFixture,
      );
      final repository = FakeRiderTripTrackingRepository(
        trip: ownTrip,
        additionalTrips: [otherTrip],
      );

      expect(
          await repository.findByTrip(tripId: ownTrip.tripId), same(ownTrip));
      expect(await repository.findByTrip(tripId: otherTrip.tripId), isNull);
      expect(
        await repository.findByBooking(
          bookingRequestId: otherTrip.bookingRequestId,
        ),
        isNull,
      );
      await expectLater(repository.watch(tripId: otherTrip.tripId), emitsDone);
      await expectLater(
        repository.watch(tripId: '99999999-9999-4999-8999-999999999999'),
        emitsDone,
      );

      final otherSession = FakeRiderTripTrackingRepository(
        trip: otherTrip,
        authenticatedRiderId: unrelatedRiderIdFixture,
      );
      expect(
        await otherSession.findByTrip(tripId: otherTrip.tripId),
        same(otherTrip),
      );
      await repository.close();
      await otherSession.close();
    });

    test('stale references cannot read Trip data after disposal', () async {
      final trip = riderAssignedTripFixture();
      final repository = FakeRiderTripTrackingRepository(trip: trip);
      final staleReference = repository;
      repository.bookingLoadError = StateError('ignored after disposal');
      repository.tripLoadError = StateError('ignored after disposal');

      await repository.close();
      expect(
        await staleReference.findByBooking(
          bookingRequestId: trip.bookingRequestId,
        ),
        isNull,
      );
      expect(
        await staleReference.findByTrip(tripId: trip.tripId),
        isNull,
      );
      await expectLater(staleReference.watch(tripId: trip.tripId), emitsDone);
    });
  });

  group('FakeRiderTripTrackingRepository watch', () {
    test('does not invent an initial snapshot and releases canceled listeners',
        () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final received = <RiderTripTrackingEvent>[];
      final subscription =
          repository.watch(tripId: riderTripIdFixture).listen(received.add);

      await _flush();
      expect(received, isEmpty);
      expect(repository.hasListener, isTrue);
      await subscription.cancel();
      expect(repository.hasListener, isFalse);
      await repository.close();
    });

    test('isolates two simultaneous Trip watchers, including uppercase IDs',
        () async {
      final primary = riderAssignedTripFixture();
      final secondary = riderAssignedTripFixture(
        tripId: secondaryRiderTripIdFixture,
        bookingRequestId: secondaryRiderBookingIdFixture,
      );
      final repository = FakeRiderTripTrackingRepository(
        trip: primary,
        additionalTrips: [secondary],
      );
      final first = <RiderTripTrackingEvent>[];
      final second = <RiderTripTrackingEvent>[];
      final firstSubscription = repository
          .watch(tripId: primary.tripId.toUpperCase())
          .listen(first.add);
      final secondSubscription =
          repository.watch(tripId: secondary.tripId).listen(second.add);

      repository.emitSnapshot(primary);
      repository.emitSnapshot(secondary);
      repository.emit(RiderTripStatusChanged(
        tripId: primary.tripId.toUpperCase(),
        tripVersion: 4,
        eventSequence: 2,
        status: DriverTripLifecycleStatus.driverArriving,
        occurredAt: DateTime.utc(2026, 11, 4, 8, 10),
      ));
      repository.emit(RiderTripStatusChanged(
        tripId: secondary.tripId,
        tripVersion: 4,
        eventSequence: 2,
        status: DriverTripLifecycleStatus.driverArriving,
        occurredAt: DateTime.utc(2026, 11, 4, 8, 10),
      ));
      await _flush();
      await repository.close();

      expect(first.map((event) => event.tripId), [
        primary.tripId,
        primary.tripId.toUpperCase(),
      ]);
      expect(second.map((event) => event.tripId), [
        secondary.tripId,
        secondary.tripId,
      ]);
      await firstSubscription.cancel();
      await secondSubscription.cancel();
    });

    test('foreign delivery requires an explicit negative-test injection',
        () async {
      final primary = riderAssignedTripFixture();
      final secondary = riderAssignedTripFixture(
        tripId: secondaryRiderTripIdFixture,
        bookingRequestId: secondaryRiderBookingIdFixture,
      );
      final repository = FakeRiderTripTrackingRepository(
        trip: primary,
        additionalTrips: [secondary],
      );
      final received = <RiderTripTrackingEvent>[];
      final subscription =
          repository.watch(tripId: primary.tripId).listen(received.add);
      final foreign = RiderTripSnapshot(secondary);

      repository.emit(foreign);
      repository.emitSnapshot(
        riderAssignedTripFixture(riderId: unrelatedRiderIdFixture),
      );
      await _flush();
      expect(received, isEmpty);
      expect(
        () => repository.emitForeignFor(
          watchedTripId: primary.tripId,
          event: RiderTripSnapshot(primary),
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.emitForeignFor(
          watchedTripId: secondary.tripId,
          event: RiderTripSnapshot(primary),
        ),
        throwsStateError,
      );
      repository.emitForeignFor(watchedTripId: primary.tripId, event: foreign);
      await _flush();
      await repository.close();
      expect(received, hasLength(1));
      expect(received.single, same(foreign));
      await subscription.cancel();
    });

    test('stops normal delivery if the seeded Trip loses Rider ownership',
        () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final received = <RiderTripTrackingEvent>[];
      final subscription =
          repository.watch(tripId: riderTripIdFixture).listen(received.add);

      repository.trip =
          riderAssignedTripFixture(riderId: unrelatedRiderIdFixture);
      expect(await repository.findByTrip(tripId: riderTripIdFixture), isNull);
      repository.emitSnapshot();
      repository.emitStatus(
        tripVersion: 4,
        eventSequence: 2,
        status: DriverTripLifecycleStatus.driverArriving,
      );
      await repository.close();

      expect(received, isEmpty);
      await subscription.cancel();
    });

    test('drops an event queued before ownership changes', () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final received = <RiderTripTrackingEvent>[];
      final subscription =
          repository.watch(tripId: riderTripIdFixture).listen(received.add);

      repository.emitSnapshot();
      repository.trip =
          riderAssignedTripFixture(riderId: unrelatedRiderIdFixture);
      await _flush();

      expect(received, isEmpty);
      await subscription.cancel();
      await repository.close();
    });

    test('checks ownership separately when a paused subscriber resumes',
        () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final pausedEvents = <RiderTripTrackingEvent>[];
      final activeEvents = <RiderTripTrackingEvent>[];
      final activeDelivered = Completer<void>();
      final paused =
          repository.watch(tripId: riderTripIdFixture).listen(pausedEvents.add);
      final active =
          repository.watch(tripId: riderTripIdFixture).listen((event) {
        activeEvents.add(event);
        activeDelivered.complete();
      });
      paused.pause();

      repository.emitSnapshot();
      await activeDelivered.future;
      repository.trip =
          riderAssignedTripFixture(riderId: unrelatedRiderIdFixture);
      paused.resume();
      await _flush();

      expect(activeEvents, hasLength(1));
      expect(pausedEvents, isEmpty);
      await paused.cancel();
      await active.cancel();
      await repository.close();
    });

    test('keeps terminal Trip streams open until the listener disposes',
        () async {
      final terminal = riderAssignedTripFixture(
        status: DriverTripLifecycleStatus.completed,
      );
      final repository = FakeRiderTripTrackingRepository(trip: terminal);
      final received = <RiderTripTrackingEvent>[];
      final subscription =
          repository.watch(tripId: terminal.tripId).listen(received.add);

      expect((await repository.findByTrip(tripId: terminal.tripId))!.isTerminal,
          isTrue);
      repository.emitStatus(
        tripVersion: 4,
        eventSequence: 2,
        status: DriverTripLifecycleStatus.completed,
      );
      await _flush();
      expect(received, hasLength(1));
      expect(repository.hasListener, isTrue);
      await subscription.cancel();
      expect(repository.hasListener, isFalse);
      await repository.close();
    });

    test('broadcasts per-Trip events to every listener of that Trip', () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final first = <RiderTripTrackingEvent>[];
      final second = <RiderTripTrackingEvent>[];
      final firstSubscription =
          repository.watch(tripId: riderTripIdFixture).listen(first.add);
      final secondSubscription =
          repository.watch(tripId: riderTripIdFixture).listen(second.add);

      repository.emitSnapshot();
      await _flush();
      await firstSubscription.cancel();
      await secondSubscription.cancel();

      expect(repository.watchCount, 2);
      expect(repository.watchedTripIds, [
        riderTripIdFixture,
        riderTripIdFixture,
      ]);
      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(first.single, same(second.single));
      await repository.close();
    });

    test(
      'preserves deterministic ordering, duplicates, and out-of-order data',
      () async {
        final repository = FakeRiderTripTrackingRepository(
          trip: riderAssignedTripFixture(),
        );
        final received = <RiderTripTrackingEvent>[];
        final subscription =
            repository.watch(tripId: riderTripIdFixture).listen(received.add);

        repository.emitStatus(
          tripVersion: 4,
          eventSequence: 2,
          status: DriverTripLifecycleStatus.inProgress,
        );
        repository.emitStatus(
          tripVersion: 4,
          eventSequence: 1,
          status: DriverTripLifecycleStatus.driverArriving,
        );
        repository.emitStatus(
          tripVersion: 4,
          eventSequence: 2,
          status: DriverTripLifecycleStatus.inProgress,
        );
        await _flush();
        await subscription.cancel();

        final statuses = received.cast<RiderTripStatusChanged>();
        expect(statuses.map((event) => event.eventSequence), [2, 1, 2]);
        expect(statuses.map((event) => event.status), [
          DriverTripLifecycleStatus.inProgress,
          DriverTripLifecycleStatus.driverArriving,
          DriverTripLifecycleStatus.inProgress,
        ]);
        await repository.close();
      },
    );

    test('preserves duplicate and out-of-order location sequences', () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final received = <RiderTripTrackingEvent>[];
      final subscription =
          repository.watch(tripId: riderTripIdFixture).listen(received.add);

      repository.emitLocation(sample: _sample(sequence: 2));
      repository.emitLocation(sample: _sample(sequence: 1));
      repository.emitLocation(sample: _sample(sequence: 2));
      await _flush();
      await subscription.cancel();

      expect(
        received
            .cast<RiderTripLocationChanged>()
            .map((event) => event.locationSequence),
        [2, 1, 2],
      );
      await repository.close();
    });

    test('retains snapshots, locations, and disconnect evidence', () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final received = <RiderTripTrackingEvent>[];
      final subscription =
          repository.watch(tripId: riderTripIdFixture).listen(received.add);
      final sample = _sample(sequence: 2);

      repository.emitSnapshot();
      repository.emitLocation(sample: sample);
      repository.emitDisconnected(reason: 'network');
      await _flush();
      await subscription.cancel();

      expect(received, hasLength(3));
      expect(received[0], isA<RiderTripSnapshot>());
      expect(received[1], isA<RiderTripLocationChanged>());
      expect(received[2], isA<RiderTripTrackingDisconnected>());
      expect(
        (received[1] as RiderTripLocationChanged).locationSequence,
        sample.sequence,
      );
      expect((received[2] as RiderTripTrackingDisconnected).reason, 'network');
      await repository.close();
    });

    test('supports deterministic disconnect and reconnect snapshots', () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(version: 2),
      );
      final received = <RiderTripTrackingEvent>[];
      final subscription =
          repository.watch(tripId: riderTripIdFixture).listen(received.add);

      repository.emitSnapshot();
      repository.trip = riderAssignedTripFixture(
        version: 4,
        status: DriverTripLifecycleStatus.driverArriving,
      );
      repository.emitDisconnected(reason: 'reconnecting');
      repository.emitSnapshot();
      repository.emitSnapshot(riderAssignedTripFixture(version: 2));
      final canonical = await repository.findByTrip(tripId: riderTripIdFixture);
      await _flush();
      await subscription.cancel();

      expect((received[0] as RiderTripSnapshot).trip.version, 2);
      expect(
        (received[1] as RiderTripTrackingDisconnected).reason,
        'reconnecting',
      );
      expect((received[2] as RiderTripSnapshot).trip.version, 4);
      expect(
        (received[2] as RiderTripSnapshot).trip.status,
        DriverTripLifecycleStatus.driverArriving,
      );
      expect((received[3] as RiderTripSnapshot).trip.version, 2);
      expect(canonical!.version, 4);
      await repository.close();
    });

    test('uses the injected clock for convenience emissions', () async {
      final now = DateTime.utc(2026, 11, 4, 9);
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
        clock: () => now,
      );
      final received = <RiderTripTrackingEvent>[];
      final subscription =
          repository.watch(tripId: riderTripIdFixture).listen(received.add);

      repository.emitStatus(
        tripVersion: 4,
        eventSequence: 1,
        status: DriverTripLifecycleStatus.inProgress,
      );
      repository.emitLocation(sample: _sample(sequence: 1));
      repository.emitDisconnected();
      await _flush();
      await subscription.cancel();

      expect((received[0] as RiderTripStatusChanged).occurredAt, now);
      expect((received[1] as RiderTripLocationChanged).receivedAt, now);
      expect(
        (received[2] as RiderTripTrackingDisconnected).disconnectedAt,
        now,
      );
      await repository.close();
    });

    test('requires a seeded Trip for convenience emissions', () async {
      final repository = FakeRiderTripTrackingRepository();

      expect(repository.emitSnapshot, throwsStateError);
      expect(
        () => repository.emitStatus(
          tripVersion: 1,
          eventSequence: 1,
          status: DriverTripLifecycleStatus.accepted,
        ),
        throwsStateError,
      );
      expect(
        () => repository.emitLocation(sample: _sample(sequence: 1)),
        throwsStateError,
      );
      expect(repository.emitDisconnected, throwsStateError);
      await repository.close();
    });

    test('closes idempotently and rejects later emissions', () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );

      await repository.close();
      expect(repository.isClosed, isTrue);
      expect(repository.emitSnapshot, throwsStateError);
      await repository.close();
      await expectLater(
        repository.watch(tripId: riderTripIdFixture),
        emitsDone,
      );
    });

    test('closes an active listener without delivering queued events',
        () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final done = Completer<void>();
      final received = <RiderTripTrackingEvent>[];
      final subscription = repository.watch(tripId: riderTripIdFixture).listen(
            received.add,
            onDone: () => done.complete(),
          );

      repository.emitSnapshot();
      await repository.close();
      await done.future;
      expect(received, isEmpty);
      expect(repository.isClosed, isTrue);
      expect(repository.hasListener, isFalse);
      await subscription.cancel();
    });

    test('starts every Trip shutdown even when another listener is paused',
        () async {
      final primary = riderAssignedTripFixture();
      final secondary = riderAssignedTripFixture(
        tripId: secondaryRiderTripIdFixture,
        bookingRequestId: secondaryRiderBookingIdFixture,
      );
      final repository = FakeRiderTripTrackingRepository(
        trip: primary,
        additionalTrips: [secondary],
      );
      final paused = repository.watch(tripId: primary.tripId).listen((_) {});
      final secondDone = Completer<void>();
      final second = repository.watch(tripId: secondary.tripId).listen(
            (_) {},
            onDone: () => secondDone.complete(),
          );
      paused.pause();
      repository.emitSnapshot(primary);

      final closing = repository.close();
      expect(identical(repository.close(), closing), isTrue);
      expect(
        await repository.findByTrip(tripId: primary.tripId),
        isNull,
      );
      await secondDone.future;
      var finished = false;
      closing.then((_) => finished = true);
      await _flush();
      expect(finished, isFalse);

      await paused.cancel();
      await closing;
      expect(finished, isTrue);
      expect(identical(repository.close(), closing), isTrue);
      await second.cancel();
    });
  });
}

DriverLocationSample _sample({required int sequence}) {
  return DriverLocationSample(
    point: LocationPoint(
      latitude: 31.9539,
      longitude: 35.9106,
      accuracyMeters: 8,
    ),
    sequence: sequence,
    recordedAt: DateTime.utc(2026, 11, 4, 8, 30),
    tripId: riderTripIdFixture,
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
