import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_repository.dart';
import 'package:ridex/features/driver_flow/data/supabase_canonical_driver_port.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_authority_foundation_test.dart' as auth;
import 'helpers/fake_canonical_driver_port.dart' as f;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late SupabaseInitializationProvenance provenance;
  late AuthService service;
  late SupabaseCanonicalDriverPort port;
  late CanonicalDriverRepository repository;
  late f.FakeCanonicalDriverPort rows;
  HttpOverrides? previous;
  final requests = <(String, Uri, Map<String, dynamic>?, String?)>[];
  bool failRpc = false;

  setUp(() async {
    requests.clear();
    failRpc = false;
    rows = f.FakeCanonicalDriverPort();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.app_links/events'),
            (_) async => null);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final content = await utf8.decoder.bind(request).join();
      final payload =
          content.isEmpty ? null : jsonDecode(content) as Map<String, dynamic>;
      requests.add((
        request.method,
        request.uri,
        payload,
        request.headers.value('authorization')
      ));
      request.response.headers.contentType = ContentType.json;
      Object? response;
      final path = request.uri.path;
      if (path == '/auth/v1/token') {
        response = auth.authResponse();
      } else if (path == '/auth/v1/logout') {
        request.response.statusCode = 204;
      } else if (path == '/rest/v1/users') {
        response = rows.user;
      } else if (path == '/rest/v1/driver_profiles') {
        response = rows.profile;
      } else if (path == '/rest/v1/driver_availability') {
        response = rows.availability;
      } else if (path == '/rest/v1/driver_match_offers') {
        response = request.uri.queryParameters['status'] == 'eq.offered'
            ? [
                if (rows.offer != null)
                  {...rows.offer!, 'offered_at': f.now.toIso8601String()}
              ]
            : rows.offer;
      } else if (path == '/rest/v1/booking_requests') {
        response = rows.booking;
      } else if (path == '/rest/v1/trips') {
        response = rows.trip;
      } else if (path == '/rest/v1/rpc/driver_transition_trip') {
        if (failRpc) {
          request.response.statusCode = 409;
          response = {'code': '40001', 'message': 'private-stale-canary'};
        } else {
          rows.accept();
          response = {'trip_id': f.otherId, 'status': 'accepted'};
        }
      } else if (path == '/rest/v1/rpc/driver_decline_match_offer') {
        rows.decline();
        response = rows.offer;
      } else {
        request.response.statusCode = 404;
        response = {
          'code': 'unexpected',
          'message': 'Unexpected local request.'
        };
      }
      if (response != null) request.response.write(jsonEncode(response));
      await request.response.close();
    });
    previous = HttpOverrides.current;
    HttpOverrides.global = auth.LocalHttp(server.port);
    provenance = SupabaseInitializationProvenance();
    await provenance.initialize(auth.environment);
    final client = Supabase.instance.client;
    client.auth.stopAutoRefresh();
    service = AuthService(client);
    await service.signIn(
        email: 'fixture@unit-test.invalid', password: 'local-only');
    final access =
        provenance.driverAccess(DriverBackendRegistry([auth.backend()]))!;
    port = SupabaseCanonicalDriverPort.create(access: access, auth: service);
    repository = CanonicalDriverRepository(port,
        offerCommandsEnabled: true, clock: () => f.now);
    requests.clear();
  });

  tearDown(() async {
    repository.dispose();
    await port.dispose();
    await Supabase.instance.dispose();
    await server.close(force: true);
    HttpOverrides.global = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.app_links/events'), null);
  });

  test(
      'discovery uses bounded owned offered expiry SELECT with normal-user auth',
      () async {
    final original = Supabase.instance.client.auth.currentSession!;
    final result = await port.readOfferedRows(f.now);
    expect(result.single['id'], f.offerId);
    final request = requests.single;
    expect(request.$1, 'GET');
    expect(request.$2.path, '/rest/v1/driver_match_offers');
    expect(request.$4, 'Bearer ${original.accessToken}');
    expect(request.$2.queryParameters['driver_id'], 'eq.${f.driverId}');
    expect(request.$2.queryParameters['status'], 'eq.offered');
    expect(request.$2.queryParameters['expires_at'],
        'gt.${f.now.toIso8601String()}');
    expect(request.$2.queryParameters['order'],
        'expires_at.asc.nullslast,id.asc.nullslast');
    expect(request.$2.queryParameters['limit'], '2');
    expect(request.$2.queryParameters['select'], contains('offered_at'));
  });

  test('discovery after application logout sends no query', () async {
    await service.signOut();
    requests.clear();
    await expectLater(port.readOfferedRows(f.now), throwsStateError);
    expect(requests, isEmpty);
  });

  test(
      'actual SDK uses same authenticated client and owned availability/offer filters',
      () async {
    final original = Supabase.instance.client.auth.currentSession!;
    final result = await repository.observe(offerId: f.offerId);
    expect(result.outcome, CanonicalDriverOutcome.observed);
    expect(result.offer!.id, f.offerId);
    expect(requests.where((r) => r.$2.path.startsWith('/auth')), isEmpty);
    expect(requests.every((r) => r.$4 == 'Bearer ${original.accessToken}'),
        isTrue);
    for (final path in ['driver_availability', 'driver_match_offers']) {
      final request = requests.firstWhere((r) => r.$2.path == '/rest/v1/$path');
      expect(request.$2.queryParameters['driver_id'], 'eq.${f.driverId}');
    }
    final offerRequest =
        requests.firstWhere((r) => r.$2.path.endsWith('driver_match_offers'));
    expect(offerRequest.$2.queryParameters['id'], 'eq.${f.offerId}');
  });

  test(
      'exact accept RPC signature and canonical Trip readback, no financial endpoint',
      () async {
    final offer = (await repository.observe(offerId: f.offerId)).offer!;
    requests.clear();
    final result = await repository.decideOffer(
        offer, CanonicalOfferDecision.accept, 'exact-original-key');
    expect(result.outcome, CanonicalDriverOutcome.accepted);
    expect(result.trip!.id, f.tripId);
    final rpc = requests.where((r) => r.$2.path.contains('/rpc/')).single;
    expect(rpc.$2.path, '/rest/v1/rpc/driver_transition_trip');
    expect(rpc.$3, {
      'target_id': f.offerId,
      'requested_status': 'accepted',
      'expected_version': 1,
      'idempotency_key': 'exact-original-key'
    });
    final tripRead = requests.firstWhere((r) => r.$2.path == '/rest/v1/trips');
    expect(tripRead.$2.queryParameters['driver_id'], 'eq.${f.driverId}');
    expect(
        tripRead.$2.queryParameters['booking_request_id'], 'eq.${f.bookingId}');
    expect(
        requests.every((r) =>
            !RegExp('payments|receipts|stripe|backend_').hasMatch(r.$2.path)),
        isTrue);
  });

  test('exact decline RPC signature and version', () async {
    final offer = (await repository.observe(offerId: f.offerId)).offer!;
    requests.clear();
    final result = await repository.decideOffer(
        offer, CanonicalOfferDecision.decline, 'decline-original');
    expect(result.outcome, CanonicalDriverOutcome.declined);
    final rpc = requests.where((r) => r.$2.path.contains('/rpc/')).single;
    expect(rpc.$2.path, '/rest/v1/rpc/driver_decline_match_offer');
    expect(rpc.$3, {
      'target_offer_id': f.offerId,
      'expected_offer_version': 1,
      'idempotency_key': 'decline-original'
    });
  });

  test('SDK stale-version conflict stays UNKNOWN and never retries RPC',
      () async {
    final offer = (await repository.observe(offerId: f.offerId)).offer!;
    failRpc = true;
    requests.clear();
    expect(
        (await repository.decideOffer(
                offer, CanonicalOfferDecision.accept, 'conflict'))
            .outcome,
        CanonicalDriverOutcome.unknown);
    expect(
        (await repository.reconcile()).outcome, CanonicalDriverOutcome.unknown);
    expect(requests.where((r) => r.$2.path.contains('/rpc/')), hasLength(1));
  });

  test('Trip read scopes exact Trip ID and driver', () async {
    rows.trip = f.tripRow();
    expect((await repository.readTrip(f.tripId)).trip!.id, f.tripId);
    final request = requests.firstWhere((r) => r.$2.path == '/rest/v1/trips');
    expect(request.$2.queryParameters['id'], 'eq.${f.tripId}');
    expect(request.$2.queryParameters['driver_id'], 'eq.${f.driverId}');
  });

  test(
      'application logout revokes reads before cleanup and leaves no copied data',
      () async {
    final prior = await repository.observe(offerId: f.offerId);
    final logout = service.signOut();
    requests.clear();
    expect(prior.offer, isNull);
    expect((await repository.observe()).outcome,
        CanonicalDriverOutcome.unauthorized);
    await logout;
    expect(requests.where((r) => r.$2.path.startsWith('/rest')), isEmpty);
  });

  test('same-user SDK session replacement invalidates the captured instance',
      () async {
    final prior = await repository.observe(offerId: f.offerId);
    await Supabase.instance.client.auth
        .setInitialSession(jsonEncode(auth.authResponse()));
    requests.clear();
    expect(prior.offer, isNull);
    expect((await repository.observe()).outcome,
        CanonicalDriverOutcome.unauthorized);
    expect(requests, isEmpty);
  });

  test('provenance invalidation disables borrowed port without remote requests',
      () async {
    await provenance.initialize(auth.environment);
    requests.clear();
    expect((await repository.observe()).outcome,
        CanonicalDriverOutcome.unauthorized);
    expect(requests, isEmpty);
  });

  test('disposing the port never disposes or signs out application client',
      () async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    await port.dispose();
    expect(client.isDisposingOrDisposed, isFalse);
    expect(client.auth.currentSession, same(session));
    expect((await repository.observe()).outcome,
        CanonicalDriverOutcome.unauthorized);
    expect(requests, isEmpty);
  });
}
