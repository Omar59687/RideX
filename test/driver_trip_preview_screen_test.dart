import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/providers/route_providers.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_trip_presentation_controller.dart';
import 'package:ridex/features/driver_flow/presentation/screens/driver_trip_preview_screen.dart';
import 'driver_trip_presentation_controller_test.dart'
    show TripHarness, previewTrip, tripSession;
import 'helpers/fake_driver_flow_repository.dart';

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 160,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  Future<void> mount(WidgetTester tester, TripHarness h) async {
    await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
            theme: AppTheme.light(), home: DriverTripPreviewScreen())));
    await tester.pump();
  }

  for (final loss in ['reply after UNKNOWN', 'unconfigured snapshot']) {
    testWidgets('P2 authorization $loss hides summary and open route sheet',
        (tester) async {
      final h = TripHarness();
      addTearDown(h.dispose);
      await h.settle();
      await mount(tester, h);
      await reveal(tester, find.text('View route preview'));
      await tester.tap(find.text('View route preview'));
      await tester.pumpAndSettle();
      expect(find.byType(MapPlaceholder), findsOneWidget);
      if (loss == 'reply after UNKNOWN') {
        final pending = h.act();
        h.repository.events.addError(StateError('watch lost'));
        expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
        h.repository.replies.single
            .complete(const DriverFlowResult(DriverFlowOutcome.unauthorized));
        await pending;
      } else {
        h.repository.emit(DriverFlowSnapshot(
            session: h.repository.current.session,
            revision: 2,
            phase: DriverFlowPhase.unauthorized,
            source: DriverFlowSource.unconfigured));
      }
      await tester.pump();
      expect(h.view.phase, DriverFlowPhase.unauthorized);
      expect(h.view.trip, isNull);
      expect(find.byType(MapPlaceholder), findsNothing);
      expect(find.text('Route preview is no longer current.'), findsOneWidget);
      expect(find.text('Pickup: Pickup', skipOffstage: false), findsNothing);
      h.repository.emit(h.result(revision: 9));
      await h.controller.refresh();
      await tester.pump();
      expect(h.view.trip, isNull);
      expect(h.view.canProgress, isFalse);
      expect(
          h.repository.commands.length, loss == 'reply after UNKNOWN' ? 1 : 0);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'complete simulated summary retains ordered stops and exact Cash fare',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    final base = driverFlowJourney();
    final journey = DriverFlowJourney(
        pickup: base.pickup,
        destination: base.destination,
        stops: [
          RideLocation(
              point: base.pickup.point,
              label: 'First stop',
              address: 'Stop one',
              source: LocationSelectionSource.demo),
          RideLocation(
              point: base.destination.point,
              label: 'Second stop',
              address: 'Stop two',
              source: LocationSelectionSource.demo)
        ],
        vehicleId: base.vehicleId,
        vehicleLabel: base.vehicleLabel,
        lockedFareFils: 1001,
        distanceMeters: base.distanceMeters,
        durationSeconds: base.durationSeconds);
    h.repository.current =
        driverFlowSnapshot(trip: previewTrip(journey: journey));
    await h.settle();
    await mount(tester, h);
    expect(find.text('Local demonstration only'), findsOneWidget);
    expect(find.text('Pickup: Pickup'), findsOneWidget);
    expect(find.text('Stop 1: First stop'), findsOneWidget);
    expect(find.text('Stop 2: Second stop'), findsOneWidget);
    expect(find.text('Destination: Destination'), findsOneWidget);
    expect(find.text('Locked Cash fare: JOD 1.001'), findsOneWidget);
    expect(find.text('Vehicle: Taxi (fake-vehicle)'), findsOneWidget);
    expect(find.text('Status: Accepted'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Stop 1: First stop')).dy,
        lessThan(tester.getTopLeft(find.text('Stop 2: Second stop')).dy));
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'default gate presents disabled progression and no financial controls',
      (tester) async {
    final h = TripHarness(enabled: null);
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await reveal(tester, find.text('Progression unavailable'));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(find.text('Complete trip'), findsNothing);
    expect(find.text('Issue receipt'), findsNothing);
    expect(find.byIcon(Icons.phone), findsNothing);
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'double tap dispatches once, pending and UNKNOWN are live regions',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await reveal(tester, find.text('Simulate driver arriving'));
    await tester.tap(find.text('Simulate driver arriving'));
    await tester.tap(find.text('Simulate driver arriving'));
    await tester.pump();
    expect(h.repository.commands, hasLength(1));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    for (final message in [
      'Simulated progression pending. No real Trip changed.',
      'Outcome unknown. Do not repeat the action.'
    ]) {
      if (message.startsWith('Outcome')) {
        h.timers.single();
        await tester.pump();
        await tester.pump();
      }
      expect(find.text(message), findsOneWidget);
      expect(
          tester
              .widgetList<Semantics>(find.ancestor(
                  of: find.text(message), matching: find.byType(Semantics)))
              .any((w) => w.properties.liveRegion == true),
          isTrue);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('pending survives remount and resume; resume only reads',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await reveal(tester, find.text('Simulate driver arriving'));
    await tester.tap(find.text('Simulate driver arriving'));
    final command = h.view.command;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, h);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(h.view.command, same(command));
    expect(h.repository.commands, hasLength(1));
    expect(h.view.progressStatus, DriverTripProgressStatus.pending);
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.unknown));
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await mount(tester, h);
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    expect(h.repository.commands, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('route handoff is passive, identity bound and revoked on logout',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await reveal(tester, find.text('View route preview'));
    await tester.tap(find.text('View route preview'));
    await tester.pumpAndSettle();
    final map = tester.widget<MapPlaceholder>(find.byType(MapPlaceholder));
    expect(map.showCars, isFalse);
    expect(map.liveState, MapLiveState.idle);
    expect(map.semanticLabel, contains('no live tracking'));
    expect(map.routePoints, hasLength(2));
    expect(
        map.routePoints.every((p) => p.dx.isFinite && p.dy.isFinite), isTrue);
    expect(find.text('Trip demo-trip · version 1'), findsWidgets);
    expect(h.repository.commands, isEmpty);
    h.session.replace(const SessionState.unauthenticated());
    await tester.pump();
    expect(find.byType(MapPlaceholder), findsNothing);
    expect(find.text('Route preview is no longer current.'), findsOneWidget);
    expect(find.text('Pickup: Pickup'), findsNothing);
    expect(h.container.exists(locationRepositoryProvider), isFalse);
    expect(h.container.exists(routeControllerProvider), isFalse);
    expect(h.container.exists(bookingControllerProvider), isFalse);
    expect(h.container.exists(activeTripControllerProvider), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'captured route handoff cannot silently follow a newer Trip version',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await reveal(tester, find.text('View route preview'));
    await tester.tap(find.text('View route preview'));
    await tester.pumpAndSettle();
    h.repository.emit(h.result());
    await tester.pump();
    expect(find.byType(MapPlaceholder), findsNothing);
    expect(find.text('Route preview is no longer current.'), findsOneWidget);
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('safe back leaves pending owner intact and does not replay',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
                builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const DriverTripPreviewScreen())),
                    child: const Text('Open preview'))))));
    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Simulate driver arriving'));
    await tester.tap(find.text('Simulate driver arriving'));
    await tester.pump();
    final command = h.view.command;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open preview'), findsOneWidget);
    expect(h.view.command, same(command));
    expect(h.view.progressStatus, DriverTripProgressStatus.pending);
    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    expect(h.repository.commands, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'simulated success stays on preview and never navigates to canonical Trip',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await reveal(tester, find.text('Simulate driver arriving'));
    await tester.tap(find.text('Simulate driver arriving'));
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.result()));
    await tester.pump();
    await tester.pump();
    expect(find.byType(DriverTripPreviewScreen), findsOneWidget);
    expect(
        find.text(
            'Simulated status observed. No assignment or payment authority.'),
        findsOneWidget);
    expect(find.text('Status: Driver arriving'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'large text at narrow width and coincident route points stays safe',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    final base = driverFlowJourney();
    h.repository.current = driverFlowSnapshot(
        trip: previewTrip(
            journey: DriverFlowJourney(
                pickup: base.pickup,
                destination: base.pickup,
                vehicleId: base.vehicleId,
                vehicleLabel: base.vehicleLabel,
                lockedFareFils: 0,
                distanceMeters: 1,
                durationSeconds: 1)));
    await h.settle();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!),
            home: const DriverTripPreviewScreen())));
    await tester.pump();
    await reveal(tester, find.text('View route preview'));
    await tester.tap(find.text('View route preview'));
    await tester.pumpAndSettle();
    final map = tester.widget<MapPlaceholder>(find.byType(MapPlaceholder));
    expect(
        map.routePoints.every((p) => p.dx.isFinite && p.dy.isFinite), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final phase in [
    DriverFlowPhase.unavailable,
    DriverFlowPhase.stale,
    DriverFlowPhase.unauthorized,
    DriverFlowPhase.completionBlocked
  ]) {
    testWidgets('$phase disables action and exposes accessible state',
        (tester) async {
      final h = TripHarness();
      addTearDown(h.dispose);
      await h.settle();
      h.repository.emit(
          driverFlowSnapshot(revision: 2, phase: phase, trip: previewTrip()));
      await mount(tester, h);
      await reveal(tester, find.byType(FilledButton));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      if (phase == DriverFlowPhase.unauthorized) {
        expect(find.text('Pickup: Pickup'), findsNothing);
      }
      expect(h.repository.commands, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'role loss hides summary and a stale action callback cannot dispatch',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await reveal(tester, find.text('Simulate driver arriving'));
    final callback =
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
    h.session.replace(tripSession(role: RideRole.rider));
    callback();
    await tester.pump();
    expect(find.text('Pickup: Pickup'), findsNothing);
    expect(find.text('Access ended. Trip details are hidden.'), findsOneWidget);
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('missing Trip cannot show an accepted status or route handoff',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    h.repository.current = driverFlowSnapshot();
    await h.settle();
    await mount(tester, h);
    expect(find.text('No Trip available'), findsOneWidget);
    expect(find.text('Status: Accepted'), findsNothing);
    expect(find.text('View route preview'), findsNothing);
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
