import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_repository.dart';
import 'package:ridex/features/driver_flow/domain/driver_restoration_hints.dart';
import 'package:ridex/features/driver_flow/presentation/providers/canonical_driver_presentation_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_active_trip_restoration_provider.dart';
import 'package:ridex/features/driver_flow/presentation/screens/driver_active_trip_restoration_screen.dart';
import 'package:ridex/features/driver_flow/presentation/widgets/canonical_driver_reference_panel.dart';
import 'helpers/fake_canonical_driver_port.dart' as f;
import 'helpers/canonical_driver_presentation_harness.dart' as b;

class RestorationHarness {
  RestorationHarness({String driver = f.driverId}) {
    session.value = b.driverSession(id: driver);
    port.driver = driver;
    port.user!['id'] = driver;
    port.profile!['user_id'] = driver;
    port.accept();
    port.availability!['driver_id'] = driver;
    port.trip!['driver_id'] = driver;
    port.trip = {...port.trip!, 'status': 'inProgress', 'version': 4};
    repository = CanonicalDriverRepository(port);
    controller = CanonicalDriverPresentationController(
        repository: repository,
        session: session,
        authorityInvalidations: authority,
        delivery: delivery,
        enabled: true,
        restorationEnabled: true,
        recoveryHints: hints,
        locationHints: gps,
        retireCompletion: (defer) {
          retired++;
          retirementModes.add(defer);
        },
        clock: () => now);
  }
  final port = f.FakeCanonicalDriverPort();
  final session = ValueNotifier<SessionState>(b.driverSession());
  final authority = ValueNotifier(0);
  final delivery = b.FakeCanonicalDelivery();
  final hints = ValueNotifier(const DriverRestorationRecoveryHint());
  final gps = ValueNotifier<DriverRestorationLocationHint?>(null);
  late final CanonicalDriverRepository repository;
  late final CanonicalDriverPresentationController controller;
  DateTime now = f.now;
  int retired = 0;
  final retirementModes = <bool>[];
  CanonicalDriverPresentationView get view => controller.view;
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Future<void> start() async {
    delivery.connect();
    await flush();
  }

  Future<void> dispose({bool disposeController = true}) async {
    if (disposeController) controller.dispose();
    repository.dispose();
    session.dispose();
    authority.dispose();
    hints.dispose();
    gps.dispose();
    await delivery.events.close();
  }
}

