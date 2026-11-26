import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/rider_payments/data/supabase_a04_rider_financial_read_source.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _rider = 'a5000000-0000-0000-0000-000000000001';
const _otherRider = 'a5000000-0000-0000-0000-000000000002';
const _trip = 'a5100000-0000-0000-0000-000000000001';
const _booking = 'a5200000-0000-0000-0000-000000000001';
const _driver = 'a5300000-0000-0000-0000-000000000001';

class _Backend {
  late HttpServer server;
  late SupabaseClient client;
  final requests = <String>[];
  Map<String, dynamic>? profile = {
    'id': _rider,
    'role': 'rider',
    'is_blocked': false,
  };
  Map<String, dynamic>? trip = {
    'id': _trip,
    'booking_request_id': _booking,
    'rider_id': _rider,
    'driver_id': _driver,
    'version': 4,
    'current_fare_fils': 14500,
    'currency': 'JOD',
    'status': 'driverArriving',
    'payment_method': 'card',
  };
  Future<void> Function()? tripBoundary;
  Completer<void>? tripStarted;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      Object? response;
      if (request.uri.path.endsWith('/users')) {
        response = profile == null ? [] : [profile];
      } else if (request.uri.path.endsWith('/trips')) {
        tripStarted?.complete();
        await tripBoundary?.call();
        response = trip == null ? [] : [trip];
      } else {
        request.response.statusCode = 404;
        response = {'message': 'unexpected request'};
      }
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'offline-publishable',
    );
    await setRider(_rider);
  }

  Future<void> setRider(String id) => client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'offline-session',
          'token_type': 'bearer',
          'expires_at': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
          'user': {'id': id, 'aud': 'authenticated'},
        }),
      );

  Future<void> close() async {
    await client.dispose();
    await server.close(force: true);
  }
}

void main() {
  late _Backend backend;
  HttpOverrides? oldOverrides;
  final appSession = SessionState.fromUser(const AppUser(
    id: _rider,
    name: 'Synthetic Rider',
    email: 'rider@example.invalid',
    role: RideRole.rider,
  ));

  setUp(() async {
    oldOverrides = HttpOverrides.current;
    HttpOverrides.global = _NoProxyHttpOverrides();
    backend = _Backend();
    await backend.start();
  });

  tearDown(() async {
    await backend.close();
    HttpOverrides.global = oldOverrides;
  });

  SupabaseA04AuthorizedTripContextReader reader() =>
      SupabaseA04AuthorizedTripContextReader(
        client: backend.client,
        riderId: _rider,
        readSession: () => appSession,
        isCurrent: () => true,
      );

  test(
    'reads exact assigned Card Trip through authenticated RLS client',
    () async {
      final trip = await reader().readAuthorizedTrip(
        tripId: _trip,
        riderId: _rider,
      );
      expect(trip?.tripId, _trip);
      expect(trip?.bookingRequestId, _booking);
      expect(trip?.driverId, _driver);
      expect(trip?.currentFareFils, 14500);
      expect(trip?.paymentMethod, PaymentMethod.card);
      expect(backend.requests, ['/rest/v1/users', '/rest/v1/trips']);
    },
  );

  test('blocked profile fails closed before reading the Trip', () async {
    backend.profile = {...backend.profile!, 'is_blocked': true};
    await expectLater(
      reader().readAuthorizedTrip(tripId: _trip, riderId: _rider),
      throwsA(isA<RiderCheckoutTripReadException>()),
    );
    expect(backend.requests, ['/rest/v1/users']);
  });

  test('foreign Trip row is rejected rather than mapped', () async {
    backend.trip = {...backend.trip!, 'rider_id': _otherRider};
    await expectLater(
      reader().readAuthorizedTrip(tripId: _trip, riderId: _rider),
      throwsA(isA<RiderCheckoutTripReadException>()),
    );
  });

  test(
    'session replacement during Trip read suppresses the late row',
    () async {
      final release = Completer<void>();
      backend.tripStarted = Completer<void>();
      backend.tripBoundary = () => release.future;
      final operation = reader().readAuthorizedTrip(
        tripId: _trip,
        riderId: _rider,
      );
      await backend.tripStarted!.future;
      await backend.setRider(_otherRider);
      release.complete();
      await expectLater(
        operation,
        throwsA(isA<RiderCheckoutTripReadException>()),
      );
    },
  );

  test(
    'foreign requested identity is rejected before network access',
    () async {
      await expectLater(
        reader().readAuthorizedTrip(tripId: _trip, riderId: _otherRider),
        throwsA(isA<RiderCheckoutTripReadException>()),
      );
      expect(backend.requests, isEmpty);
    },
  );
}

class _NoProxyHttpOverrides extends HttpOverrides {}
