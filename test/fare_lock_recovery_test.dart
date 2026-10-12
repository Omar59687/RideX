import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridex/core/services/fare/supabase_fare_lock_reader.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/features/booking/presentation/screens/fare_estimate_screen.dart';

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
  _Harness(FareCanonicalReader reader) {
    repository = SupabaseFareRepository(
      bookingMutationGate: (dispatch) => pending.runBookingMutation(dispatch),
      rpc: (
              {required String name,
              required Map<String, dynamic> params}) async =>
          throw StateError('recovery must not mutate'),
      quoteEdge: (_) async => throw StateError('recovery must not requote'),
      canonicalReader: reader,
    );
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      appErrorReporterProvider.overrideWithValue(const NoopAppErrorReporter()),
      fareRepositoryProvider.overrideWithValue(repository),
      pendingFareLockStoreProvider.overrideWithValue(store),
    ]);
  }
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

final _mutationBlocked = throwsA(isA<FareException>()
    .having((error) => error.failure, 'failure', FareFailure.mutationBlocked));

// Flutter widget bindings replace HTTP globally. Enable real HTTP only in
// these loopback-only adapter tests; every URL points to their local server.
class _LoopbackHttpOverrides extends HttpOverrides {}

Future<T> _withLoopback<T>(Future<T> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _LoopbackHttpOverrides());