void main() {
  group('C04 read-only canonical restoration', () {
    late RestorationHarness h;
    setUp(() => h = RestorationHarness());
    tearDown(() async {
      expect(h.port.calls, isEmpty);
      await h.dispose();
    });
    test(
        'cold start discovers exact assigned Trip without a cached ID or progression',
        () async {
      await h.start();
      expect(h.view.phase, CanonicalDriverPresentationPhase.trip);
      expect(h.view.trip!.id, f.tripId);
      expect(h.view.trip!.version, 4);
      expect(h.view.trip!.status, DriverTripLifecycleStatus.inProgress);
      expect(h.view.canDecide, isFalse);
      expect(h.view.gpsFresh, isFalse);
    });
    for (final scenario in [
      'foreign-driver',
      'foreign-trip',
      'vehicle',
      'blocked',
      'rider',
      'pending',
      'expired',
      'malformed-id',
      'card'
    ]) {
      test('rejects $scenario without restoring mock or foreign state',
          () async {
        switch (scenario) {
          case 'foreign-driver':
            h.port.trip!['driver_id'] = f.otherId;
          case 'foreign-trip':
            h.port.trip!['id'] = f.otherId;
          case 'vehicle':
            h.port.availability!['vehicle_id'] = f.otherId;
          case 'blocked':
            h.port.user!['is_blocked'] = true;
          case 'rider':
            h.port.user!['role'] = 'rider';
          case 'pending':
            h.port.profile!['approval_status'] = 'pending';
          case 'expired':
            h.port.valid = false;
          case 'malformed-id':
            h.port.availability!['active_trip_id'] = 'trip-1';
          case 'card':
            h.port.trip!['payment_method'] = 'card';
        }
        await h.start();
        expect(h.view.trip, isNull);
        expect(h.view.canDecide, isFalse);
      });
    }
    test(
        'no assignment is empty; local/journal hint cannot assign a nonterminal Trip',
        () async {
      h.port.availability = f.availabilityRow();
      await h.start();
      expect(h.view.phase, CanonicalDriverPresentationPhase.empty);
      expect(h.port.reads, isNot(contains('trip')));
      h.hints.value = const DriverRestorationRecoveryHint(
          tripId: f.tripId, requiresRecovery: true);
      await h.flush();
      expect(h.view.trip, isNull);
      expect(h.view.phase, CanonicalDriverPresentationPhase.stale);
    });
    test('availability replaced during Trip read prevents publication',
        () async {
      h.port.beforeRead = (name) async {
        if (name == 'trip') h.port.availability!['active_trip_id'] = f.otherId;
      };
      await h.start();
      expect(h.view.phase, CanonicalDriverPresentationPhase.stale);
      expect(h.view.trip, isNull);
    });
    test(
        'empty assignment changed during revalidation is not published as empty',
        () async {
      h.port.availability = f.availabilityRow();
      var reads = 0;
      h.port.beforeRead = (name) async {
        if (name == 'availability' && ++reads == 2) h.port.accept();
      };
      await h.start();
      expect(h.view.phase, CanonicalDriverPresentationPhase.stale);
    });
    for (final terminal in [
      DriverTripLifecycleStatus.completed,
      DriverTripLifecycleStatus.cancelledByRider,
      DriverTripLifecycleStatus.cancelledByDriver,
      DriverTripLifecycleStatus.cancelledByAdmin,
      DriverTripLifecycleStatus.failed
    ]) {
      test('restart terminal $terminal is never restored as active', () async {
        h.port.availability = f.availabilityRow();
        h.port.trip = {
          ...h.port.trip!,
          'status': terminal.backendValue,
          'version': 5
        };
        h.hints.value = const DriverRestorationRecoveryHint(tripId: f.tripId);
        await h.start();
        expect(h.view.phase, CanonicalDriverPresentationPhase.terminal);
        expect(h.view.trip, isNull);
        expect(h.view.terminalTrip!.status, terminal);
      });
    }
    test('reconnect verifies canonical completion and never replays progress',
        () async {
      await h.start();
      final old = h.view;
      h.delivery.disconnect();
      expect(h.view.phase, CanonicalDriverPresentationPhase.disconnected);
      expect(h.view.trip, isNull);
      expect(old.trip, isNull);
      expect(h.retired, 1);
      h.port.availability = f.availabilityRow();
      h.port.trip = {...h.port.trip!, 'status': 'completed', 'version': 5};
      h.delivery.connect();
      await h.flush();
      expect(h.view.phase, CanonicalDriverPresentationPhase.terminal);
      expect(h.view.terminalTrip!.version, 5);
    });
    test('older async read cannot overwrite newer canonical version', () async {
      await h.start();
      final entered = Completer<void>();
      final gate = Completer<void>();
      var once = false;
      h.port.beforeRead = (name) async {
        if (name == 'trip' && !once) {
          once = true;
          entered.complete();
          await gate.future;
        }
      };
      final old = h.controller.refresh();
      await entered.future;
      h.port.trip!['version'] = 6;
      await h.controller.refresh();
      gate.complete();
      await old;
      expect(h.view.trip!.version, 6);
    });
    for (final change in ['logout', 'B', 'A-B-A', 'SDK', 'epoch', 'approval']) {
      test('late callback after $change cannot restore old state', () async {
        await h.start();
        final prior = h.view;
        final entered = Completer<void>();
        final gate = Completer<void>();
        h.port.beforeRead = (name) async {
          if (name == 'trip') {
            entered.complete();
            await gate.future;
          }
        };
        final pending = h.controller.refresh();
        await entered.future;
        switch (change) {
          case 'logout':
            h.session.value = const SessionState.unauthenticated();
          case 'B':
            h.session.value = b.driverSession(id: f.otherId);
          case 'A-B-A':
            h.session.value = b.driverSession(id: f.otherId);
            h.session.value = b.driverSession();
          case 'SDK':
            h.port.sessionIdentity = Object();
          case 'epoch':
            h.port.epoch++;
          case 'approval':
            h.port.profile!['approval_status'] = 'rejected';
        }
        gate.complete();
        await pending;
        await h.flush();
        expect(h.view.trip, isNull);
        expect(prior.trip, isNull);
        expect(h.view.phase, CanonicalDriverPresentationPhase.unauthorized);
        expect(h.delivery.listeners, 0);
      });
    }
    test(
        'new login B restores only B assignment while retired A remains hidden',
        () async {
      await h.start();
      final old = h.view;
      h.session.value = const SessionState.unauthenticated();
      await h.flush();
      final next = RestorationHarness(driver: f.otherId);
      try {
        next.port.trip!['id'] = f.otherId;
        next.port.availability!['active_trip_id'] = f.otherId;
        next.hints.value =
            const DriverRestorationRecoveryHint(tripId: f.tripId);
        await next.start();
        expect(next.view.trip!.driverId, f.otherId);
        expect(next.view.trip!.id, f.otherId);
        expect(old.trip, isNull);
        expect(h.delivery.listeners, 0);
        expect(next.port.calls, isEmpty);
      } finally {
        await next.dispose();
      }
    });

    test(
        'pending journal state blocks action presentation without changing verified Trip',
        () async {
      h.hints.value = const DriverRestorationRecoveryHint(
          tripId: f.tripId, requiresRecovery: true);
      await h.start();
      expect(h.view.phase, CanonicalDriverPresentationPhase.recoveryRequired);
      expect(h.view.trip!.id, f.tripId);
      expect(h.view.recoveryRequired, isTrue);
      expect(h.view.canDecide, isFalse);
    });
    test('restoration ignores unrelated offer hints, including malformed IDs',
        () async {
      await h.start();
      final reads = h.port.reads.length;
      h.delivery.offer('mock-offer');
      await h.flush();
      expect(h.view.trip!.id, f.tripId);
      expect(h.view.phase, CanonicalDriverPresentationPhase.trip);
      expect(h.port.reads.length, reads);
    });

    test(
        'GPS age, foreign scope and retired SDK sample never show current location',
        () async {
      await h.start();
      h.gps.value = DriverRestorationLocationHint(
          owner: h.port.currentOwner,
          sdkSession: h.port.sessionIdentity!,
          tripId: f.tripId,
          recordedAt: h.now);
      expect(h.view.gpsFresh, isTrue);
      h.now = h.now.add(const Duration(seconds: 46));
      h.controller.tick();
      expect(h.view.gpsFresh, isFalse);
      h.gps.value = DriverRestorationLocationHint(
          owner: h.port.currentOwner,
          sdkSession: Object(),
          tripId: f.tripId,
          recordedAt: h.now);
      expect(h.view.gpsFresh, isFalse);
      h.gps.value = DriverRestorationLocationHint(
          owner: h.port.currentOwner,
          sdkSession: h.port.sessionIdentity!,
          tripId: f.otherId,
          recordedAt: h.now);
      expect(h.view.gpsFresh, isFalse);
    });
    for (final scenario in ['version', 'backwards', 'changed-assignment']) {
      test('rejects $scenario across restoration reads', () async {
        await h.start();
        switch (scenario) {
          case 'version':
            h.port.trip!['version'] = 3;
          case 'backwards':
            h.port.trip = {
              ...h.port.trip!,
              'version': 5,
              'status': 'driverArriving'
            };
          case 'changed-assignment':
            h.port.trip!['vehicle_id'] = f.otherId;
        }
        await h.controller.refresh();
        expect(h.view.trip, isNull);
        expect(h.view.phase, CanonicalDriverPresentationPhase.stale);
      });
    }
  });

  testWidgets(
      'C04 panel shows verified restoration, stale GPS, UNKNOWN and canonical terminal',
      (tester) async {
    final h = RestorationHarness();
    addTearDown(h.dispose);
    await tester.runAsync(h.start);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: CanonicalDriverReferencePanel(
                        controller: h.controller))))));
    expect(find.text('Trip ID: ${f.tripId}'), findsOneWidget);
    expect(find.text('GPS stale or unavailable. Location hidden.'),
        findsOneWidget);
    h.hints.value = const DriverRestorationRecoveryHint(
        tripId: f.tripId, requiresRecovery: true);
    await tester.runAsync(h.flush);
    await tester.pump();
    expect(find.textContaining('Completion recovery required'), findsOneWidget);
    h.delivery.disconnect();
    await tester.pump();
    expect(find.textContaining('Source disconnected'), findsOneWidget);
    expect(find.text('Trip ID: ${f.tripId}'), findsNothing);
    h.port.trip = {...h.port.trip!, 'version': 5, 'status': 'completed'};
    h.port.availability = f.availabilityRow();
    h.delivery.connect();
    await tester.runAsync(h.flush);
    await tester.pump();
    expect(find.text('Canonical terminal status: completed'), findsOneWidget);
    expect(find.textContaining('Payment and receipt are not verified.'),
        findsOneWidget);
    expect(find.text('Trip ID: ${f.tripId}'), findsNothing);
    expect(h.port.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('C04 screen defaults unconfigured without inventing an SDK owner',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: DriverActiveTripRestorationScreen())));
    expect(find.text('Canonical Driver restoration is not configured.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('C04 mounting before foreground never restores until resumed',
      (tester) async {
    final owners = <RestorationHarness>[];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(ProviderScope(overrides: [
      driverActiveTripRestorationProvider.overrideWith((ref) {
        final h = RestorationHarness();
        owners.add(h);
        ref.onDispose(h.repository.dispose);
        scheduleMicrotask(h.delivery.connect);
        return h.controller;
      }),
    ], child: const MaterialApp(home: DriverActiveTripRestorationScreen())));
    await tester.pump();
    expect(owners.single.view.trip, isNull);
    expect(owners.single.delivery.listeners, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(owners.length, 2);
    expect(owners.last.view.trip!.id, f.tripId);
    await tester.pumpWidget(const SizedBox());
    for (final h in owners) {
      await h.dispose(disposeController: false);
    }
  });

  testWidgets(
      'C04 replacement immediately followed by pause retires the current provider owner',
      (tester) async {
    final owners = <RestorationHarness>[];
    await tester.pumpWidget(ProviderScope(overrides: [
      driverActiveTripRestorationProvider.overrideWith((ref) {
        final h = RestorationHarness();
        owners.add(h);
        ref.onDispose(h.repository.dispose);
        scheduleMicrotask(h.delivery.connect);
        return h.controller;
      }),
    ], child: const MaterialApp(home: DriverActiveTripRestorationScreen())));
    await tester.pump();
    await tester.pump();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DriverActiveTripRestorationScreen)));
    container.invalidate(driverActiveTripRestorationProvider);
    container.read(driverActiveTripRestorationProvider);
    expect(owners.length, 2);
    await tester
        .idle(); // complete delivery/reads without rebuilding the screen
    expect(owners.last.view.trip!.id, f.tripId);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.idle();
    expect(owners.last.view.trip, isNull);
    expect(owners.last.delivery.listeners, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(owners.last.view.trip!.id, f.tripId);
    await tester.pumpWidget(const SizedBox());
    for (final h in owners) {
      await h.dispose(disposeController: false);
    }
  });

  testWidgets(
      'C04 foreground creates fresh read-only owner; old callbacks and route cover stay retired',
      (tester) async {
    final owners = <RestorationHarness>[];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          driverActiveTripRestorationProvider.overrideWith((ref) {
            final h = RestorationHarness();
            owners.add(h);
            ref.onDispose(() {
              h.repository.dispose();
            });
            scheduleMicrotask(h.delivery.connect);
            return h.controller;
          }),
        ],
        child: MaterialApp(
            navigatorKey: navigator,
            home: const DriverActiveTripRestorationScreen())));
    await tester.pump();
    await tester.pump();
    expect(find.text('Trip ID: ${f.tripId}'), findsOneWidget);
    final first = owners.single;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(first.view.trip, isNull);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DriverActiveTripRestorationScreen)));
    container.invalidate(driverActiveTripRestorationProvider);
    container.read(
        driverActiveTripRestorationProvider); // dependency eagerly rebuilt while paused
    await tester.pump();
    await tester.pump();
    expect(owners.length, 2);
    expect(owners.last.view.trip, isNull);
    expect(owners.last.delivery.listeners, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(owners.length, 3);
    expect(owners.last.view.trip!.id, f.tripId);
    expect(first.view.trip, isNull);
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covered'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(owners.last.view.trip, isNull);
    expect(owners.last.retirementModes.last, isTrue);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(owners.last.view.trip, isNull);
    for (final h in owners) {
      expect(h.port.calls, isEmpty);
    }
    await tester.pumpWidget(const SizedBox());
    for (final h in owners) {
      await h.dispose(disposeController: false);
    }
  });
}
