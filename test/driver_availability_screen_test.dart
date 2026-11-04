import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_availability_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_flow_repository_provider.dart';
import 'package:ridex/features/driver_flow/presentation/screens/driver_availability_screen.dart';
import 'driver_availability_controller_test.dart' show availabilitySnapshot;
import 'helpers/fake_driver_flow_repository.dart';

void main() {
  Future<void> mount(WidgetTester tester, FakeDriverFlowRepository fake) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      driverFlowRepositoryProvider.overrideWithValue(fake),
      driverAvailabilityScopeProvider.overrideWithValue(
          DriverAvailabilityScope(fake.current.session, 'fake-vehicle')),
    ], child: const MaterialApp(home: DriverAvailabilityScreen())));
    await tester.pump();
  }

  for (final outcome in ['pending', 'unknown']) {
    testWidgets('$outcome write stays protected across screen remount',
        (tester) async {
      final fake = FakeDriverFlowRepository(availabilitySnapshot(),
          now: () => driverFlowTestTime);
      final container = ProviderContainer(overrides: [
        driverFlowRepositoryProvider.overrideWithValue(fake),
        driverAvailabilityScopeProvider.overrideWithValue(
            DriverAvailabilityScope(fake.current.session, 'fake-vehicle')),
      ]);
      addTearDown(() async {
        container.dispose();
        await fake.dispose();
      });
      Future<void> showScreen(bool show) async {
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                home: show
                    ? const DriverAvailabilityScreen()
                    : const SizedBox())));
        await tester.pump();
      }

      await showScreen(true);
      final response = Completer<DriverFlowResult>();
      fake.nextCommand = response.future;
      final oldCallback =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!;
      await tester.tap(find.byType(Switch));
      await tester.pump();
      if (outcome == 'unknown') {
        response.complete(const DriverFlowResult(DriverFlowOutcome.unknown));
        await tester.pump();
      }
      try {
        await showScreen(false);
        await showScreen(true);
        expect(find.text('Offline'), findsOneWidget);
        expect(
            tester
                .widget<SwitchListTile>(find.byType(SwitchListTile))
                .onChanged,
            isNull);
        // A callback captured by an overlapping/old screen is also harmless.
        oldCallback(true);
        await container
            .read(driverAvailabilityControllerProvider.notifier)
            .refresh();
        await container
            .read(driverAvailabilityControllerProvider.notifier)
            .setOnline(true);
        await tester.pump();
        expect(fake.commands, hasLength(1));
      } finally {
        if (!response.isCompleted) {
          response.complete(const DriverFlowResult(DriverFlowOutcome.unknown));
        }
        await tester.pump();
      }
      expect(find.textContaining('Change outcome is unknown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final value in DriverAvailabilityState.values) {
    testWidgets('$value accessible controls and observed state',
        (tester) async {
      final fake = FakeDriverFlowRepository(availabilitySnapshot(value: value),
          now: () => driverFlowTestTime);
      addTearDown(fake.dispose);
      await mount(tester, fake);
      expect(find.text('Local demonstration only'), findsOneWidget);
      expect(
          find.text(switch (value) {
            DriverAvailabilityState.offline => 'Offline',
            DriverAvailabilityState.available => 'Online',
            DriverAvailabilityState.reserved => 'Reserved',
            DriverAvailabilityState.onTrip => 'On trip',
          }),
          findsOneWidget);
      final tile = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('availability-switch')));
      expect(tile.value, value == DriverAvailabilityState.available);
      expect(
          tile.onChanged != null,
          value == DriverAvailabilityState.available ||
              value == DriverAvailabilityState.offline);
      final semantics = tester.ensureSemantics();
      expect(
          tester
              .getSemantics(find.byKey(const ValueKey('availability-switch')))
              .getSemanticsData()
              .label,
          contains('Receive requests in local preview'));
      semantics.dispose();
      expect(fake.commands, isEmpty);
    });
  }
  for (final phase
      in DriverFlowPhase.values.where((p) => p != DriverFlowPhase.ready)) {
    testWidgets('$phase is visible and disabled', (tester) async {
      final fake = FakeDriverFlowRepository(availabilitySnapshot(phase: phase),
          now: () => driverFlowTestTime);
      addTearDown(fake.dispose);
      await mount(tester, fake);
      expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
          isNull);
      if (phase == DriverFlowPhase.loading ||
          phase == DriverFlowPhase.pending) {
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      }
      expect(
          find.textContaining(switch (phase) {
            DriverFlowPhase.loading => 'Loading availability',
            DriverFlowPhase.pending => 'Changing availability',
            DriverFlowPhase.unavailable => 'Availability is unavailable',
            DriverFlowPhase.unauthorized => 'Access ended',
            DriverFlowPhase.stale => 'Availability changed',
            DriverFlowPhase.unknown => 'Change outcome is unknown',
            DriverFlowPhase.completionBlocked =>
              'Availability changes are blocked',
            _ => 'Choose whether',
          }),
          findsOneWidget);
      expect(fake.commands, isEmpty);
    });
  }
  testWidgets('double tap pending leaves Offline then shows simulated Online',
      (tester) async {
    final fake = FakeDriverFlowRepository(availabilitySnapshot(),
        now: () => driverFlowTestTime);
    addTearDown(fake.dispose);
    await mount(tester, fake);
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    await tester.tap(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(fake.commands, hasLength(1));
    expect(find.text('Offline'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull);
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 2,
            version: 2,
            value: DriverAvailabilityState.available)));
    await tester.pump();
    expect(find.text('Online'), findsOneWidget);
  });
  testWidgets('unmount during pending command is safe', (tester) async {
    final fake = FakeDriverFlowRepository(availabilitySnapshot(),
        now: () => driverFlowTestTime);
    addTearDown(fake.dispose);
    await mount(tester, fake);
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    await tester.tap(find.byType(Switch));
    await tester.pumpWidget(const SizedBox());
    response.complete(const DriverFlowResult(DriverFlowOutcome.unknown));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('unconfigured preview fails closed', (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: DriverAvailabilityScreen())));
    await tester.pump();
    expect(find.textContaining('unavailable'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull);
  });
  testWidgets('late read after screen disposal is ignored', (tester) async {
    final fake = FakeDriverFlowRepository(availabilitySnapshot(),
        now: () => driverFlowTestTime);
    addTearDown(fake.dispose);
    final read = Completer<DriverFlowSnapshot>();
    fake.nextRead = read.future;
    await mount(tester, fake);
    expect(find.text('Loading availability?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    read.complete(availabilitySnapshot(revision: 9, version: 9));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(fake.commands, isEmpty);
  });
  testWidgets('authorization loss disables refresh and cannot show late Online',
      (tester) async {
    final fake = FakeDriverFlowRepository(availabilitySnapshot(),
        now: () => driverFlowTestTime);
    addTearDown(fake.dispose);
    await mount(tester, fake);
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    await tester.tap(find.byType(Switch));
    await tester.pump();
    fake.emit(
        availabilitySnapshot(revision: 2, phase: DriverFlowPhase.unauthorized));
    await tester.pump();
    expect(find.textContaining('Access ended'), findsOneWidget);
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 3,
            version: 2,
            value: DriverAvailabilityState.available)));
    await tester.pump();
    expect(find.text('Online'), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('availability-refresh')))
            .onPressed,
        isNull);
  });
}
