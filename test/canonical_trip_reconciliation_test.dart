import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/canonical_trip_reconciliation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/canonical_trip_reconciliation_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const tripId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const driverId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const foreignId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const namespace = 'ridex-test';

CanonicalTripReadSession session({
  String? driver = driverId,
  String backend = namespace,
  int epoch = 1,
  bool approved = true,
}) =>
    CanonicalTripReadSession(
      driverId: driver,
      backendNamespace: backend,
      epoch: epoch,
      isApprovedDriver: approved,
    );

Map<String, Object?> row({String status = 'completed', int version = 37}) => {
      'id': tripId,
      'driver_id': driverId,
      'status': status,
      'version': version,
    };

final command = DriverCompleteTripCommand(
  tripId: tripId,
  expectedTripVersion: 2,
  idempotencyKey: 'original-durable-key',
);

class ReadTransport implements CanonicalTripReadTransport {
  CanonicalTripReadSession owner = session();
  Future<Map<String, Object?>?> Function() read = () async => row();
  final requestedTrips = <String>[];
  bool throwSession = false;

  @override
  CanonicalTripReadSession get currentSession {
    if (throwSession) throw StateError('unavailable');
    return owner;
  }

  @override
  Future<Map<String, Object?>?> readTrip(String trip) {
    requestedTrips.add(trip);
    return read();
  }
}

