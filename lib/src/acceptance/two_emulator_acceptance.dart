import 'dart:convert';

enum ReadinessStatus { pass, fail, blocked, unknown }

const riderEmulator = 'emulator-5554';
const driverEmulator = 'emulator-5556';
final _sha = RegExp(r'^[a-f0-9]{40}$');
final _digest = RegExp(r'^[a-f0-9]{64}$');
final _uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$');
final _project = RegExp(r'^[a-z]{20}$');
final evidenceReferencePattern = RegExp(r'^evidence-[0-9]{3,6}$');

class DeviceObservation {
  const DeviceObservation(
      {this.connected = false,
      this.booted = false,
      this.applicationId,
      this.apkSha256,
      this.versionCode});
  final bool connected, booted;
  final String? applicationId, apkSha256, versionCode;
}

class LocalPreflight {
  const LocalPreflight(
      {this.repositorySha,
      this.flutterVersion,
      this.cleanRepository = false,
      this.adbAvailable = false,
      this.sdkAvailable = false,
      this.sourceApplicationId,
      this.sourceComponents = const {},
      this.rider = const DeviceObservation(),
      this.driver = const DeviceObservation()});
  final String? repositorySha, flutterVersion, sourceApplicationId;
  final bool cleanRepository, adbAvailable, sdkAvailable;
  final Map<String, bool> sourceComponents;
  final DeviceObservation rider, driver;
}

/// Future approved normal-user read seam. No implementation, credentials, network
/// client, role-changing API or hosted access is invented by this tooling.
/// A collector must validate SDK identity, owner approval and actor records under
/// approved read-only access; test fakes are always level B, never C acceptance.
abstract interface class ApprovedReadOnlyActorAccess {
  Future<ReadOnlyActors?> readActors(String projectRef);
}

class ReadOnlyActors {
  const ReadOnlyActors(
      {required this.projectRef,
      required this.riderId,
      required this.driverId,
      required this.capturedAt,
      required this.evidenceRef,
      required this.authorized,
      required this.riderRole,
      required this.driverRole,
      required this.driverApproved,
      required this.eitherBlocked});
  final String projectRef,
      riderId,
      driverId,
      evidenceRef,
      riderRole,
      driverRole;
  final DateTime capturedAt;
  final bool authorized, driverApproved, eitherBlocked;
}

class ReadinessCheck {
  const ReadinessCheck(
      this.code, this.status, this.owner, this.basis, this.action,
      {this.reference, this.scenario = false});
  final String code, owner, basis, action;
  final ReadinessStatus status;
  final String? reference;
  final bool scenario;
  Map<String, Object?> toJson() => {
        'code': code,
        'status': status.name.toUpperCase(),
        'owner': owner,
        'basis': basis,
        'next_action': action,
        if (reference != null) 'evidence_ref': reference,
      };
}

const scenarioOwners = {
  'S01': 'Sanad',
  'S02': 'Moath',
  'S03': 'Moath/Yousuf',
  'S04': 'Omar',
  'S05': 'Sanad',
  'S06': 'Yousuf',
  'S07': 'Moath/Omar',
  'S08': 'Moath',
  'S09': 'Moath/Yousuf',
  'S10': 'Sanad',
  'S11': 'Sanad/Omar',
  'S12': 'All owners/security',
  'S13': 'Sanad/Moath/Yousuf',
  'S14': 'Moath/payment owner',
};
const sourcePaths = {
  'matching': 'supabase/functions/cash-matching/index.ts',
  'offer_delivery':
      'lib/features/driver_flow/data/polling_canonical_driver_offer_delivery.dart',
  'driver_composition':
      'lib/features/driver_flow/presentation/providers/canonical_driver_presentation_controller.dart',
  'rider_assignment':
      'lib/core/repositories/cash_booking_assignment_repository.dart',
  'realtime': 'lib/core/services/trips/trip_realtime_adapter.dart',
};
const integrationOwners = {
  'matching': 'Yousuf',
  'offer_delivery': 'Moath',
  'driver_composition': 'Moath',
  'rider_assignment': 'Sanad',
  'tracking': 'Sanad/Omar',
  'realtime': 'Omar',
  'safe_publication': 'Omar/backend owner',
  'eligibility': 'Moath/Yousuf',
};

