import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'helpers/fake_driver_flow_repository.dart';

void main() {
  late FakeDriverFlowRepository repository;
  late DateTime now;
  DriverFlowDecideOffer decision({
    String id = 'fake-offer',
    int version = 3,
    DriverFlowOfferDecision value = DriverFlowOfferDecision.accept,
  }) =>
      DriverFlowDecideOffer(
        session: repository.current.session,
        targetId: id,
        expectedVersion: version,
        idempotencyToken: 'original-token',
        decision: value,
      );
  setUp(() {
    now = driverFlowTestTime;
    repository = FakeDriverFlowRepository(
      driverFlowSnapshot(offer: driverFlowOffer()),
      now: () => now,
    );
  });
  tearDown(() => repository.dispose());

  test('B04 lost decline remains uncertain across equivalent reads and events',
      () async {
    final command = decision(value: DriverFlowOfferDecision.decline);
    expect(
        (await repository.execute(command)).outcome, DriverFlowOutcome.unknown);
    repository.emit(driverFlowSnapshot(revision: 5, offer: driverFlowOffer()));
    expect((await repository.read(command.session)).snapshot!.phase,
        DriverFlowPhase.unknown);
    expect((await repository.execute(decision())).outcome,
        DriverFlowOutcome.stale);
    expect(repository.commands, hasLength(1));
    expect(repository.commands.single.idempotencyToken, 'original-token');
  });

  test('B04 pending decline expiry rejects late simulated success', () async {
    final reply = Completer<DriverFlowResult>();
    repository.nextCommand = reply.future;
    final pending =
        repository.execute(decision(value: DriverFlowOfferDecision.decline));
    now = repository.current.offer!.expiresAt;
    expect((await repository.read(repository.current.session)).snapshot!.phase,
        DriverFlowPhase.unknown);
    reply.complete(DriverFlowResult(
        DriverFlowOutcome.simulated, driverFlowSnapshot(revision: 9)));
    expect((await pending).outcome, DriverFlowOutcome.unknown);
    expect(repository.current.phase, DriverFlowPhase.unknown);
  });

  test('read and watch do not dispatch commands', () async {
    final events = <DriverFlowSnapshot>[];
    final subscription =
        repository.watch(repository.current.session).listen(events.add);
    await repository.read(repository.current.session);
    expect(
      repository.emit(
        driverFlowSnapshot(revision: 2, phase: DriverFlowPhase.unavailable),
      ),
      isTrue,
    );
    expect(events.single.phase, DriverFlowPhase.unavailable);
    expect(repository.commands, isEmpty);
    await subscription.cancel();
  });
  test('duplicate and older events cannot replace a current offer', () {
    expect(
      repository.emit(
        driverFlowSnapshot(
          revision: 2,
          offer: driverFlowOffer(id: 'new-offer'),
        ),
      ),
      isTrue,
    );
    expect(
      repository.emit(
        driverFlowSnapshot(revision: 2, offer: driverFlowOffer()),
      ),
      isFalse,
    );
    expect(repository.emit(driverFlowSnapshot(revision: 1)), isFalse);
    expect(repository.current.offer!.id, 'new-offer');
  });
  test('wrong offer identity/version and no offer never dispatch', () async {
    expect(
      (await repository.execute(decision(id: 'foreign'))).outcome,
      DriverFlowOutcome.stale,
    );
    expect(
      (await repository.execute(decision(version: 2))).outcome,
      DriverFlowOutcome.stale,
    );
    repository.emit(driverFlowSnapshot(revision: 2));
    expect(
      (await repository.execute(decision())).outcome,
      DriverFlowOutcome.stale,
    );
    expect(repository.commands, isEmpty);
  });
  test(
    'injected clock expires accept and decline exactly at deadline',
    () async {
      now = repository.current.offer!.expiresAt;
      for (final value in DriverFlowOfferDecision.values) {
        expect(
          (await repository.execute(decision(value: value))).outcome,
          DriverFlowOutcome.expired,
        );
      }
      expect(repository.commands, isEmpty);
    },
  );
  test(
    'lost response stays unknown without assignment or replay on read',
    () async {
      final original = repository.current;
      expect(
        (await repository.execute(decision())).outcome,
        DriverFlowOutcome.unknown,
      );
      await repository.read(original.session);
      expect(repository.current.phase, DriverFlowPhase.unknown);
      expect(repository.current.offer, same(original.offer));
      expect(repository.current.session.sameSession(original.session), isTrue);
      expect(repository.current.trip, isNull);
      expect(repository.commands.single.idempotencyToken, 'original-token');
      expect(() => repository.commands.clear(), throwsUnsupportedError);
    },
  );
  test(
    'pending command does not synthesize assignment; late result stays stale',
    () async {
      final response = Completer<DriverFlowResult>();
      repository.nextCommand = response.future;
      final pending = repository.execute(decision());
      expect(repository.current.trip, isNull);
      repository.emit(
        driverFlowSnapshot(
          revision: 3,
          offer: driverFlowOffer(id: 'replacement'),
        ),
      );
      response.complete(
        DriverFlowResult(
          DriverFlowOutcome.simulated,
          driverFlowSnapshot(revision: 2),
        ),
      );
      expect((await pending).outcome, DriverFlowOutcome.stale);
      expect(repository.current.offer!.id, 'replacement');
    },
  );
  test(
    'scripted acceptance is simulation only and never canonical evidence',
    () async {
      repository.nextCommand = Future.value(
        DriverFlowResult(
          DriverFlowOutcome.simulated,
          driverFlowSnapshot(
            revision: 2,
            trip: DriverFlowTrip(
              id: 'fake-trip',
              version: 1,
              status: DriverTripLifecycleStatus.accepted,
              journey: driverFlowJourney(),
            ),
          ),
        ),
      );
      final result = await repository.execute(decision());
      expect(result.outcome, DriverFlowOutcome.simulated);
      expect(result.snapshot!.source, DriverFlowSource.simulated);
      expect(result.snapshot!.trip!.status, DriverTripLifecycleStatus.accepted);
    },
  );
  for (final outcome in [
    DriverFlowOutcome.rejected,
    DriverFlowOutcome.unknown,
    DriverFlowOutcome.unavailable,
    DriverFlowOutcome.unsupported,
  ]) {
    test('scripted ${outcome.name} leaves assignment absent', () async {
      repository.nextCommand = Future.value(DriverFlowResult(outcome));
      expect(
          (await repository.execute(decision())).outcome,
          outcome == DriverFlowOutcome.unavailable
              ? DriverFlowOutcome.unknown
              : outcome);
      expect(repository.current.trip, isNull);
    });
  }
  test('read response cannot overwrite a newer event', () async {
    final response = Completer<DriverFlowSnapshot>();
    repository.nextRead = response.future;
    final pending = repository.read(repository.current.session);
    repository.emit(driverFlowSnapshot(revision: 4));
    response.complete(
      driverFlowSnapshot(revision: 2, offer: driverFlowOffer()),
    );
    expect((await pending).outcome, DriverFlowOutcome.stale);
    expect(repository.current.revision, 4);
  });
  for (final operation in ['read', 'command']) {
    test(
      'A-B-A replacement invalidates pending $operation and old subscriptions',
      () async {
        final old = repository.current.session;
        final events = <DriverFlowSnapshot>[];
        final subscription = repository.watch(old).listen(events.add);
        final response = Completer<DriverFlowSnapshot>();
        final commandResponse = Completer<DriverFlowResult>();
        repository.nextRead = response.future;
        repository.nextCommand = commandResponse.future;
        final pending = operation == 'read'
            ? repository.read(old)
            : repository.execute(decision());
        repository.replaceSession(DriverFlowSession('other-driver', 2));
        repository.replaceSession(DriverFlowSession(old.driverId, 3));
        response.complete(driverFlowSnapshot(revision: 2));
        commandResponse.complete(
          DriverFlowResult(
            DriverFlowOutcome.simulated,
            driverFlowSnapshot(
                revision: 2,
                trip: DriverFlowTrip(
                  id: 'retired-trip',
                  version: 1,
                  status: DriverTripLifecycleStatus.accepted,
                  journey: driverFlowJourney(),
                )),
          ),
        );
        final result = await pending;
        expect(result.outcome, DriverFlowOutcome.unauthorized);
        expect(result.snapshot, isNull);
        expect(repository.current.session.generation, 3);
        expect(repository.current.revision, 0);
        expect(repository.current.phase, DriverFlowPhase.loading);
        expect(repository.current.offer, isNull);
        expect(repository.current.trip, isNull);
        expect(repository.commands, hasLength(operation == 'read' ? 0 : 1));
        expect(repository.emit(driverFlowSnapshot(revision: 99)), isFalse);
        expect(events, isEmpty);
        expect(() => repository.replaceSession(old), throwsStateError);
        await subscription.cancel();
      },
    );
  }
  test(
    'availability command validates version and never overrides reservations',
    () async {
      repository.emit(
        driverFlowSnapshot(
          revision: 2,
          availability: DriverFlowAvailability(
            state: DriverAvailabilityState.reserved,
            version: 8,
            vehicleId: 'vehicle',
            bookingId: 'booking',
          ),
        ),
      );
      DriverFlowSetAvailability command(int version) =>
          DriverFlowSetAvailability(
            session: repository.current.session,
            targetId: repository.current.session.driverId,
            expectedVersion: version,
            idempotencyToken: 'availability-token',
            state: DriverAvailabilityState.offline,
          );
      expect(
        (await repository.execute(command(7))).outcome,
        DriverFlowOutcome.stale,
      );
      expect(
        (await repository.execute(command(8))).outcome,
        DriverFlowOutcome.rejected,
      );
      repository.emit(
        driverFlowSnapshot(
          revision: 3,
          availability: DriverFlowAvailability(
            state: DriverAvailabilityState.offline,
            version: 9,
          ),
        ),
      );
      expect(
        (await repository.execute(command(9))).outcome,
        DriverFlowOutcome.unknown,
      );
      expect(
        repository.current.availability!.state,
        DriverAvailabilityState.offline,
      );
    },
  );
  test(
    'Trip command uses Trip version and rejects skipped progression',
    () async {
      repository.emit(
        driverFlowSnapshot(
          revision: 2,
          trip: DriverFlowTrip(
            id: 'trip',
            version: 9,
            status: DriverTripLifecycleStatus.accepted,
            journey: driverFlowJourney(),
          ),
        ),
      );
      DriverFlowProgressTrip command(
              int version, DriverTripLifecycleStatus status) =>
          DriverFlowProgressTrip(
            session: repository.current.session,
            targetId: 'trip',
            expectedVersion: version,
            idempotencyToken: 'trip-token',
            status: status,
          );
      expect(
        (await repository.execute(
          command(3, DriverTripLifecycleStatus.driverArriving),
        ))
            .outcome,
        DriverFlowOutcome.stale,
      );
      expect(
        (await repository
                .execute(command(9, DriverTripLifecycleStatus.inProgress)))
            .outcome,
        DriverFlowOutcome.rejected,
      );
      expect(
        (await repository.execute(
          command(9, DriverTripLifecycleStatus.driverArriving),
        ))
            .outcome,
        DriverFlowOutcome.unknown,
      );
      expect(
          repository.current.trip!.status, DriverTripLifecycleStatus.accepted);
    },
  );
  test('unauthorized state prevents dispatch', () async {
    repository.emit(
      driverFlowSnapshot(
        revision: 2,
        phase: DriverFlowPhase.unauthorized,
        offer: driverFlowOffer(),
      ),
    );
    expect(
      (await repository.execute(decision())).outcome,
      DriverFlowOutcome.unauthorized,
    );
    expect(repository.commands, isEmpty);
  });
  test(
      'transport timeout is unknown; failed read is unavailable without replay',
      () async {
    repository.nextCommand = Future.error(TimeoutException('private detail'));
    expect((await repository.execute(decision())).outcome,
        DriverFlowOutcome.unknown);
    repository.nextRead = Future.error(StateError('private detail'));
    expect((await repository.read(repository.current.session)).outcome,
        DriverFlowOutcome.unavailable);
    expect(repository.current.trip, isNull);
    expect(repository.commands, hasLength(1));
  });
  test('foreign scripted response cannot publish into the current session',
      () async {
    repository.nextCommand = Future.value(DriverFlowResult(
        DriverFlowOutcome.simulated,
        driverFlowSnapshot(
            session: DriverFlowSession('other-driver', 1), revision: 2)));
    expect((await repository.execute(decision())).outcome,
        DriverFlowOutcome.stale);
    expect(repository.current.revision, 1);
  });
  test('disposing an owner invalidates a pending command', () async {
    final response = Completer<DriverFlowResult>();
    repository.nextCommand = response.future;
    final pending = repository.execute(decision());
    await repository.dispose();
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated, driverFlowSnapshot(revision: 2)));
    expect((await pending).outcome, DriverFlowOutcome.unauthorized);
    expect(repository.current.trip, isNull);
  });
  for (final phase in DriverFlowPhase.values) {
    test(
        '${phase.name} is observable through watch and read with safe dispatch',
        () async {
      final session = repository.current.session;
      final events = <DriverFlowSnapshot>[];
      final subscription = repository.watch(session).listen(events.add);
      addTearDown(subscription.cancel);
      final snapshot = driverFlowSnapshot(
        revision: 2,
        phase: phase,
        offer: driverFlowOffer(),
      );
      expect(repository.emit(snapshot), isTrue);
      expect(events.single, same(snapshot));
      final read = await repository.read(session);
      expect(read.outcome, DriverFlowOutcome.observed);
      expect(read.snapshot, same(snapshot));
      expect(read.snapshot!.phase, phase);
      expect(read.snapshot!.source, DriverFlowSource.simulated);
      expect(read.snapshot!.offer!.id, 'fake-offer');
      expect(read.snapshot!.trip, isNull);
      expect(repository.commands, isEmpty);
      final result = await repository.execute(decision());
      expect(
          result.outcome,
          phase == DriverFlowPhase.ready
              ? DriverFlowOutcome.unknown
              : phase == DriverFlowPhase.unauthorized
                  ? DriverFlowOutcome.unauthorized
                  : DriverFlowOutcome.stale);
      expect(repository.commands,
          hasLength(phase == DriverFlowPhase.ready ? 1 : 0));
      if (phase == DriverFlowPhase.ready) {
        expect(repository.current.phase, DriverFlowPhase.unknown);
        expect(repository.current.offer, same(snapshot.offer));
        expect(events.last, same(repository.current));
        expect(events, hasLength(2));
      } else {
        expect(repository.current, same(snapshot));
        expect(events, hasLength(1));
      }
    });
  }

  for (final status in DriverTripLifecycleStatus.values) {
    test('${status.name} Trip is independently observable without authority',
        () async {
      final session = repository.current.session;
      final events = <DriverFlowSnapshot>[];
      final subscription = repository.watch(session).listen(events.add);
      addTearDown(subscription.cancel);
      final trip = DriverFlowTrip(
          id: 'observed-trip',
          version: 17,
          status: status,
          journey: driverFlowJourney());
      final snapshot = driverFlowSnapshot(revision: 2, trip: trip);
      expect(repository.emit(snapshot), isTrue);
      expect(events.single.trip, same(trip));
      final result = await repository.read(session);
      expect(result.outcome, DriverFlowOutcome.observed);
      expect(result.snapshot, same(snapshot));
      expect(result.snapshot!.source, DriverFlowSource.simulated);
      expect(result.snapshot!.trip!.status, status);
      expect(result.snapshot!.trip!.id, 'observed-trip');
      expect(result.snapshot!.trip!.version, 17);
      expect(result.snapshot!.offer, isNull);
      expect(repository.commands, isEmpty);
    });
  }

  for (final terminal in [
    DriverTripLifecycleStatus.completed,
    DriverTripLifecycleStatus.cancelledByRider,
    DriverTripLifecycleStatus.cancelledByDriver,
    DriverTripLifecycleStatus.cancelledByAdmin,
    DriverTripLifecycleStatus.failed,
  ]) {
    test(
        '${terminal.name} rejects every supported progression without dispatch',
        () async {
      final snapshot = driverFlowSnapshot(
          revision: 2,
          trip: DriverFlowTrip(
              id: 'terminal-trip',
              version: 19,
              status: terminal,
              journey: driverFlowJourney()));
      repository.emit(snapshot);
      for (final next in [
        DriverTripLifecycleStatus.driverArriving,
        DriverTripLifecycleStatus.driverArrived,
        DriverTripLifecycleStatus.inProgress
      ]) {
        final result = await repository.execute(DriverFlowProgressTrip(
            session: snapshot.session,
            targetId: 'terminal-trip',
            expectedVersion: 19,
            idempotencyToken: 'terminal-intent',
            status: next));
        expect(result.outcome, DriverFlowOutcome.rejected);
        expect(result.snapshot, isNull);
      }
      expect(repository.current, same(snapshot));
      expect(repository.commands, isEmpty);
    });
  }

  test('successful simulated decline clears only the offer', () async {
    final offer = repository.current.offer!;
    final events = <DriverFlowSnapshot>[];
    final subscription =
        repository.watch(repository.current.session).listen(events.add);
    addTearDown(subscription.cancel);
    repository.nextCommand = Future.value(DriverFlowResult(
        DriverFlowOutcome.simulated, driverFlowSnapshot(revision: 2)));
    final result = await repository
        .execute(decision(value: DriverFlowOfferDecision.decline));
    expect(result.outcome, DriverFlowOutcome.simulated);
    expect(result.snapshot, same(repository.current));
    expect(result.snapshot!.source, DriverFlowSource.simulated);
    expect(result.snapshot!.offer, isNull);
    expect(result.snapshot!.trip, isNull);
    expect(events.single, same(result.snapshot));
    expect(repository.commands.single.targetId, offer.id);
    expect(repository.commands.single.expectedVersion, offer.version);
    expect((repository.commands.single as DriverFlowDecideOffer).decision,
        DriverFlowOfferDecision.decline);
    expect(repository.commands.single.idempotencyToken, 'original-token');
  });

  for (final lateOutcome in [
    DriverFlowOutcome.simulated,
    DriverFlowOutcome.rejected,
    DriverFlowOutcome.unknown
  ]) {
    test(
        'pending accept crossing expiry stays unresolved after late ${lateOutcome.name}',
        () async {
      final session = repository.current.session;
      final offer = repository.current.offer!;
      final response = Completer<DriverFlowResult>();
      final events = <DriverFlowSnapshot>[];
      final subscription = repository.watch(session).listen(events.add);
      addTearDown(subscription.cancel);
      repository.nextCommand = response.future;
      final pending = repository.execute(decision());
      now = offer.expiresAt.subtract(const Duration(microseconds: 1));
      expect((await repository.read(session)).snapshot!.phase,
          DriverFlowPhase.ready);
      expect(events, isEmpty);
      now = offer.expiresAt;
      final unresolved = await repository.read(session);
      expect(unresolved.snapshot!.phase, DriverFlowPhase.unknown);
      expect(unresolved.snapshot!.offer, same(offer));
      expect(unresolved.snapshot!.trip, isNull);
      expect(events.single.phase, DriverFlowPhase.unknown);
      expect(events.single.source, DriverFlowSource.simulated);
      // Even a scripted command success is not an authoritative assignment read.
      response.complete(DriverFlowResult(
          lateOutcome,
          lateOutcome == DriverFlowOutcome.simulated
              ? driverFlowSnapshot(
                  revision: 3,
                  trip: DriverFlowTrip(
                      id: 'late-trip',
                      version: 1,
                      status: DriverTripLifecycleStatus.accepted,
                      journey: driverFlowJourney()))
              : null));
      final result = await pending;
      expect(result.outcome, DriverFlowOutcome.unknown);
      expect(result.snapshot, same(unresolved.snapshot));
      expect(repository.current.trip, isNull);
      expect((await repository.read(session)).snapshot!.phase,
          DriverFlowPhase.unknown);
      expect((await repository.execute(decision())).outcome,
          DriverFlowOutcome.stale);
      expect(repository.commands, hasLength(1));
      expect(repository.commands.single.idempotencyToken, 'original-token');
      expect(events, hasLength(1));
      // A separate, explicit observation can resolve a scripted scenario only.
      final observedTrip = DriverFlowTrip(
          id: 'reread-trip',
          version: 4,
          status: DriverTripLifecycleStatus.accepted,
          journey: driverFlowJourney());
      expect(
          repository.observeAcceptanceOutcome(
              driverFlowSnapshot(revision: 4, trip: observedTrip)),
          isTrue);
      final reread = await repository.read(session);
      expect(reread.snapshot!.phase, DriverFlowPhase.ready);
      expect(reread.snapshot!.trip, same(observedTrip));
      expect(reread.snapshot!.source, DriverFlowSource.simulated);
      expect(repository.commands, hasLength(1));
    });
  }

  test(
      'response crossing expiry without an intervening read also stays unknown',
      () async {
    final response = Completer<DriverFlowResult>();
    repository.nextCommand = response.future;
    final pending = repository.execute(decision());
    now = repository.current.offer!.expiresAt;
    response.complete(const DriverFlowResult(DriverFlowOutcome.rejected));
    expect((await pending).outcome, DriverFlowOutcome.unknown);
    expect(repository.current.phase, DriverFlowPhase.unknown);
    expect(repository.current.trip, isNull);
    expect(repository.commands, hasLength(1));
  });

  test('delayed read after disposal cannot publish a snapshot', () async {
    final original = repository.current;
    final events = <DriverFlowSnapshot>[];
    final subscription = repository.watch(original.session).listen(events.add);
    final response = Completer<DriverFlowSnapshot>();
    repository.nextRead = response.future;
    final pending = repository.read(original.session);
    await repository.dispose();
    response.complete(driverFlowSnapshot(
        revision: 99,
        trip: DriverFlowTrip(
            id: 'retired-trip',
            version: 1,
            status: DriverTripLifecycleStatus.accepted,
            journey: driverFlowJourney())));
    final result = await pending;
    expect(result.outcome, DriverFlowOutcome.unauthorized);
    expect(result.snapshot, isNull);
    expect(repository.current, same(original));
    expect(events, isEmpty);
    expect(repository.commands, isEmpty);
    await subscription.cancel();
  });
  test('reconstructed equivalent offer preserves pending expiry uncertainty',
      () async {
    final original = repository.current.offer!;
    final session = repository.current.session;
    final response = Completer<DriverFlowResult>();
    repository.nextCommand = response.future;
    final pending = repository.execute(decision());
    try {
      final rebuilt = driverFlowOffer(expiresAt: original.expiresAt);
      expect(rebuilt, isNot(same(original)));
      expect(repository.emit(driverFlowSnapshot(revision: 2, offer: rebuilt)),
          isTrue);
      now = original.expiresAt;
      final read = await repository.read(session);
      expect(read.snapshot!.phase, DriverFlowPhase.unknown);
      expect(read.snapshot!.offer!.id, original.id);
      expect(read.snapshot!.offer!.version, original.version);
      expect(read.snapshot!.trip, isNull);
    } finally {
      response.complete(DriverFlowResult(
          DriverFlowOutcome.simulated,
          driverFlowSnapshot(
              revision: 9,
              trip: DriverFlowTrip(
                  id: 'late-trip',
                  version: 1,
                  status: DriverTripLifecycleStatus.accepted,
                  journey: driverFlowJourney()))));
    }
    final result = await pending;
    expect(result.outcome, DriverFlowOutcome.unknown);
    expect(repository.current.phase, DriverFlowPhase.unknown);
    expect(repository.current.trip, isNull);
  });

  for (final atExpiry in [false, true]) {
    for (final lateOutcome in [
      DriverFlowOutcome.simulated,
      DriverFlowOutcome.rejected,
      DriverFlowOutcome.unknown
    ]) {
      test(
          'equivalent reobservation atExpiry=$atExpiry late=$lateOutcome stays unresolved',
          () async {
        final original = repository.current.offer!;
        final session = repository.current.session;
        final events = <DriverFlowSnapshot>[];
        final subscription = repository.watch(session).listen(events.add);
        addTearDown(subscription.cancel);
        final response = Completer<DriverFlowResult>();
        repository.nextCommand = response.future;
        final pending = repository.execute(decision());
        now = atExpiry
            ? original.expiresAt
            : original.expiresAt.subtract(const Duration(microseconds: 1));
        final rebuilt =
            driverFlowOffer(expiresAt: original.expiresAt.toLocal());
        expect(rebuilt, isNot(same(original)));
        expect(rebuilt.journey, isNot(same(original.journey)));
        expect(repository.emit(driverFlowSnapshot(revision: 7, offer: rebuilt)),
            isTrue);
        expect(repository.current.phase,
            atExpiry ? DriverFlowPhase.unknown : DriverFlowPhase.pending);
        expect(events.single.phase, repository.current.phase);
        expect(repository.current.revision, 7);
        expect(repository.current.offer, same(rebuilt));
        expect(
            repository.emit(driverFlowSnapshot(revision: 7, offer: original)),
            isFalse);
        expect(
            repository.emit(driverFlowSnapshot(revision: 6, offer: original)),
            isFalse);
        expect(events, hasLength(1));
        // Another equivalent higher revision cannot reset pending state.
        repository
            .emit(driverFlowSnapshot(revision: 8, offer: driverFlowOffer()));
        expect(repository.current.phase,
            atExpiry ? DriverFlowPhase.unknown : DriverFlowPhase.pending);
        now = original.expiresAt;
        final read = await repository.read(session);
        expect(read.snapshot!.phase, DriverFlowPhase.unknown);
        expect(read.snapshot!.source, DriverFlowSource.simulated);
        expect(read.snapshot!.trip, isNull);
        response.complete(DriverFlowResult(
            lateOutcome,
            lateOutcome == DriverFlowOutcome.simulated
                ? driverFlowSnapshot(
                    revision: 99,
                    trip: DriverFlowTrip(
                        id: 'late-trip',
                        version: 1,
                        status: DriverTripLifecycleStatus.accepted,
                        journey: driverFlowJourney()))
                : null));
        final result = await pending;
        expect(result.outcome, DriverFlowOutcome.unknown);
        expect(repository.current.trip, isNull);
        final nextRevision = repository.current.revision + 1;
        repository.emit(driverFlowSnapshot(
            revision: nextRevision, offer: driverFlowOffer()));
        expect(repository.current.phase, DriverFlowPhase.unknown);
        expect(events.last.phase, DriverFlowPhase.unknown);
        expect((await repository.read(session)).snapshot!.phase,
            DriverFlowPhase.unknown);
        expect((await repository.execute(decision())).outcome,
            DriverFlowOutcome.stale);
        expect(repository.commands, hasLength(1));
        expect(repository.commands.single.idempotencyToken, 'original-token');
      });
    }
  }

  for (final change in [
    'id',
    'version',
    'expiry',
    'booking',
    'quote',
    'vehicle',
    'vehicleLabel',
    'fare',
    'distance',
    'duration',
    'pickup',
    'destination',
    'stops'
  ]) {
    test('incompatible offer $change fails closed and retires late acceptance',
        () async {
      final original = repository.current.offer!;
      final j = original.journey;
      final response = Completer<DriverFlowResult>();
      repository.nextCommand = response.future;
      final pending = repository.execute(decision());
      final changed = DriverFlowOffer(
          id: change == 'id' ? 'different-offer' : original.id,
          version:
              change == 'version' ? original.version + 1 : original.version,
          bookingId:
              change == 'booking' ? 'different-booking' : original.bookingId,
          quoteId: change == 'quote' ? 'different-quote' : original.quoteId,
          expiresAt: change == 'expiry'
              ? original.expiresAt.add(const Duration(seconds: 1))
              : original.expiresAt,
          journey: DriverFlowJourney(
            pickup: change == 'pickup' ? j.destination : j.pickup,
            destination: change == 'destination' ? j.pickup : j.destination,
            vehicleId: change == 'vehicle' ? 'different-vehicle' : j.vehicleId,
            vehicleLabel:
                change == 'vehicleLabel' ? 'different-label' : j.vehicleLabel,
            lockedFareFils:
                change == 'fare' ? j.lockedFareFils + 1 : j.lockedFareFils,
            distanceMeters:
                change == 'distance' ? j.distanceMeters + 1 : j.distanceMeters,
            durationSeconds: change == 'duration'
                ? j.durationSeconds + 1
                : j.durationSeconds,
            stops: change == 'stops' ? [j.pickup] : j.stops,
          ));
      expect(repository.emit(driverFlowSnapshot(revision: 2, offer: changed)),
          isTrue);
      expect(repository.current.phase, DriverFlowPhase.stale);
      expect(repository.current.trip, isNull);
      expect((await repository.execute(decision())).outcome,
          DriverFlowOutcome.stale);
      response.complete(DriverFlowResult(
          DriverFlowOutcome.simulated,
          driverFlowSnapshot(
              revision: 99,
              trip: DriverFlowTrip(
                  id: 'late-trip',
                  version: 1,
                  status: DriverTripLifecycleStatus.accepted,
                  journey: j))));
      expect((await pending).outcome, DriverFlowOutcome.stale);
      repository
          .emit(driverFlowSnapshot(revision: 3, offer: driverFlowOffer()));
      expect(repository.current.phase, DriverFlowPhase.stale);
      expect(repository.current.trip, isNull);
      expect(repository.commands, hasLength(1));
      expect(repository.commands.single.expectedVersion, original.version);
    });
  }

  for (final assigned in [false, true]) {
    test(
        'explicit simulated outcome assigned=$assigned resolves unknown without authority',
        () async {
      final session = repository.current.session;
      expect((await repository.execute(decision())).outcome,
          DriverFlowOutcome.unknown);
      repository
          .emit(driverFlowSnapshot(revision: 3, offer: driverFlowOffer()));
      expect(repository.current.phase, DriverFlowPhase.unknown);
      final outcome = driverFlowSnapshot(
          revision: 4,
          trip: assigned
              ? DriverFlowTrip(
                  id: 'observed-trip',
                  version: 12,
                  status: DriverTripLifecycleStatus.accepted,
                  journey: driverFlowJourney())
              : null);
      expect(
          repository.observeAcceptanceOutcome(driverFlowSnapshot(
              revision: 4, session: DriverFlowSession('other-driver', 1))),
          isFalse);
      expect(
          repository.observeAcceptanceOutcome(driverFlowSnapshot(revision: 3)),
          isFalse);
      expect(
          repository.observeAcceptanceOutcome(
              driverFlowSnapshot(revision: 4, offer: driverFlowOffer())),
          isFalse);
      expect(repository.observeAcceptanceOutcome(outcome), isTrue);
      final read = await repository.read(session);
      expect(read.outcome, DriverFlowOutcome.observed);
      expect(read.snapshot, same(outcome));
      expect(read.snapshot!.phase, DriverFlowPhase.ready);
      expect(read.snapshot!.source, DriverFlowSource.simulated);
      expect(read.snapshot!.offer, isNull);
      if (assigned) {
        expect(read.snapshot!.trip!.id, 'observed-trip');
        expect(read.snapshot!.trip!.version, 12);
      } else {
        expect(read.snapshot!.trip, isNull);
      }
      expect(repository.commands, hasLength(1));
    });
  }

  test('reconstructed pending offer cannot survive session replacement',
      () async {
    final old = repository.current.session;
    final response = Completer<DriverFlowResult>();
    repository.nextCommand = response.future;
    final pending = repository.execute(decision());
    repository.emit(driverFlowSnapshot(revision: 2, offer: driverFlowOffer()));
    expect(repository.current.phase, DriverFlowPhase.pending);
    final replacement = DriverFlowSession(old.driverId, old.generation + 1);
    repository.replaceSession(replacement);
    repository.emit(
        driverFlowSnapshot(session: replacement, offer: driverFlowOffer()));
    final fresh = repository.current;
    now = driverFlowTestTime.add(const Duration(seconds: 31));
    expect(
        repository.emit(driverFlowSnapshot(
            session: old, revision: 99, offer: driverFlowOffer())),
        isFalse);
    expect(
        repository.observeAcceptanceOutcome(
            driverFlowSnapshot(session: old, revision: 100)),
        isFalse);
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        driverFlowSnapshot(
            session: old,
            revision: 101,
            trip: DriverFlowTrip(
                id: 'old-trip',
                version: 1,
                status: DriverTripLifecycleStatus.accepted,
                journey: driverFlowJourney()))));
    expect((await pending).outcome, DriverFlowOutcome.unauthorized);
    expect((await repository.read(replacement)).snapshot, same(fresh));
    expect(repository.current.phase, DriverFlowPhase.ready);
    expect(repository.current.trip, isNull);
    expect(repository.commands.single.session.sameSession(old), isTrue);
  });

  for (final state in DriverAvailabilityState.values) {
    test('availability $state read/watch values and references remain isolated',
        () async {
      final session = repository.current.session;
      final other =
          FakeDriverFlowRepository(driverFlowSnapshot(), now: () => now);
      addTearDown(other.dispose);
      final untouched = other.current;
      final events = <DriverFlowSnapshot>[];
      final otherEvents = <DriverFlowSnapshot>[];
      final subscription = repository.watch(session).listen(events.add);
      final otherSubscription = other.watch(session).listen(otherEvents.add);
      addTearDown(subscription.cancel);
      addTearDown(otherSubscription.cancel);
      DriverFlowAvailability availability(int version, String suffix) =>
          DriverFlowAvailability(
              state: state,
              version: version,
              vehicleId: state == DriverAvailabilityState.offline
                  ? null
                  : 'vehicle-$suffix',
              bookingId: state == DriverAvailabilityState.reserved
                  ? 'booking-$suffix'
                  : null,
              tripId: state == DriverAvailabilityState.onTrip
                  ? 'trip-$suffix'
                  : null);
      final original = availability(21, 'first');
      final snapshot = driverFlowSnapshot(revision: 2, availability: original);
      expect(repository.emit(snapshot), isTrue);
      final read = await repository.read(session);
      expect(read.outcome, DriverFlowOutcome.observed);
      expect(events.single, same(snapshot));
      expect(read.snapshot!.availability, same(original));
      void check(DriverFlowAvailability value, int version, String suffix) {
        expect(value.state, state);
        expect(value.version, version);
        expect(
            value.vehicleId,
            state == DriverAvailabilityState.offline
                ? isNull
                : 'vehicle-$suffix');
        expect(
            value.bookingId,
            state == DriverAvailabilityState.reserved
                ? 'booking-$suffix'
                : isNull);
        expect(value.tripId,
            state == DriverAvailabilityState.onTrip ? 'trip-$suffix' : isNull);
      }

      check(events.single.availability!, 21, 'first');
      check(read.snapshot!.availability!, 21, 'first');
      final changed = availability(22, 'second');
      expect(
          repository
              .emit(driverFlowSnapshot(revision: 3, availability: changed)),
          isTrue);
      final secondRead = await repository.read(session);
      expect(secondRead.snapshot!.availability, same(changed));
      expect(secondRead.snapshot!.availability, isNot(same(original)));
      check(events.last.availability!, 22, 'second');
      check(secondRead.snapshot!.availability!, 22, 'second');
      check(read.snapshot!.availability!, 21, 'first');
      expect(repository.emit(snapshot), isFalse);
      expect(events, hasLength(2));
      expect((await other.read(session)).snapshot, same(untouched));
      expect(other.current.availability, isNull);
      expect(otherEvents, isEmpty);
      expect(repository.commands, isEmpty);
      expect(other.commands, isEmpty);
    });
  }
  for (final late in [
    DriverFlowOutcome.simulated,
    DriverFlowOutcome.rejected,
    DriverFlowOutcome.unknown
  ]) {
    test('separate outcome observation outranks pending late $late', () async {
      final session = repository.current.session;
      final response = Completer<DriverFlowResult>();
      repository.nextCommand = response.future;
      final pending = repository.execute(decision());
      repository
          .emit(driverFlowSnapshot(revision: 2, offer: driverFlowOffer()));
      now = repository.current.offer!.expiresAt;
      expect((await repository.read(session)).snapshot!.phase,
          DriverFlowPhase.unknown);
      final observation = driverFlowSnapshot(
          revision: 10,
          trip: DriverFlowTrip(
              id: 'independently-observed',
              version: 15,
              status: DriverTripLifecycleStatus.accepted,
              journey: driverFlowJourney()));
      expect(repository.observeAcceptanceOutcome(observation), isTrue);
      response.complete(DriverFlowResult(
          late,
          late == DriverFlowOutcome.simulated
              ? driverFlowSnapshot(
                  revision: 99,
                  trip: DriverFlowTrip(
                      id: 'different-late-trip',
                      version: 99,
                      status: DriverTripLifecycleStatus.accepted,
                      journey: driverFlowJourney()))
              : null));
      final result = await pending;
      expect(result.outcome, DriverFlowOutcome.stale);
      expect(result.snapshot, isNull);
      final read = await repository.read(session);
      expect(read.snapshot, same(observation));
      expect(read.snapshot!.phase, DriverFlowPhase.ready);
      expect(read.snapshot!.trip!.id, 'independently-observed');
      expect(read.snapshot!.trip!.version, 15);
      expect(read.snapshot!.source, DriverFlowSource.simulated);
      expect(repository.commands, hasLength(1));
    });
  }

  test('same-length stop reordering invalidates pending offer correlation',
      () async {
    final j = driverFlowJourney();
    DriverFlowJourney journey(bool reversed) => DriverFlowJourney(
        pickup: j.pickup,
        destination: j.destination,
        vehicleId: j.vehicleId,
        vehicleLabel: j.vehicleLabel,
        lockedFareFils: j.lockedFareFils,
        distanceMeters: j.distanceMeters,
        durationSeconds: j.durationSeconds,
        stops:
            reversed ? [j.destination, j.pickup] : [j.pickup, j.destination]);
    DriverFlowOffer offer(bool reversed) => DriverFlowOffer(
        id: 'fake-offer',
        bookingId: 'fake-booking',
        quoteId: 'fake-quote',
        version: 3,
        expiresAt: driverFlowTestTime.add(const Duration(seconds: 30)),
        journey: journey(reversed));
    repository.emit(driverFlowSnapshot(revision: 2, offer: offer(false)));
    final response = Completer<DriverFlowResult>();
    repository.nextCommand = response.future;
    final pending = repository.execute(decision());
    repository.emit(driverFlowSnapshot(revision: 3, offer: offer(true)));
    expect(repository.current.phase, DriverFlowPhase.stale);
    response.complete(const DriverFlowResult(DriverFlowOutcome.simulated));
    expect((await pending).outcome, DriverFlowOutcome.stale);
    expect(repository.current.trip, isNull);
    expect(repository.commands, hasLength(1));
  });
}
