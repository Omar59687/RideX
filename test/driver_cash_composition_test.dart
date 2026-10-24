import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/canonical_trip_reconciliation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/supabase_driver_cash_completion_composition.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Reuse only the B1-A suite's public loopback/auth fixtures, never its main().
import 'driver_authority_foundation_test.dart' as fixture;

const tripId = 'd7000000-0000-0000-0000-000000000001';
const namespace = 'cash-composition-test';
final command = DriverCompleteTripCommand(
    tripId: tripId,
    expectedTripVersion: 4,
    idempotencyKey: 'original-cash-completion-key');

class _CanonicalSource implements CanonicalDriverCompletionSource {
  @override
  Future<CanonicalDriverCompletionContext?> load() async =>
      CanonicalDriverCompletionContext(
          driverId: fixture.driver, command: command);
}

class _JournalGateway implements DriverCompletionStagingGateway {
  _JournalGateway(this.store);
  final FileDriverCompletionCommandStore store;
  @override
  Future<CoordinatorStagingDecision> stage(
      CanonicalDriverCompletionContext context) async {
    final result = await store.stage(
        backendNamespace: namespace,
        driverId: context.driverId,
        command: context.command);
    return switch (result) {
      CompletionCreated(:final command) => StagingNewlyCreated(command),
      CompletionExisting(:final command) => StagingExistingEvidence(command),
      CompletionConflict() => const StagingConflict(),
      CompletionBlocked() =>
        const StagingBlocked(StagingBlockReason.persistenceUncertain),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late SupabaseDriverAuthorityBinding binding;
  late VerifiedSupabaseDriverAccess access;
  late DriverAuthorityLifecycle lifecycle;
  late SupabaseDriverCashCompletionComposition composition;
  late Directory journalDirectory;
  late FileDriverCompletionCommandStore store;
  HttpOverrides? previousHttp;
  SharedPreferencesAsyncPlatform? previousPreferences;
  final requests = <(String, String)>[];
  final rpcBodies = <Map<String, dynamic>>[];
  late String status, method, assignedDriver, role, approval;
  late int version;
  late bool blocked, missingReceipt, wrongReceipt, rpcReject;
  Future<void> Function(String)? boundary;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.app_links/events'),
            (_) async => null);
    previousPreferences = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    requests.clear();
    rpcBodies.clear();
    boundary = null;
    status = 'inProgress';
    method = 'cash';
    assignedDriver = fixture.driver;
    role = 'driver';
    approval = 'approved';
    version = 4;
    blocked = false;
    missingReceipt = false;
    wrongReceipt = false;
    rpcReject = false;
    lifecycle = const DriverAuthorityLifecycle(epoch: 1, isActive: true);
    journalDirectory =
        await Directory.systemTemp.createTemp('ridex-cash-composition-');
    store = FileDriverCompletionCommandStore(directory: journalDirectory);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      requests.add((request.method, path));
      Map<String, dynamic>? body;
      if (request.method == 'POST') {
        body = Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map);
      }
      request.response.headers.contentType = ContentType.json;
      await boundary?.call(path);
      if (path.endsWith('/users')) {
        request.response.write(jsonEncode(
            {'id': fixture.driver, 'role': role, 'is_blocked': blocked}));
      } else if (path.endsWith('/driver_profiles')) {
        request.response.write(jsonEncode(
            {'user_id': fixture.driver, 'approval_status': approval}));
      } else if (path.endsWith('/trips')) {
        request.response.write(jsonEncode({
          'id': tripId,
          'driver_id': assignedDriver,
          'status': status,
          'version': version,
          'payment_method': method
        }));
      } else if (path.endsWith('/driver_transition_trip')) {
        rpcBodies.add(body!);
        if (rpcReject) {
          request.response.statusCode = 409;
          request.response.write(
              jsonEncode({'code': '40001', 'message': 'private-stale-error'}));
        } else {
          status = 'completed';
          version = 11;
          request.response
              .write(jsonEncode({'trip_id': tripId, 'status': status}));
        }
      } else if (path.endsWith('/user_trip_receipt_summary')) {
        if (missingReceipt) {
          request.response.statusCode = 404;
          request.response.write(jsonEncode(
              {'code': 'P0002', 'message': 'private-receipt-absent'}));
        } else {
          request.response.write(jsonEncode([
            {
              'id': 'e7000000-0000-0000-0000-000000000001',
              'trip_id': wrongReceipt ? fixture.other : tripId,
              'receipt_number': 'R-TEST'
            }
          ]));
        }
      } else {
        request.response.statusCode = 500;
        request.response.write(
            jsonEncode({'code': 'unexpected-request', 'message': 'forbidden'}));
      }
      await request.response.close();
    });
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = fixture.LocalHttp(server.port);
    final provenance = SupabaseInitializationProvenance();
    await provenance.initialize(fixture.environment);
    access = provenance.driverAccess(DriverBackendRegistry([
      DriverBackendIdentity(
          endpoint: Uri.parse(fixture.environment.url), namespace: namespace),
    ]))!;
    binding = SupabaseDriverAuthorityBinding.create(
        access: access, lifecycleReader: () => lifecycle);
    await Supabase.instance.client.auth
        .setInitialSession(jsonEncode(fixture.authResponse()));
    composition = SupabaseDriverCashCompletionComposition(
        access: access, authority: binding);
  });
  tearDown(() async {
    await binding.dispose();
    await Supabase.instance.dispose();
    await server.close(force: true);
    HttpOverrides.global = previousHttp;
    SharedPreferencesAsyncPlatform.instance = previousPreferences;
    // Only the independently created test temp directory is removed.
    await journalDirectory.delete(recursive: true);
  });

  DriverCompletionCoordinator coordinator() => DriverCompletionCoordinator(
        canonicalSource: _CanonicalSource(),
        stagingGateway: _JournalGateway(store),
        repository: composition,
        sessionReader: () async => DriverCompletionSessionSnapshot(
            driverId: binding.currentOwner.driverId,
            epoch: lifecycle.epoch,
            isApprovedDriver: lifecycle.isActive),
      );
  test(
      'real journal → verified singleton → exact trusted RPC → canonical Trip and safe receipt',
      () async {
    final c = coordinator();
    final results = await Future.wait([c.complete(), c.complete()]);
    final result = results.first as CoordinatorCompleted;
    expect(result.result.backendVersion, 11);
    expect(result.result.receiptVerified, isTrue);
    expect(result.result.receiptNumber, 'R-TEST');
    expect(rpcBodies.single, {
      'target_id': tripId,
      'requested_status': 'completed',
      'expected_version': 4,
      'idempotency_key': command.idempotencyKey
    });
    expect(
        requests.any((r) =>
            r.$2.contains('payments') || r.$2.contains('payment_attempt')),
        isFalse);
    final slot = await store.inspect(
        backendNamespace: namespace, driverId: fixture.driver, tripId: tripId);
    expect((slot as CompletionValid).command, command);
    expect(await coordinator().complete(), isA<CoordinatorUnresolved>());
    expect(rpcBodies, hasLength(1));
  });
  for (final scenario in [
    'rider',
    'blocked',
    'unapproved',
    'wrong driver',
    'stale version',
    'card',
    'not started',
    'inactive'
  ]) {
    test('$scenario fails before completion RPC', () async {
      switch (scenario) {
        case 'rider':
          role = 'rider';
        case 'blocked':
          blocked = true;
        case 'unapproved':
          approval = 'pending';
        case 'wrong driver':
          assignedDriver = fixture.other;
        case 'stale version':
          version = 9;
        case 'card':
          method = 'card';
        case 'not started':
          status = 'accepted';
        case 'inactive':
          lifecycle = const DriverAuthorityLifecycle(epoch: 2, isActive: false);
      }
      await expectLater(
          composition.completeTrip(command),
          throwsA(isA<DriverCompletionAttemptException>().having((e) => e.stage,
              'stage', DriverCompletionAttemptStage.beforeDispatch)));
      expect(rpcBodies, isEmpty);
    });
  }
  test('B1-B epoch revocation while preflight awaits prevents RPC', () async {
    boundary = (path) async {
      if (path.endsWith('/trips'))
        lifecycle = const DriverAuthorityLifecycle(epoch: 2, isActive: false);
    };
    await expectLater(composition.completeTrip(command),
        throwsA(isA<DriverCompletionAttemptException>()));
    expect(rpcBodies, isEmpty);
  });
  test('late RPC success after revocation is unresolved with journal retained',
      () async {
    boundary = (path) async {
      if (path.endsWith('/driver_transition_trip'))
        lifecycle = const DriverAuthorityLifecycle(epoch: 2, isActive: false);
    };
    expect(await coordinator().complete(), isA<CoordinatorInvalidated>());
    expect(rpcBodies, hasLength(1));
    expect(
        await store.inspect(
            backendNamespace: namespace,
            driverId: fixture.driver,
            tripId: tripId),
        isA<CompletionValid>());
  });
  test('receipt absence confirms Trip only, never invents financial success',
      () async {
    missingReceipt = true;
    final result = await composition.completeTrip(command);
    expect(result.backendVersion, 11);
    expect(result.receiptVerified, isFalse);
    expect(result.receiptNumber, isNull);
  });
  test('wrong receipt lineage retains verified Trip in unresolved evidence',
      () async {
    wrongReceipt = true;
    await expectLater(
        composition.completeTrip(command),
        throwsA(isA<DriverCompletionAttemptException>()
            .having((e) => e.stage, 'stage',
                DriverCompletionAttemptStage.receiptReread)
            .having((e) => e.confirmedTrip?.backendVersion, 'canonical version',
                11)));
  });
  test('trusted stale rejection never rotates the command or retries',
      () async {
    rpcReject = true;
    await expectLater(composition.completeTrip(command),
        throwsA(isA<DriverCompletionAttemptException>()));
    expect(rpcBodies, hasLength(1));
    expect(rpcBodies.single['idempotency_key'], command.idempotencyKey);
  });

  test('SDK A-B-A replacement during RPC cannot publish completion', () async {
    boundary = (path) async {
      if (path.endsWith('/driver_transition_trip')) {
        await Supabase.instance.client.auth.setInitialSession(
            jsonEncode(fixture.authResponse(id: fixture.other)));
        await Supabase.instance.client.auth
            .setInitialSession(jsonEncode(fixture.authResponse()));
      }
    };
    expect(await coordinator().complete(), isA<CoordinatorUnresolved>());
    expect(rpcBodies, hasLength(1));
  });

  test('revocation during absent-receipt read never returns a success',
      () async {
    missingReceipt = true;
    boundary = (path) async {
      if (path.endsWith('/user_trip_receipt_summary')) {
        lifecycle = const DriverAuthorityLifecycle(epoch: 2, isActive: false);
      }
    };
    await expectLater(composition.completeTrip(command),
        throwsA(isA<DriverCompletionAttemptException>()));
    expect(rpcBodies, hasLength(1));
  });

  test(
      'recovery composes same verified client with GET-only canonical classification',
      () async {
    status = 'completed';
    version = 21;
    final result = await composition.readCanonicalTrip(
        command: command,
        capturedDriverId: fixture.driver,
        capturedBackendNamespace: namespace);
    expect(result, isA<CanonicalTripVisible>());
    expect((result as CanonicalTripVisible).trip.backendVersion, 21);
    expect(requests.every((r) => r.$1 == 'GET'), isTrue);
    expect(rpcBodies, isEmpty);
  });

  test('recovery cannot borrow another Driver journal namespace', () async {
    final result = await composition.readCanonicalTrip(
        command: command,
        capturedDriverId: fixture.other,
        capturedBackendNamespace: namespace);
    expect(result, isA<CanonicalTripReadFailed>());
    expect(requests.any((r) => r.$2.endsWith('/trips')), isFalse);
    expect(rpcBodies, isEmpty);
  });
}
