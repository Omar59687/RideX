import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/router/app_router.dart';
import 'package:ridex/app/router/route_names.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/repositories/canonical_payment_repository.dart';
import 'package:ridex/core/repositories/rider_canonical_trip_detail_repository.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/features/history/presentation/providers/rider_canonical_trip_detail_providers.dart';
import 'package:ridex/features/history/presentation/screens/rider_canonical_trip_detail_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const rider = 'a5000000-0000-0000-0000-000000000001';
const foreign = 'a5000000-0000-0000-0000-000000000002';
const trip = 'a5100000-0000-0000-0000-000000000001';
const booking = 'a5200000-0000-0000-0000-000000000001';
const payment = 'a5300000-0000-0000-0000-000000000001';
const receipt = 'a5400000-0000-0000-0000-000000000001';

class _LocalHttp extends HttpOverrides {}

class _RiderSession extends SessionController {
  @override
  SessionState build() => SessionState.fromUser(const AppUser(
      id: rider,
      name: 'Local Rider',
      email: 'rider@example.invalid',
      role: RideRole.rider));
}

class Backend {
  late HttpServer server;
  late SupabaseClient client;
  final requests = <(String, String)>[];
  final queries = <Map<String, String>>[];
  Map<String, dynamic> tripRow = {
    'id': trip,
    'booking_request_id': booking,
    'rider_id': rider,
    'status': 'completed',
    'version': 5,
    'payment_method': 'cash'
  };
  Map<String, dynamic> paymentRow = {
    'id': payment,
    'booking_request_id': booking,
    'trip_id': trip,
    'rider_id': rider,
    'method': 'cash',
    'final_amount_fils': 16000,
    'currency': 'JOD',
    'cash_status': 'paid',
    'card_status': null,
    'card_brand': null,
    'card_last_four': null,
    'version': 2
  };
  Map<String, dynamic> receiptRow = {
    'id': receipt,
    'trip_id': trip,
    'payment_method': 'cash',
    'amount_paid_fils': 16000,
    'currency': 'JOD',
    'issued_at': '2026-10-26T12:00:00Z'
  };
  String role = 'rider';
  String linkedTrip = trip, linkedPayment = payment;
  bool blocked = false,
      noTrip = false,
      noReceipt = false,
      receiptDenied = false,
      receiptFailure = false;
  bool changedTrip = false, changedPayment = false;
  int tripReads = 0, paymentReads = 0;
  final receivedReceipt = Completer<void>(), releaseReceipt = Completer<void>();
  bool delayReceipt = false;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      requests.add((request.method, path));
      request.response.headers.contentType = ContentType.json;
      Map<String, dynamic>? body;
      if (request.method == 'POST') {
        body = Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map);
      }
      Object? response;
      if (path.endsWith('/users')) {
        response = [
          {'id': rider, 'role': role, 'is_blocked': blocked}
        ];
      } else if (path.endsWith('/trips')) {
        tripReads++;
        if (!request.uri.queryParameters.containsKey('id')) {
          queries.add(request.uri.queryParameters);
          expect(request.uri.queryParameters['rider_id'], 'eq.$rider');
          expect(request.uri.queryParameters['status'], 'eq.completed');
          expect(request.uri.queryParameters['payment_method'], 'eq.cash');
          expect(request.uri.queryParameters['limit'], '1');
          expect(request.uri.queryParameters['order'],
              'created_at.desc.nullslast,id.asc.nullslast');
        }
        response = noTrip
            ? []
            : [
                {...tripRow, if (changedTrip && tripReads > 1) 'version': 6}
              ];
      } else if (path.endsWith('/user_trip_payment_summary')) {
        expect(body!['target_trip_id'], trip);
        response = [
          {'id': linkedPayment, 'trip_id': linkedTrip, 'method': 'cash'}
        ];
      } else if (path.endsWith('/user_canonical_payment_record')) {
        expect(body!['target_payment_id'], payment);
        paymentReads++;
        response = [
          {...paymentRow, if (changedPayment && paymentReads > 1) 'version': 3}
        ];
      } else if (path.endsWith('/user_trip_receipt_summary')) {
        expect(body!['target_trip_id'], trip);
        if (!receivedReceipt.isCompleted) receivedReceipt.complete();
        if (delayReceipt) await releaseReceipt.future;
        if (receiptDenied || receiptFailure) {
          request.response.statusCode = receiptDenied ? 403 : 400;
          response = {
            'code': receiptDenied ? '42501' : '08006',
            'message': 'private payload must stay private'
          };
        } else {
          response = noReceipt ? [] : [receiptRow];
        }
      } else if (path.endsWith('/logout')) {
        response = {};
      } else {
        request.response.statusCode = 500;
        response = {'message': 'unexpected endpoint'};
      }
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
        'http://127.0.0.1:${server.port}', 'offline-publishable');
    await setUser(rider);
  }

  Future<void> setUser(String id) => client.auth.setInitialSession(jsonEncode({
        'access_token': 'offline-session',
        'token_type': 'bearer',
        'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'user': {'id': id, 'aud': 'authenticated'}
      }));
  RiderCanonicalTripDetailRepository repository({bool Function()? current}) =>
      RiderCanonicalTripDetailRepository(
          client: client,
          riderId: rider,
          payments: SupabaseCanonicalPaymentRepository(client),
          isCurrent: current ?? () => true);
  Future<void> close() async {
    if (!releaseReceipt.isCompleted) releaseReceipt.complete();
    await client.dispose();
    await server.close(force: true);
  }
}

