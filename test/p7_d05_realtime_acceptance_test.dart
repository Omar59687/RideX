import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// P7-D05 local-only real Realtime acceptance harness.
//
// Covered: authenticated Postgres Changes INSERT/UPDATE delivery for Trips and
// INSERT delivery for Driver locations, plus canonical authenticated rereads.
//
// Not covered: trip_status_events INSERT delivery, DELETE/TRUNCATE Realtime
// exposure, and any hosted Supabase acceptance. Direct Trip updates are used
// so the append-only trip_status_events table is never populated by fixtures.
//
// The service-role client is used only for fixture setup, cleanup, and
// canonical fixture writes. It is never used as a subscribing identity.
//
// Live execution is fail-closed: assertD05Identity inspects fixed Docker
// containers and requires D05 project labels, expected loopback port bindings,
// and a healthy Realtime container before any service-role client or DB write.
// Docker labels are local configuration evidence, not cryptographic identity;
// they do not protect against a compromised Docker daemon or containers being
// changed after this preflight.

const _acceptanceFlag = 'D05_REALTIME_ACCEPTANCE';
const _urlVariable = 'D05_SUPABASE_URL';
const _anonVariable = 'D05_SUPABASE_ANON_KEY';
const _serviceVariable = 'D05_SUPABASE_SERVICE_ROLE_KEY';
const _localHosts = {'127.0.0.1', 'localhost'};
const _localPort = 55421;
const _eventTimeout = Duration(seconds: 20);
const _settleTimeout = Duration(seconds: 5);
const _d05Project = 'ridex-d05-isolated';
const _d05Workdir = r'C:\RideX-D05-Isolated';
const _d05DatabaseContainer = 'supabase_db_ridex-d05-isolated';
const _d05KongContainer = 'supabase_kong_ridex-d05-isolated';
const _d05RealtimeContainer = 'supabase_realtime_ridex-d05-isolated';
const _d05DatabasePort = '55422';
const _d05KongPort = '55421';
const _d05DatabaseContainerPort = '5432/tcp';
const _d05KongContainerPort = '8000/tcp';
const _d05InspectTimeout = Duration(seconds: 10);

