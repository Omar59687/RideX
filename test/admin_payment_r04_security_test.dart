import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/supabase_admin_payment_reader.dart';
import 'package:ridex/features/auth/presentation/providers/admin_payment_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Loopback-only fixtures. These are never hosted accounts or payment records.
const _admin = 'a4000000-0000-0000-0000-000000000001';
const _other = 'a4000000-0000-0000-0000-000000000002';

Map<String, Object?> _payment() => {
      'id': 'a4100000-0000-0000-0000-000000000001',
      'booking_request_id': 'a4200000-0000-0000-0000-000000000001',
      'trip_id': 'a4300000-0000-0000-0000-000000000001',
      'rider_id': _other,
      'method': 'cash',
      'final_amount_fils': 4200,
      'currency': 'JOD',
      'cash_status': 'cashSelected',
      'card_status': null,
      'version': 1,
      'card_brand': null,
      'card_last_four': null,
    };

class _AdminSession extends SessionController {
  @override
  SessionState build() => SessionState.fromUser(const AppUser(
        id: _admin,
        name: 'Local audit fixture',
        email: 'audit@example.invalid',
        role: RideRole.admin,
      ));
}

class _Loopback {
  final received = Completer<void>();
  final release = Completer<void>();
  final requests = <String>[];
  late HttpServer server;
  late SupabaseClient client;
  String serverRole = 'admin';
  bool serverBlocked = false;
  bool failRpc = false;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/admin_recent_canonical_payments')) {
        // Model authorization at the server snapshot, followed by network delay.
        final authorized = serverRole == 'admin' && !serverBlocked;
        if (!received.isCompleted) received.complete();
        await release.future;
        if (!authorized || failRpc) {
          request.response.statusCode = 403;
          request.response.write(jsonEncode({
            'code': '42501',
            'message': 'private-audit-error-marker',
            'details': 'private-audit-payload-marker',
          }));
        } else {
          request.response.write(jsonEncode([_payment()]));
        }
      } else if (request.uri.path.endsWith('/users')) {
        request.response.write(jsonEncode([
          {'id': _admin, 'role': serverRole, 'is_blocked': serverBlocked},
        ]));
      } else if (request.uri.path.endsWith('/logout')) {
        request.response.write('{}');
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });
    client = SupabaseClient(
        'http://127.0.0.1:${server.port}', 'offline-publishable');
    await client.auth.setInitialSession(jsonEncode({
      'access_token': 'offline-audit-session',
      'token_type': 'bearer',
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
      'user': {'id': _admin, 'aud': 'authenticated'},
    }));
  }

  Future<void> close() async {
    if (!release.isCompleted) release.complete();
    await client.dispose();
    await server.close(force: true);
  }
}

void main() {
  late _Loopback backend;
  setUp(() async {
    backend = _Loopback();
    await backend.start();
  });
  tearDown(() => backend.close());

  ProviderContainer container() {
    final value = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(_AdminSession.new),
      adminPaymentReaderProvider.overrideWithValue(
          SupabaseAdminPaymentReader(backend.client, adminUserId: _admin)),
    ]);
    value.listen(adminPaymentsProvider, (_, __) {});
    addTearDown(value.dispose);
    return value;
  }

  test('logout during Admin RPC rejects the delayed response', () async {
    final reader =
        SupabaseAdminPaymentReader(backend.client, adminUserId: _admin);
    final pending = reader.readPayments();
    await backend.received.future;
    await backend.client.auth.signOut(scope: SignOutScope.local);
    backend.release.complete();
    await expectLater(
        pending,
        throwsA(isA<AdminPaymentReadException>().having(
            (error) => error.failure,
            'failure',
            AdminPaymentReadFailure.unauthorized)));
  });

  test('application/SDK identity mismatch blocks dispatch', () async {
    final reader =
        SupabaseAdminPaymentReader(backend.client, adminUserId: _other);
    await expectLater(
        reader.readPayments(), throwsA(isA<AdminPaymentReadException>()));
    expect(backend.requests, isEmpty);
  });

  for (final change in ['demotion', 'blocking']) {
    // Characterization of R04-F01, NOT a passing revocation-acceptance claim.
    // Change this expectation when separately scoped production hardening lands.
    test('R04-F01: unobserved server $change permits a delayed summary',
        () async {
      final value = container();
      final pending = value.read(adminPaymentsProvider.future);
      await backend.received.future;
      if (change == 'demotion') {
        backend.serverRole = 'rider';
      } else {
        backend.serverBlocked = true;
      }
      backend.release.complete();
      expect(await pending, hasLength(1));
      expect(
          backend.requests.where((path) => path.endsWith('/users')), isEmpty);
    });
  }

  test('provider sanitizes a raw RPC permission exception', () async {
    backend.failRpc = true;
    final pending = container().read(adminPaymentsProvider.future);
    await backend.received.future;
    backend.release.complete();
    await expectLater(
        pending,
        throwsA(isA<AdminPaymentReadException>()
            .having((error) => error.failure, 'failure',
                AdminPaymentReadFailure.failed)
            .having((error) => error.toString(), 'safe exception text',
                isNot(contains('private-audit')))));
  });

  test('R04-F02: one schema-valid unlinked payment blocks the whole list', () {
    final pendingTrip = {..._payment(), 'trip_id': null};
    expect(
        () => parseAdminCanonicalPayments([_payment(), pendingTrip]),
        throwsA(isA<FormatException>().having((error) => error.message,
            'safe parser failure', 'Invalid canonical payment field')));
  });
}
