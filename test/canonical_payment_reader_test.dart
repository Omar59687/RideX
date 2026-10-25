import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/repositories/canonical_payment_repository.dart';
import 'package:ridex/core/repositories/payment_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actorId = 'aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee';
const paymentId = 'bbbbbbbb-bbbb-4ccc-9ddd-eeeeeeeeeeee';
const bookingId = 'cccccccc-bbbb-4ccc-9ddd-eeeeeeeeeeee';
const tripId = 'dddddddd-bbbb-4ccc-9ddd-eeeeeeeeeeee';
const otherId = 'eeeeeeee-bbbb-4ccc-9ddd-eeeeeeeeeeee';
Map<String, dynamic> row({bool card = false}) => {
      'id': paymentId,
      'booking_request_id': bookingId,
      'trip_id': tripId,
      'rider_id': actorId,
      'method': card ? 'card' : 'cash',
      'final_amount_fils': 13300,
      'currency': 'JOD',
      'version': 7,
      'cash_status': card ? null : 'cashSelected',
      'card_status': card ? 'cardPaymentAuthorized' : null,
      'card_brand': card ? 'Visa' : null,
      'card_last_four': card ? '4242' : null,
    };
final invalid = throwsA(isA<CanonicalPaymentReadException>().having(
    (e) => e.failure, 'failure', CanonicalPaymentReadFailure.invalidResponse));
final unauthorized = throwsA(isA<CanonicalPaymentReadException>().having(
    (e) => e.failure, 'failure', CanonicalPaymentReadFailure.unauthorized));

class _Backend {
  late HttpServer server;
  late SupabaseClient client;
  final requests = <(String, Uri)>[];
  String role = 'admin';
  bool blocked = false;
  int userReads = 0;
  int status = 200;
  List<Map<String, dynamic>> rows = [row()];
  Future<void> Function()? paymentBoundary;
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add((request.method, request.uri));
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/users')) {
        userReads++;
        request.response.write(jsonEncode([
          {'id': actorId, 'role': role, 'is_blocked': blocked}
        ]));
      } else if (request.uri.path.contains('/rpc/')) {
        await paymentBoundary?.call();
        request.response.statusCode = status;
        request.response.write(jsonEncode(status == 200
            ? rows
            : {
                'code': '42501',
                'message': 'private-provider-error',
              }));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'message': 'Unexpected endpoint'}));
      }
      await request.response.close();
    });
    client = SupabaseClient(
        'http://127.0.0.1:${server.port}', 'offline-publishable');
    await session(actorId);
  }

  Future<void> session(String id) => client.auth.setInitialSession(jsonEncode({
        'access_token': 'offline-session',
        'token_type': 'bearer',
        'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'user': {'id': id, 'aud': 'authenticated'},
      }));
  SupabaseCanonicalPaymentRepository get repository =>
      SupabaseCanonicalPaymentRepository(client);
  Future<void> dispose() async {
    await client.dispose();
    await server.close(force: true);
  }
}

