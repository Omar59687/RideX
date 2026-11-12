import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'helpers/cash_assignment_fixtures.dart';
import 'package:ridex/core/repositories/cash_booking_assignment_repository.dart';

void main() {
  test(
      'resolves exact confirmed reference to canonical accepted Trip and offer',
      () async {
    final p = Fake();
    final result = (await run(p))!;
    expect(result.tripId, tId);
    expect(result.offerId, oId);
    expect(result.bookingId, bId);
    expect(result.fareQuoteId, qId);
    expect(result.driverId, dId);
    expect(result.vehicleId, vId);
    expect(result.lockedFareFils, 2000);
    expect(result.tripVersion, 1);
    expect(result.owner.same(p.owner), isTrue);
  });
  test('repeated reads recover same actual ID without command replay',
      () async {
    final p = Fake();
    expect((await run(p))!.tripId, (await run(p))!.tripId);
  });
  for (final status in ['confirmed', 'searching']) {
    test('$status is pending, not assignment', () async {
      final p = Fake();
      p.value!['status'] = status;
      p.value!['trips'] = [];
      p.value!['driver_match_offers'] = [];
      expect(await run(p), isNull);
    });
  }
  final invalid = <String, void Function(Fake)>{
    'Card': (p) => p.value!['payment_method'] = 'card',
    'cancelled': (p) => p.value!['status'] = 'cancelled',
    'stale booking': (p) => p.value!['version'] = 2,
    'wrong linked quote': (p) => p.value!['fare_quote_id'] = id(99),
    'unlocked quote': (p) => fare(p)['status'] = 'calculated',
    'foreign quote owner': (p) => fare(p)['rider_id'] = id(99),
    'wrong quote booking': (p) => fare(p)['booking_request_id'] = id(99),
    'changed quote amount': (p) => fare(p)['fixed_fare_fils'] = 2050,
    'wrong Trip ID': (p) => trip(p)['id'] = 'booking-instead-of-trip',
    'wrong Trip booking': (p) => trip(p)['booking_request_id'] = id(99),
    'wrong Trip quote': (p) => trip(p)['fare_quote_id'] = id(99),
    'wrong Trip rider': (p) => trip(p)['rider_id'] = id(99),
    'wrong Trip driver': (p) => trip(p)['driver_id'] = id(99),
    'wrong Trip vehicle': (p) => trip(p)['vehicle_id'] = id(99),
    'wrong Trip version': (p) => trip(p)['version'] = 0,
    'wrong Trip status': (p) => trip(p)['status'] = 'unknown',
    'wrong currency': (p) => trip(p)['currency'] = 'USD',
    'changed original fare': (p) => trip(p)['original_fare_fils'] = 1999,
    'changed route': (p) => trip(p)['route_geometry_reference'] = 'changed',
    'changed distance': (p) => trip(p)['route_distance_meters'] = 1,
    'changed duration': (p) => trip(p)['route_duration_seconds'] = 1,
    'changed pickup': (p) =>
        trip(p)['pickup'] = {'latitude': 0, 'longitude': 0},
    'changed destination': (p) =>
        trip(p)['destination'] = {'latitude': 0, 'longitude': 0},
    'missing Trip stops': (p) => trip(p)['trip_stops'] = [],
    'missing booking stops': (p) => p.value!['booking_stops'] = [],
    'duplicate Trip': (p) => (p.value!['trips'] as List).add(trip(p)),
    'wrong accepted offer quote': (p) =>
        (p.value!['driver_match_offers'] as List).single['fare_quote_id'] =
            id(99),
    'wrong accepted offer booking': (p) =>
        (p.value!['driver_match_offers'] as List).single['booking_request_id'] =
            id(99),
    'no accepted offer': (p) =>
        (p.value!['driver_match_offers'] as List).single['status'] = 'offered',
  };
  for (final entry in invalid.entries) {
    test('fail closed: ${entry.key}', () async {
      final p = Fake();
      entry.value(p);
      await expectLater(run(p), throwsA(isA<CashAssignmentException>()));
    });
  }
  test('foreign booking fails authorization', () async {
    final p = Fake();
    p.value!['rider_id'] = id(99);
    await expectLater(
        run(p), throwsA(failure(CashAssignmentFailure.unauthorized)));
  });
  test('wrong booking locator fails authorization', () async {
    final p = Fake();
    p.value!['id'] = id(99);
    await expectLater(
        run(p), throwsA(failure(CashAssignmentFailure.unauthorized)));
  });
  for (final field in ['epoch', 'session', 'namespace', 'user']) {
    test('$field change while read pending blocks publication', () async {
      final p = Fake();
      final pending = Completer<void>();
      p.before = () => pending.future;
      final future = run(p);
      final old = p.owner;
      p.owner = RiderAssignmentOwner(
          field == 'user' ? id(99) : rId,
          field == 'namespace' ? 'other' : 'local',
          field == 'epoch' ? 2 : 0,
          field == 'session' ? Object() : old.session);
      pending.complete();
      await expectLater(
          future, throwsA(failure(CashAssignmentFailure.unauthorized)));
    });
  }
  test('A-B-A lifecycle epoch rejects even same Rider and SDK object',
      () async {
    final p = Fake();
    p.before = () async {
      p.owner = RiderAssignmentOwner(rId, 'local', 2, p.owner.session);
    };
    await expectLater(
        run(p), throwsA(failure(CashAssignmentFailure.unauthorized)));
  });
  test('session loss overrides network error', () async {
    final p = Fake();
    p.before = () async {
      p.owner = const RiderAssignmentOwner(null, 'local', 1, null);
      throw StateError('sensitive transport detail');
    };
    await expectLater(
        run(p), throwsA(failure(CashAssignmentFailure.unauthorized)));
  });
  test('unknown read error sanitized and never fabricates assignment',
      () async {
    final p = Fake();
    p.before = () async {
      throw StateError('private detail');
    };
    await expectLater(
        run(p), throwsA(failure(CashAssignmentFailure.unavailable)));
  });
  test('invisible booking remains unavailable', () async {
    final p = Fake()..value = null;
    await expectLater(
        run(p), throwsA(failure(CashAssignmentFailure.unavailable)));
  });
  test(
      'later legitimate current-fare adjustment does not alter locked original identity',
      () async {
    final p = Fake();
    trip(p)['current_fare_fils'] = 2200;
    trip(p)['status'] = 'completed';
    expect((await run(p))!.lockedFareFils, 2000);
  });

  group('production SDK transport over local HTTP only', () {
    late HttpServer server;
    late SupabaseClient client;
    late SupabaseCashAssignmentReadTransport transport;
    final requests = <HttpRequest>[];
    var epoch = 0;
    var blocked = false;
    var replaceSession = false;
    Future<void> authenticate() => client.auth.setInitialSession(jsonEncode({
          'access_token': 'offline-test-session',
          'token_type': 'bearer',
          'user': {'id': rId, 'aud': 'authenticated'},
        }));
    setUp(() async {
      requests.clear();
      epoch = 0;
      blocked = false;
      replaceSession = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request);
        final profile = request.uri.path.endsWith('/users');
        if (!profile && replaceSession) {
          epoch++;
          await authenticate();
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(profile
            ? [
                {'id': rId, 'role': 'rider', 'is_blocked': blocked}
              ]
            : booking()));
        await request.response.close();
      });
      client = SupabaseClient(
          'http://127.0.0.1:${server.port}', 'offline-public',
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      await authenticate();
      transport =
          SupabaseCashAssignmentReadTransport(client, 'local', () => epoch);
    });
    tearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
    test('Rider bearer GETs only; explicit relationships and owner filters',
        () async {
      final result =
          await CashBookingAssignmentRepository(transport).read(reference());
      expect(result!.tripId, tId);
      expect(requests, hasLength(3));
      expect(requests.map((r) => r.method), everyElement('GET'));
      expect(requests.map((r) => r.uri.path),
          ['/rest/v1/users', '/rest/v1/booking_requests', '/rest/v1/users']);
      final query = requests[1].uri.queryParameters;
      expect(query['id'], 'eq.$bId');
      expect(query['rider_id'], 'eq.$rId');
      expect(query['select'],
          contains('fare_quotes!fare_quotes_booking_rider_fk('));
      expect(query['select'], contains('trips!trips_booking_request_id_fkey('));
      expect(
          query['select'],
          contains(
              'driver_match_offers!driver_match_offers_booking_request_id_fkey('));
      expect(requests.map((r) => r.headers.value('authorization')),
          everyElement('Bearer offline-test-session'));
    });
    test('blocked profile stops before Booking read', () async {
      blocked = true;
      await expectLater(
          CashBookingAssignmentRepository(transport).read(reference()),
          throwsA(failure(CashAssignmentFailure.unauthorized)));
      expect(requests, hasLength(1));
    });
    test('real SDK A-B-A replacement during response cannot publish', () async {
      replaceSession = true;
      await expectLater(
          CashBookingAssignmentRepository(transport).read(reference()),
          throwsA(failure(CashAssignmentFailure.unauthorized)));
      expect(requests, hasLength(2));
    });
  });
}
