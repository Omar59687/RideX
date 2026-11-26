import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/history/data/supabase_rider_history_summary_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _rider = 'a6000000-0000-0000-0000-000000000001';
const _otherRider = 'a6000000-0000-0000-0000-000000000002';
const _trip1 = 'a6100000-0000-0000-0000-000000000001';
const _trip2 = 'a6100000-0000-0000-0000-000000000002';
const _payment = 'a6200000-0000-0000-0000-000000000001';

class _Backend {
  late HttpServer server;
  late SupabaseClient client;
  final requests = <(String, Uri)>[];
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? exact = {
    'id': _trip1,
    'rider_id': _rider,
    'version': 4,
    'status': 'completed',
    'created_at': '2026-11-26T10:00:00.000Z',
    'payment_method': 'card',
  };
  Future<void> Function()? historyBoundary;
  Completer<void>? historyStarted;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add((request.method, request.uri));
      request.response.headers.contentType = ContentType.json;
      Object? response;
      if (request.uri.path.endsWith('/users')) {
        response = [
          {'id': _rider, 'role': 'rider', 'is_blocked': false},
        ];
      } else if (request.uri.path.endsWith('/rpc/user_trip_history_v1')) {
        historyStarted?.complete();
        await historyBoundary?.call();
        response = rows;
      } else if (request.uri.path.endsWith('/trips')) {
        response = exact == null ? [] : [exact];
      } else {
        request.response.statusCode = 404;
        response = {'message': 'unexpected endpoint'};
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
                  .millisecondsSinceEpoch ~/ 1000,
          'user': {'id': id, 'aud': 'authenticated'},
        }),
      );

  Future<void> close() async {
    await client.dispose();
    await server.close(force: true);
  }
}

Map<String, dynamic> _historyRow({
  required String id,
  required String createdAt,
  String? paymentId,
  int? paymentVersion,
  String? method,
}) => {
      'contract_version': 1,
      'trip_id': id,
      'trip_version': 3,
      'trip_status': 'completed',
      'created_at': createdAt,
      'payment_id': paymentId,
      'payment_version': paymentVersion,
      'payment_method': method,
    };

void main() {
  late _Backend backend;
  HttpOverrides? oldOverrides;
  final session = SessionState.fromUser(const AppUser(
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

  SupabaseRiderHistorySummaryRepository repository() =>
      SupabaseRiderHistorySummaryRepository(
        client: backend.client,
        riderId: _rider,
        readSession: () => session,
        isCurrent: () => true,
      );

  test('parses the supported fields and stable keyset cursor', () async {
    backend.rows = [
      _historyRow(
        id: _trip1,
        createdAt: '2026-11-26T10:00:00.000Z',
        paymentId: _payment,
        paymentVersion: 2,
        method: 'card',
      ),
      _historyRow(id: _trip2, createdAt: '2026-11-25T10:00:00.000Z'),
    ];
    final page = await repository().readPage(limit: 2);
    expect(page.rows.map((row) => row.tripId), [_trip1, _trip2]);
    expect(page.rows.first.paymentId, _payment);
    expect(page.rows.last.paymentMethod, isNull);
    expect(page.nextCursor?.tripId, _trip2);
    expect(
      backend.requests.map((request) => request.$1),
      ['GET', 'POST', 'GET'],
    );
  });

  test('malformed and out of order history rows fail closed', () async {
    backend.rows = [
      _historyRow(id: _trip1, createdAt: '2026-11-25T10:00:00.000Z'),
      _historyRow(id: _trip2, createdAt: '2026-11-26T10:00:00.000Z'),
    ];
    await expectLater(repository().readPage(), throwsFormatException);
    backend.rows = [
      {
        ..._historyRow(
          id: _trip1,
          createdAt: '2026-11-26T10:00:00.000Z',
        ),
        'trip_version': 0,
      },
    ];
    await expectLater(repository().readPage(), throwsFormatException);
    backend.rows = [
      {
        ..._historyRow(
          id: _trip1,
          createdAt: '2026-11-26T10:00:00.000Z',
        ),
        'payment_id': _payment,
      },
    ];
    await expectLater(repository().readPage(), throwsFormatException);
  });

  test(
    'exact Trip read is participant filtered and exposes only returned fields',
    () async {
      final trip = await repository().readExactTrip(_trip1);
      expect(trip?.tripId, _trip1);
      expect(trip?.status.name, 'completed');
      expect(trip?.paymentMethod?.name, 'card');
      expect(trip?.paymentId, isNull);
      final tripRequest = backend.requests.firstWhere(
        (request) => request.$2.path.endsWith('/trips'),
      );
      expect(tripRequest.$2.queryParameters['rider_id'], 'eq.$_rider');
    },
  );

  test('missing exact record remains unavailable, not fabricated', () async {
    backend.exact = null;
    expect(await repository().readExactTrip(_trip1), isNull);
  });

  test(
    'session replacement suppresses late history page',
    () async {
      backend.rows = [
        _historyRow(
          id: _trip1,
          createdAt: '2026-11-26T10:00:00.000Z',
        ),
      ];
      final release = Completer<void>();
      backend.historyStarted = Completer<void>();
      backend.historyBoundary = () => release.future;
      final operation = repository().readPage();
      await backend.historyStarted!.future;
      await backend.setRider(_otherRider);
      release.complete();
      await expectLater(
        operation,
        throwsA(isA<RiderHistorySummarySessionChanged>()),
      );
    },
  );
}

class _NoProxyHttpOverrides extends HttpOverrides {}