void main() {
  test(
      'complete Cash and Card rows preserve persisted identity, fils and version',
      () {
    final cash = CanonicalPaymentRecord.fromRow(row()) as CanonicalCashPayment;
    expect(cash.payment.bookingRequestId, bookingId);
    expect(cash.payment.tripId, tripId);
    expect(cash.payment.version, 7);
    expect(cash.payment.amountFils, 13300);
    expect(cash.payment.status, CashPaymentStatus.cashSelected);
    final card =
        CanonicalPaymentRecord.fromRow(row(card: true)) as CanonicalCardPayment;
    expect(card.payment.status, CardPaymentStatus.cardPaymentAuthorized);
    expect(card.payment.cardLastFour, '4242');
  });
  test('canonical Cash and Card records allow an explicitly null Trip link', () {
    final cash = CanonicalPaymentRecord.fromRow(
        {...row(), 'trip_id': null}) as CanonicalCashPayment;
    final card = CanonicalPaymentRecord.fromRow(
        {...row(card: true), 'trip_id': null}) as CanonicalCardPayment;
    expect(cash.payment.tripId, isNull);
    expect(card.payment.tripId, isNull);
  });
  for (final field in [
    'id',
    'booking_request_id',
    'trip_id',
    'rider_id',
    'version',
    'final_amount_fils',
    'currency',
    'cash_status'
  ]) {
    test('missing $field is rejected, never invented from summary data', () {
      final value = row()..remove(field);
      expect(() => CanonicalPaymentRecord.fromRow(value), invalid);
    });
  }
  for (final change in [
    {'version': 0},
    {'version': '7'},
    {'final_amount_fils': -1},
    {'final_amount_fils': 13.3},
    {'currency': 'USD'},
    {'method': 'unknown'},
    {'card_status': 'cardPaymentSucceeded'},
    {'trip_id': 'local-trip'},
    {'trip_id': ''},
    {'trip_id': 42},
  ]) {
    test('invalid canonical value ${change.keys.single} fails closed $change',
        () {
      expect(
          () => CanonicalPaymentRecord.fromRow({...row(), ...change}), invalid);
    });
  }
  group('SDK read-only boundary', () {
    late _Backend backend;
    setUp(() async {
      backend = _Backend();
      await backend.start();
    });
    tearDown(() => backend.dispose());
    test('Rider reads exact canonical Cash record through authorized RPC',
        () async {
      backend.role = 'rider';
      final payment =
          await backend.repository.readCashPayment(paymentId: paymentId);
      expect(payment.version, 7);
      expect(backend.userReads, 2);
      final read = backend.requests.singleWhere((r) =>
          r.$2.path.endsWith('/rpc/user_canonical_payment_record'));
      expect(read.$1, 'POST');
      expect(backend.requests.any((r) => r.$2.path.endsWith('/payments')),
          isFalse);
    });
    test('method mismatch never coerces Cash to Card', () async {
      await expectLater(
          backend.repository.readCardPayment(paymentId: paymentId), invalid);
    });
    test('Rider cannot consume a foreign record even if transport returns one',
        () async {
      backend.role = 'rider';
      backend.rows = [
        {...row(), 'rider_id': otherId}
      ];
      await expectLater(
          backend.repository.readCashPayment(paymentId: paymentId),
          unauthorized);
    });
    test('wrong returned payment identity is rejected', () async {
      backend.rows = [
        {...row(), 'id': otherId}
      ];
      await expectLater(
          backend.repository.readCashPayment(paymentId: paymentId),
          unauthorized);
    });
    test('missing row stays notFound, not an empty successful payment',
        () async {
      backend.rows = [];
      await expectLater(
          backend.repository.readCashPayment(paymentId: paymentId),
          throwsA(isA<PaymentException>()
              .having((e) => e.failure, 'failure', PaymentFailure.notFound)));
    });
    for (final role in ['rider', 'driver', 'unknown']) {
      test('$role cannot enumerate Admin payments', () async {
        backend.role = role;
        await expectLater(
            backend.repository.readRecentAdminPayments(), unauthorized);
        expect(backend.requests.any((r) => r.$2.path.endsWith('/payments')),
            isFalse);
      });
    }
    test('blocked Admin cannot read', () async {
      backend.blocked = true;
      await expectLater(
          backend.repository.readRecentAdminPayments(), unauthorized);
    });
    test('Admin list uses authorized bounded RPC; duplicate evidence is invalid',
        () async {
      final records = await backend.repository.readRecentAdminPayments();
      expect(records, hasLength(1));
      expect(backend.requests.any((r) =>
          r.$1 == 'POST' &&
          r.$2.path.endsWith('/rpc/admin_recent_canonical_payments')), isTrue);
      expect(backend.requests.any((r) => r.$2.path.endsWith('/payments')),
          isFalse);
      backend.rows = [row(), row()];
      await expectLater(backend.repository.readRecentAdminPayments(), invalid);
    });
    test('role revocation during RPC prevents publication', () async {
      backend.paymentBoundary = () async {
        backend.role = 'rider';
      };
      await expectLater(
          backend.repository.readRecentAdminPayments(), unauthorized);
    });
    test('SDK account switch during RPC discards its result', () async {
      backend.paymentBoundary = () => backend.session(otherId);
      await expectLater(
          backend.repository.readRecentAdminPayments(), unauthorized);
    });
    test('SDK A-B-A session replacement cannot resurrect the old result',
        () async {
      backend.paymentBoundary = () async {
        await backend.session(otherId);
        await backend.session(actorId);
      };
      await expectLater(
          backend.repository.readRecentAdminPayments(), unauthorized);
    });
    test('RLS rejection is sanitized', () async {
      backend.status = 403;
      await expectLater(
          backend.repository.readRecentAdminPayments(), unauthorized);
    });
    test('legacy canonical reader remains isolated from production Admin RPC', () async {
      backend.rows = [row(card: true)];
      final records = await backend.repository.readRecentAdminPayments();
      expect(records, hasLength(1));
      expect(records.single, isA<CanonicalCardPayment>());
      expect(backend.requests.any((r) =>
          r.$1 == 'POST' &&
          r.$2.path.endsWith('/rpc/admin_recent_canonical_payments')), isTrue);
      expect(backend.requests.any((r) => r.$2.path.endsWith('/payments')),
          isFalse);
    });
  });
}