void main() {
  late Backend b;
  HttpOverrides? previousHttp;
  setUp(() async {
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = _LocalHttp();
    b = Backend();
    await b.start();
  });
  tearDown(() async {
    await b.close();
    HttpOverrides.global = previousHttp;
  });

  test(
      'discovers owned bounded Trip and obtains original Payment ID only from RPC',
      () async {
    final result = (await b.repository().loadLatest())!;
    expect(result.tripId, trip);
    expect(result.tripVersion, 5);
    expect(result.payment.paymentId, payment);
    expect(result.payment.status, CashPaymentStatus.paid);
    expect(result.amountDisplay, 'JOD 16.00');
    expect(result.receipt, RiderReceiptEvidence.issued);
    expect(
        b.requests.where((r) => r.$1 == 'POST').every((r) =>
            r.$2.endsWith('/user_trip_payment_summary') ||
            r.$2.endsWith('/user_canonical_payment_record') ||
            r.$2.endsWith('/user_trip_receipt_summary')),
        isTrue);
    expect(
        b.requests.any(
            (r) => r.$2.endsWith('/payments') || r.$2.endsWith('/receipts')),
        isFalse);
  });
  test('missing Trip performs no financial RPC', () async {
    b.noTrip = true;
    expect(await b.repository().loadLatest(), isNull);
    expect(b.requests.every((r) => r.$1 == 'GET'), isTrue);
  });
  for (final scenario in [
    'foreign Trip',
    'invalid Trip ID',
    'wrong method',
    'in progress',
    'bad version',
    'foreign linkage',
    'invalid Payment ID',
    'wrong payment Trip',
    'wrong booking',
    'foreign payment owner',
    'malformed amount',
    'changed Trip',
    'changed Payment'
  ]) {
    test('$scenario fails closed', () async {
      switch (scenario) {
        case 'foreign Trip':
          b.tripRow['rider_id'] = foreign;
        case 'invalid Trip ID':
          b.tripRow['id'] = 'mock-1';
        case 'wrong method':
          b.tripRow['payment_method'] = 'card';
        case 'in progress':
          b.tripRow['status'] = 'inProgress';
        case 'bad version':
          b.tripRow['version'] = 0;
        case 'foreign linkage':
          b.linkedTrip = foreign;
        case 'invalid Payment ID':
          b.linkedPayment = 'mock-payment';
        case 'wrong payment Trip':
          b.paymentRow['trip_id'] = foreign;
        case 'wrong booking':
          b.paymentRow['booking_request_id'] = foreign;
        case 'foreign payment owner':
          b.paymentRow['rider_id'] = foreign;
        case 'malformed amount':
          b.paymentRow['final_amount_fils'] = '16000';
        case 'changed Trip':
          b.changedTrip = true;
        case 'changed Payment':
          b.changedPayment = true;
      }
      await expectLater(b.repository().loadLatest(),
          throwsA(isA<RiderTripDetailException>()));
    });
  }
  for (final role in ['admin', 'driver']) {
    test('$role profile cannot discover Rider financial context', () async {
      b.role = role;
      await expectLater(b.repository().loadLatest(),
          throwsA(isA<RiderTripDetailException>()));
      expect(b.requests, hasLength(1));
    });
  }
  test('blocked Rider is denied before discovery', () async {
    b.blocked = true;
    await expectLater(
        b.repository().loadLatest(), throwsA(isA<RiderTripDetailException>()));
    expect(b.requests, hasLength(1));
  });
  for (final scenario in [
    'missing',
    'transport',
    'wrong Trip',
    'wrong amount',
    'invalid issuance'
  ]) {
    test('receipt $scenario does not invent issuance or downgrade paid status',
        () async {
      switch (scenario) {
        case 'missing':
          b.noReceipt = true;
        case 'transport':
          b.receiptFailure = true;
        case 'wrong Trip':
          b.receiptRow['trip_id'] = foreign;
        case 'wrong amount':
          b.receiptRow['amount_paid_fils'] = 1;
        case 'invalid issuance':
          b.receiptRow['issued_at'] = 'invalid';
      }
      final result = (await b.repository().loadLatest())!;
      expect(result.receipt, RiderReceiptEvidence.unverified);
      expect(result.payment.status, CashPaymentStatus.paid);
    });
  }
  test('receipt authorization failure prevents publication', () async {
    b.receiptDenied = true;
    await expectLater(
        b.repository().loadLatest(),
        throwsA(predicate((e) =>
            e is RiderTripDetailException &&
            e.failure == RiderTripDetailFailure.unauthorized)));
  });
  test('unpaid canonical record never inherits receipt success', () async {
    b.paymentRow['cash_status'] = 'cashSelected';
    final result = (await b.repository().loadLatest())!;
    expect(result.payment.status, CashPaymentStatus.cashSelected);
    expect(result.receipt, RiderReceiptEvidence.unverified);
  });
  test('amount formatting preserves non-cent JOD precision', () async {
    b.paymentRow['final_amount_fils'] = 16001;
    b.noReceipt = true;
    expect((await b.repository().loadLatest())!.amountDisplay, 'JOD 16.001');
  });
  for (final change in ['logout', 'A-B-A', 'namespace invalidated']) {
    test('$change during delayed read cannot publish old snapshot', () async {
      var current = true;
      b.delayReceipt = true;
      final repository = b.repository(current: () => current);
      final future = repository.loadLatest();
      await b.receivedReceipt.future;
      if (change == 'logout') {
        await b.client.auth.signOut();
      }
      if (change == 'A-B-A') {
        await b.setUser(foreign);
        await b.setUser(rider);
      }
      if (change == 'namespace invalidated') {
        current = false;
      }
      b.releaseReceipt.complete();
      await expectLater(
          future,
          throwsA(predicate((e) =>
              e is RiderTripDetailException &&
              e.failure == RiderTripDetailFailure.unauthorized)));
    });
  }
  test('provider auth event hides previously loaded canonical snapshot',
      () async {
    final c = ProviderContainer(overrides: [
      supabaseClientProvider.overrideWithValue(b.client),
      riderCanonicalTripDetailRepositoryProvider
          .overrideWithValue(b.repository()),
    ]);
    addTearDown(c.dispose);
    final listener = c.listen(riderCanonicalTripDetailProvider, (_, __) {});
    addTearDown(listener.close);
    expect(await c.read(riderCanonicalTripDetailProvider.future), isNotNull);
    await b.setUser(foreign);
    await Future<void>.delayed(Duration.zero);
    await expectLater(c.read(riderCanonicalTripDetailProvider.future),
        throwsA(isA<RiderTripDetailException>()));
    expect(c.read(riderCanonicalTripDetailProvider).hasError, isTrue);
  });

  test('production composition rejects unverified application provenance',
      () async {
    final c = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(_RiderSession.new),
      supabaseClientProvider.overrideWithValue(b.client),
    ]);
    addTearDown(c.dispose);
    final listener = c.listen(riderCanonicalTripDetailProvider, (_, __) {});
    addTearDown(listener.close);
    expect(await c.read(riderCanonicalTripDetailProvider.future), isNull);
    expect(b.requests, isEmpty);
  });

  for (final unpaid in [false, true]) {
    testWidgets(
        'canonical surface shows ${unpaid ? 'unpaid' : 'paid'} and independent receipt evidence',
        (tester) async {
      b.noReceipt = true;
      if (unpaid) b.paymentRow['cash_status'] = 'cashSelected';
      final detail = await tester.runAsync(() => b.repository().loadLatest());
      await tester.pumpWidget(ProviderScope(overrides: [
        riderCanonicalTripDetailProvider.overrideWith((ref) async => detail),
      ], child: const MaterialApp(home: RiderCanonicalTripDetailScreen())));
      await tester.pumpAndSettle();
      expect(
          find.text(unpaid
              ? 'Cash selected (unpaid)'
              : 'Canonical Cash status: paid'),
          findsOneWidget);
      expect(find.text('JOD 16.00'), findsOneWidget);
      expect(
          find.text('Receipt unverified. This does not mean payment failed.'),
          findsOneWidget);
      expect(find.textContaining('Receipt issuance verified'), findsNothing);
    });
  }
  testWidgets('loading and unavailable states do not imply paid',
      (tester) async {
    final pending = Completer<RiderCanonicalTripDetail?>();
    await tester.pumpWidget(ProviderScope(overrides: [
      riderCanonicalTripDetailProvider.overrideWith((ref) => pending.future),
    ], child: const MaterialApp(home: RiderCanonicalTripDetailScreen())));
    expect(find.text('Loading canonical Trip and payment'), findsOneWidget);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Canonical Trip and payment information unavailable.'),
        findsOneWidget);
    expect(find.text('Canonical Cash status: paid'), findsNothing);
  });
  testWidgets(
      'named Rider route mounts canonical surface and ignores query identities',
      (tester) async {
    final detail = await tester.runAsync(() => b.repository().loadLatest());
    final c = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(_RiderSession.new),
      riderCanonicalTripDetailProvider.overrideWith((ref) async => detail),
    ]);
    addTearDown(c.dispose);
    final router = c.read(appRouterProvider);
    addTearDown(router.dispose);
    router.goNamed(RouteNames.riderCanonicalPayment,
        queryParameters: {'trip': foreign, 'payment': 'mock-payment'});
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.byType(RiderCanonicalTripDetailScreen), findsOneWidget);
    expect(find.text('Canonical Cash status: paid'), findsOneWidget);
    expect(find.text('Receipt issuance verified.'), findsOneWidget);
    expect(find.text('mock-payment'), findsNothing);
  });

  testWidgets('refresh hides old success and discards an out-of-order read',
      (tester) async {
    final paid = await tester.runAsync(() => b.repository().loadLatest());
    b.paymentRow['cash_status'] = 'cashSelected';
    b.noReceipt = true;
    final unpaid = await tester.runAsync(() => b.repository().loadLatest());
    final old = Completer<RiderCanonicalTripDetail?>();
    final current = Completer<RiderCanonicalTripDetail?>();
    var reads = 0;
    final c = ProviderContainer(overrides: [
      riderCanonicalTripDetailProvider.overrideWith((ref) => switch (++reads) {
            1 => Future.value(paid),
            2 => old.future,
            _ => current.future,
          }),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: RiderCanonicalTripDetailScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Canonical Cash status: paid'), findsOneWidget);
    expect(c.refresh(riderCanonicalTripDetailProvider).isLoading, isTrue);
    await tester.pump();
    expect(find.text('Loading canonical Trip and payment'), findsOneWidget);
    expect(find.text('Canonical Cash status: paid'), findsNothing);
    expect(c.refresh(riderCanonicalTripDetailProvider).isLoading, isTrue);
    await tester.pump();
    current.complete(unpaid);
    await tester.pumpAndSettle();
    old.complete(paid);
    await tester.pumpAndSettle();
    expect(find.text('Cash selected (unpaid)'), findsOneWidget);
    expect(find.text('Canonical Cash status: paid'), findsNothing);
  });

  testWidgets('authorization failure is sanitized and distinct',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      riderCanonicalTripDetailProvider.overrideWith((ref) async =>
          throw const RiderTripDetailException(
              RiderTripDetailFailure.unauthorized)),
    ], child: const MaterialApp(home: RiderCanonicalTripDetailScreen())));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Payment access could not be verified. Sign in as the owning Rider.'),
        findsOneWidget);
    expect(find.textContaining('private payload'), findsNothing);
  });
}