void main() {
  group('Supabase read adapter', () {
    Future<void> setRider(SupabaseClient client, String id) =>
        client.auth.setInitialSession(jsonEncode({
          'access_token': 'offline-test-session',
          'token_type': 'bearer',
          'user': {'id': id, 'aud': 'authenticated'}
        }));

    test(
        'one GET selects booking plus all quotes using explicit FK and owner filters',
        () => _withLoopback(() async {
              final requests = <HttpRequest>[];
              final server =
                  await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
              addTearDown(() => server.close(force: true));
              server.listen((request) async {
                requests.add(request);
                request.response.headers.contentType = ContentType.json;
                request.response.write(jsonEncode([_bookingRow()]));
                await request.response.close();
              });
              final client = SupabaseClient(
                  'http://127.0.0.1:${server.port}', 'offline-publishable');
              addTearDown(client.dispose);
              await setRider(client, 'rider-1');
              final rows = await SupabaseFareLockReader(client)
                  .read(bookingRequestId: 'booking-1', riderId: 'rider-1');
              expect(rows, hasLength(1));
              expect(requests, hasLength(1));
              final request = requests.single;
              expect(request.method, 'GET');
              expect(request.uri.path, '/rest/v1/booking_requests');
              expect(request.uri.queryParameters['id'], 'eq.booking-1');
              expect(request.uri.queryParameters['rider_id'], 'eq.rider-1');
              expect(request.uri.queryParameters['select'],
                  contains('fare_quotes!fare_quotes_booking_rider_fk('));
              expect(request.uri.queryParameters['limit'], isNull);
              expect(request.uri.queryParameters['order'], isNull);
            }));
    test(
        'wrong SDK rider is rejected before any HTTP request',
        () => _withLoopback(() async {
              int requests = 0;
              final server =
                  await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
              addTearDown(() => server.close(force: true));
              server.listen((request) async {
                requests++;
                request.response.statusCode = 500;
                await request.response.close();
              });
              final client = SupabaseClient(
                  'http://127.0.0.1:${server.port}', 'offline-publishable');
              addTearDown(client.dispose);
              await setRider(client, 'rider-2');
              await expectLater(
                  SupabaseFareLockReader(client)
                      .read(bookingRequestId: 'booking-1', riderId: 'rider-1'),
                  throwsA(isA<FareException>().having(
                      (e) => e.failure, 'failure', FareFailure.unauthorized)));
              expect(requests, 0);
            }));
    test(
        'SDK rider change while GET runs rejects returned records',
        () => _withLoopback(() async {
              late SupabaseClient client;
              final server =
                  await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
              addTearDown(() => server.close(force: true));
              server.listen((request) async {
                await setRider(client, 'rider-2');
                request.response.headers.contentType = ContentType.json;
                request.response.write(jsonEncode([_bookingRow()]));
                await request.response.close();
              });
              client = SupabaseClient(
                  'http://127.0.0.1:${server.port}', 'offline-publishable');
              addTearDown(client.dispose);
              await setRider(client, 'rider-1');
              await expectLater(
                  SupabaseFareLockReader(client)
                      .read(bookingRequestId: 'booking-1', riderId: 'rider-1'),
                  throwsA(isA<FareException>().having(
                      (e) => e.failure, 'failure', FareFailure.unauthorized)));
            }));
  });

  group('fare-screen canonical recovery', () {
    testWidgets(
        'unreadable storage exposes recovery and retries without replacement',
        (tester) async {
      final h = _Harness((
              {required bookingRequestId, required riderId}) async =>
          [_bookingRow()]);
      addTearDown(h.container.dispose);
      h.store.corrupt = true;
      await h.authenticate();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
              theme: AppTheme.light(), home: const FareEstimateScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Fare recovery blocked'), findsOneWidget);
      await tester.ensureVisible(find.text('Check fare status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check fare status'));
      await tester.pumpAndSettle();
      expect(find.text('Fare recovery blocked'), findsOneWidget);
      h.store.corrupt = false;
      await tester.tap(find.text('Check fare status'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('Recovered the fare for your original booking.'),
          findsOneWidget);
      await expectLater(_createDraft(h), _mutationBlocked);
      expect(h.store.slots['rider-1'], _command);
    });
    testWidgets(
        'same-rider restored lock displays original fare without a local route or new booking',
        (tester) async {
      final h = _Harness((
              {required bookingRequestId, required riderId}) async =>
          [_bookingRow()]);
      addTearDown(h.container.dispose);
      await h.authenticate();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
              theme: AppTheme.light(), home: const FareEstimateScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Check fare status'), findsOneWidget);
      await tester.ensureVisible(find.text('Check fare status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check fare status'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Recovered the fare for your original booking. Current route selections may differ.'),
          findsOneWidget);
      expect(h.store.slots['rider-1'], _command);
      expect(find.text('Check fare status'), findsNothing);
    });
    testWidgets(
        'missing canonical records retain the recovery panel and evidence',
        (tester) async {
      final h =
          _Harness(({required bookingRequestId, required riderId}) async => []);
      addTearDown(h.container.dispose);
      await h.authenticate();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
              theme: AppTheme.light(), home: const FareEstimateScreen())));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check fare status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check fare status'));
      await tester.pumpAndSettle();
      expect(find.text('Fare recovery blocked'), findsOneWidget);
      expect(find.text('Check fare status'), findsOneWidget);
      expect(h.store.slots['rider-1'], _command);
    });
  });

  group('canonical read boundary', () {
    test(
        'reads exact rider and booking through injected repository without mutations',
        () async {
      final h = _Harness(({required bookingRequestId, required riderId}) async {
        expect(bookingRequestId, _command.bookingRequestId);
        expect(riderId, _command.riderId);
        return [_bookingRow()];
      });
      addTearDown(h.container.dispose);
      final rows = await h.repository.readCanonicalFareLock(
          bookingRequestId: 'booking-1', riderId: 'rider-1');
      expect(rows.single.quotes.single.quote.status, FareQuoteStatus.locked);
      expect(rows.single.version, 2);
    });
    test('rejects foreign ownership and malformed records', () async {
      for (final row in [
        {..._bookingRow(), 'rider_id': 'rider-2'},
        _bookingRow(quotes: [_quoteRow(rider: 'rider-2')]),
        {..._bookingRow(), 'version': '2'},
        {..._bookingRow(), 'status': 'invented'},
        {..._bookingRow(), 'fare_quotes': null},
      ]) {
        final h = _Harness(
            ({required bookingRequestId, required riderId}) async => [row]);
        addTearDown(h.container.dispose);
        await expectLater(
            h.repository.readCanonicalFareLock(
                bookingRequestId: 'booking-1', riderId: 'rider-1'),
            throwsA(isA<FareException>().having(
                (e) => e.failure, 'failure', FareFailure.invalidResponse)));
      }
    });
    for (final code in ['PGRST301', '401', '403']) {
      test('maps authorization rejection $code', () async {
        final h = _Harness((
                {required bookingRequestId, required riderId}) async =>
            throw FareTransportFailure(code: code));
        addTearDown(h.container.dispose);
        await expectLater(
            h.repository.readCanonicalFareLock(
                bookingRequestId: 'booking-1', riderId: 'rider-1'),
            throwsA(isA<FareException>().having(
                (e) => e.failure,
                'failure',
                code == '403'
                    ? FareFailure.forbidden
                    : FareFailure.unauthorized)));
      });
    }
  });
  group('same-rider canonical recovery', () {
    test(
        'confirmed original linked locked quote retains durable mutation protection',
        () async {
      final h = _Harness((
              {required bookingRequestId, required riderId}) async =>
          [_bookingRow()]);
      addTearDown(h.container.dispose);
      await h.authenticate();
      final result = await h.pending.recoverCanonically();
      expect(result!.status, FareLockRecoveryStatus.confirmed);
      expect(result.command, _command);
      expect(result.booking!.version, 2);
      expect(h.container.read(pendingFareLockControllerProvider), _command);
      expect(h.store.slots['rider-1'], _command);
      expect(h.store.deletes, 0);
      await expectLater(_createDraft(h), _mutationBlocked);
      h.pending.clearMemory();
      // Same-Rider restart/re-entry still cannot abandon the confirmed fare.
      await expectLater(_createDraft(h), _mutationBlocked);
    });
    test('lost response after commit restores from persisted command',
        () async {
      final h = _Harness((
              {required bookingRequestId, required riderId}) async =>
          [_bookingRow()]);
      addTearDown(h.container.dispose);
      await h.authenticate();
      h.pending.clearMemory();
      expect(h.container.read(pendingFareLockControllerProvider), isNull);
      final result = await h.pending.recoverCanonically();
      expect(result!.quote!.id, _command.fareQuoteId);
      expect(result.status, FareLockRecoveryStatus.confirmed);
    });
    test('quote expiry after commit does not invalidate the linked lock',
        () async {
      final h = _Harness((
              {required bookingRequestId, required riderId}) async =>
          [_bookingRow()]);
      addTearDown(h.container.dispose);
      await h.authenticate();
      final result = await h.pending.recoverCanonically();
      expect(
          result!.quote!.isExpiredAt(DateTime.utc(2026, 10, 10, 13)), isTrue);
      expect(result.status, FareLockRecoveryStatus.confirmed);
    });
    final uncertainCases = <String, List<Map<String, dynamic>>>{
      'original request still uncertain': [
        _bookingRow(
            version: 1, link: null, quotes: [_quoteRow(status: 'calculated')])
      ],
      'booking version advanced after a lock': [_bookingRow(version: 3)],
      'missing booking record': [],
      'missing quote record': [_bookingRow(quotes: [])],
      'inconsistent booking/quote linkage': [_bookingRow(link: 'other-quote')],
      'quote version mismatch': [
        _bookingRow(quotes: [_quoteRow(version: 2)])
      ],
      'multiple locked candidates': [
        _bookingRow(quotes: [_quoteRow(), _quoteRow(id: 'quote-2', version: 2)])
      ],
      'multiple booking candidates': [_bookingRow(), _bookingRow()],
      'duplicate quote candidates': [
        _bookingRow(quotes: [_quoteRow(), _quoteRow()])
      ],
      'expired calculated quote is not proof of non-commit': [
        _bookingRow(
            version: 1, link: null, quotes: [_quoteRow(status: 'expired')])
      ],
      'later terminal booking is not automatically abandoned': [
        _bookingRow(version: 3, status: 'cancelled')
      ],
      'locked quote without lock timestamp': [
        _bookingRow(quotes: [
          {..._quoteRow(), 'locked_at': null}
        ])
      ],
    };
    for (final entry in uncertainCases.entries) {
      test(entry.key, () async {
        final h = _Harness((
                {required bookingRequestId, required riderId}) async =>
            entry.value);
        addTearDown(h.container.dispose);
        await h.authenticate();
        final result = await h.pending.recoverCanonically();
        expect(result!.status, FareLockRecoveryStatus.uncertain);
        expect(h.store.slots['rider-1'], _command);
        expect(h.container.read(pendingFareLockControllerProvider), _command);
        expect(h.store.deletes, 0);
      });
    }
    for (final failure in [
      FareFailure.unauthorized,
      FareFailure.forbidden,
      FareFailure.versionConflict
    ]) {
      test('retains evidence on $failure', () async {
        final h = _Harness((
                {required bookingRequestId, required riderId}) async =>
            throw FareException(failure));
        addTearDown(h.container.dispose);
        await h.authenticate();
        final result = await h.pending.recoverCanonically();
        expect(
            result!.status,
            failure == FareFailure.versionConflict
                ? FareLockRecoveryStatus.uncertain
                : FareLockRecoveryStatus.suspended);
        expect(h.store.slots['rider-1'], _command);
        expect(result.command.expectedBookingVersion, 1);
      });
    }
    test('same-rider reauthentication can recover suspended evidence',
        () async {
      bool authorized = false;
      final h = _Harness(({required bookingRequestId, required riderId}) async {
        if (!authorized) throw const FareException(FareFailure.unauthorized);
        return [_bookingRow()];
      });
      addTearDown(h.container.dispose);
      await h.authenticate();
      expect((await h.pending.recoverCanonically())!.status,
          FareLockRecoveryStatus.suspended);
      h.auth.user = null;
      await h.authenticate();
      expect(h.container.read(pendingFareLockControllerProvider), isNull);
      expect(h.store.slots['rider-1'], _command);
      h.auth.user = MockData.demoRider;
      authorized = true;
      await h.authenticate();
      expect((await h.pending.recoverCanonically())!.status,
          FareLockRecoveryStatus.confirmed);
    });
    test('different rider never reads or clears original evidence', () async {
      int reads = 0;
      final h = _Harness(({required bookingRequestId, required riderId}) async {
        reads++;
        return [_bookingRow()];
      });
      addTearDown(h.container.dispose);
      await h.authenticate();
      h.auth.user = AppUser(
          id: 'rider-2',
          name: 'Another rider',
          email: 'another@example.test',
          role: MockData.demoRider.role);
      await h.authenticate();
      expect(await h.pending.recoverCanonically(), isNull);
      expect(reads, 0);
      expect(h.store.slots['rider-1'], _command);
    });
    test('session change during SELECT discards late confirmation', () async {
      final started = Completer<void>();
      final gate = Completer<List<Map<String, dynamic>>>();
      final h = _Harness(({required bookingRequestId, required riderId}) {
        started.complete();
        return gate.future;
      });
      addTearDown(h.container.dispose);
      await h.authenticate();
      final recovery = h.pending.recoverCanonically();
      await started.future;
      h.auth.user = null;
      await h.container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      gate.complete([_bookingRow()]);
      expect(await recovery, isNull);
      expect(h.store.slots['rider-1'], _command);
      expect(h.store.deletes, 0);
    });
    test('disposal during SELECT preserves evidence', () async {
      final started = Completer<void>();
      final gate = Completer<List<Map<String, dynamic>>>();
      final h = _Harness(({required bookingRequestId, required riderId}) {
        started.complete();
        return gate.future;
      });
      await h.authenticate();
      final recovery = h.pending.recoverCanonically();
      await started.future;
      h.container.dispose();
      gate.complete([_bookingRow()]);
      expect(await recovery, isNull);
      expect(h.store.deletes, 0);
    });
    test(
        'late original success and earlier empty SELECT retain mutation protection',
        () async {
      final started = Completer<void>();
      final gate = Completer<List<Map<String, dynamic>>>();
      final h = _Harness(({required bookingRequestId, required riderId}) {
        started.complete();
        return gate.future;
      });
      addTearDown(h.container.dispose);
      await h.authenticate();
      final recovery = h.pending.recoverCanonically();
      await started.future;
      // Slice 3 retains the staged evidence even when the original RPC
      // succeeds. A cross-route draft call waits behind the canonical read.
      final replacement = _createDraft(h);
      final blocked = expectLater(replacement, _mutationBlocked);
      expect(h.store.slots['rider-1'], _command);
      gate.complete([]);
      expect((await recovery)!.status, FareLockRecoveryStatus.uncertain);
      await blocked;
      expect(h.store.deletes, 0);
      expect(h.container.read(pendingFareLockControllerProvider), _command);
    });
    test('confirmation does not attempt deletion of protected evidence',
        () async {
      final h = _Harness((
              {required bookingRequestId, required riderId}) async =>
          [_bookingRow()]);
      addTearDown(h.container.dispose);
      await h.authenticate();
      h.store.failClear = true;
      expect((await h.pending.recoverCanonically())!.status,
          FareLockRecoveryStatus.confirmed);
      expect(h.store.slots['rider-1'], _command);
      expect(h.store.deletes, 0);
    });
    test('a changed persisted command is never deleted by canonical cleanup',
        () async {
      final competing = PendingFareLock(
          bookingRequestId: 'booking-other',
          expectedBookingVersion: 1,
          fareQuoteId: 'quote-other',
          expectedQuoteVersion: 1,
          riderId: 'rider-1',
          status: PendingLockRecoveryStatus.uncertain,
          createdAt: _command.createdAt);
      final gate = Completer<List<Map<String, dynamic>>>();
      final started = Completer<void>();
      final raced = _Harness(({required bookingRequestId, required riderId}) {
        started.complete();
        return gate.future;
      });
      addTearDown(raced.container.dispose);
      await raced.authenticate();
      final recovery = raced.pending.recoverCanonically();
      await started.future;
      raced.store.slots['rider-1'] = competing;
      gate.complete([_bookingRow()]);
      expect((await recovery)!.status, FareLockRecoveryStatus.uncertain);
      expect(raced.store.slots['rider-1'], competing);
      expect(raced.store.deletes, 0);
    });
  });
}