class AcceptanceReport {
  AcceptanceReport(this.repositorySha, this.generatedAt, this.checks,
      this.synthetic, this.projectRef, this.localObservations);
  final String? repositorySha, projectRef;
  final DateTime generatedAt;
  final List<ReadinessCheck> checks;
  final bool synthetic;
  final Map<String, Object?> localObservations;
  // Raw supplied claims cannot satisfy independent environment/build verification.
  bool get preflightReady =>
      !synthetic &&
      checks
          .where((c) => !c.scenario)
          .every((c) => c.status == ReadinessStatus.pass);
  bool get allChecksPass =>
      !synthetic && checks.every((c) => c.status == ReadinessStatus.pass);
  Map<String, Object?> toJson() => {
        'schema': 1,
        'repository_sha': repositorySha,
        'generated_at': generatedAt.toUtc().toIso8601String(),
        'devices': [riderEmulator, driverEmulator],
        'environment_project_ref': projectRef,
        'synthetic_evidence': synthetic,
        'local_observations': localObservations,
        'preflight_ready': preflightReady,
        'e2e_execution': 'NOT RUN BY HARNESS',
        'scope':
            'Local observations and supplied-evidence consistency only. Scenario actions are never executed.',
        'checks': checks.map((c) => c.toJson()).toList(),
      };
  String toMarkdown() {
    final out = StringBuffer('# RideX B09A readiness and evidence report\n\n')
      ..writeln(
          'E2E execution: **NOT RUN BY HARNESS**. S01–S14 are not certified by this tool.')
      ..writeln(
          'A: independent Mock UI. B: synthetic/local validation. C: genuine shared-backend devices.')
      ..writeln(
          'A/B passes never establish C. Supplied claims are not independent backend verification.')
      ..writeln('Repository: ${repositorySha ?? 'UNKNOWN'}')
      ..writeln('Devices: $riderEmulator (Rider), $driverEmulator (Driver)')
      ..writeln(
          'Observed package: ${localObservations['application_id'] ?? 'UNKNOWN'}; Flutter: ${localObservations['flutter_version'] ?? 'UNKNOWN'}. APK versions and fingerprints are in report.json.')
      ..writeln(
          'Nonsecret project reference: ${projectRef ?? 'NOT PROVIDED'} (supplied only)')
      ..writeln(
          'Preflight ready: $preflightReady. Synthetic input: $synthetic.\n')
      ..writeln(
          '| Check | Status | Basis | Owner | Evidence | Exact next action |')
      ..writeln('|---|---|---|---|---|---|');
    for (final c in checks) {
      out.writeln(
          '| ${c.code} | ${c.status.name.toUpperCase()} | ${c.basis} | ${c.owner} | ${c.reference ?? 'missing'} | ${c.action} |');
    }
    out.writeln(
        '\nEvidence IDs refer to separately retained evidence-NNN.json artifacts; existence does not authenticate their contents.');
    return out.toString();
  }
}

Map<String, Object?> _node(Object? input, Set<String> allowed) {
  if (input == null) return {};
  if (input is! Map<String, Object?> ||
      input.keys.any((k) => !allowed.contains(k))) {
    throw const FormatException('Invalid sanitized schema.');
  }
  return input;
}

String? _text(Object? v, RegExp pattern) =>
    v is String && pattern.stringMatch(v) == v ? v : null;
DateTime? _time(Object? v) {
  if (v is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(v)) return null;
  return DateTime.tryParse(v)?.toUtc();
}

bool _positive(Object? v) => v is int && v > 0 && v <= 2147483647;
bool _fresh(DateTime? v, DateTime now, Duration maximumAge) =>
    v != null && !v.isAfter(now) && now.difference(v) <= maximumAge;

