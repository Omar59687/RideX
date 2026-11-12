import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/src/acceptance/two_emulator_acceptance.dart';

final now = DateTime.utc(2026, 11, 12, 12);
final sha = 'a' * 40;
final digest = 'b' * 64;
const project = 'abcdefghijklmnopqrst';
const rider = '11111111-1111-4111-8111-111111111111';
const driver = '22222222-2222-4222-8222-222222222222';
const booking = '33333333-3333-4333-8333-333333333333';
const quote = '44444444-4444-4444-8444-444444444444';
const offer = '55555555-5555-4555-8555-555555555555';
const trip = '66666666-6666-4666-8666-666666666666';
const references = {'evidence-001'};

LocalPreflight local({bool connected = true, String? hash}) {
  final device = DeviceObservation(
      connected: connected,
      booted: true,
      applicationId: 'com.ridex.app',
      apkSha256: hash ?? digest,
      versionCode: '1');
  return LocalPreflight(
      repositorySha: sha,
      cleanRepository: true,
      flutterVersion: '3.41.2',
      adbAvailable: true,
      sdkAvailable: true,
      sourceApplicationId: 'com.ridex.app',
      sourceComponents: {for (final key in sourcePaths.keys) key: true},
      rider: device,
      driver: device);
}

Map<String, dynamic> fixture() => {
      'schema': 1,
      'kind': 'operator_attested',
      'repository_sha': sha,
      'captured_at': now.toIso8601String(),
      'environment': {
        'project_ref': project,
        'approved_nonproduction': true,
        'approval_ref': 'evidence-001'
      },
      'actors': {
        'rider_id': rider,
        'driver_id': driver,
        'roles_verified': true,
        'evidence_ref': 'evidence-001'
      },
      'builds': {
        for (final role in ['rider', 'driver'])
          role: {
            'apk_sha256': digest,
            'project_ref': project,
            'evidence_ref': 'evidence-001'
          }
      },
      'integrations': {
        for (final key in integrationOwners.keys)
          key: {'available': true, 'evidence_ref': 'evidence-001'}
      },
      'gps': {
        'recorded_at': now.toIso8601String(),
        'received_at': now.toIso8601String(),
        'accuracy_meters': 10,
        'sequence': 1,
        'latest_verified': true,
        'evidence_ref': 'evidence-001'
      },
      'safety': {
        'completion_disabled': true,
        'card_disabled': true,
        'receipt_writes_disabled': true,
        'no_mutations_requested': true,
        'evidence_ref': 'evidence-001'
      },
      'journey': {
        'booking_id': booking,
        'quote_id': quote,
        'offer_id': offer,
        'accepted_offer_id': offer,
        'trip_id': trip,
        'rider_trip_id': trip,
        'trip_driver_id': driver,
        'trip_rider_id': rider,
        'trip_booking_id': booking,
        'trip_quote_id': quote,
        'trip_version': 1,
        'payment_method': 'cash',
        'authorized_reads': true,
        'evidence_ref': 'evidence-001'
      },
    };

AcceptanceReport evaluate(Object? evidence,
        {LocalPreflight? observation,
        Set<String> refs = references,
        ReadOnlyActors? actors}) =>
    validateAcceptance(observation ?? local(), evidence, now,
        availableReferences: refs, verifiedActors: actors);
ReadinessStatus status(AcceptanceReport r, String code) =>
    r.checks.singleWhere((c) => c.code == code).status;

class FakeActorAccess implements ApprovedReadOnlyActorAccess {
  FakeActorAccess(
      {this.authorized = true, this.foreign = false, this.throwError = false});
  final bool authorized, foreign, throwError;
  int calls = 0;
  @override
  Future<ReadOnlyActors?> readActors(String projectRef) async {
    calls++;
    if (throwError) {
      throw StateError('secret exception must never appear');
    }
    return ReadOnlyActors(
        projectRef: foreign ? 'zyxwvutsrqponmlkjihg' : projectRef,
        riderId: rider,
        driverId: driver,
        capturedAt: now,
        evidenceRef: 'evidence-001',
        authorized: authorized,
        riderRole: 'rider',
        driverRole: 'driver',
        driverApproved: true,
        eitherBlocked: false);
  }
}

