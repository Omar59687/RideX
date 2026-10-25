import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/canonical_payment_repository.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/features/history/presentation/providers/rider_payment_providers.dart';
import 'package:ridex/features/history/presentation/widgets/rider_payment_status_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _riderId = 'a5000000-0000-0000-0000-000000000001';
const _otherRiderId = 'a5000000-0000-0000-0000-000000000002';
const _paymentId = 'a5100000-0000-0000-0000-000000000001';
const _bookingId = 'a5200000-0000-0000-0000-000000000001';

class _AuthenticatedRider extends SessionController {
  @override
  SessionState build() => SessionState.fromUser(
    const AppUser(
      id: _riderId,
      name: 'Local integration fixture',
      email: 'rider@example.invalid',
      role: RideRole.rider,
    ),
  );
}

class _LoopbackBackend {
  final requestedPaths = <String>[];
  final receivedRpc = Completer<void>();
  final releaseRpc = Completer<void>();
  late HttpServer server;
  late SupabaseClient client;
  String profileRole = 'rider';
  bool profileBlocked = false;
  String rowRiderId = _riderId;
  bool delayRpc = false;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestedPaths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/users')) {
        request.response.write(
          jsonEncode([
            {'id': _riderId, 'role': profileRole, 'is_blocked': profileBlocked},
          ]),
        );
      } else if (request.uri.path.endsWith('/user_canonical_payment_record')) {
        if (!receivedRpc.isCompleted) receivedRpc.complete();
        if (delayRpc) await releaseRpc.future;
        request.response.write(
          jsonEncode([
            {
              'id': _paymentId,
              'booking_request_id': _bookingId,
              'trip_id': null,
              'rider_id': rowRiderId,
              'method': 'cash',
              'final_amount_fils': 7350,
              'currency': 'JOD',
              'cash_status': 'cashSelected',
              'card_status': null,
              'version': 4,
              'card_brand': null,
              'card_last_four': null,
            },
          ]),
        );
      } else if (request.uri.path.endsWith('/logout')) {
        request.response.write('{}');
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'offline-publishable',
    );
    await setSdkUser(_riderId);
  }

  Future<void> setSdkUser(String id) => client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'offline-integration-session',
      'token_type': 'bearer',
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000,
      'user': {'id': id, 'aud': 'authenticated'},
    }),
  );

  Future<void> close() async {
    if (!releaseRpc.isCompleted) releaseRpc.complete();
    await client.dispose();
    await server.close(force: true);
  }
}

void main() {
  late _LoopbackBackend backend;
  setUp(() async {
    backend = _LoopbackBackend();
    await backend.start();
  });
  tearDown(() => backend.close());

  ProviderContainer container() {
    final value = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(_AuthenticatedRider.new),
        supabaseClientProvider.overrideWithValue(backend.client),
      ],
    );
    value.listen(riderPaymentReadControllerProvider, (_, __) {});
    addTearDown(value.dispose);
    return value;
  }

  test(
    'production Rider provider uses app client and canonical RPC only',
    () async {
      final value = container();
      expect(
        value.read(riderCashPaymentRepositoryProvider),
        isA<SupabaseCanonicalPaymentRepository>(),
      );
      expect(
        value.read(riderCardPaymentRepositoryProvider),
        isA<SupabaseCanonicalPaymentRepository>(),
      );

      await value
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: _paymentId, method: PaymentMethod.cash);

      final state = value.read(riderPaymentReadControllerProvider);
      expect(state, isA<RiderPaymentReady>());
      final presentation = (state as RiderPaymentReady).presentation;
      expect(presentation.amountFils, 7350);
      expect(presentation.tripNotLinked, isTrue);
      expect(presentation.canDescribeAsPaid, isFalse);
      expect(
        backend.requestedPaths,
        contains('/rest/v1/rpc/user_canonical_payment_record'),
      );
      expect(backend.requestedPaths, isNot(contains('/rest/v1/payments')));
    },
  );

  test('SDK/app identity mismatch blocks provider and dispatch', () async {
    await backend.setSdkUser(_otherRiderId);
    final value = container();
    expect(value.read(riderCashPaymentRepositoryProvider), isNull);

    await value
        .read(riderPaymentReadControllerProvider.notifier)
        .readPayment(paymentId: _paymentId, method: PaymentMethod.cash);

    expect(
      value.read(riderPaymentReadControllerProvider),
      isA<RiderPaymentAuthorizationFailure>(),
    );
    expect(backend.requestedPaths, isEmpty);
  });

  test('server role change to Admin cannot use Rider exact reader', () async {
    backend.profileRole = 'admin';
    final value = container();
    await value
        .read(riderPaymentReadControllerProvider.notifier)
        .readPayment(paymentId: _paymentId, method: PaymentMethod.cash);

    expect(
      value.read(riderPaymentReadControllerProvider),
      isA<RiderPaymentAuthorizationFailure>(),
    );
    expect(
      backend.requestedPaths,
      isNot(contains('/rest/v1/rpc/user_canonical_payment_record')),
    );
  });

  test(
    'SDK A-B-A replacement during response cannot publish stale data',
    () async {
      backend.delayRpc = true;
      final value = container();
      final read = value
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: _paymentId, method: PaymentMethod.cash);
      await backend.receivedRpc.future;
      await backend.setSdkUser(_otherRiderId);
      await backend.setSdkUser(_riderId);
      backend.releaseRpc.complete();
      await read;

      expect(
        value.read(riderPaymentReadControllerProvider),
        isA<RiderPaymentAuthorizationFailure>(),
      );
    },
  );

  test(
    'foreign Rider row cannot publish through the application reader',
    () async {
      backend.rowRiderId = _otherRiderId;
      final value = container();
      await value
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: _paymentId, method: PaymentMethod.cash);

      expect(
        value.read(riderPaymentReadControllerProvider),
        isA<RiderPaymentAuthorizationFailure>(),
      );
    },
  );
}