/// No raw input strings or errors enter output. References must have an actual
/// external artifact; the body is never copied into the generated report.
AcceptanceReport validateAcceptance(
    LocalPreflight local, Object? evidence, DateTime now,
    {Set<String> availableReferences = const {},
    ReadOnlyActors? verifiedActors}) {
  final checks = <ReadinessCheck>[];
  void check(String code, ReadinessStatus status, String owner, String basis,
          String action, {String? reference, bool scenario = false}) =>
      checks.add(ReadinessCheck(code, status, owner, basis, action,
          reference: reference, scenario: scenario));
  void observed(String code, bool ok, String action) => check(
      code,
      ok ? ReadinessStatus.pass : ReadinessStatus.blocked,
      'Moath',
      'local observation',
      action);
  final sha = _text(local.repositorySha, _sha);
  observed('repository', sha != null && local.cleanRepository,
      'Use an intended clean source revision; retain its exact SHA.');
  observed(
      'flutter',
      local.flutterVersion != null &&
          RegExp(r'^\d+\.\d+\.\d+$').hasMatch(local.flutterVersion!),
      'Select the project Flutter SDK and rerun preflight.');
  observed('android-tools', local.adbAvailable && local.sdkAvailable,
      'Provide ADB, SDK platforms and build-tools; this checks availability, not licenses/Gradle health.');
  final package = _text(local.sourceApplicationId,
      RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,5}$'));
  observed('android-package-source', package != null,
      'Resolve one literal applicationId from Android configuration; computed IDs stay blocked.');
  for (final entry in [
    (riderEmulator, local.rider),
    (driverEmulator, local.driver)
  ]) {
    observed('${entry.$1}-connected', entry.$2.connected,
        'Connect and authorize the expected emulator.');
    observed('${entry.$1}-booted', entry.$2.connected && entry.$2.booted,
        'Complete emulator boot; do not wipe it.');
    observed(
        '${entry.$1}-application',
        package != null && entry.$2.applicationId == package,
        'Install the separately approved application build; B09A never installs or launches.');
    observed('${entry.$1}-artifact', _text(entry.$2.apkSha256, _digest) != null,
        'Retain an inspectable installed standalone APK fingerprint. Splits/unreadable APKs remain blocked.');
    observed(
        '${entry.$1}-version',
        entry.$2.versionCode != null &&
            RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(entry.$2.versionCode!),
        'Read installed versionCode; matching versions alone cannot prove source/build/backend identity.');
  }
  for (final key in sourcePaths.keys) {
    observed('source-$key', local.sourceComponents[key] == true,
        'Inspect the committed component. Source presence alone is not runtime/deployment acceptance.');
  }
  String? project;
  var synthetic = true;
  try {
    final root = _node(evidence, {
      'schema',
      'kind',
      'repository_sha',
      'captured_at',
      'environment',
      'actors',
      'builds',
      'integrations',
      'gps',
      'safety',
      'journey'
    });
    final env = _node(root['environment'],
        {'project_ref', 'approved_nonproduction', 'approval_ref'});
    final actors = _node(root['actors'],
        {'rider_id', 'driver_id', 'roles_verified', 'evidence_ref'});
    final builds = _node(root['builds'], {'rider', 'driver'});
    final integrations =
        _node(root['integrations'], integrationOwners.keys.toSet());
    final gps = _node(root['gps'], {
      'recorded_at',
      'received_at',
      'accuracy_meters',
      'sequence',
      'latest_verified',
      'evidence_ref'
    });
    final safety = _node(root['safety'], {
      'completion_disabled',
      'card_disabled',
      'receipt_writes_disabled',
      'no_mutations_requested',
      'evidence_ref'
    });
    final journey = _node(root['journey'], {
      'booking_id',
      'quote_id',
      'offer_id',
      'accepted_offer_id',
      'trip_id',
      'rider_trip_id',
      'trip_driver_id',
      'trip_rider_id',
      'trip_booking_id',
      'trip_quote_id',
      'trip_version',
      'payment_method',
      'authorized_reads',
      'evidence_ref'
    });
    synthetic = root['kind'] != 'operator_attested';
    project = _text(env['project_ref'], _project);
    String? reference(Object? raw) {
      final ref = _text(raw, evidenceReferencePattern);
      return ref != null && availableReferences.contains(ref) ? ref : null;
    }

    void attested(
        String code, bool? valid, String owner, String action, Object? ref) {
      final actual = reference(ref);
      check(
          code,
          valid == null || actual == null
              ? ReadinessStatus.blocked
              : valid
                  ? ReadinessStatus.unknown
                  : ReadinessStatus.fail,
          owner,
          'supplied consistency only; authority unverified',
          action,
          reference: actual);
    }

    attested(
        'evidence-envelope',
        root.isEmpty
            ? null
            : root['schema'] == 1 &&
                {'synthetic', 'operator_attested'}.contains(root['kind']) &&
                root['repository_sha'] == sha &&
                _fresh(_time(root['captured_at']), now,
                    const Duration(minutes: 5)),
        'Moath',
        'Retain current SHA-bound sanitized evidence; imported claims cannot certify C.',
        env['approval_ref']);
    attested(
        'approved-environment',
        env.isEmpty
            ? null
            : project != null && env['approved_nonproduction'] == true,
        'Environment owner',
        'Obtain independently reviewed target/namespace/fixture-operation approval.',
        env['approval_ref']);
    final rider = _text(actors['rider_id'], _uuid)?.toLowerCase();
    final driver = _text(actors['driver_id'], _uuid)?.toLowerCase();
    attested(
        'actor-claims',
        actors.isEmpty
            ? null
            : rider != null &&
                driver != null &&
                rider != driver &&
                actors['roles_verified'] == true,
        'Moath/Sanad',
        'Verify distinct principals, roles, Driver approval and block state through approved read-only access.',
        actors['evidence_ref']);
    final verifiedRef =
        verifiedActors == null ? null : reference(verifiedActors.evidenceRef);
    final verified = verifiedActors;
    check(
        'verified-actors',
        verified == null || verifiedRef == null
            ? ReadinessStatus.blocked
            : verified.authorized &&
                    verified.projectRef == project &&
                    rider != null &&
                    driver != null &&
                    verified.riderId.toLowerCase() == rider &&
                    verified.driverId.toLowerCase() == driver &&
                    rider != driver &&
                    verified.riderRole == 'rider' &&
                    verified.driverRole == 'driver' &&
                    verified.driverApproved &&
                    !verified.eitherBlocked &&
                    _fresh(verified.capturedAt, now, const Duration(minutes: 5))
                ? ReadinessStatus.pass
                : ReadinessStatus.fail,
        'Moath/Sanad',
        'injected approved read-only observation; no scenario executed',
        'Supply an approved normal-user actor reader; CLI has no hosted reader and cannot invent one.',
        reference: verifiedRef);
    for (final entry in [('rider', local.rider), ('driver', local.driver)]) {
      final b = _node(
          builds[entry.$1], {'apk_sha256', 'project_ref', 'evidence_ref'});
      attested(
          '${entry.$1}-backend-build',
          b.isEmpty
              ? null
              : _text(b['apk_sha256'], _digest) != null &&
                  b['apk_sha256'] == entry.$2.apkSha256 &&
                  project != null &&
                  b['project_ref'] == project,
          entry.$1 == 'rider' ? 'Sanad' : 'Moath',
          'Independently verify public backend configuration bound to the installed APK hash and source SHA; do not extract secrets.',
          b['evidence_ref']);
    }
    for (final key in integrationOwners.keys) {
      final item = _node(integrations[key], {'available', 'evidence_ref'});
      attested(
          'runtime-$key',
          item['available'] != true ? null : true,
          integrationOwners[key]!,
          'Obtain reviewed runtime/deployment and actor-scoped acceptance evidence for this component.',
          item['evidence_ref']);
    }
    final recorded = _time(gps['recorded_at']),
        received = _time(gps['received_at']);
    final accuracy = gps['accuracy_meters'];
    attested(
        'gps-freshness',
        gps.isEmpty
            ? null
            : recorded != null &&
                received != null &&
                now.difference(recorded) <= const Duration(seconds: 60) &&
                recorded.difference(now) <= const Duration(seconds: 5) &&
                _fresh(received, now, const Duration(seconds: 60)) &&
                recorded.difference(received) <= const Duration(seconds: 5) &&
                accuracy is num &&
                accuracy.isFinite &&
                accuracy > 0 &&
                accuracy <= 50 &&
                _positive(gps['sequence']) &&
                gps['latest_verified'] == true,
        'Omar',
        'Verify latest genuine sequence, quality and server receipt; do not retimestamp old fixes.',
        gps['evidence_ref']);
    attested(
        'financial-stop',
        safety.isEmpty
            ? null
            : safety['completion_disabled'] == true &&
                safety['card_disabled'] == true &&
                safety['receipt_writes_disabled'] == true &&
                safety['no_mutations_requested'] == true,
        'Moath/payment owner',
        'Verify disabled completion/Card/receipt gates against intended build. No financial action is permitted.',
        safety['evidence_ref']);
    final trip = _text(journey['trip_id'], _uuid);
    attested(
        'trip-consistency',
        journey.isEmpty
            ? null
            : rider != null &&
                driver != null &&
                _text(journey['booking_id'], _uuid) != null &&
                _text(journey['quote_id'], _uuid) != null &&
                _text(journey['offer_id'], _uuid) != null &&
                journey['accepted_offer_id'] == journey['offer_id'] &&
                trip != null &&
                journey['rider_trip_id'] == trip &&
                journey['trip_rider_id'] == rider &&
                journey['trip_driver_id'] == driver &&
                journey['trip_booking_id'] == journey['booking_id'] &&
                journey['trip_quote_id'] == journey['quote_id'] &&
                _positive(journey['trip_version']) &&
                journey['payment_method'] == 'cash' &&
                journey['authorized_reads'] == true,
        'All owners',
        'Obtain independent participant canonical reads and exact original booking/quote/offer/Trip correlation.',
        journey['evidence_ref']);
  } on Object {
    check('evidence-schema', ReadinessStatus.fail, 'Moath', 'input validation',
        'Use the strict sanitized schema; unknown fields, raw credentials and malformed nodes are rejected without echo.');
  }
  for (final entry in scenarioOwners.entries) {
    check(
        entry.key,
        ReadinessStatus.blocked,
        entry.value,
        'C action NOT RUN by B09A',
        'Follow the S01-S14 specification only after prerequisites, approvals and reviewed integration are ready.',
        scenario: true);
  }
  return AcceptanceReport(
      sha,
      now,
      List.unmodifiable(checks),
      synthetic,
      project,
      Map.unmodifiable({
        'application_id': package,
        'flutter_version':
            _text(local.flutterVersion, RegExp(r'^\d+\.\d+\.\d+$')),
        for (final entry in [
          (riderEmulator, local.rider),
          (driverEmulator, local.driver)
        ])
          entry.$1: {
            'connected': entry.$2.connected,
            'booted': entry.$2.booted,
            'apk_sha256': _text(entry.$2.apkSha256, _digest),
            'version_code':
                _text(entry.$2.versionCode, RegExp(r'^[1-9][0-9]{0,9}$')),
          },
      }));
}

