import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_availability_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_flow_repository_provider.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_incoming_offer_controller.dart';
import 'helpers/fake_driver_flow_repository.dart';

DriverFlowOffer offerFixture(
    {String id = 'offer-a',
    int version = 1,
    int seconds = 30,
    int fare = 1990,
    bool stops = false}) {
  final j = driverFlowJourney();
  return DriverFlowOffer(
      id: id,
      bookingId: 'booking',
      quoteId: 'quote',
      version: version,
      expiresAt: driverFlowTestTime.add(Duration(seconds: seconds)),
      journey: DriverFlowJourney(
          pickup: j.pickup,
          destination: j.destination,
          vehicleId: j.vehicleId,
          vehicleLabel: j.vehicleLabel,
          lockedFareFils: fare,
          distanceMeters: j.distanceMeters,
          durationSeconds: j.durationSeconds,
          stops: stops ? [j.destination, j.pickup] : []));
}

final offerTestScope = StateProvider<DriverAvailabilityScope?>((ref) =>
    DriverAvailabilityScope(
        DriverFlowSession('fake-driver', 1), 'fake-vehicle'));
final offerTestRepository = StateProvider<DriverFlowRepository?>((ref) => null);

void main() {
  late DateTime now;
  late FakeDriverFlowRepository fake;
  late ProviderContainer container;
  DriverIncomingOfferView view() => container.read(driverIncomingOfferProvider);
  DriverIncomingOfferController controller() =>
      container.read(driverIncomingOfferProvider.notifier);
  Future<void> settle() async {
    container.read(driverIncomingOfferProvider);
    await container.pump();
    await Future<void>.value();
  }

  setUp(() {
    now = driverFlowTestTime;
    fake = FakeDriverFlowRepository(driverFlowSnapshot(offer: offerFixture()),
        now: () => now);
    container = ProviderContainer(overrides: [
      driverAvailabilityScopeProvider
          .overrideWith((ref) => ref.watch(offerTestScope)),
      driverFlowRepositoryProvider
          .overrideWith((ref) => ref.watch(offerTestRepository) ?? fake),
      driverOfferClockProvider.overrideWithValue(() => now),
    ]);
    container.read(driverIncomingOfferProvider);
  });
  tearDown(() async {
    container.dispose();
    await fake.dispose();
  });

  test('observes offer without command dispatch', () async {
    expect(view().status, IncomingOfferStatus.loading);
    await settle();
    expect(view().offer!.id, 'offer-a');
    expect(view().remainingSeconds, 30);
    expect(fake.commands, isEmpty);
  });
  for (final expired in [false, true]) {
    test('unfiltered lower offer version cannot replace v2 expired=$expired',
        () async {
      final raw = UnfilteredOfferRepository(
          driverFlowSnapshot(offer: offerFixture(version: 2)));
      addTearDown(raw.dispose);
      container.read(offerTestRepository.notifier).state = raw;
      await settle();
      final original = view().offer;
      if (expired) {
        now = now.add(const Duration(seconds: 30));
        controller().updateTime();
      }
      raw.emit(driverFlowSnapshot(
          revision: 2,
          offer: offerFixture(version: 1, seconds: 90, fare: 1001)));
      expect(view().offer, same(original));
      expect(view().offer!.version, 2);
      expect(view().status, isNot(IncomingOfferStatus.offer));
      expect(view().status, isNot(IncomingOfferStatus.replaced));
      if (expired) expect(view().remainingSeconds, 0);
      expect(raw.commands, isEmpty);
    });
  }
  test('ceil countdown and exact deadline cannot revive after clock rollback',
      () async {
    await settle();
    now = now.add(const Duration(milliseconds: 29500));
    controller().updateTime();
    expect(view().remainingSeconds, 1);
    now = now.add(const Duration(milliseconds: 500));
    controller().updateTime();
    expect(view().status, IncomingOfferStatus.expired);
    expect(view().remainingSeconds, 0);
    now = driverFlowTestTime;
    controller().updateTime();
    fake.emit(driverFlowSnapshot(revision: 2, offer: offerFixture()));
    expect(view().status, IncomingOfferStatus.expired);
    expect(fake.commands, isEmpty);
  });
  test(
      'unfiltered upgrade, reconstructed equivalent and conflict preserve rules',
      () async {
    final raw =
        UnfilteredOfferRepository(driverFlowSnapshot(offer: offerFixture()));
    addTearDown(raw.dispose);
    container.read(offerTestRepository.notifier).state = raw;
    await settle();
    raw.emit(driverFlowSnapshot(revision: 2, offer: offerFixture(version: 2)));
    expect(view().status, IncomingOfferStatus.replaced);
    final upgraded = view().offer;
    raw.emit(driverFlowSnapshot(revision: 3, offer: offerFixture(version: 2)));
    expect(view().offer, same(upgraded));
    expect(view().status, IncomingOfferStatus.offer);
    raw.emit(driverFlowSnapshot(
        revision: 4, offer: offerFixture(version: 2, fare: 1001)));
    expect(view().status, IncomingOfferStatus.stale);
    expect(view().offer, same(upgraded));
    raw.emit(driverFlowSnapshot(revision: 5, offer: offerFixture(version: 2)));
    expect(view().status, IncomingOfferStatus.stale);
    expect(raw.commands, isEmpty);
  });
  test('unfiltered offer IDs have independent high-water versions', () async {
    final raw = UnfilteredOfferRepository(
        driverFlowSnapshot(offer: offerFixture(version: 2)));
    addTearDown(raw.dispose);
    container.read(offerTestRepository.notifier).state = raw;
    await settle();
    raw.emit(
        driverFlowSnapshot(revision: 2, offer: offerFixture(id: 'offer-b')));
    expect(view().offer!.id, 'offer-b');
    expect(view().offer!.version, 1);
    expect(view().status, IncomingOfferStatus.replaced);
    raw.emit(driverFlowSnapshot(revision: 3, offer: offerFixture()));
    expect(view().offer!.id, 'offer-b');
    expect(view().status, IncomingOfferStatus.stale);
    raw.emit(driverFlowSnapshot(revision: 4, offer: offerFixture(version: 3)));
    expect(view().offer!.version, 3);
    expect(view().status, IncomingOfferStatus.replaced);
    expect(raw.commands, isEmpty);
  });
  for (final phase in [
    DriverFlowPhase.ready,
    DriverFlowPhase.loading,
    DriverFlowPhase.unavailable
  ]) {
    test('unfiltered version barrier survives missing $phase data', () async {
      final raw = UnfilteredOfferRepository(
          driverFlowSnapshot(offer: offerFixture(version: 2)));
      addTearDown(raw.dispose);
      container.read(offerTestRepository.notifier).state = raw;
      await settle();
      raw.emit(driverFlowSnapshot(revision: 2, phase: phase));
      raw.emit(driverFlowSnapshot(
          revision: 3, offer: offerFixture(seconds: 90, fare: 1001)));
      expect(view().offer?.version, isNot(1));
      expect(view().status, isNot(IncomingOfferStatus.offer));
      expect(view().status, isNot(IncomingOfferStatus.replaced));
      expect(raw.commands, isEmpty);
    });
  }
  for (final boundary in ['session', 'repository']) {
    test('unfiltered $boundary replacement resets only retired version memory',
        () async {
      final raw = UnfilteredOfferRepository(
          driverFlowSnapshot(offer: offerFixture(version: 8)));
      addTearDown(raw.dispose);
      container.read(offerTestRepository.notifier).state = raw;
      await settle();
      final session = boundary == 'session'
          ? DriverFlowSession('driver-b', 2)
          : raw.current.session;
      final fresh = driverFlowSnapshot(session: session, offer: offerFixture());
      final other = UnfilteredOfferRepository(fresh);
      addTearDown(other.dispose);
      if (boundary == 'session') {
        raw.current = fresh;
        container.read(offerTestScope.notifier).state =
            DriverAvailabilityScope(session, 'vehicle');
      } else {
        container.read(offerTestRepository.notifier).state = other;
      }
      // Deliver queued old data without flushing the scope/repository change.
      raw.events.add(
          driverFlowSnapshot(revision: 99, offer: offerFixture(version: 99)));
      expect(view().offer, isNull);
      await settle();
      expect(view().offer!.version, 1);
      expect(view().status, IncomingOfferStatus.offer);
      expect(raw.commands, isEmpty);
      expect(other.commands, isEmpty);
    });
  }
  test(
      'unfiltered duplicate and older event revisions cannot change version memory',
      () async {
    final raw = UnfilteredOfferRepository(
        driverFlowSnapshot(offer: offerFixture(version: 2)));
    addTearDown(raw.dispose);
    container.read(offerTestRepository.notifier).state = raw;
    await settle();
    final original = view().offer;
    raw.emit(driverFlowSnapshot(revision: 5, offer: offerFixture(version: 2)));
    raw.emit(driverFlowSnapshot(revision: 4, offer: offerFixture(version: 9)));
    expect(view().offer, same(original));
    raw.emit(driverFlowSnapshot(revision: 6, offer: offerFixture()));
    expect(view().offer, same(original));
    raw.emit(
        driverFlowSnapshot(revision: 6, offer: offerFixture(id: 'offer-b')));
    expect(view().offer, same(original));
    raw.emit(driverFlowSnapshot(revision: 7, offer: offerFixture(version: 3)));
    expect(view().offer!.version, 3);
    expect(view().status, IncomingOfferStatus.replaced);
    expect(raw.commands, isEmpty);
  });
  test('reconstructed equivalent offer retains original object and expiry',
      () async {
    await settle();
    final original = view().offer;
    now = now.add(const Duration(seconds: 10));
    fake.emit(driverFlowSnapshot(revision: 2, offer: offerFixture()));
    expect(view().offer, same(original));
    expect(view().remainingSeconds, 20);
    expect(fake.emit(driverFlowSnapshot(revision: 2, offer: offerFixture())),
        isFalse);
    expect(view().remainingSeconds, 20);
  });
  for (final phase in [DriverFlowPhase.pending, DriverFlowPhase.unknown]) {
    test('equivalent ready cannot clear $phase uncertainty, including expiry',
        () async {
      await settle();
      fake.emit(
          driverFlowSnapshot(revision: 2, phase: phase, offer: offerFixture()));
      fake.emit(driverFlowSnapshot(revision: 3, offer: offerFixture()));
      expect(
          view().status,
          phase == DriverFlowPhase.pending
              ? IncomingOfferStatus.pending
              : IncomingOfferStatus.unknown);
      now = now.add(const Duration(seconds: 30));
      controller().updateTime();
      expect(view().status, IncomingOfferStatus.unknown);
      expect(fake.commands, isEmpty);
    });
  }
  for (final changed in ['expiry', 'fare', 'stops']) {
    test('incompatible $changed for same identity latches stale', () async {
      await settle();
      fake.emit(driverFlowSnapshot(
          revision: 2,
          offer: offerFixture(
              seconds: changed == 'expiry' ? 90 : 30,
              fare: changed == 'fare' ? 1001 : 1990,
              stops: changed == 'stops')));
      expect(view().status, IncomingOfferStatus.stale);
      fake.emit(driverFlowSnapshot(revision: 3, offer: offerFixture()));
      expect(view().status, IncomingOfferStatus.stale);
      expect(view().offer!.expiresAt,
          driverFlowTestTime.add(const Duration(seconds: 30)));
    });
  }
  test('replacement retires old identity even at a newer event revision',
      () async {
    await settle();
    fake.emit(
        driverFlowSnapshot(revision: 2, offer: offerFixture(id: 'offer-b')));
    expect(view().status, IncomingOfferStatus.replaced);
    expect(view().offer!.id, 'offer-b');
    fake.emit(driverFlowSnapshot(revision: 3, offer: offerFixture()));
    expect(view().status, IncomingOfferStatus.stale);
  });
  test('no offer retires previous offer; older observations cannot revive it',
      () async {
    await settle();
    fake.emit(driverFlowSnapshot(revision: 3));
    expect(view().status, IncomingOfferStatus.empty);
    expect(view().offer, isNull);
    expect(fake.emit(driverFlowSnapshot(revision: 2, offer: offerFixture())),
        isFalse);
    fake.emit(driverFlowSnapshot(revision: 4, offer: offerFixture()));
    expect(view().status, IncomingOfferStatus.stale);
  });
  test('unauthorized is terminal and hides details', () async {
    await settle();
    fake.emit(
        driverFlowSnapshot(revision: 2, phase: DriverFlowPhase.unauthorized));
    fake.emit(driverFlowSnapshot(revision: 3, offer: offerFixture()));
    await controller().refresh();
    controller().updateTime();
    expect(view().status, IncomingOfferStatus.unauthorized);
    expect(view().offer, isNull);
    expect(fake.commands, isEmpty);
  });
  test('new session starts independently and ignores prior subscriptions',
      () async {
    await settle();
    final session = DriverFlowSession('driver-b', 2);
    fake.replaceSession(session);
    fake.emit(driverFlowSnapshot(
        session: session, offer: offerFixture(id: 'offer-b')));
    container.read(offerTestScope.notifier).state =
        DriverAvailabilityScope(session, 'vehicle');
    await settle();
    expect(view().offer!.id, 'offer-b');
    expect(view().status, IncomingOfferStatus.offer);
  });
  for (final phase in [DriverFlowPhase.ready, DriverFlowPhase.unauthorized]) {
    test('no-flush repository replacement rejects retired $phase events',
        () async {
      await settle();
      final other =
          FakeDriverFlowRepository(driverFlowSnapshot(), now: () => now);
      addTearDown(other.dispose);
      container.read(offerTestRepository.notifier).state = other;
      fake.emit(
          driverFlowSnapshot(revision: 9, phase: phase, offer: offerFixture()));
      expect(view().offer, isNull);
      await settle();
      expect(view().status, IncomingOfferStatus.empty);
    });
  }
  test('late read cannot overwrite newer offer event', () async {
    await settle();
    final reply = Completer<DriverFlowSnapshot>();
    fake.nextRead = reply.future;
    final pending = controller().refresh();
    fake.emit(
        driverFlowSnapshot(revision: 3, offer: offerFixture(id: 'offer-b')));
    reply.complete(driverFlowSnapshot(revision: 2, offer: offerFixture()));
    await pending;
    expect(view().offer!.id, 'offer-b');
  });
  test('scope clearing and disposal retire delayed reads', () async {
    await settle();
    final reply = Completer<DriverFlowSnapshot>();
    fake.nextRead = reply.future;
    final pending = controller().refresh();
    container.read(offerTestScope.notifier).state = null;
    reply.complete(driverFlowSnapshot(revision: 9, offer: offerFixture()));
    await pending;
    expect(view().offer, isNull);
    expect(view().status, IncomingOfferStatus.unavailable);
    final second = Completer<DriverFlowSnapshot>();
    container.read(offerTestScope.notifier).state =
        DriverAvailabilityScope(fake.current.session, 'vehicle');
    fake.nextRead = second.future;
    view();
    await Future<void>.value();
    container.dispose();
    second.complete(driverFlowSnapshot(revision: 10, offer: offerFixture()));
    await Future<void>.value();
    expect(fake.commands, isEmpty);
  });
  for (final phase in [
    DriverFlowPhase.pending,
    DriverFlowPhase.unknown,
    DriverFlowPhase.stale
  ]) {
    test('payload-less $phase cannot be cleared by equivalent ready', () async {
      await settle();
      fake.emit(driverFlowSnapshot(revision: 2, phase: phase));
      fake.emit(driverFlowSnapshot(revision: 3, offer: offerFixture()));
      expect(
          view().status,
          switch (phase) {
            DriverFlowPhase.pending => IncomingOfferStatus.pending,
            DriverFlowPhase.unknown => IncomingOfferStatus.unknown,
            _ => IncomingOfferStatus.stale,
          });
      expect(fake.commands, isEmpty);
    });
  }
  test('default fails closed', () async {
    final defaults = ProviderContainer();
    addTearDown(defaults.dispose);
    expect(defaults.read(driverIncomingOfferProvider).status,
        IncomingOfferStatus.unavailable);
  });
}

// Delivers every event verbatim: controller checks cannot rely on B01 filtering.
class UnfilteredOfferRepository implements DriverFlowRepository {
  UnfilteredOfferRepository(this.current);
  DriverFlowSnapshot current;
  final events = StreamController<DriverFlowSnapshot>.broadcast(sync: true);
  final commands = <DriverFlowCommand>[];
  void emit(DriverFlowSnapshot snapshot) {
    current = snapshot;
    events.add(snapshot);
  }

  Future<void> dispose() => events.close();
  @override
  Stream<DriverFlowSnapshot> watch(DriverFlowSession session) => events.stream;
  @override
  Future<DriverFlowResult> read(DriverFlowSession session) async =>
      DriverFlowResult(DriverFlowOutcome.observed, current);
  @override
  Future<DriverFlowResult> execute(DriverFlowCommand command) async {
    commands.add(command);
    return const DriverFlowResult(DriverFlowOutcome.unknown);
  }
}