void main() {
  late ReadTransport transport;
  late CanonicalTripReconciliationRepository repository;

  Future<CanonicalTripReadOutcome> read({
    String driver = driverId,
    String backend = namespace,
  }) =>
      repository.readCanonicalTrip(
        command: command,
        capturedDriverId: driver,
        capturedBackendNamespace: backend,
      );

  void failure(
      CanonicalTripReadOutcome outcome, CanonicalTripReadFailure value) {
    expect(outcome, isA<CanonicalTripReadFailed>());
    expect((outcome as CanonicalTripReadFailed).failure, value);
  }

  setUp(() {
    transport = ReadTransport();
    repository = ReadOnlyCanonicalTripReconciliationRepository(transport);
  });

  for (final status in DriverTripLifecycleStatus.values) {
    test('matching canonical ${status.name} preserves exact backend version',
        () async {
      transport.read =
          () async => row(status: status.name, version: 2147483647);
      final result = await read() as CanonicalTripVisible;
      expect(result.trip.tripId, tripId);
      expect(result.trip.driverId, driverId);
      expect(result.trip.status, status);
      expect(result.trip.backendVersion, 2147483647);
      expect(result.session.epoch, 1);
      expect(transport.requestedTrips, [tripId]);
      expect(command.expectedTripVersion, 2);
      expect(command.idempotencyKey, 'original-durable-key');
    });
  }

  test('UUID case is insignificant; evidence remains unchanged', () async {
    transport.read = () async => {
          ...row(),
          'id': tripId.toUpperCase(),
          'driver_id': driverId.toUpperCase(),
        };
    final result =
        await read(driver: driverId.toUpperCase()) as CanonicalTripVisible;
    expect(result.trip.tripId, tripId.toUpperCase());
    expect(result.trip.driverId, driverId.toUpperCase());
  });

  test('missing or hidden row is only not visible', () async {
    transport.read = () async => null;
    expect(await read(), isA<CanonicalTripNotVisible>());
  });

  for (final field in ['id', 'driver_id']) {
    test('foreign $field fails closed', () async {
      transport.read = () async => {...row(), field: foreignId};
      failure(await read(), CanonicalTripReadFailure.foreignEvidence);
    });
    test('missing $field is malformed evidence', () async {
      transport.read = () async => row()..remove(field);
      failure(await read(), CanonicalTripReadFailure.malformedEvidence);
    });
  }

  for (final version in <Object?>[null, 0, -1, 2.0, '2']) {
    test('invalid version $version (${version.runtimeType})', () async {
      transport.read = () async => {...row(), 'version': version};
      failure(await read(), CanonicalTripReadFailure.invalidVersion);
    });
  }
  for (final status in ['requested', 'COMPLETED', ' completed', 'deleted']) {
    test('unsupported status $status', () async {
      transport.read = () async => row(status: status);
      failure(await read(), CanonicalTripReadFailure.unsupportedStatus);
    });
  }
  test('missing status is malformed', () async {
    transport.read = () async => row()..remove('status');
    failure(await read(), CanonicalTripReadFailure.malformedEvidence);
  });

  final errors = <String, (Object, CanonicalTripReadFailure)>{
    'explicit authorization denial': (
      const PostgrestException(message: 'private detail', code: '42501'),
      CanonicalTripReadFailure.authorizationDenied,
    ),
    'invalid JWT': (
      const PostgrestException(message: 'private detail', code: 'PGRST301'),
      CanonicalTripReadFailure.sessionInvalidated,
    ),
    'auth failure': (
      const AuthException('private detail'),
      CanonicalTripReadFailure.sessionInvalidated,
    ),
    'timeout': (
      TimeoutException('timeout'),
      CanonicalTripReadFailure.transportUncertain
    ),
    'disconnect': (
      const SocketException('disconnect'),
      CanonicalTripReadFailure.transportUncertain
    ),
    'unknown backend error': (
      const PostgrestException(message: 'private detail', code: 'XX000'),
      CanonicalTripReadFailure.transportUncertain,
    ),
    'malformed transport payload': (
      const FormatException('private payload'),
      CanonicalTripReadFailure.malformedEvidence,
    ),
  };
  for (final entry in errors.entries) {
    test(entry.key, () async {
      transport.read = () async => throw entry.value.$1;
      final outcome = await read();
      failure(outcome, entry.value.$2);
      expect(outcome.toString(), isNot(contains('private')));
    });
  }

  for (final owner in [
    session(driver: null),
    session(driver: foreignId),
    session(approved: false),
    session(backend: 'other'),
    session(epoch: -1),
  ]) {
    test(
        'invalid initial authority ${owner.driverId}/${owner.backendNamespace}/'
        '${owner.epoch}/${owner.isApprovedDriver} prevents I/O', () async {
      transport.owner = owner;
      failure(await read(), CanonicalTripReadFailure.sessionInvalidated);
      expect(transport.requestedTrips, isEmpty);
    });
  }
  test('caller owner cannot authorize another account', () async {
    failure(await read(driver: foreignId),
        CanonicalTripReadFailure.sessionInvalidated);
    expect(transport.requestedTrips, isEmpty);
  });
  test('invalid captured identity prevents I/O', () async {
    failure(await read(driver: 'mock-driver'),
        CanonicalTripReadFailure.invalidRequest);
    expect(transport.requestedTrips, isEmpty);
  });
  test('session authority unavailable prevents I/O', () async {
    transport.throwSession = true;
    failure(await read(), CanonicalTripReadFailure.sessionInvalidated);
    expect(transport.requestedTrips, isEmpty);
  });

  final replacements = <String, CanonicalTripReadSession>{
    'logout': session(driver: null, epoch: 2, approved: false),
    'account switch': session(driver: foreignId, epoch: 2),
    'approval loss': session(approved: false),
    'backend replacement': session(backend: 'other'),
    'A-B-A': session(epoch: 3),
  };
  for (final entry in replacements.entries) {
    for (final response in ['visible', 'absent', 'denied']) {
      test('${entry.key} suppresses stale $response response', () async {
        final pending = Completer<Map<String, Object?>?>();
        transport.read = () => pending.future;
        final outcome = read();
        expect(transport.requestedTrips, [tripId]);
        if (entry.key == 'A-B-A') {
          transport.owner = session(driver: foreignId, epoch: 2);
        }
        transport.owner = entry.value;
        if (response == 'denied') {
          pending.completeError(
              const PostgrestException(message: 'denied', code: '42501'));
        } else {
          pending.complete(response == 'visible' ? row() : null);
        }
        failure(await outcome, CanonicalTripReadFailure.sessionInvalidated);
      });
    }
  }
  test('failed post-read session check suppresses evidence', () async {
    transport.read = () async {
      transport.throwSession = true;
      return row();
    };
    failure(await read(), CanonicalTripReadFailure.sessionInvalidated);
  });

  test('no cached truth survives into a later account', () async {
    expect(await read(), isA<CanonicalTripVisible>());
    transport.owner = session(driver: foreignId, epoch: 2);
    failure(await read(), CanonicalTripReadFailure.sessionInvalidated);
    expect(transport.requestedTrips, [tripId]);
  });

  group('real SDK transport with local HTTP only', () {
    late HttpServer server;
    late SupabaseClient client;
    late CanonicalTripReadSession lifecycle;
    final requests = <(String, Uri, String?)>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add((
          request.method,
          request.uri,
          request.headers.value('authorization')
        ));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(row()));
        await request.response.close();
      });
      client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      lifecycle = session();
      repository = ReadOnlyCanonicalTripReconciliationRepository(
        SupabaseCanonicalTripReadTransport(
          client: client,
          backendNamespace: namespace,
          lifecycleReader: () => lifecycle,
        ),
      );
    });
    tearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });

    Future<void> authenticate(
        {String userId = driverId, bool expired = false}) async {
      final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          (expired ? -3600 : 3600);
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'exp': expiry, 'sub': userId})))
          .replaceAll('=', '');
      await client.auth.setInitialSession(jsonEncode({
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test-signature',
        'refresh_token': 'local-test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': userId,
          'app_metadata': <String, Object?>{},
          'user_metadata': <String, Object?>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z'
        },
      }));
    }

    test(
        'only authenticated single-Trip SELECT; no completion RPC or financial operations',
        () async {
      await authenticate();
      expect(await read(), isA<CanonicalTripVisible>());
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.$1, 'GET');
      expect(request.$2.path, '/rest/v1/trips');
      expect(request.$2.queryParameters,
          {'select': 'id,driver_id,status,version', 'id': 'eq.$tripId'});
      expect(request.$3, startsWith('Bearer eyJ'));
    });
    test('caller/lifecycle identity cannot replace SDK authentication',
        () async {
      await authenticate(userId: foreignId);
      failure(await read(), CanonicalTripReadFailure.sessionInvalidated);
      expect(requests, isEmpty);
    });
    test('signed out SDK prevents I/O even with approved lifecycle', () async {
      failure(await read(), CanonicalTripReadFailure.sessionInvalidated);
      expect(requests, isEmpty);
    });
    test('expired SDK session prevents I/O', () async {
      await authenticate(expired: true);
      failure(await read(), CanonicalTripReadFailure.sessionInvalidated);
      expect(requests, isEmpty);
    });
    test('lifecycle namespace must match configured client namespace',
        () async {
      await authenticate();
      lifecycle = session(backend: 'other');
      failure(await read(), CanonicalTripReadFailure.sessionInvalidated);
      expect(requests, isEmpty);
    });
  });
}
