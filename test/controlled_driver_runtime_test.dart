import 'dart:async';
import 'dart:convert';
import 'helpers/cash_assignment_fixtures.dart' as cash;
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/repositories/cash_booking_assignment_repository.dart';
import 'dart:io';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_repository.dart';
import 'package:ridex/features/driver_flow/data/driver_offer_command_journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/router/route_guards.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_offer_discovery_port.dart';
import 'package:ridex/features/driver_flow/presentation/providers/controlled_driver_runtime.dart';
import 'package:ridex/features/driver_flow/presentation/providers/canonical_driver_presentation_controller.dart';
import 'package:ridex/features/driver_flow/presentation/screens/controlled_driver_runtime_screen.dart';
import 'helpers/canonical_driver_presentation_harness.dart' show driverSession;
import 'helpers/fake_canonical_driver_port.dart' as f;

class _FlushFailure extends NativeCompletionJournalIo {
  const _FlushFailure();
  @override
  Future<void> flush(RandomAccessFile handle) async =>
      throw const FileSystemException('flush unavailable');
}

class _Port extends f.FakeCanonicalDriverPort
    implements CanonicalDriverOfferDiscoveryPort {
  int polls = 0;
  bool network = true;
  List<Map<String, Object?>> rows = [
    {...f.offerRow(), 'offered_at': f.now.toIso8601String()}
  ];
  @override
  Future<List<Map<String, Object?>>> readOfferedRows(DateTime after) async {
    polls++;
    if (!network) throw StateError('private backend error');
    return rows.map(Map<String, Object?>.of).toList();
  }
}

class _Session extends SessionController {
  _Session(this.initial);
  final SessionState initial;
  @override
  SessionState build() => initial;
  void replace(SessionState value) => state = value;
}

class _Harness {
  _Harness(
      {SessionState? initial,
      bool enabled = true,
      bool replayAuth = false,
      bool commands = false}) {
    overrides = [
      driverOfferCommandJournalProvider.overrideWithValue(
          DriverOfferCommandJournal(directory: journalDirectory)),
      controlledDriverCommandsEnabledProvider.overrideWithValue(commands),
      sessionControllerProvider
          .overrideWith(() => session = _Session(initial ?? driverSession())),
      controlledDriverRuntimeEnabledProvider.overrideWithValue(enabled),
      controlledDriverInputsProvider
          .overrideWith((ref) => ControlledDriverInputs(
              port: port,
              discovery: port,
              target: target,
              clock: () => now,
              readVehicle: () async => vehicle,
              release: () async {
                releases++;
              },
              authEvents: replayAuth
                  ? Stream<void>.multi((events) {
                      events.add(null);
                      final sub = auth.stream.listen(events.add,
                          onError: events.addError, onDone: events.close);
                      events.onCancel = sub.cancel;
                    })
                  : auth.stream)),
    ];
  }
  late final List<Override> overrides;
  final journalDirectory =
      Directory.systemTemp.createTempSync('ridex-offer-test-');
  final port = _Port();
  final auth = StreamController<void>.broadcast(sync: true);
  final target = CanonicalDriverTestTarget(
      backend: f.backend, driverId: f.driverId, vehicleId: f.vehicleId);
  Map<String, Object?>? vehicle = {
    'id': f.vehicleId,
    'driver_id': f.driverId,
    'is_active': true
  };
  DateTime now = f.now;
  int releases = 0;
  late _Session session;
  late ProviderContainer container;
  ControlledDriverRuntime? get runtime =>
      container.read(controlledDriverRuntimeProvider);
  bool launcher = false;
  Widget page() => ProviderScope(
      overrides: overrides,
      child: Builder(builder: (context) {
        container = ProviderScope.containerOf(context);
        return MaterialApp(
            home: launcher
                ? Builder(
                    builder: (context) => Scaffold(
                        body: TextButton(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const ControlledDriverRuntimeScreen())),
                            child: const Text('Open controlled'))))
                : const ControlledDriverRuntimeScreen());
      }));
  Future<void> dispose() async {
    await auth.close();
    if (journalDirectory.existsSync()) {
      journalDirectory.deleteSync(recursive: true);
    }
  }
}