void main() {
  final environment = _Environment.fromPlatform();

  group('P7-D05 local real Realtime acceptance', () {
    late _Harness harness;
    var harnessReady = false;

    setUp(() async {
      environment.assertLocalOnly();
      harness = await _Harness.create(environment);
      harnessReady = true;
    });

    tearDown(() async {
      if (harnessReady) await harness.dispose();
    });

    test(
      'delivers Trip INSERT and UPDATE only to active participants',
      () async {
        final probes = <_Probe>[];
        addTearDown(() => _disposeProbes(probes));

        // Static schema review: driver_availability has one active_trip_id per
        // Driver, and the Trip acceptance path assumes one active Trip per
        // Driver. Use two Drivers instead of two simultaneous Trips for one
        // Driver; no production constraint or trigger is bypassed.
        final bookingA = await harness.createBookingAndFare(
          riderId: harness.rider.id,
        );
        final bookingB = await harness.createBookingAndFare(
          riderId: harness.blockedRider.id,
        );
        final tripA = harness.newId();
        final tripB = harness.newId();
        final bindings = [
          for (final tripId in [tripA, tripB]) ...[
            _Binding(
              event: PostgresChangeEvent.insert,
              table: 'trips',
              column: 'id',
              value: tripId,
            ),
            _Binding(
              event: PostgresChangeEvent.update,
              table: 'trips',
              column: 'id',
              value: tripId,
            ),
          ],
        ];
        for (final actor in harness.actors) {
          probes.add(
            await _Probe.subscribe(
              name: actor.key,
              client: actor.client,
              topic: 'p7-d05-${harness.namespace}-${actor.key}-trips',
              bindings: bindings,
            ),
          );
        }

        await Future<void>.delayed(const Duration(milliseconds: 400));
        await harness.insertTrip(
          id: tripA,
          bookingId: bookingA.bookingId,
          fareQuoteId: bookingA.fareQuoteId,
          riderId: harness.rider.id,
          driverId: harness.driver.id,
          vehicleId: harness.vehicleIdFor('driver'),
        );
        await harness.insertTrip(
          id: tripB,
          bookingId: bookingB.bookingId,
          fareQuoteId: bookingB.fareQuoteId,
          riderId: harness.blockedRider.id,
          driverId: harness.secondDriver.id,
          vehicleId: harness.vehicleIdFor('driver2'),
        );
        await harness.updateTripStatus(tripA, 'driverArriving');
        await harness.updateTripStatus(tripB, 'driverArriving');

        await _probe(probes, 'rider').waitForTripEvents(tripA, 2);
        await _probe(probes, 'driver').waitForTripEvents(tripA, 2);
        await _probe(probes, 'driver2').waitForTripEvents(tripB, 2);
        await Future<void>.delayed(_settleTimeout);

        final riderProbe = _probe(probes, 'rider');
        final driverProbe = _probe(probes, 'driver');
        final secondDriverProbe = _probe(probes, 'driver2');
        final unrelatedProbe = _probe(probes, 'unrelated');
        final blockedProbe = _probe(probes, 'blocked');

        expect(riderProbe.eventsForTrip(tripA), hasLength(2));
        expect(riderProbe.eventsForTrip(tripB), isEmpty);
        expect(driverProbe.eventsForTrip(tripA), hasLength(2));
        expect(driverProbe.eventsForTrip(tripB), isEmpty);
        expect(secondDriverProbe.eventsForTrip(tripA), isEmpty);
        expect(secondDriverProbe.eventsForTrip(tripB), hasLength(2));
        expect(unrelatedProbe.eventsForTrip(tripA), isEmpty);
        expect(unrelatedProbe.eventsForTrip(tripB), isEmpty);
        expect(blockedProbe.eventsForTrip(tripA), isEmpty);
        expect(blockedProbe.eventsForTrip(tripB), isEmpty);

        expect(
          riderProbe
              .eventsForTrip(tripA)
              .map((event) => event.newRecord['status']),
          containsAll(['accepted', 'driverArriving']),
        );
        expect(
          secondDriverProbe
              .eventsForTrip(tripB)
              .map((event) => event.newRecord['status']),
          containsAll(['accepted', 'driverArriving']),
        );

        await _expectTripRead(
          actor: harness.rider,
          tripId: tripA,
          present: true,
          status: 'driverArriving',
        );
        await _expectTripRead(
          actor: harness.rider,
          tripId: tripB,
          present: false,
        );
        await _expectTripRead(
          actor: harness.driver,
          tripId: tripA,
          present: true,
          status: 'driverArriving',
        );
        await _expectTripRead(
          actor: harness.driver,
          tripId: tripB,
          present: false,
        );
        await _expectTripRead(
          actor: harness.secondDriver,
          tripId: tripA,
          present: false,
        );
        await _expectTripRead(
          actor: harness.secondDriver,
          tripId: tripB,
          present: true,
          status: 'driverArriving',
        );
        await _expectTripRead(
          actor: harness.unrelated,
          tripId: tripA,
          present: false,
        );
        await _expectTripRead(
          actor: harness.unrelated,
          tripId: tripB,
          present: false,
        );
        await _expectTripRead(
          actor: harness.blockedRider,
          tripId: tripA,
          present: false,
        );
        await _expectTripRead(
          actor: harness.blockedRider,
          tripId: tripB,
          present: false,
        );
      },
      skip: environment.skipReason,
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'delivers Driver location INSERT only to Trip participants',
      () async {
        final probes = <_Probe>[];
        addTearDown(() => _disposeProbes(probes));

        final booking = await harness.createBookingAndFare(
          riderId: harness.rider.id,
        );
        final tripId = harness.newId();
        await harness.insertTrip(
          id: tripId,
          bookingId: booking.bookingId,
          fareQuoteId: booking.fareQuoteId,
          riderId: harness.rider.id,
          driverId: harness.driver.id,
          vehicleId: harness.vehicleIdFor('driver'),
        );
        await harness.setDriverOnTrip(tripId);

        final bindings = [
          _Binding(
            event: PostgresChangeEvent.insert,
            table: 'driver_locations',
            column: 'trip_id',
            value: tripId,
          ),
        ];
        for (final actor in harness.actors) {
          probes.add(
            await _Probe.subscribe(
              name: actor.key,
              client: actor.client,
              topic: 'p7-d05-${harness.namespace}-${actor.key}-locations',
              bindings: bindings,
            ),
          );
        }

        await Future<void>.delayed(const Duration(milliseconds: 400));
        final location = await harness.recordDriverLocation(tripId);

        await _probe(probes, 'rider').waitForTripEvents(tripId, 1);
        await _probe(probes, 'driver').waitForTripEvents(tripId, 1);
        await Future<void>.delayed(_settleTimeout);

        final riderProbe = _probe(probes, 'rider');
        final driverProbe = _probe(probes, 'driver');
        final secondDriverProbe = _probe(probes, 'driver2');
        final unrelatedProbe = _probe(probes, 'unrelated');
        final blockedProbe = _probe(probes, 'blocked');

        expect(riderProbe.eventsForTrip(tripId), hasLength(1));
        expect(driverProbe.eventsForTrip(tripId), hasLength(1));
        expect(secondDriverProbe.eventsForTrip(tripId), isEmpty);
        expect(unrelatedProbe.eventsForTrip(tripId), isEmpty);
        expect(blockedProbe.eventsForTrip(tripId), isEmpty);
        expect(
          riderProbe.eventsForTrip(tripId).single.newRecord['sequence'],
          location['sequence'],
        );

        await _expectLocationRead(
          actor: harness.rider,
          locationId: location['id'] as String,
          present: true,
          sequence: location['sequence'] as int,
        );
        await _expectLocationRead(
          actor: harness.driver,
          locationId: location['id'] as String,
          present: true,
          sequence: location['sequence'] as int,
        );
        await _expectLocationRead(
          actor: harness.secondDriver,
          locationId: location['id'] as String,
          present: false,
        );
        await _expectLocationRead(
          actor: harness.unrelated,
          locationId: location['id'] as String,
          present: false,
        );
        await _expectLocationRead(
          actor: harness.blockedRider,
          locationId: location['id'] as String,
          present: false,
        );
      },
      skip: environment.skipReason,
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  group('D05 Docker identity preflight', () {
    test('accepts matching synthetic snapshots', () {
      expect(
        () => _verifyD05DockerIdentity(_validD05DockerSnapshots()),
        returnsNormally,
      );
    });

    test('parses a one-container inspect JSON array', () {
      final snapshot = _validD05DockerSnapshots()[_d05DatabaseContainer]!;
      final parsed = _parseDockerInspect(
        _d05DatabaseContainer,
        jsonEncode([snapshot]),
      );
      expect(parsed['State'], isA<Map>());
    });

    test('rejects malformed inspect JSON', () {
      expect(
        () => _parseDockerInspect(_d05DatabaseContainer, '{not-json'),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects an empty inspect array', () {
      expect(
        () => _parseDockerInspect(_d05DatabaseContainer, '[]'),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a wrong compose project label', () {
      final snapshots = _validD05DockerSnapshots();
      _labelsOf(snapshots[_d05DatabaseContainer]!)[
          'com.docker.compose.project'] = 'other-project';
      expect(
        () => _verifyD05DockerIdentity(snapshots),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a wrong CLI workdir label', () {
      final snapshots = _validD05DockerSnapshots();
      _labelsOf(snapshots[_d05KongContainer]!)[
          'com.supabase.cli.workdir'] = r'C:\Other-Project';
      expect(
        () => _verifyD05DockerIdentity(snapshots),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a wrong database host port', () {
      final snapshots = _validD05DockerSnapshots();
      _bindingOf(
        snapshots[_d05DatabaseContainer]!,
        _d05DatabaseContainerPort,
      )['HostPort'] = '55423';
      expect(
        () => _verifyD05DockerIdentity(snapshots),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a non-loopback API binding', () {
      final snapshots = _validD05DockerSnapshots();
      _bindingOf(
        snapshots[_d05KongContainer]!,
        _d05KongContainerPort,
      )['HostIp'] = '0.0.0.0';
      expect(
        () => _verifyD05DockerIdentity(snapshots),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects an unhealthy Realtime container', () {
      final snapshots = _validD05DockerSnapshots();
      _healthOf(snapshots[_d05RealtimeContainer]!)['Status'] = 'unhealthy';
      expect(
        () => _verifyD05DockerIdentity(snapshots),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a missing Realtime snapshot', () {
      final snapshots = _validD05DockerSnapshots()
        ..remove(_d05RealtimeContainer);
      expect(
        () => _verifyD05DockerIdentity(snapshots),
        throwsA(isA<StateError>()),
      );
    });

    test('uses the injected inspect runner without real Docker', () async {
      final environment = _Environment(
        url: 'http://127.0.0.1:55421',
        anonKey: 'test-anon-value',
        serviceKey: 'test-service-value',
        skipReason: null,
      );
      final inspected = <String>[];
      await environment.assertD05Identity(
        inspect: (container) async {
          inspected.add(container);
          final snapshot = _validD05DockerSnapshots()[container]!;
          return ProcessResult(0, 0, jsonEncode([snapshot]), '');
        },
      );
      expect(inspected, [
        _d05DatabaseContainer,
        _d05KongContainer,
        _d05RealtimeContainer,
      ]);
    });

    test('rejects a missing Docker executable via the runner', () async {
      final environment = _Environment(
        url: 'http://127.0.0.1:55421',
        anonKey: 'test-anon-value',
        serviceKey: 'test-service-value',
        skipReason: null,
      );
      await expectLater(
        environment.assertD05Identity(
          inspect: (container) async {
            throw ProcessException('docker', ['inspect', container]);
          },
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

final class _Environment {
  const _Environment({
    required this.url,
    required this.anonKey,
    required this.serviceKey,
    required this.skipReason,
  });

  factory _Environment.fromPlatform() {
    final values = Platform.environment;
    if (values[_acceptanceFlag] != '1') {
      return const _Environment(
        url: '',
        anonKey: '',
        serviceKey: '',
        skipReason: 'Set D05_REALTIME_ACCEPTANCE, D05_SUPABASE_URL, '
            'D05_SUPABASE_ANON_KEY, D05_SUPABASE_SERVICE_ROLE_KEY to run '
            'local D05 Realtime acceptance.',
      );
    }
    return _Environment(
      url: (values[_urlVariable] ?? '').trim(),
      anonKey: (values[_anonVariable] ?? '').trim(),
      serviceKey: (values[_serviceVariable] ?? '').trim(),
      skipReason: null,
    );
  }

  final String url;
  final String anonKey;
  final String serviceKey;
  final String? skipReason;

  // Read-only Docker preflight. This runs before the service-role client is
  // created and before any fixture write. It rejects missing Docker, missing
  // containers, wrong labels, wrong port bindings, unhealthy Realtime, and
  // malformed inspect output. It intentionally does not skip on failure.
  Future<void> assertD05Identity({
    _DockerInspectRunner inspect = _runDockerInspect,
  }) async {
    assertLocalOnly();
    final snapshots = <String, Map<String, Object?>>{};
    for (final container in const [
      _d05DatabaseContainer,
      _d05KongContainer,
      _d05RealtimeContainer,
    ]) {
      ProcessResult result;
      try {
        result = await inspect(container);
      } on TimeoutException {
        throw StateError(
          'Docker identity preflight timed out while inspecting $container.',
        );
      } on ProcessException {
        throw StateError(
          'Docker identity preflight could not run docker inspect for '
          '$container.',
        );
      }
      if (result.exitCode != 0) {
        throw StateError(
          'Docker identity preflight could not inspect $container '
          '(exit ${result.exitCode}).',
        );
      }
      snapshots[container] = _parseDockerInspect(container, result.stdout);
    }
    _verifyD05DockerIdentity(snapshots);
  }

  void assertLocalOnly() {
    final missing = [
      if (url.isEmpty) _urlVariable,
      if (anonKey.isEmpty) _anonVariable,
      if (serviceKey.isEmpty) _serviceVariable,
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'D05 Realtime acceptance is enabled but missing ${missing.join(', ')}.',
      );
    }
    final parsed = Uri.tryParse(url);
    final isLocal = parsed != null &&
        parsed.scheme == 'http' &&
        _localHosts.contains(parsed.host) &&
        parsed.port == _localPort &&
        parsed.userInfo.isEmpty &&
        parsed.query.isEmpty &&
        parsed.fragment.isEmpty &&
        (parsed.path.isEmpty || parsed.path == '/');
    if (!isLocal) {
      throw StateError(
        'D05 Realtime acceptance is restricted to '
        'http://127.0.0.1:$_localPort or http://localhost:$_localPort.',
      );
    }
  }
}

typedef _DockerInspectRunner = Future<ProcessResult> Function(
  String container,
);

Future<ProcessResult> _runDockerInspect(String container) {
  return Process.run(
    'docker',
    ['inspect', '--type', 'container', container],
    runInShell: false,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  ).timeout(_d05InspectTimeout);
}

Map<String, Object?> _parseDockerInspect(String container, Object? stdout) {
  if (stdout is! String) {
    throw StateError(
      'Docker identity preflight rejected $container: inspect output is not '
      'text.',
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(stdout);
  } on FormatException {
    throw StateError(
      'Docker identity preflight rejected $container: malformed JSON.',
    );
  }
  if (decoded is! List || decoded.length != 1) {
    throw StateError(
      'Docker identity preflight rejected $container: expected exactly one '
      'container snapshot.',
    );
  }
  final item = decoded.single;
  if (item is! Map) {
    throw StateError(
      'Docker identity preflight rejected $container: snapshot is not an '
      'object.',
    );
  }
  try {
    return Map<String, Object?>.from(item);
  } on TypeError {
    throw StateError(
      'Docker identity preflight rejected $container: snapshot has an invalid '
      'shape.',
    );
  }
}

void _verifyD05DockerIdentity(Map<String, Map<String, Object?>> snapshots) {
  final database = snapshots[_d05DatabaseContainer];
  final kong = snapshots[_d05KongContainer];
  final realtime = snapshots[_d05RealtimeContainer];
  if (database == null || kong == null || realtime == null) {
    throw StateError(
      'Docker identity preflight is missing one or more D05 snapshots.',
    );
  }

  _verifyRunning(database, _d05DatabaseContainer);
  _verifyProjectLabels(database, _d05DatabaseContainer, requireWorkdir: true);
  _verifyPortBinding(
    database,
    _d05DatabaseContainer,
    _d05DatabaseContainerPort,
    _d05DatabasePort,
  );

  _verifyRunning(kong, _d05KongContainer);
  _verifyProjectLabels(kong, _d05KongContainer, requireWorkdir: true);
  _verifyPortBinding(
    kong,
    _d05KongContainer,
    _d05KongContainerPort,
    _d05KongPort,
  );

  _verifyRunning(realtime, _d05RealtimeContainer);
  _verifyProjectLabels(realtime, _d05RealtimeContainer, requireWorkdir: false);
  _verifyHealthy(realtime, _d05RealtimeContainer);
}

void _verifyRunning(Map<String, Object?> snapshot, String container) {
  final state = _snapshotMap(snapshot, 'State', container);
  if (state['Running'] != true) {
    throw StateError(
      'Docker identity preflight rejected $container: container is not '
      'running.',
    );
  }
}

void _verifyProjectLabels(
  Map<String, Object?> snapshot,
  String container, {
  required bool requireWorkdir,
}) {
  final config = _snapshotMap(snapshot, 'Config', container);
  final labels = _snapshotMap(config, 'Labels', container);
  if (labels['com.docker.compose.project'] != _d05Project ||
      labels['com.supabase.cli.project'] != _d05Project) {
    throw StateError(
      'Docker identity preflight rejected $container: project labels do not '
      'match $_d05Project.',
    );
  }
  if (requireWorkdir) {
    final workdir = labels['com.supabase.cli.workdir'];
    if (workdir is! String || !_isExpectedWorkdir(workdir)) {
      throw StateError(
        'Docker identity preflight rejected $container: workdir label does '
        'not match $_d05Workdir.',
      );
    }
  }
}

void _verifyPortBinding(
  Map<String, Object?> snapshot,
  String container,
  String containerPort,
  String hostPort,
) {
  final network = _snapshotMap(snapshot, 'NetworkSettings', container);
  final ports = _snapshotMap(network, 'Ports', container);
  final value = ports[containerPort];
  if (value is! List || value.length != 1) {
    throw StateError(
      'Docker identity preflight rejected $container: expected exactly one '
      'binding for $containerPort.',
    );
  }
  final binding = value.single;
  if (binding is! Map) {
    throw StateError(
      'Docker identity preflight rejected $container: invalid binding for '
      '$containerPort.',
    );
  }
  final bindingMap = Map<String, Object?>.from(binding);
  if (bindingMap['HostPort'] != hostPort) {
    throw StateError(
      'Docker identity preflight rejected $container: $containerPort must be '
      'published on host port $hostPort.',
    );
  }
  final hostIp = bindingMap['HostIp'];
  if (hostIp is! String || !_isLoopbackHost(hostIp)) {
    throw StateError(
      'Docker identity preflight rejected $container: $containerPort must be '
      'bound to a loopback address.',
    );
  }
}

void _verifyHealthy(Map<String, Object?> snapshot, String container) {
  final state = _snapshotMap(snapshot, 'State', container);
  final health = _snapshotMap(state, 'Health', container);
  if (health['Status'] != 'healthy') {
    throw StateError(
      'Docker identity preflight rejected $container: container is not '
      'healthy.',
    );
  }
}

Map<String, Object?> _snapshotMap(
  Map<String, Object?> parent,
  String key,
  String container,
) {
  final value = parent[key];
  if (value is! Map) {
    throw StateError(
      'Docker identity preflight rejected $container: missing $key object.',
    );
  }
  try {
    return Map<String, Object?>.from(value);
  } on TypeError {
    throw StateError(
      'Docker identity preflight rejected $container: invalid $key object.',
    );
  }
}

bool _isLoopbackHost(String host) {
  final normalized = host.replaceAll('[', '').replaceAll(']', '');
  final address = InternetAddress.tryParse(normalized);
  return address != null && address.isLoopback;
}

bool _isExpectedWorkdir(String value) {
  String normalize(String path) {
    return path
        .trim()
        .replaceAll('/', '\\')
        .replaceAll(RegExp(r'\\+$'), '')
        .toLowerCase();
  }

  return normalize(value) == normalize(_d05Workdir);
}

Map<String, Map<String, Object?>> _validD05DockerSnapshots() {
  return {
    _d05DatabaseContainer: _dockerSnapshot(
      containerPort: _d05DatabaseContainerPort,
      hostPort: _d05DatabasePort,
    ),
    _d05KongContainer: _dockerSnapshot(
      containerPort: _d05KongContainerPort,
      hostPort: _d05KongPort,
    ),
    _d05RealtimeContainer: _dockerSnapshot(
      containerPort: '4000/tcp',
      hostPort: '4000',
      health: 'healthy',
    ),
  };
}

Map<String, Object?> _dockerSnapshot({
  required String containerPort,
  required String hostPort,
  String project = _d05Project,
  String workdir = _d05Workdir,
  String hostIp = '127.0.0.1',
  bool running = true,
  String? health,
}) {
  final labels = <String, Object?>{
    'com.docker.compose.project': project,
    'com.supabase.cli.project': project,
    'com.supabase.cli.workdir': workdir,
  };
  final ports = <String, Object?>{
    containerPort: <Object?>[
      <String, Object?>{'HostIp': hostIp, 'HostPort': hostPort},
    ],
  };
  final state = <String, Object?>{
    'Running': running,
    if (health != null) 'Health': <String, Object?>{'Status': health},
  };
  return <String, Object?>{
    'Config': <String, Object?>{'Labels': labels},
    'NetworkSettings': <String, Object?>{'Ports': ports},
    'State': state,
  };
}

Map<String, Object?> _labelsOf(Map<String, Object?> snapshot) {
  return (snapshot['Config']! as Map<String, Object?>)['Labels']!
      as Map<String, Object?>;
}

Map<String, Object?> _portsOf(Map<String, Object?> snapshot) {
  return (snapshot['NetworkSettings']! as Map<String, Object?>)['Ports']!
      as Map<String, Object?>;
}

Map<String, Object?> _bindingOf(
  Map<String, Object?> snapshot,
  String containerPort,
) {
  final bindings = _portsOf(snapshot)[containerPort]! as List<Object?>;
  return bindings.single as Map<String, Object?>;
}

Map<String, Object?> _healthOf(Map<String, Object?> snapshot) {
  final state = snapshot['State']! as Map<String, Object?>;
  return state['Health']! as Map<String, Object?>;
}

final class _Actor {
  _Actor({
    required this.key,
    required this.role,
    required this.blocked,
    required this.email,
    required this.displayName,
  });

  final String key;
  final String role;
  final bool blocked;
  final String email;
  final String displayName;
  String id = '';
  late SupabaseClient client;
}

final class _Harness {
  _Harness._({
    required this.service,
    required this.namespace,
    required this.actors,
    required this.vehicleIdsByActor,
    required this.pricingId,
    required this.pricingVersion,
    required this.redactions,
  });

  static Future<_Harness> create(_Environment environment) async {
    await environment.assertD05Identity();
    final service = _client(environment, environment.serviceKey);
    final namespace = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    final password = 'D05a!$namespace';
    final random = Random.secure();
    final clients = <SupabaseClient>[];
    final vehiclesByActor = <String, String>{};
    String? pricingId;
    final actors = <_Actor>[
      _Actor(
        key: 'rider',
        role: 'rider',
        blocked: false,
        email: 'p7-d05-$namespace-rider@example.test',
        displayName: 'D05 Rider $namespace',
      ),
      _Actor(
        key: 'driver',
        role: 'driver',
        blocked: false,
        email: 'p7-d05-$namespace-driver@example.test',
        displayName: 'D05 Driver $namespace',
      ),
      _Actor(
        key: 'driver2',
        role: 'driver',
        blocked: false,
        email: 'p7-d05-$namespace-driver2@example.test',
        displayName: 'D05 Second Driver $namespace',
      ),
      _Actor(
        key: 'unrelated',
        role: 'rider',
        blocked: false,
        email: 'p7-d05-$namespace-unrelated@example.test',
        displayName: 'D05 Unrelated $namespace',
      ),
      _Actor(
        key: 'blocked',
        role: 'rider',
        blocked: true,
        email: 'p7-d05-$namespace-blocked@example.test',
        displayName: 'D05 Blocked $namespace',
      ),
    ];

    try {
      for (final actor in actors) {
        final created = await service.auth.admin.createUser(
          AdminUserAttributes(
            email: actor.email,
            password: password,
            emailConfirm: true,
            userMetadata: {
              'role': actor.role,
              'display_name': actor.displayName,
            },
          ),
        );
        final user = created.user;
        if (user == null) {
          throw StateError('Unable to create the ${actor.key} fixture user.');
        }
        actor.id = user.id;
      }

      final driverActors = actors
          .where((actor) => actor.role == 'driver')
          .toList(growable: false);
      final blocked = actors.firstWhere((actor) => actor.key == 'blocked');
      for (final actor in [...driverActors, blocked]) {
        await service.from('users').delete().eq('id', actor.id);
        await service.from('users').insert({
          'id': actor.id,
          'role': actor.role,
          'display_name': actor.displayName,
          'email': actor.email,
          'is_blocked': actor.blocked,
        });
      }
      for (final actor in driverActors) {
        await service.from('driver_profiles').insert({
          'user_id': actor.id,
          'approval_status': 'approved',
        });
      }
      await service.from('rider_profiles').insert({'user_id': blocked.id});
      for (final actor in driverActors) {
        final row = await service
            .from('users')
            .select('role,is_blocked')
            .eq('id', actor.id)
            .single();
        final profile = await service
            .from('driver_profiles')
            .select('approval_status')
            .eq('user_id', actor.id)
            .single();
        expect(row['role'], 'driver');
        expect(row['is_blocked'], isFalse);
        expect(profile['approval_status'], 'approved');
      }
      final blockedRow = await service
          .from('users')
          .select('role,is_blocked')
          .eq('id', blocked.id)
          .single();
      expect(blockedRow['role'], 'rider');
      expect(blockedRow['is_blocked'], isTrue);

      for (final actor in actors) {
        final client = _client(environment, environment.anonKey);
        clients.add(client);
        final signedIn = await client.auth.signInWithPassword(
          email: actor.email,
          password: password,
        );
        if (signedIn.user?.id != actor.id) {
          throw StateError('Unable to sign in the ${actor.key} fixture user.');
        }
        actor.client = client;
      }

      final pricingVersion = random.nextInt(900000000) + 1000;
      final createdPricingId = _newUuid(random);
      pricingId = createdPricingId;
      await service.from('pricing_configurations').insert({
        'id': createdPricingId,
        'vehicle_type_code': 'economy',
        'pricing_version': pricingVersion,
        'base_fare_fils': 500,
        'per_kilometer_fils': 300,
        'per_minute_fils': 50,
        'per_stop_fils': 200,
        'minimum_fare_fils': 1000,
        'is_active': false,
      });

      final plateSuffix = namespace.substring(namespace.length - 12);
      for (final (index, actor) in driverActors.indexed) {
        final vehicleId = _newUuid(random);
        vehiclesByActor[actor.key] = vehicleId;
        await service.from('vehicles').insert({
          'id': vehicleId,
          'driver_id': actor.id,
          'vehicle_type_code': 'economy',
          'make': 'Toyota',
          'model': 'Corolla',
          'color': 'White',
          'registration_plate': 'D05$plateSuffix$index',
          'seat_capacity': 4,
          'is_active': true,
        });
      }

      return _Harness._(
        service: service,
        namespace: namespace,
        actors: actors,
        vehicleIdsByActor: Map<String, String>.unmodifiable(vehiclesByActor),
        pricingId: createdPricingId,
        pricingVersion: pricingVersion,
        redactions: [environment.anonKey, environment.serviceKey],
      );
    } catch (error, stackTrace) {
      final cleanupErrors = <String>[];
      Future<void> cleanup(
        String label,
        Future<void> Function() action,
      ) async {
        try {
          await action();
        } catch (cleanupError) {
          cleanupErrors.add('$label: $cleanupError');
        }
      }

      for (final client in clients) {
        await cleanup('actor client', () => _signOutAndDispose(client));
      }
      for (final vehicleId in vehiclesByActor.values) {
        await cleanup(
          'vehicle',
          () => service.from('vehicles').delete().eq('id', vehicleId),
        );
      }
      final trackedPricingId = pricingId;
      if (trackedPricingId != null) {
        await cleanup(
          'pricing',
          () => service
              .from('pricing_configurations')
              .delete()
              .eq('id', trackedPricingId),
        );
      }
      for (final actor in actors.where((actor) => actor.id.isNotEmpty)) {
        await cleanup(
          'driver profile',
          () => service
              .from('driver_profiles')
              .delete()
              .eq('user_id', actor.id),
        );
        await cleanup(
          'rider profile',
          () => service
              .from('rider_profiles')
              .delete()
              .eq('user_id', actor.id),
        );
        await cleanup(
          'auth user',
          () => service.auth.admin.deleteUser(actor.id),
        );
      }
      await cleanup('service client', service.dispose);

      Error.throwWithStackTrace(
        _SetupFailure(
          error,
          cleanupErrors,
          [environment.anonKey, environment.serviceKey],
        ),
        stackTrace,
      );
    }
  }

  final SupabaseClient service;
  final String namespace;
  final List<_Actor> actors;
  final Map<String, String> vehicleIdsByActor;
  final String pricingId;
  final int pricingVersion;
  final List<String> redactions;
  final _random = Random.secure();
  final List<String> _tripIds = [];
  final List<String> _bookingIds = [];
  final List<String> _fareQuoteIds = [];
  bool _disposed = false;

  _Actor get rider => actors.firstWhere((actor) => actor.key == 'rider');
  _Actor get driver => actors.firstWhere((actor) => actor.key == 'driver');
  _Actor get secondDriver =>
      actors.firstWhere((actor) => actor.key == 'driver2');
  _Actor get unrelated =>
      actors.firstWhere((actor) => actor.key == 'unrelated');
  _Actor get blockedRider =>
      actors.firstWhere((actor) => actor.key == 'blocked');

  String vehicleIdFor(String actorKey) {
    final id = vehicleIdsByActor[actorKey];
    if (id == null) {
      throw StateError('Missing fixture vehicle for $actorKey.');
    }
    return id;
  }

  String newId() => _newUuid(_random);

  Future<({String bookingId, String fareQuoteId})> createBookingAndFare({
    required String riderId,
  }) async {
    final bookingId = newId();
    final fareQuoteId = newId();
    _bookingIds.add(bookingId);
    _fareQuoteIds.add(fareQuoteId);
    final now = DateTime.now().toUtc().toIso8601String();
    await service.from('booking_requests').insert({
      'id': bookingId,
      'rider_id': riderId,
      'pickup': _pickup,
      'destination': _destination,
      'vehicle_type_code': 'economy',
      'payment_method': 'cash',
    });
    await service.from('fare_quotes').insert({
      'id': fareQuoteId,
      'booking_request_id': bookingId,
      'rider_id': riderId,
      'status': 'locked',
      'pickup': _pickup,
      'destination': _destination,
      'ordered_stops': <Object?>[],
      'route_distance_meters': 1000,
      'route_duration_seconds': 300,
      'vehicle_type_code': 'economy',
      'breakdown': <String, Object?>{},
      'fixed_fare_fils': 1000,
      'pricing_configuration_id': pricingId,
      'pricing_version': pricingVersion,
      'quote_version': 1,
      'locked_at': now,
    });
    await service
        .from('booking_requests')
        .update({'fare_quote_id': fareQuoteId}).eq('id', bookingId);
    return (bookingId: bookingId, fareQuoteId: fareQuoteId);
  }

  Future<void> insertTrip({
    required String id,
    required String bookingId,
    required String fareQuoteId,
    required String riderId,
    required String driverId,
    required String vehicleId,
  }) async {
    _tripIds.add(id);
    await service.from('trips').insert({
      'id': id,
      'booking_request_id': bookingId,
      'fare_quote_id': fareQuoteId,
      'rider_id': riderId,
      'driver_id': driverId,
      'vehicle_id': vehicleId,
      'status': 'accepted',
      'payment_method': 'cash',
      'pickup': _pickup,
      'destination': _destination,
      'route_distance_meters': 1000,
      'route_duration_seconds': 300,
      'original_fare_fils': 1000,
      'current_fare_fils': 1000,
    });
  }

  Future<Map<String, dynamic>> updateTripStatus(
    String tripId,
    String status,
  ) {
    return service
        .from('trips')
        .update({'status': status})
        .eq('id', tripId)
        .select('id,status,version')
        .single();
  }

  Future<void> setDriverOnTrip(String tripId) async {
    final vehicleId = vehicleIdFor('driver');
    final existing = await service
        .from('driver_availability')
        .select('driver_id')
        .eq('driver_id', driver.id)
        .maybeSingle();
    if (existing == null) {
      await service.from('driver_availability').insert({
        'driver_id': driver.id,
        'state': 'onTrip',
        'vehicle_id': vehicleId,
        'active_trip_id': tripId,
      });
      return;
    }
    await service.from('driver_availability').update({
      'state': 'onTrip',
      'vehicle_id': vehicleId,
      'active_trip_id': tripId,
    }).eq('driver_id', driver.id);
  }

  Future<Map<String, dynamic>> recordDriverLocation(String tripId) async {
    final result = await driver.client.rpc('driver_record_location', params: {
      'requested_trip_id': tripId,
      'requested_sequence': 1,
      'requested_latitude': 31.95,
      'requested_longitude': 35.93,
      'requested_accuracy_meters': 4.0,
      'requested_heading_degrees': 0.0,
      'requested_speed_meters_per_second': 0.0,
      'requested_recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is List && result.length == 1 && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    throw StateError('Driver location RPC returned no row.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final cleanupErrors = <String>[];
    StackTrace? firstStackTrace;

    Future<void> attempt(
      String label,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } catch (error, stackTrace) {
        cleanupErrors.add('$label: $error');
        firstStackTrace ??= stackTrace;
      }
    }

    // FK-safe exact-ID cleanup order: driver_locations -> driver_availability
    // -> trips -> booking fare link -> fare_quotes -> booking_requests ->
    // vehicles -> pricing_configurations -> profiles -> auth users.
    // trip_status_events is append-only; this harness never creates them.
    for (final tripId in _tripIds.reversed) {
      await attempt(
        'driver locations for trip $tripId',
        () => service.from('driver_locations').delete().eq('trip_id', tripId),
      );
    }
    for (final actor in actors.where((actor) => actor.role == 'driver')) {
      await attempt(
        'driver availability for ${actor.key}',
        () =>
            service.from('driver_availability').delete().eq(
                  'driver_id',
                  actor.id,
                ),
      );
    }
    for (final tripId in _tripIds.reversed) {
      await attempt(
        'trip $tripId',
        () => service.from('trips').delete().eq('id', tripId),
      );
    }
    for (final bookingId in _bookingIds.reversed) {
      await attempt(
        'booking fare link $bookingId',
        () => service
            .from('booking_requests')
            .update({'fare_quote_id': null}).eq('id', bookingId),
      );
    }
    for (final fareQuoteId in _fareQuoteIds.reversed) {
      await attempt(
        'fare quote $fareQuoteId',
        () => service.from('fare_quotes').delete().eq('id', fareQuoteId),
      );
    }
    for (final bookingId in _bookingIds.reversed) {
      await attempt(
        'booking $bookingId',
        () => service.from('booking_requests').delete().eq('id', bookingId),
      );
    }
    for (final vehicleId in vehicleIdsByActor.values) {
      await attempt(
        'vehicle $vehicleId',
        () => service.from('vehicles').delete().eq('id', vehicleId),
      );
    }
    await attempt(
      'pricing configuration $pricingId',
      () =>
          service.from('pricing_configurations').delete().eq('id', pricingId),
    );
    for (final actor in actors.reversed) {
      await attempt(
        'driver profile for ${actor.key}',
        () =>
            service.from('driver_profiles').delete().eq('user_id', actor.id),
      );
      await attempt(
        'rider profile for ${actor.key}',
        () => service.from('rider_profiles').delete().eq('user_id', actor.id),
      );
    }
    for (final actor in actors.reversed) {
      await attempt(
        'actor client for ${actor.key}',
        () => _signOutAndDispose(actor.client),
      );
    }
    for (final actor in actors.reversed) {
      await attempt(
        'auth user for ${actor.key}',
        () => service.auth.admin.deleteUser(actor.id),
      );
    }
    await attempt('service client', service.dispose);

    if (cleanupErrors.isNotEmpty) {
      Error.throwWithStackTrace(
        _CleanupFailure('Fixture cleanup failed', cleanupErrors, redactions),
        firstStackTrace ?? StackTrace.current,
      );
    }
  }
}

final class _Binding {
  const _Binding({
    required this.event,
    required this.table,
    required this.column,
    required this.value,
  });

  final PostgresChangeEvent event;
  final String table;
  final String column;
  final String value;
}

final class _Probe {
  _Probe._({
    required this.name,
    required this.client,
    required this.channel,
  });

  static Future<_Probe> subscribe({
    required String name,
    required SupabaseClient client,
    required String topic,
    required List<_Binding> bindings,
  }) async {
    final channel = client.channel(topic);
    final probe = _Probe._(name: name, client: client, channel: channel);
    final subscribed = Completer<void>();
    try {
      for (final binding in bindings) {
        channel.onPostgresChanges(
          event: binding.event,
          schema: 'public',
          table: binding.table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: binding.column,
            value: binding.value,
          ),
          callback: probe._record,
        );
      }
      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (!subscribed.isCompleted) subscribed.complete();
          return;
        }
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          if (!subscribed.isCompleted) {
            subscribed.completeError(
              StateError('Realtime subscription failed for $name.'),
            );
          }
        }
      });
      await subscribed.future.timeout(_eventTimeout);
      return probe;
    } catch (error, stackTrace) {
      Object? cleanupError;
      StackTrace? cleanupStackTrace;
      try {
        await probe.dispose();
      } catch (subscribeCleanupError, subscribeCleanupStackTrace) {
        cleanupError = subscribeCleanupError;
        cleanupStackTrace = subscribeCleanupStackTrace;
      }
      if (cleanupError != null) {
        Error.throwWithStackTrace(
          _ProbeSubscribeFailure(
            name,
            error,
            cleanupError,
            cleanupStackTrace ?? StackTrace.current,
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  final String name;
  final SupabaseClient client;
  final RealtimeChannel channel;
  final List<PostgresChangePayload> _events = [];
  bool _disposed = false;

  List<PostgresChangePayload> eventsForTrip(String tripId) {
    return List<PostgresChangePayload>.unmodifiable(
      _events.where(
        (event) =>
            event.newRecord['id'] == tripId ||
            event.newRecord['trip_id'] == tripId,
      ),
    );
  }

  Future<void> waitForTripEvents(String tripId, int count) async {
    final deadline = DateTime.now().add(_eventTimeout);
    while (eventsForTrip(tripId).length < count) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          '$name did not receive $count Realtime event(s) for $tripId.',
          _eventTimeout,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _record(PostgresChangePayload payload) {
    _events.add(payload);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await client.removeChannel(channel);
  }
}

SupabaseClient _client(_Environment environment, String key) {
  return SupabaseClient(
    environment.url,
    key,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

Future<void> _signOutAndDispose(SupabaseClient client) async {
  try {
    await client.auth.signOut();
  } catch (_) {}
  await client.dispose();
}

String _newUuid(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final value =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
      '${value.substring(12, 16)}-${value.substring(16, 20)}-'
      '${value.substring(20)}';
}

_Probe _probe(List<_Probe> probes, String name) {
  return probes.firstWhere((probe) => probe.name == name);
}

Future<void> _disposeProbes(List<_Probe> probes) async {
  final failures = <String>[];
  for (final probe in probes) {
    try {
      await probe.dispose();
    } catch (error) {
      failures.add('${probe.name}: ${error.runtimeType}');
    }
  }
  if (failures.isNotEmpty) {
    throw StateError('Probe channel cleanup failed: ${failures.join('; ')}.');
  }
}

Future<void> _expectTripRead({
  required _Actor actor,
  required String tripId,
  required bool present,
  String? status,
}) async {
  final row = await actor.client
      .from('trips')
      .select('id,rider_id,driver_id,status,version')
      .eq('id', tripId)
      .maybeSingle();
  if (!present) {
    expect(row, isNull, reason: '${actor.key} must not read $tripId.');
    return;
  }
  expect(row, isNotNull, reason: '${actor.key} must read $tripId.');
  final trip = row!;
  expect(trip['id'], tripId);
  if (status != null) expect(trip['status'], status);
}

Future<void> _expectLocationRead({
  required _Actor actor,
  required String locationId,
  required bool present,
  int? sequence,
}) async {
  final row = await actor.client
      .from('driver_locations')
      .select('id,trip_id,driver_id,sequence')
      .eq('id', locationId)
      .maybeSingle();
  if (!present) {
    expect(row, isNull, reason: '${actor.key} must not read $locationId.');
    return;
  }
  expect(row, isNotNull, reason: '${actor.key} must read $locationId.');
  final location = row!;
  expect(location['id'], locationId);
  if (sequence != null) expect(location['sequence'], sequence);
}

final class _SetupFailure implements Exception {
  _SetupFailure(this.setupError, this.cleanupErrors, this.redactions);

  final Object setupError;
  final List<String> cleanupErrors;
  final List<String> redactions;

  @override
  String toString() {
    final setup = _redactText(setupError.toString(), redactions);
    final cleanup = cleanupErrors.isEmpty
        ? 'none'
        : cleanupErrors
            .map((error) => _redactText(error, redactions))
            .join('; ');
    return 'D05 acceptance setup failed: $setup. Cleanup errors: $cleanup';
  }
}

final class _CleanupFailure implements Exception {
  _CleanupFailure(this.message, this.cleanupErrors, this.redactions);

  final String message;
  final List<String> cleanupErrors;
  final List<String> redactions;

  @override
  String toString() {
    final errors = cleanupErrors
        .map((error) => _redactText(error, redactions))
        .join('; ');
    return '$message: $errors';
  }
}

final class _ProbeSubscribeFailure implements Exception {
  _ProbeSubscribeFailure(
    this.name,
    this.subscribeError,
    this.cleanupError,
    this.cleanupStackTrace,
  );

  final String name;
  final Object subscribeError;
  final Object cleanupError;
  final StackTrace cleanupStackTrace;

  @override
  String toString() {
    final frames = cleanupStackTrace.toString().split('\n');
    final firstFrame = frames.isEmpty ? '' : frames.first;
    return 'Realtime subscription for $name failed: $subscribeError; '
        'channel cleanup failed: $cleanupError ($firstFrame)';
  }
}

String _redactText(String text, Iterable<String> secrets) {
  var result = text;
  for (final secret in secrets) {
    if (secret.length >= 8) {
      result = result.replaceAll(secret, '[redacted]');
    }
  }
  return result;
}

const _pickup = <String, Object?>{'latitude': 31.95, 'longitude': 35.93};
const _destination = <String, Object?>{'latitude': 31.96, 'longitude': 35.94};
