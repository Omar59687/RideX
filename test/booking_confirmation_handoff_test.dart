import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridex/app/router/app_router.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';

import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/features/booking/presentation/screens/booking_confirmation_screen.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/widgets/app_button.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/fare_lock_recovery.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';

final _command = PendingFareLock(
  bookingRequestId: 'booking-1',
  expectedBookingVersion: 1,
  fareQuoteId: 'quote-1',
  expectedQuoteVersion: 1,
  riderId: 'rider-1',
  status: PendingLockRecoveryStatus.uncertain,
  createdAt: DateTime.utc(2026, 10, 10, 12),
);

// Matches the migration 007 projection; a lock preserves the original expiry
// and quote version, links the booking, and advances its version by one.
Map<String, dynamic> _quoteRow(
        {String status = 'locked',
        String id = 'quote-1',
        int version = 1,
        String rider = 'rider-1'}) =>
    {
      'id': id,
      'booking_request_id': 'booking-1',
      'rider_id': rider,
      'status': status,
      'quote_version': version,
      'pricing_version': 1,
      'currency': 'JOD',
      'fixed_fare_fils': 2000,
      'breakdown': {
        'base_fare_fils': 500,
        'distance_fils': 1200,
        'duration_fils': 300,
        'stops_fils': 0,
        'subtotal_fils': 2000,
        'minimum_fare_fils': 1000,
        'rounding_increment_fils': 50,
        'fixed_fare_fils': 2000
      },
      'created_at': '2026-10-10T12:00:00Z',
      'expires_at': '2026-10-10T12:10:00Z',
      'locked_at': status == 'locked' ? '2026-10-10T12:01:00Z' : null,
      'route_distance_meters': 5400,
      'route_duration_seconds': 720,
    };
Map<String, dynamic> _bookingRow(
        {int version = 2,
        String? link = 'quote-1',
        String status = 'draft',
        List<Map<String, dynamic>>? quotes}) =>
    {
      'id': 'booking-1',
      'rider_id': 'rider-1',
      'version': version,
      'status': status,
      'fare_quote_id': link,
      'fare_quotes': quotes ?? [_quoteRow()],
    };

class _Auth extends MockAuthRepository {
  AppUser? user = MockData.demoRider;
  @override
  Future<AppUser?> restoreSession() async => user;
}

class _Store implements PendingFareLockStore {
  final slots = <String, PendingFareLock>{'rider-1': _command};
  bool failClear = false;
  bool corrupt = false;
  int deletes = 0;
  @override
  Future<void> save(PendingFareLock command) async {
    slots[command.riderId] = command;
  }

  @override
  Future<PendingFareLock?> loadForRider(String riderId) async => slots[riderId];
  @override
  Future<PendingFareLockSlot> inspectForRider(String riderId) async {
    if (corrupt) return const PendingFareLockSlot.corrupt();
    final command = slots[riderId];
    return command == null
        ? const PendingFareLockSlot.absent()
        : PendingFareLockSlot.valid(command);
  }

  @override
  Future<void> clearForRider(String riderId) async {
    if (failClear) throw StateError('storage unavailable');
    deletes++;
    slots.remove(riderId);
  }
}

class _Harness {
  _Harness(FareCanonicalReader reader, {SupabaseClient? client}) {
    repository = SupabaseFareRepository(
      bookingMutationGate: (dispatch) => pending.runBookingMutation(dispatch),
      rpc: (
              {required String name,
              required Map<String, dynamic> params}) async =>
          throw StateError('recovery must not mutate'),
      quoteEdge: (_) async => throw StateError('recovery must not requote'),
      canonicalReader: reader,
      bookingConfirmer: (
          {required bookingRequestId,
          required expectedVersion,
          required idempotencyKey,
          required riderId}) async {
        confirmations++;
        expectSync(bookingRequestId, _command.bookingRequestId);
        expectSync(expectedVersion, 2);
        expectSync(riderId, _command.riderId);
        expectSync(idempotencyKey, 'confirm:booking-1:2');
        if (confirmGate != null) await confirmGate!.future;
        confirmed = true;
        if (loseResponse) throw const FareException(FareFailure.networkFailure);
        return {'booking_request_id': bookingRequestId, 'status': 'confirmed'};
      },
    );
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      appErrorReporterProvider.overrideWithValue(const NoopAppErrorReporter()),
      if (client == null) fareRepositoryProvider.overrideWithValue(repository),
      if (client != null) supabaseClientProvider.overrideWithValue(client),
      pendingFareLockStoreProvider.overrideWithValue(store),
    ]);
  }
  int confirmations = 0;
  bool confirmed = false;
  bool loseResponse = false;
  Completer<void>? confirmGate;
  final auth = _Auth();
  final store = _Store();
  late final SupabaseFareRepository repository;
  late final ProviderContainer container;
  PendingFareLockController get pending =>
      container.read(pendingFareLockControllerProvider.notifier);
  Future<void> authenticate() async {
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await pending.restorePendingLock();
  }
}