void main() {
  test('build gate denies release even with opt-in; defaults deny', () {
    for (final release in [true, false]) {
      for (final optIn in [true, false]) {
        expect(controlledDriverRuntimeAllowed(release: release, optIn: optIn),
            !release && optIn);
      }
    }
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(controlledDriverRuntimeEnabledProvider), isFalse);
    expect(c.read(approvedCanonicalDriverTargetProvider), isNull);
    expect(c.read(controlledDriverRuntimeProvider), isNull);
  });
  test('controlled route uses existing session and role guard', () {
    const path = '/driver/canonical-discovery';
    expect(redirectForLocation(path, const SessionState.unauthenticated()),
        '/sign-in');
    expect(redirectForLocation(path, driverSession(role: RideRole.rider)),
        '/rider/home');
    expect(redirectForLocation(path, driverSession(blocked: true)),
        '/account-blocked');
    expect(redirectForLocation(path, driverSession()), isNull);
  });

  Future<void> pump(WidgetTester tester, _Harness h) async {
    await tester.pumpWidget(h.page());
    await tester.pump();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester, _Harness h) async {
    expect(h.port.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await h.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> advance(WidgetTester tester, _Harness h, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      h.now = h.now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
  }

  testWidgets(
      'signed-in Driver mounts real B07/B08/B09; fields canonically reread and commands off',
      (tester) async {
    final h = _Harness();
    await pump(tester, h);
    expect(find.text('Offer ID: ${f.offerId}'), findsOneWidget);
    expect(h.port.reads, contains('offer'));
    final runtime = h.runtime!;
    expect(runtime.repository.offerCommandsEnabled, isFalse);
    expect(runtime.controller.view.canDecide, isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Accept canonical offer'))
            .onPressed,
        isNull);
    expect(find.text('Completion unavailable'), findsOneWidget);
    expect(find.text('Fare unavailable. Route unavailable.'), findsOneWidget);
    await finish(tester, h);
  });
  testWidgets(
      'sign-in requires fresh guarded entry; stopped unauthenticated route never autostarts',
      (tester) async {
    final h = _Harness(initial: const SessionState.unauthenticated());
    await pump(tester, h);
    expect(h.port.polls, 0);
    h.session.replace(driverSession());
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Offer ID:'), findsNothing);
    expect(h.runtime, isNull);
    await finish(tester, h);
    final signedIn = _Harness();
    await pump(tester, signedIn);
    expect(find.text('Offer ID: ${f.offerId}'), findsOneWidget);
    await finish(tester, signedIn);
  });
  testWidgets(
      'real Navigator Back releases owner; reentry has one fresh subscription',
      (tester) async {
    final h = _Harness()..launcher = true;
    await pump(tester, h);
    await tester.tap(find.text('Open controlled'));
    await tester.pumpAndSettle();
    final old = h.runtime!;
    expect(find.text('Offer ID: ${f.offerId}'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(h.releases, 1);
    final polls = h.port.polls;
    await advance(tester, h, 2);
    expect(h.port.polls, polls);
    await tester.tap(find.text('Open controlled'));
    await tester.pumpAndSettle();
    expect(identical(old, h.runtime), isFalse);
    expect(find.text('Offer ID: ${f.offerId}'), findsOneWidget);
    await finish(tester, h);
  });
  testWidgets('covering route invalidates polling until explicit reentry',
      (tester) async {
    final h = _Harness();
    await pump(tester, h);
    final context = tester.element(find.byType(ControlledDriverRuntimeScreen));
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covered')))));
    await tester.pumpAndSettle();
    final count = h.port.polls;
    await advance(tester, h, 3);
    expect(h.port.polls, count);
    await finish(tester, h);
  });
  testWidgets(
      'SDK replay of captured auth observation does not revoke new owner',
      (tester) async {
    final h = _Harness(replayAuth: true);
    await pump(tester, h);
    expect(find.text('Offer ID: ${f.offerId}'), findsOneWidget);
    await finish(tester, h);
  });
  for (final mode in ['background', 'auth-change']) {
    testWidgets(
        '$mode plus same-Driver session refresh cannot silently restart route owner',
        (tester) async {
      final h = _Harness();
      await pump(tester, h);
      final original = h.runtime!;
      if (mode == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else {
        h.port.sessionIdentity = Object();
        h.auth.add(null);
      }
      await tester.pump();
      final polls = h.port.polls;
      h.session.replace(driverSession());
      await tester.pump();
      await advance(tester, h, 3);
      expect(identical(h.runtime, original), isTrue);
      expect(h.port.polls, polls);
      expect(find.textContaining('Offer ID:'), findsNothing);
      await finish(tester, h);
    });
  }
  testWidgets('no offer remains empty without fabricated data', (tester) async {
    final h = _Harness();
    h.port.rows = [];
    await pump(tester, h);
    expect(h.runtime!.controller.view.phase,
        CanonicalDriverPresentationPhase.empty);
    expect(find.textContaining('Offer ID:'), findsNothing);
    await finish(tester, h);
  });
  for (final mode in ['flag-off', 'signed-out', 'rider', 'blocked']) {
    testWidgets('$mode cannot start polling', (tester) async {
      final h = _Harness(
          enabled: mode != 'flag-off',
          initial: switch (mode) {
            'signed-out' => const SessionState.unauthenticated(),
            'rider' => driverSession(role: RideRole.rider),
            'blocked' => driverSession(blocked: true),
            _ => driverSession(),
          });
      await pump(tester, h);
      expect(h.port.polls, 0);
      expect(h.runtime, isNull);
      await finish(tester, h);
    });
  }
  for (final mode in [
    'backend-blocked',
    'vehicle-inactive',
    'vehicle-foreign',
    'vehicle-missing',
    'wrong-vehicle',
    'foreign-driver'
  ]) {
    testWidgets('$mode rejects canonical presentation', (tester) async {
      final h = _Harness();
      switch (mode) {
        case 'backend-blocked':
          h.port.user!['is_blocked'] = true;
        case 'vehicle-inactive':
          h.vehicle!['is_active'] = false;
        case 'vehicle-foreign':
          h.vehicle!['driver_id'] = f.otherId;
        case 'vehicle-missing':
          h.vehicle = null;
        case 'wrong-vehicle':
          h.port.offer!['vehicle_id'] = f.otherId;
        case 'foreign-driver':
          h.port.driver = f.otherId;
      }
      await pump(tester, h);
      expect(find.textContaining('Offer ID:'), findsNothing);
      expect(h.runtime!.controller.view.canDecide, isFalse);
      await finish(tester, h);
    });
  }
  testWidgets('15 second deadline hides offer and never dispatches',
      (tester) async {
    final h = _Harness();
    await pump(tester, h);
    await advance(tester, h, 15);
    expect(find.textContaining('Offer ID:'), findsNothing);
    expect(h.runtime!.controller.view.canDecide, isFalse);
    await finish(tester, h);
  });
  testWidgets(
      'duplicate observations do not create duplicate subscription or reread',
      (tester) async {
    final h = _Harness();
    await pump(tester, h);
    final count = h.port.reads.where((r) => r == 'offer').length;
    await advance(tester, h, 4);
    expect(h.port.polls, 3);
    expect(h.port.reads.where((r) => r == 'offer').length, count);
    await finish(tester, h);
  });
  testWidgets('out-of-order observations hide data', (tester) async {
    final h = _Harness();
    h.port.rows.single['version'] = 2;
    h.port.offer!['version'] = 2;
    await pump(tester, h);
    h.port.rows.single['version'] = 1;
    await advance(tester, h, 2);
    expect(find.textContaining('Offer ID:'), findsNothing);
    await finish(tester, h);
  });
  testWidgets('network loss hides data; recovery requires B07 reread',
      (tester) async {
    final h = _Harness();
    await pump(tester, h);
    h.port.network = false;
    await advance(tester, h, 2);
    expect(find.textContaining('Offer ID:'), findsNothing);
    h.port.network = true;
    await advance(tester, h, 2);
    expect(find.text('Offer ID: ${f.offerId}'), findsOneWidget);
    expect(h.port.reads.where((r) => r == 'offer').length, greaterThan(1));
    await finish(tester, h);
  });
  for (final logout in [true, false]) {
    testWidgets(
        'session replacement logout=$logout revokes old views and reads',
        (tester) async {
      final h = _Harness();
      await pump(tester, h);
      final old = h.runtime!;
      final view = old.controller.view;
      h.session.replace(logout
          ? const SessionState.unauthenticated()
          : driverSession(id: f.otherId));
      expect(view.offer, isNull);
      await tester.pump();
      await advance(tester, h, 3);
      expect(find.textContaining('Offer ID:'), findsNothing);
      await finish(tester, h);
    });
  }
  testWidgets('auth error stops polling and does not expose raw error',
      (tester) async {
    final h = _Harness();
    await pump(tester, h);
    final view = h.runtime!.controller.view;
    h.auth.addError(StateError('private token'));
    await tester.pump();
    final polls = h.port.polls;
    expect(view.offer, isNull);
    await advance(tester, h, 3);
    expect(h.port.polls, polls);
    expect(find.textContaining('private token'), findsNothing);
    await finish(tester, h);
  });
  testWidgets(
      'background stops owner; resume does not restart commands or polling',
      (tester) async {
    final h = _Harness();
    await pump(tester, h);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final count = h.port.polls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await advance(tester, h, 3);
    expect(h.port.polls, count);
    expect(find.textContaining('Offer ID:'), findsNothing);
    await finish(tester, h);
  });
  testWidgets(
      'navigation disposal and remount release old polling exactly once',
      (tester) async {
    final h = _Harness();
    await pump(tester, h);
    final old = h.runtime!;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(h.releases, 1);
    final count = h.port.polls;
    await advance(tester, h, 2);
    expect(h.port.polls, count);
    await pump(tester, h);
    expect(identical(h.runtime, old), isFalse);
    expect(find.text('Offer ID: ${f.offerId}'), findsOneWidget);
    await finish(tester, h);
    expect(h.releases, 2);
  });
  testWidgets(
      'Trip identity from canonical availability is independently reread',
      (tester) async {
    final h = _Harness();
    h.port.rows = [];
    h.port.accept();
    await pump(tester, h);
    expect(find.text('Trip ID: ${f.tripId}'), findsOneWidget);
    expect(h.port.reads, contains('trip'));
    expect(find.text('Trip status: accepted'), findsOneWidget);
    await finish(tester, h);
  });
  testWidgets('foreign canonical Trip never appears', (tester) async {
    final h = _Harness();
    h.port.rows = [];
    h.port.accept();
    h.port.trip!['driver_id'] = f.otherId;
    await pump(tester, h);
    expect(find.textContaining('Trip ID:'), findsNothing);
    await finish(tester, h);
  });
  testWidgets('late discovery after disposal cannot publish or replay',
      (tester) async {
    final h = _Harness();
    final wait = Completer<void>();
    h.port.beforeRead = (_) => wait.future;
    await pump(tester, h);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    wait.complete();
    await tester.pump();
    expect(h.port.polls, 0);
    await h.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'approved command preserves intent and proves Trip by reread after lost response',
      (tester) async {
    final h = _Harness(commands: true);
    await pump(tester, h);
    final replacements = {
      cash.bId: f.bookingId,
      cash.qId: f.quoteId,
      cash.rId: f.otherId,
      cash.dId: f.driverId,
      cash.vId: f.vehicleId,
      cash.oId: f.offerId,
      cash.tId: f.tripId
    };
    String translate(String value) {
      for (final entry in replacements.entries) {
        value = value.replaceAll(entry.key, entry.value);
      }
      return value;
    }

    final rider = cash.Fake()
      ..owner = RiderAssignmentOwner(f.otherId, 'local', 1, Object())
      ..value = jsonDecode(translate(jsonEncode(cash.booking())))
          as Map<String, dynamic>;
    final reference = ConfirmedBookingReference(
        command: PendingFareLock(
            bookingRequestId: f.bookingId,
            expectedBookingVersion: 1,
            fareQuoteId: f.quoteId,
            expectedQuoteVersion: 1,
            riderId: f.otherId,
            status: PendingLockRecoveryStatus.uncertain,
            createdAt: f.now),
        quote: FareQuote.fromJson(
            jsonDecode(translate(jsonEncode(cash.quote())))
                as Map<String, dynamic>));
    final matchedGraph = rider.value!;
    rider.value = {
      ...matchedGraph,
      'status': 'searching',
      'version': 3,
      'trips': <Object?>[],
      'driver_match_offers': <Object?>[]
    };
    expect(
        await tester.runAsync(
            () => CashBookingAssignmentRepository(rider).read(reference)),
        isNull);
    h.port.onCommand = (_) async {
      // One simulated atomic backend commit is consumed by BOTH transports.
      rider.value = matchedGraph;
      final graphTrip =
          (matchedGraph['trips'] as List).single as Map<String, dynamic>;
      h.port.offer = {...h.port.offer!, 'status': 'accepted', 'version': 2};
      h.port.trip = Map<String, Object?>.from(graphTrip);
      h.port.availability = {
        ...h.port.availability!,
        'state': 'onTrip',
        'reserved_booking_request_id': null,
        'active_trip_id': graphTrip['id'],
        'version': 4
      };
      throw StateError('lost response');
    };
    final runtime = h.runtime!;
    final view = runtime.controller.view;
    await tester.runAsync(() => Future.wait([
          runtime.controller.decide(view, CanonicalOfferDecision.accept),
          runtime.controller.decide(view, CanonicalOfferDecision.accept),
        ]));
    await tester.pump();
    expect(h.port.calls.length, 1);
    expect(h.port.calls.single.$2, f.offerId);
    expect(h.port.calls.single.$3, 1);
    expect(runtime.controller.view.trip?.id, f.tripId);
    // The Rider independently reads the SAME post-accept canonical graph.
    // Matching hints/RPC responses never supply assignment authority.
    final assigned = await tester
        .runAsync(() => CashBookingAssignmentRepository(rider).read(reference));
    expect(assigned?.tripId, runtime.controller.view.trip?.id);
    expect(assigned?.offerId, h.port.calls.single.$2);
    expect(assigned?.bookingId, f.bookingId);
    expect(assigned?.fareQuoteId, f.quoteId);
    rider.owner = RiderAssignmentOwner(f.driverId, 'local', 2, Object());
    await tester.runAsync(() => expectLater(
        CashBookingAssignmentRepository(rider).read(reference),
        throwsA(isA<CashAssignmentException>())));

    expect(runtime.controller.view.canDecide, isFalse);
    await tester.pumpWidget(const SizedBox());
    await h.dispose();
  });

  test(
      'durable journal refuses replay across reconstructed owners and changed versions',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('ridex-offer-persistence-');
    addTearDown(() => directory.delete(recursive: true));
    final results = await Future.wait(List.generate(2, (i) async {
      try {
        await DriverOfferCommandJournal(directory: directory)
            .reserve(f.backend, f.driverId, f.offerId, 1, 'original-$i', true);
        return true;
      } on Object {
        return false;
      }
    }));
    expect(results.where((r) => r).length, 1);
    await expectLater(
        DriverOfferCommandJournal(directory: directory)
            .reserve(f.backend, f.driverId, f.offerId, 2, 'replacement', false),
        throwsA(isA<FileSystemException>()));
    final files =
        await directory.list(recursive: true).where((f) => f is File).toList();
    expect(files.length, 1);
    expect(await (files.single as File).readAsString(), contains('original-'));
  });

  test('failed flush leaves reservation blocking reconstructed owners',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('ridex-offer-fault-');
    addTearDown(() => directory.delete(recursive: true));
    await expectLater(
        DriverOfferCommandJournal(
                directory: directory, io: const _FlushFailure())
            .reserve(f.backend, f.driverId, f.offerId, 1, 'original', true),
        throwsA(isA<FileSystemException>()));
    await expectLater(
        DriverOfferCommandJournal(directory: directory)
            .reserve(f.backend, f.driverId, f.offerId, 1, 'replay', true),
        throwsA(isA<FileSystemException>()));
  });

  test('runtime has no financial SDK, direct auth or write RPC seam', () {
    final source = File(
            'lib/features/driver_flow/presentation/providers/controlled_driver_runtime.dart')
        .readAsStringSync();
    for (final forbidden in [
      '.rpc(',
      '.insert(',
      '.update(',
      'SupabaseClient(',
      '.signIn',
      'complete_trip',
      'settlement',
      'issue_receipt'
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });
}
