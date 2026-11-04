import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/driver_cash_completion_providers.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_flow_repository_provider.dart';
import 'helpers/fake_driver_flow_repository.dart';

void main() {
  test('unconfigured boundary exposes no data and cannot execute', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repository = container.read(driverFlowRepositoryProvider);
    final session = DriverFlowSession('driver', 1);
    final read = await repository.read(session);
    expect(read.outcome, DriverFlowOutcome.unavailable);
    expect(read.snapshot, isNull);
    expect(await repository.watch(session).toList(), isEmpty);
    expect(
      (await repository.execute(
        DriverFlowDecideOffer(
          session: session,
          targetId: 'offer',
          expectedVersion: 1,
          idempotencyToken: 'original',
          decision: DriverFlowOfferDecision.accept,
        ),
      ))
          .outcome,
      DriverFlowOutcome.unavailable,
    );
  });
  test(
    'fake override does not alter other containers, mock trip or Cash gate',
    () async {
      final fake = FakeDriverFlowRepository(
        driverFlowSnapshot(offer: driverFlowOffer()),
        now: () => driverFlowTestTime,
      );
      final isolated = ProviderContainer(
        overrides: [driverFlowRepositoryProvider.overrideWithValue(fake)],
      );
      final other = ProviderContainer();
      addTearDown(() async {
        isolated.dispose();
        other.dispose();
        await fake.dispose();
      });
      expect(isolated.read(driverFlowRepositoryProvider), same(fake));
      expect(other.read(driverFlowRepositoryProvider), isNot(same(fake)));
      final before = isolated.read(driverOnlineProvider);
      fake.nextCommand = Future.value(
        DriverFlowResult(
          DriverFlowOutcome.simulated,
          driverFlowSnapshot(
              revision: 2,
              trip: DriverFlowTrip(
                id: 'fake-trip',
                version: 1,
                status: DriverTripLifecycleStatus.accepted,
                journey: driverFlowJourney(),
              )),
        ),
      );
      final session = fake.current.session;
      final offer = fake.current.offer!;
      final result = await isolated.read(driverFlowRepositoryProvider).execute(
            DriverFlowDecideOffer(
              session: fake.current.session,
              targetId: 'fake-offer',
              expectedVersion: 3,
              idempotencyToken: 'original',
              decision: DriverFlowOfferDecision.accept,
            ),
          );
      expect(result.outcome, DriverFlowOutcome.simulated);
      expect(result.snapshot, same(fake.current));
      expect(result.snapshot!.source, DriverFlowSource.simulated);
      expect(result.snapshot!.session.sameSession(session), isTrue);
      expect(result.snapshot!.revision, 2);
      expect(result.snapshot!.offer, isNull);
      expect(result.snapshot!.trip!.id, 'fake-trip');
      expect(result.snapshot!.trip!.status, DriverTripLifecycleStatus.accepted);
      expect(result.snapshot!.trip!.version, 1);
      expect(fake.commands.single.targetId, offer.id);
      expect(fake.commands.single.expectedVersion, offer.version);
      expect(fake.commands.single.idempotencyToken, 'original');
      expect(fake.commands.single.session.sameSession(session), isTrue);
      expect(isolated.read(activeTripControllerProvider), isNull);
      expect(isolated.read(driverOnlineProvider), before);
      expect(isolated.read(driverCashRuntimeEnabledProvider), isFalse);
      expect(other.read(activeTripControllerProvider), isNull);
      expect(other.read(driverCashRuntimeEnabledProvider), isFalse);
      expect(
          (await other.read(driverFlowRepositoryProvider).read(session))
              .snapshot,
          isNull);
      expect(
        (await other
                .read(driverFlowRepositoryProvider)
                .read(fake.current.session))
            .outcome,
        DriverFlowOutcome.unavailable,
      );
    },
  );
  test('two fake overrides keep observations and command histories separate',
      () async {
    final first = FakeDriverFlowRepository(
        driverFlowSnapshot(offer: driverFlowOffer()),
        now: () => driverFlowTestTime);
    final second = FakeDriverFlowRepository(
        driverFlowSnapshot(offer: driverFlowOffer()),
        now: () => driverFlowTestTime);
    final firstContainer = ProviderContainer(
        overrides: [driverFlowRepositoryProvider.overrideWithValue(first)]);
    final secondContainer = ProviderContainer(
        overrides: [driverFlowRepositoryProvider.overrideWithValue(second)]);
    addTearDown(() async {
      firstContainer.dispose();
      secondContainer.dispose();
      await first.dispose();
      await second.dispose();
    });
    final untouched = second.current;
    final events = <DriverFlowSnapshot>[];
    final subscription = secondContainer
        .read(driverFlowRepositoryProvider)
        .watch(second.current.session)
        .listen(events.add);
    addTearDown(subscription.cancel);
    first.nextCommand = Future.value(DriverFlowResult(
        DriverFlowOutcome.simulated,
        driverFlowSnapshot(
            revision: 2,
            trip: DriverFlowTrip(
                id: 'first-trip',
                version: 7,
                status: DriverTripLifecycleStatus.accepted,
                journey: driverFlowJourney()))));
    final result = await firstContainer
        .read(driverFlowRepositoryProvider)
        .execute(DriverFlowDecideOffer(
            session: first.current.session,
            targetId: 'fake-offer',
            expectedVersion: 3,
            idempotencyToken: 'first-original',
            decision: DriverFlowOfferDecision.accept));
    expect(result.outcome, DriverFlowOutcome.simulated);
    expect(result.snapshot!.trip!.id, 'first-trip');
    expect(result.snapshot!.trip!.version, 7);
    expect(result.snapshot!.source, DriverFlowSource.simulated);
    expect(first.commands.single.expectedVersion, 3);
    expect(first.commands.single.idempotencyToken, 'first-original');
    final otherRead = await secondContainer
        .read(driverFlowRepositoryProvider)
        .read(second.current.session);
    expect(otherRead.outcome, DriverFlowOutcome.observed);
    expect(otherRead.snapshot, same(untouched));
    expect(otherRead.snapshot!.revision, 1);
    expect(otherRead.snapshot!.offer!.id, 'fake-offer');
    expect(otherRead.snapshot!.trip, isNull);
    expect(second.commands, isEmpty);
    expect(events, isEmpty);
  });
}
