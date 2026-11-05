import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_availability_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_flow_repository_provider.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_incoming_offer_controller.dart';
import 'package:ridex/features/driver_flow/presentation/screens/driver_incoming_offer_screen.dart';
import 'driver_incoming_offer_controller_test.dart'
    show offerFixture, offerTestScope;
import 'helpers/fake_driver_flow_repository.dart';

void main() {
  late DateTime now;
  late FakeDriverFlowRepository fake;
  Future<void> mount(WidgetTester tester,
      {DriverFlowOffer? offer,
      DriverFlowPhase phase = DriverFlowPhase.ready}) async {
    now = driverFlowTestTime;
    fake = FakeDriverFlowRepository(
        driverFlowSnapshot(offer: offer, phase: phase),
        now: () => now);
    addTearDown(fake.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      driverFlowRepositoryProvider.overrideWithValue(fake),
      driverAvailabilityScopeProvider.overrideWithValue(
          DriverAvailabilityScope(fake.current.session, 'vehicle')),
      driverOfferClockProvider.overrideWithValue(() => now),
    ], child: const MaterialApp(home: DriverIncomingOfferScreen())));
    await tester.pump();
  }

  testWidgets('all contract details, ordered stops and disabled actions',
      (tester) async {
    await mount(tester, offer: offerFixture(stops: true, fare: 1001));
    for (final text in [
      'Pickup: Pickup',
      'Destination: Destination',
      'Stop 1: Destination',
      'Stop 2: Pickup',
      'Locked Cash fare: JOD 1.001',
      'Route: 5.00 km / 600 seconds',
      'Vehicle: Taxi (fake-vehicle)',
      'Remaining: 30 seconds'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(tester.getTopLeft(find.text('Stop 1: Destination')).dy,
        lessThan(tester.getTopLeft(find.text('Stop 2: Pickup')).dy));
    expect(find.textContaining('2026-11-04T12:00:30.000Z'), findsOneWidget);
    expect(find.textContaining('Ahmed'), findsNothing);
    expect(find.byIcon(Icons.phone), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(find.textContaining('do not confirm a real assignment or payment'),
        findsOneWidget);
    expect(fake.commands, isEmpty);
  });
  for (final seconds in [29, 30, 31]) {
    testWidgets('first remount frame at second $seconds reconciles deadline',
        (tester) async {
      now = driverFlowTestTime;
      fake = FakeDriverFlowRepository(driverFlowSnapshot(offer: offerFixture()),
          now: () => now);
      final container = ProviderContainer(overrides: [
        driverFlowRepositoryProvider.overrideWithValue(fake),
        driverAvailabilityScopeProvider.overrideWithValue(
            DriverAvailabilityScope(fake.current.session, 'vehicle')),
        driverOfferClockProvider.overrideWithValue(() => now),
      ]);
      addTearDown(() async {
        container.dispose();
        await fake.dispose();
      });
      Future<void> show(bool visible) =>
          tester.pumpWidget(UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                  home: visible
                      ? const DriverIncomingOfferScreen()
                      : const SizedBox())));
      await show(true);
      await tester.pump();
      expect(find.text('Incoming offer'), findsOneWidget);
      await show(false);
      now = driverFlowTestTime.add(Duration(seconds: seconds));
      // First frame only: no repository event, elapsed pump or timer tick.
      await show(true);
      expect(find.text(seconds < 30 ? 'Incoming offer' : 'Offer expired'),
          findsOneWidget);
      expect(find.text('Remaining: ${seconds < 30 ? 1 : 0} seconds'),
          findsOneWidget);
      if (seconds >= 30) expect(find.text('Incoming offer'), findsNothing);
      expect(fake.commands, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  for (final change in ['rapid', 'unauthorized', 'session']) {
    testWidgets('remount preserves $change lifecycle safety', (tester) async {
      now = driverFlowTestTime;
      fake = FakeDriverFlowRepository(driverFlowSnapshot(offer: offerFixture()),
          now: () => now);
      final container = ProviderContainer(overrides: [
        driverFlowRepositoryProvider.overrideWithValue(fake),
        driverAvailabilityScopeProvider
            .overrideWith((ref) => ref.watch(offerTestScope)),
        driverOfferClockProvider.overrideWithValue(() => now),
      ]);
      addTearDown(() async {
        container.dispose();
        await fake.dispose();
      });
      Future<void> show(bool visible) =>
          tester.pumpWidget(UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                  home: visible
                      ? const DriverIncomingOfferScreen()
                      : const SizedBox())));
      await show(true);
      await tester.pump();
      await show(false);
      if (change == 'unauthorized') {
        fake.emit(driverFlowSnapshot(
            revision: 2, phase: DriverFlowPhase.unauthorized));
      } else if (change == 'session') {
        final session = DriverFlowSession('driver-b', 2);
        fake.replaceSession(session);
        fake.emit(driverFlowSnapshot(session: session));
        container.read(offerTestScope.notifier).state =
            DriverAvailabilityScope(session, 'vehicle');
      }
      await show(true);
      if (change == 'rapid') {
        for (var i = 0; i < 3; i++) {
          await show(false);
          await show(true);
        }
        final updates = <DriverIncomingOfferView>[];
        final listener = container.listen(
            driverIncomingOfferProvider, (_, next) => updates.add(next));
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        listener.close();
        expect(updates, hasLength(1));
        expect(find.text('Remaining: 29 seconds'), findsOneWidget);
        await show(false);
        now = now.add(const Duration(seconds: 40));
        await show(true);
        expect(find.text('Offer expired'), findsOneWidget);
        await show(false);
        now = driverFlowTestTime;
        await show(true);
        expect(find.text('Offer expired'), findsOneWidget);
      } else {
        expect(find.text('Incoming offer'), findsNothing);
        expect(find.textContaining('Pickup:'), findsNothing);
        await tester.pump();
        expect(
            find.textContaining(
                change == 'session' ? 'No available offer' : 'Access ended'),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      expect(fake.commands, isEmpty);
    });
  }
  testWidgets('reconstructed offer does not reset visible countdown',
      (tester) async {
    await mount(tester, offer: offerFixture());
    now = now.add(const Duration(seconds: 10));
    fake.emit(driverFlowSnapshot(revision: 2, offer: offerFixture()));
    await tester.pump();
    expect(find.text('Remaining: 20 seconds'), findsOneWidget);
    fake.emit(driverFlowSnapshot(
        revision: 3, phase: DriverFlowPhase.unknown, offer: offerFixture()));
    fake.emit(driverFlowSnapshot(revision: 4, offer: offerFixture()));
    await tester.pump();
    expect(find.textContaining('Acceptance outcome unknown'), findsOneWidget);
    expect(fake.commands, isEmpty);
  });
  testWidgets('absent stops are omitted and 1990 fils remains exact',
      (tester) async {
    await mount(tester, offer: offerFixture());
    expect(find.textContaining('Stop 1:'), findsNothing);
    expect(find.text('Locked Cash fare: JOD 1.990'), findsOneWidget);
  });
  testWidgets('timer counts down and exact expiry is visible', (tester) async {
    await mount(tester, offer: offerFixture());
    now = now.add(const Duration(seconds: 29));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Remaining: 1 seconds'), findsOneWidget);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Offer expired'), findsOneWidget);
    expect(find.text('Remaining: 0 seconds'), findsOneWidget);
  });
  testWidgets(
      'resume recomputes absolute expiry after background and cleans lifecycle',
      (tester) async {
    await mount(tester, offer: offerFixture());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Offer expired'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(fake.commands, isEmpty);
  });
  for (final phase in DriverFlowPhase.values) {
    testWidgets('renders $phase with no unsupported offer data',
        (tester) async {
      await mount(tester, phase: phase);
      expect(find.textContaining('Pickup:'), findsNothing);
      expect(find.textContaining('Locked Cash fare:'), findsNothing);
      expect(fake.commands, isEmpty);
      expect(tester.takeException(), isNull);
      if (phase == DriverFlowPhase.ready) {
        expect(find.text('No available offer'), findsOneWidget);
      }
      if (phase == DriverFlowPhase.unauthorized) {
        expect(find.textContaining('Access ended'), findsOneWidget);
      }
      if (phase == DriverFlowPhase.unavailable) {
        expect(find.textContaining('Requests unavailable'), findsOneWidget);
      }
    });
  }
}