void main() {
  test('unsafe local tool metadata is never copied to report', () {
    final report = evaluate(null,
        observation: const LocalPreflight(
            repositorySha: 'private-canary',
            flutterVersion: 'private-canary',
            sourceApplicationId: 'private-canary',
            rider: DeviceObservation(
                apkSha256: 'private-canary', versionCode: 'private-canary')));
    expect('${reportJson(report)}${report.toMarkdown()}',
        isNot(contains('private-canary')));
  });
  for (final issue in ['role', 'approval', 'blocked', 'stale', 'ownership']) {
    test('verified actor observation rejects $issue', () {
      final actors = ReadOnlyActors(
          projectRef: project,
          riderId: rider,
          driverId: issue == 'ownership' ? rider : driver,
          capturedAt:
              issue == 'stale' ? now.subtract(const Duration(minutes: 6)) : now,
          evidenceRef: 'evidence-001',
          authorized: true,
          riderRole: 'rider',
          driverRole: issue == 'role' ? 'rider' : 'driver',
          driverApproved: issue != 'approval',
          eitherBlocked: issue == 'blocked');
      expect(status(evaluate(fixture(), actors: actors), 'verified-actors'),
          ReadinessStatus.fail);
    });
  }
  test('complete supplied claims remain UNKNOWN and never certify scenarios',
      () {
    final r = evaluate(fixture());
    expect(status(r, 'android-package-source'), ReadinessStatus.pass);
    expect(status(r, 'approved-environment'), ReadinessStatus.unknown);
    expect(status(r, 'verified-actors'), ReadinessStatus.blocked);
    expect(status(r, 'trip-consistency'), ReadinessStatus.unknown);
    expect(r.checks.where((c) => c.scenario).length, 14);
    expect(
        r.checks
            .where((c) => c.scenario)
            .every((c) => c.status == ReadinessStatus.blocked),
        isTrue);
    expect(r.preflightReady, isFalse);
    expect(r.allChecksPass, isFalse);
    expect(r.toMarkdown(), contains('NOT RUN BY HARNESS'));
  });
  test('missing emulator blocks local readiness', () {
    expect(
        status(evaluate(fixture(), observation: local(connected: false)),
            '$riderEmulator-connected'),
        ReadinessStatus.blocked);
  });
  test('wrong installed build digest fails backend consistency', () {
    expect(
        status(evaluate(fixture(), observation: local(hash: 'c' * 64)),
            'driver-backend-build'),
        ReadinessStatus.fail);
  });
  test('wrong public backend identity fails consistency', () {
    final e = fixture();
    e['builds']['driver']['project_ref'] = 'zyxwvutsrqponmlkjihg';
    expect(status(evaluate(e), 'driver-backend-build'), ReadinessStatus.fail);
  });
  test('same Rider and Driver principal fails', () {
    final e = fixture();
    e['actors']['driver_id'] = rider;
    expect(status(evaluate(e), 'actor-claims'), ReadinessStatus.fail);
  });
  for (final key in ['matching', 'offer_delivery', 'realtime']) {
    test('missing $key is BLOCKED', () {
      final e = fixture();
      e['integrations'].remove(key);
      expect(status(evaluate(e), 'runtime-$key'), ReadinessStatus.blocked);
    });
    test('unavailable $key is BLOCKED', () {
      final e = fixture();
      e['integrations'][key]['available'] = false;
      expect(status(evaluate(e), 'runtime-$key'), ReadinessStatus.blocked);
    });
  }
  test('missing GPS blocks', () {
    final e = fixture();
    e.remove('gps');
    expect(status(evaluate(e), 'gps-freshness'), ReadinessStatus.blocked);
  });
  for (final change in <String, Object>{
    'recorded_at': now.subtract(const Duration(minutes: 2)).toIso8601String(),
    'received_at': now.add(const Duration(seconds: 1)).toIso8601String(),
    'accuracy_meters': 100,
    'sequence': 0,
    'latest_verified': false,
  }.entries) {
    test('invalid GPS ${change.key} fails supplied consistency', () {
      final e = fixture();
      e['gps'][change.key] = change.value;
      expect(status(evaluate(e), 'gps-freshness'), ReadinessStatus.fail);
    });
  }
  test('unknown Trip blocks', () {
    final e = fixture();
    e.remove('journey');
    expect(status(evaluate(e), 'trip-consistency'), ReadinessStatus.blocked);
  });
  for (final change in <String, Object>{
    'rider_trip_id': booking,
    'trip_driver_id': rider,
    'trip_booking_id': trip,
    'trip_quote_id': trip,
    'accepted_offer_id': trip,
    'trip_version': 0,
    'payment_method': 'card',
    'authorized_reads': false
  }.entries) {
    test('inconsistent Trip ${change.key} fails', () {
      final e = fixture();
      e['journey'][change.key] = change.value;
      expect(status(evaluate(e), 'trip-consistency'), ReadinessStatus.fail);
    });
  }
  test('missing safety evidence blocks', () {
    final e = fixture();
    e.remove('safety');
    expect(status(evaluate(e), 'financial-stop'), ReadinessStatus.blocked);
  });
  for (final key in [
    'completion_disabled',
    'card_disabled',
    'receipt_writes_disabled',
    'no_mutations_requested'
  ]) {
    test('missing financial safety gate $key fails closed', () {
      final e = fixture();
      e['safety'].remove(key);
      expect(status(evaluate(e), 'financial-stop'), ReadinessStatus.fail);
    });
  }
  test('reference strings alone cannot serve as evidence', () {
    final r = evaluate(fixture(), refs: {});
    expect(status(r, 'actor-claims'), ReadinessStatus.blocked);
    expect(status(r, 'financial-stop'), ReadinessStatus.blocked);
    expect(r.checks.every((c) => c.reference == null), isTrue);
  });
  test('synthetic fixtures never satisfy C', () {
    final e = fixture();
    e['kind'] = 'synthetic';
    final r = evaluate(e);
    expect(r.synthetic, isTrue);
    expect(r.allChecksPass, isFalse);
    expect(r.toJson()['e2e_execution'], 'NOT RUN BY HARNESS');
  });
  test('unknown credential fields rejected without echo', () {
    final e = fixture();
    e['token'] = 'private-canary-credential';
    final r = evaluate(e);
    expect(status(r, 'evidence-schema'), ReadinessStatus.fail);
    expect(reportJson(r), isNot(contains('private-canary')));
    expect(r.toMarkdown(), isNot(contains('private-canary')));
  });
  test('invalid strings, identities and raw paths never leak into reports', () {
    final e = fixture();
    e['environment']['project_ref'] = 'private-canary-key';
    e['actors']['evidence_ref'] = '/private-canary/path';
    final output = '${reportJson(evaluate(e))}${evaluate(e).toMarkdown()}';
    expect(output, isNot(contains('private-canary')));
    expect(output, isNot(contains(rider)));
    expect(output, isNot(contains(trip)));
    expect(jsonDecode(reportJson(evaluate(e))), isA<Map>());
  });
  test('stale SHA-bound evidence fails', () {
    final e = fixture();
    e['repository_sha'] = 'c' * 40;
    expect(status(evaluate(e), 'evidence-envelope'), ReadinessStatus.fail);
    e['repository_sha'] = sha;
    e['captured_at'] =
        now.subtract(const Duration(minutes: 6)).toIso8601String();
    expect(status(evaluate(e), 'evidence-envelope'), ReadinessStatus.fail);
  });
  test('approved actor port verifies identities only, not live journey',
      () async {
    final access = FakeActorAccess();
    final r = await evaluateWithApprovedReadOnlyAccess(local(), fixture(), now,
        access: access, availableReferences: references);
    expect(access.calls, 1);
    expect(status(r, 'verified-actors'), ReadinessStatus.pass);
    expect(r.allChecksPass, isFalse);
    expect(status(r, 'S01'), ReadinessStatus.blocked);
  });
  for (final foreign in [false, true]) {
    test(
        'actor port rejects ${foreign ? 'foreign environment' : 'unauthorized access'}',
        () async {
      final r = await evaluateWithApprovedReadOnlyAccess(
          local(), fixture(), now,
          access: FakeActorAccess(authorized: foreign, foreign: foreign),
          availableReferences: references);
      expect(status(r, 'verified-actors'), ReadinessStatus.fail);
    });
  }
  test('actor interruption is blocked and errors sanitized', () async {
    final r = await evaluateWithApprovedReadOnlyAccess(local(), fixture(), now,
        access: FakeActorAccess(throwError: true),
        availableReferences: references);
    expect(status(r, 'verified-actors'), ReadinessStatus.blocked);
    expect(reportJson(r), isNot(contains('secret exception')));
  });
  for (final mode in ['synthetic', 'unapproved', 'malformed', 'stale']) {
    test('no actor read for $mode input', () async {
      final e = fixture();
      if (mode == 'synthetic') {
        e['kind'] = 'synthetic';
      }
      if (mode == 'unapproved') {
        e['environment']['approved_nonproduction'] = false;
      }
      if (mode == 'malformed') {
        e['unknown'] = true;
      }
      if (mode == 'stale') {
        e['captured_at'] = '2020-01-01T00:00:00Z';
      }
      final access = FakeActorAccess();
      await evaluateWithApprovedReadOnlyAccess(local(), e, now,
          access: access, availableReferences: references);
      expect(access.calls, 0);
    });
  }
}