Future<FareBookingRef> _createDraft(_Harness h) =>
    h.repository.createBookingDraft(
      pickup: const FareRouteLocation(latitude: 31.95, longitude: 35.92),
      destination: const FareRouteLocation(latitude: 32.0, longitude: 35.95),
      vehicleTypeCode: 'economy',
      paymentMethod: 'cash',
    );

class _LoopbackOverrides extends HttpOverrides {}

final _blocked = throwsA(isA<FareException>());

_Harness _readyHarness() {
  late _Harness h;
  h = _Harness(({required bookingRequestId, required riderId}) async => [
        _bookingRow(
            version: h.confirmed ? 3 : 2,
            status: h.confirmed ? 'confirmed' : 'draft')
      ]);
  return h;
}

void main() {
  testWidgets(
      'production gate and GoRouter hand off fresh lock, redirect and restore confirmation',
      (tester) async {
    await HttpOverrides.runWithHttpOverrides(() async {
      var confirmed = false;
      var submissions = 0;
      var drafts = 0;
      late _Harness h;
      late FareRepository fare;
      await tester.runAsync(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path.endsWith('rider_create_booking_draft')) {
            drafts++;
            request.response
                .write(jsonEncode({'id': 'booking-1', 'version': 1}));
          } else if (request.uri.path.endsWith('rider_lock_fare_quote')) {
            request.response.write(jsonEncode(_quoteRow()));
          } else if (request.uri.path.endsWith('rider_confirm_booking')) {
            submissions++;
            final body =
                jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            expectSync(body['target_booking_request_id'], 'booking-1');
            expectSync(body['expected_version'], 2);
            expectSync(body['idempotency_key'], 'confirm:booking-1:2');
            confirmed = true;
            request.response.write(jsonEncode(
                {'booking_request_id': 'booking-1', 'status': 'confirmed'}));
          } else {
            expectSync(request.uri.path, '/rest/v1/booking_requests');
            request.response.write(jsonEncode([
              _bookingRow(
                  version: confirmed ? 3 : 2,
                  status: confirmed ? 'confirmed' : 'draft')
            ]));
          }
          await request.response.close();
        });
        final client = SupabaseClient(
            'http://127.0.0.1:${server.port}', 'offline-publishable');
        addTearDown(client.dispose);
        await client.auth.setInitialSession(jsonEncode({
          'access_token': 'offline-test-session',
          'token_type': 'bearer',
          'user': {'id': 'rider-1', 'aud': 'authenticated'}
        }));
        h = _Harness(
            ({required bookingRequestId, required riderId}) async => [],
            client: client);
        addTearDown(h.container.dispose);
        h.store.slots.clear();
        await h.authenticate();
        fare = h.container.read(fareRepositoryProvider);
        await fare.createBookingDraft(
            pickup: const FareRouteLocation(latitude: 31.95, longitude: 35.91),
            destination:
                const FareRouteLocation(latitude: 31.96, longitude: 35.92),
            vehicleTypeCode: 'economy',
            paymentMethod: 'cash');
        await h.pending.stageForDispatch(_command);
        await fare.lockQuote(
            bookingRequestId: 'booking-1',
            fareQuoteId: 'quote-1',
            expectedBookingVersion: 1,
            expectedQuoteVersion: 1);
      });
      final router = h.container.read(appRouterProvider);
      addTearDown(router.dispose);
      router.go('/rider/fare');
      await tester.pumpWidget(UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp.router(
              theme: AppTheme.light(), routerConfig: router)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Review original booking'), 300,
          scrollable: find.byType(Scrollable).first);
      final review = tester
          .widget<AppButton>(
              find.widgetWithText(AppButton, 'Review original booking'))
          .onPressed!;
      review();
      review();
      await tester.pump();
      await _settleNetwork(tester);
      expect(find.text('Confirm original booking'), findsOneWidget);
      await tester.tap(find.text('Confirm original booking'));
      await tester.pump();
      await _settleNetwork(tester);
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(submissions, 1);
      expect(drafts, 1);
      await expectLater(
          fare.updateBookingDraft(
              bookingRequestId: 'booking-1',
              expectedBookingVersion: 3,
              pickup:
                  const FareRouteLocation(latitude: 31.95, longitude: 35.91),
              destination:
                  const FareRouteLocation(latitude: 31.96, longitude: 35.92),
              vehicleTypeCode: 'economy',
              paymentMethod: 'cash'),
          _blocked);
      h.auth.user = null;
      await h.container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/sign-in');
      h.auth.user = MockData.demoRider;
      await h.authenticate();
      router.go('/rider/confirmation');
      await tester.pump();
      await _settleNetwork(tester);
      await _settleNetwork(tester);
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(submissions, 1);
      expect(drafts, 1);
      expect(h.store.deletes, 0);
      await tester.pumpWidget(const SizedBox());
      // Drain dart:io's idle keep-alive timers created inside the widget zone.
      await tester.pump(const Duration(seconds: 16));
    }, _LoopbackOverrides());
  });
  test(
      'fresh locked lineage confirms once with unchanged booking quote and fare',
      () async {
    final h = _readyHarness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    final locked = await h.pending.bookingHandoff();
    final confirmed = await h.pending.bookingHandoff(confirm: true);
    expect(locked.isConfirmed, false);
    expect(confirmed.isConfirmed, true);
    expect(confirmed.booking.id, locked.booking.id);
    expect(confirmed.quote, locked.quote);
    expect(confirmed.quote.fixedFareFils, 2000);
    expect(confirmed.booking.version, 3);
    expect(h.confirmations, 1);
    expect(h.store.deletes, 0);
    expect(h.store.slots['rider-1'], _command);
    await expectLater(_createDraft(h), _blocked);
  });

  test('canonical recovered lock and recreated owner hand off same lineage',
      () async {
    final h = _readyHarness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    expect((await h.pending.recoverCanonically())!.status,
        FareLockRecoveryStatus.confirmed);
    h.container.invalidate(pendingFareLockControllerProvider);
    expect((await h.pending.bookingHandoff()).command, _command);
    await h.pending.bookingHandoff(confirm: true);
    h.pending.clearMemory();
    await h.authenticate();
    expect((await h.pending.bookingHandoff()).isConfirmed, true);
    expect(h.confirmations, 1);
  });

  test('uncertain original and advanced lifecycle never submit', () async {
    for (final rows in <List<Map<String, dynamic>>>[
      [],
      [
        _bookingRow(
            version: 1, link: null, quotes: [_quoteRow(status: 'calculated')])
      ],
      [_bookingRow(version: 4, status: 'searching')],
      [_bookingRow(link: 'other-quote')],
    ]) {
      final h = _Harness(
          ({required bookingRequestId, required riderId}) async => rows);
      await h.authenticate();
      await expectLater(h.pending.bookingHandoff(confirm: true), _blocked);
      expect(h.confirmations, 0);
      expect(h.store.deletes, 0);
      h.container.dispose();
    }
  });

  test(
      'duplicate queued confirmation and lost response reconcile without resubmission',
      () async {
    final h = _readyHarness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.loseResponse = true;
    await expectLater(h.pending.bookingHandoff(confirm: true), _blocked);
    final results = await Future.wait([
      h.pending.bookingHandoff(confirm: true),
      h.pending.bookingHandoff(confirm: true)
    ]);
    expect(results.every((r) => r.isConfirmed), true);
    expect(h.confirmations, 1);
    expect(h.store.slots['rider-1'], _command);
  });

  test(
      'same Rider session refresh during canonical read blocks delayed submission',
      () async {
    final gate = Completer<List<Map<String, dynamic>>>();
    final h = _Harness(
        ({required bookingRequestId, required riderId}) => gate.future);
    addTearDown(h.container.dispose);
    await h.authenticate();
    final result = h.pending.bookingHandoff(confirm: true);
    final blocked = expectLater(result, _blocked);
    await Future<void>.delayed(Duration.zero);
    await h.container.read(sessionControllerProvider.notifier).refreshSession();
    gate.complete([_bookingRow()]);
    await blocked;
    expect(h.confirmations, 0);
  });

  test(
      'different Rider and late confirmation result cannot publish old ownership',
      () async {
    final h = _readyHarness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.confirmGate = Completer<void>();
    final result = h.pending.bookingHandoff(confirm: true);
    final blocked = expectLater(result, _blocked);
    await Future<void>.delayed(Duration.zero);
    h.auth.user = const AppUser(
        id: 'rider-2',
        name: 'Other',
        email: 'other@test.example',
        role: RideRole.rider);
    await h.container.read(sessionControllerProvider.notifier).refreshSession();
    h.confirmGate!.complete();
    await blocked;
    await expectLater(h.pending.bookingHandoff(confirm: true), _blocked);
    expect(h.store.slots['rider-1'], _command);
    expect(h.store.deletes, 0);
  });

  testWidgets(
      'screen confirmation repeats safely and re-entry restores confirmed fare',
      (tester) async {
    final h = _readyHarness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    Future<void> pump() async {
      await tester.pumpWidget(UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
              theme: AppTheme.light(),
              home: const BookingConfirmationScreen())));
      await tester.pumpAndSettle();
    }

    await pump();
    expect(find.text('Locked fare: JOD 2.00'), findsOneWidget);
    final callback = tester
        .widget<AppButton>(
            find.widgetWithText(AppButton, 'Confirm original booking'))
        .onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    callback();
    await tester.pumpAndSettle();
    expect(h.confirmations, 1);
    expect(find.text('Booking confirmed'), findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '));
    await tester.pumpWidget(const SizedBox());
    await pump();
    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.text('Locked fare: JOD 2.00'), findsOneWidget);
    expect(h.store.deletes, 0);
  });

  testWidgets(
      'screen disposal during confirmation preserves evidence and late result',
      (tester) async {
    final h = _readyHarness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(home: const BookingConfirmationScreen())));
    await tester.pumpAndSettle();
    h.confirmGate = Completer<void>();
    await tester.tap(find.text('Confirm original booking'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    h.confirmGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(h.store.slots['rider-1'], _command);
    expect((await h.pending.bookingHandoff()).isConfirmed, true);
  });
}

Future<void> _settleNetwork(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Canonical handoff did not settle');
}