Future<AcceptanceReport> evaluateWithApprovedReadOnlyAccess(
    LocalPreflight local, Object? evidence, DateTime now,
    {ApprovedReadOnlyActorAccess? access,
    Set<String> availableReferences = const {}}) async {
  ReadOnlyActors? actors;
  // Validate/sanitize first; do not invoke an adapter with unvalidated target data.
  final initial = validateAcceptance(local, evidence, now,
      availableReferences: availableReferences);
  if (!initial.synthetic &&
      initial.projectRef != null &&
      access != null &&
      initial.checks.any((c) =>
          c.code == 'approved-environment' &&
          c.status == ReadinessStatus.unknown) &&
      initial.checks.any((c) =>
          c.code == 'evidence-envelope' &&
          c.status == ReadinessStatus.unknown) &&
      !initial.checks.any((c) => c.code == 'evidence-schema')) {
    try {
      actors = await access
          .readActors(initial.projectRef!)
          .timeout(const Duration(seconds: 10));
    } on Object {/* No raw backend exception or identity data is reported. */}
  }
  return validateAcceptance(local, evidence, now,
      availableReferences: availableReferences, verifiedActors: actors);
}

String reportJson(AcceptanceReport report) =>
    const JsonEncoder.withIndent('  ').convert(report.toJson());
