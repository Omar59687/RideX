import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/services/trips/driver_completion_staging_gateway.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/driver_cash_completion_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/supabase_driver_completion_source.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:ridex/core/services/trips/application_completion_store.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';
import 'package:ridex/features/trips/application/driver_cash_completion_controller.dart';
import 'package:ridex/features/trips/presentation/widgets/driver_cash_completion_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'driver_authority_foundation_test.dart' as fixture;

const trip = 'd7000000-0000-0000-0000-000000000001';
const namespace = 'production-composition-fixture';

class DriverSession extends SessionController {
  @override
  SessionState build() => SessionState.fromUser(const AppUser(
      id: fixture.driver,
      name: 'Driver',
      email: 'driver@example.invalid',
      role: RideRole.driver,
      driverApprovalStatus: DriverApprovalStatus.approved));
}

class FailingWrite extends NativeCompletionJournalIo {
  @override
  Future<void> write(RandomAccessFile handle, List<int> bytes) async =>
      throw const FileSystemException('Injected write failure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late Directory directory;
  late SupabaseInitializationProvenance provenance;
  late VerifiedSupabaseDriverAccess access;
  late AuthService auth;
  late SupabaseDriverAuthorityBinding binding;
  late FileDriverCompletionCommandStore store;
  HttpOverrides? previousHttp;
  SharedPreferencesAsyncPlatform? previousPreferences;
  final requests = <(String, String)>[];
  final bodies = <Map<String, dynamic>>[];
  late String role,
      approval,
      assignedDriver,
      method,
      status,
      activeTrip,
      availabilityState;
  late int version;
  late bool blocked, missingReceipt, wrongReceipt, unknownRpc, failReads;
  Future<void> Function(String)? boundary;
  final containers = <ProviderContainer>[];

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
    bodies.clear();
    boundary = null;
    role = 'driver';
    approval = 'approved';
    assignedDriver = fixture.driver;
    method = 'cash';
    status = 'inProgress';
    activeTrip = trip;
    availabilityState = 'onTrip';
    version = 4;
    blocked = false;
    missingReceipt = false;
    wrongReceipt = false;
    unknownRpc = false;
    failReads = false;
    directory = await Directory.systemTemp.createTemp('ridex-r01-r02-test-');
    store = FileDriverCompletionCommandStore(directory: directory);
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
      Object? response;
      if (failReads) {
        request.response.statusCode = 503;
        response = {'code': 'offline', 'message': 'private error'};
      } else if (path.endsWith('/users')) {
        response = {'id': fixture.driver, 'role': role, 'is_blocked': blocked};
      } else if (path.endsWith('/driver_profiles')) {
        response = {'user_id': fixture.driver, 'approval_status': approval};
      } else if (path.endsWith('/driver_availability')) {
        expect(
            request.uri.queryParameters['driver_id'], 'eq.${fixture.driver}');
        response = {
          'driver_id': fixture.driver,
          'state': availabilityState,
          'active_trip_id': activeTrip
        };
      } else if (path.endsWith('/trips')) {
        expect(request.uri.queryParameters['id'], 'eq.$trip');
        response = {
          'id': trip,
          'driver_id': assignedDriver,
          'status': status,
          'version': version,
          'payment_method': method
        };
      } else if (path.endsWith('/driver_transition_trip')) {
        bodies.add(body!);
        status = 'completed';
        version = 5;
        if (unknownRpc) {
          // Server may have committed; client receives no valid acknowledgement.
          request.response.statusCode = 503;
          response = {
            'code': 'unknown',
            'message': 'private transport failure'
          };
        } else {
          response = {'trip_id': trip, 'status': 'completed'};
        }
      } else if (path.endsWith('/user_trip_receipt_summary')) {
        if (missingReceipt) {
          request.response.statusCode = 404;
          response = {'code': 'P0002', 'message': 'private missing receipt'};
        } else {
          response = [
            {
              'id': 'e7000000-0000-0000-0000-000000000001',
              'trip_id': wrongReceipt ? fixture.other : trip,
              'receipt_number': 'R-CANONICAL'
            }
          ];
        }
      } else {
        request.response.statusCode = 500;
        response = {'message': 'unexpected endpoint'};
      }
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = fixture.LocalHttp(server.port);
    provenance = SupabaseInitializationProvenance();
    await provenance.initialize(fixture.environment);
    access = provenance.driverAccess(DriverBackendRegistry([
      DriverBackendIdentity(
          endpoint: Uri.parse(fixture.environment.url), namespace: namespace),
    ]))!;
    await Supabase.instance.client.auth
        .setInitialSession(jsonEncode(fixture.authResponse()));
    auth = AuthService(Supabase.instance.client);
    binding = auth.driverBinding(access);
  });

  tearDown(() async {
    for (final container in containers) {
      container.dispose();
    }
    containers.clear();
    await binding.dispose();
    await auth.dispose();
    await Supabase.instance.dispose();
    await server.close(force: true);
    HttpOverrides.global = previousHttp;
    SharedPreferencesAsyncPlatform.instance = previousPreferences;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    // Only the independently allocated test directory, verified by its literal prefix.
    expect(directory.absolute.path, contains('ridex-r01-r02-test-'));
    await directory.delete(recursive: true);
  });

  SupabaseDriverCompletionSource source() =>
      SupabaseDriverCompletionSource(access: access, authority: binding);

  ProviderContainer container(
      {bool approved = true,
      Future<DriverCompletionCommandStore> Function()? openStore}) {
    final c = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(DriverSession.new),
      supabaseClientProvider.overrideWithValue(Supabase.instance.client),
      supabaseInitializationProvenanceProvider.overrideWithValue(provenance),
      authServiceProvider.overrideWithValue(auth),
      if (approved)
        approvedDriverCompletionBackendsProvider
            .overrideWithValue(DriverBackendRegistry([access.backend])),
      driverCompletionStoreFactoryProvider
          .overrideWithValue(openStore ?? () async => store),
    ]);
    containers.add(c);
    c.listen(driverCashCompletionProvider, (_, __) {});
    return c;
  }

  test('source discovers canonical availability/Trip and retains exact intent',
      () async {
    final s = source();
    final first = (await s.load())!;
    expect(first.command.tripId, trip);
    expect(first.command.expectedTripVersion, 4);
    expect(first.driverId, fixture.driver);
    expect((await s.load())!.command, same(first.command));
    expect(requests.every((r) => r.$1 == 'GET'), isTrue);
    expect(bodies, isEmpty);
  });

  for (final scenario in [
    'foreign',
    'card',
    'not started',
    'unapproved',
    'blocked',
    'rider',
    'mock ID',
    'offline'
  ]) {
    test('$scenario context cannot stage or dispatch', () async {
      switch (scenario) {
        case 'foreign':
          assignedDriver = fixture.other;
        case 'card':
          method = 'card';
        case 'not started':
          status = 'accepted';
        case 'unapproved':
          approval = 'pending';
        case 'blocked':
          blocked = true;
        case 'rider':
          role = 'rider';
        case 'mock ID':
          activeTrip = 'trip-1';
        case 'offline':
          availabilityState = 'offline';
      }
      final controller = container().read(driverCashCompletionProvider)!;
      await controller.prepare();
      await controller.complete();
      expect(controller.state, isNot(DriverCashCompletionState.ready));
      expect(bodies, isEmpty);
      expect(
          await store.inspect(
              backendNamespace: namespace,
              driverId: fixture.driver,
              tripId: trip),
          isA<CompletionAbsent>());
    });
  }

  test('changed canonical version after ready is not bumped or dispatched',
      () async {
    final controller = container().read(driverCashCompletionProvider)!;
    await controller.prepare();
    version = 9;
    await controller.complete();
    expect(controller.state, DriverCashCompletionState.unresolved);
    expect(bodies, isEmpty);
  });

  test('namespace/capability mismatch fails before any backend read', () async {
    final otherAccess = provenance.driverAccess(DriverBackendRegistry([
      DriverBackendIdentity(
          endpoint: Uri.parse(fixture.environment.url),
          namespace: 'another-backend'),
    ]))!;
    final s =
        SupabaseDriverCompletionSource(access: otherAccess, authority: binding);
    await expectLater(s.load(), throwsA(isA<DriverCashContextException>()));
    expect(requests, isEmpty);
  });

  test('unapproved deployment registry disables composition and storage',
      () async {
    var opens = 0;
    expect(
        container(
            approved: false,
            openStore: () async {
              opens++;
              return store;
            }).read(driverCashCompletionProvider),
        isNull);
    expect(opens, 0);
    expect(requests, isEmpty);
  });

  for (final path in [
    '/users',
    '/driver_profiles',
    '/driver_availability',
    '/trips'
  ]) {
    test('application revocation during $path prevents context publication',
        () async {
      boundary = (p) async {
        if (p.endsWith(path)) auth.revokeSession();
      };
      final controller = container().read(driverCashCompletionProvider)!;
      await controller.prepare();
      await controller.complete();
      expect(controller.state, DriverCashCompletionState.authorizationLost);
      expect(bodies, isEmpty);
    });
  }

  test('SDK A-B-A during canonical discovery cannot revive original context',
      () async {
    boundary = (p) async {
      if (p.endsWith('/trips')) {
        await Supabase.instance.client.auth.setInitialSession(
            jsonEncode(fixture.authResponse(id: fixture.other)));
        await Supabase.instance.client.auth
            .setInitialSession(jsonEncode(fixture.authResponse()));
      }
    };
    final controller = container().read(driverCashCompletionProvider)!;
    await controller.prepare();
    await controller.complete();
    expect(controller.state, DriverCashCompletionState.authorizationLost);
    expect(bodies, isEmpty);
  });

  test(
      'concurrent taps dispatch one exact durably acknowledged canonical command',
      () async {
    final controller = container().read(driverCashCompletionProvider)!;
    await controller.prepare();
    await Future.wait([controller.complete(), controller.complete()]);
    expect(
        controller.state, DriverCashCompletionState.completedReceiptVerified);
    final stored = await store.inspect(
        backendNamespace: namespace,
        driverId: fixture.driver,
        tripId: trip) as CompletionValid;
    expect(bodies.single, {
      'target_id': stored.command.tripId,
      'requested_status': 'completed',
      'expected_version': 4,
      'idempotency_key': stored.command.idempotencyKey
    });
    expect(requests.any((r) => r.$2.contains('payments')), isFalse);
    await controller.complete();
    expect(bodies, hasLength(1));
  });

  for (final failure in ['directory', 'write']) {
    test('$failure storage failure prevents financial dispatch', () async {
      final controller = container(openStore: () async {
        if (failure == 'directory') {
          throw const FileSystemException('support unavailable');
        }
        return FileDriverCompletionCommandStore(
            directory: directory, io: FailingWrite());
      }).read(driverCashCompletionProvider)!;
      await controller.prepare();
      await controller.complete();
      expect(controller.state, DriverCashCompletionState.storageFailure);
      await controller.complete();
      expect(bodies, isEmpty);
    });
  }

  test('unknown outcome retains journal and never automatically retries',
      () async {
    unknownRpc = true;
    final c = container();
    final controller = c.read(driverCashCompletionProvider)!;
    await controller.prepare();
    await controller.complete();
    expect(controller.state, DriverCashCompletionState.unresolved);
    final stored = await store.inspect(
        backendNamespace: namespace, driverId: fixture.driver, tripId: trip);
    expect(stored, isA<CompletionValid>());
    await controller.complete();
    // A remounted screen cannot replay an existing command, even if backend
    // visibility is stale and still says inProgress.
    status = 'inProgress';
    version = 4;
    final second = container().read(driverCashCompletionProvider)!;
    await second.prepare();
    await second.complete();
    expect(second.state, DriverCashCompletionState.unresolved);
    expect(bodies, hasLength(1));
    expect(
        (await store.inspect(
                backendNamespace: namespace,
                driverId: fixture.driver,
                tripId: trip) as CompletionValid)
            .command,
        (stored as CompletionValid).command);
  });

  for (final kind in ['absent', 'wrong lineage']) {
    test('$kind receipt never reports verified issuance', () async {
      missingReceipt = kind == 'absent';
      wrongReceipt = kind == 'wrong lineage';
      final controller = container().read(driverCashCompletionProvider)!;
      await controller.prepare();
      await controller.complete();
      expect(controller.state,
          DriverCashCompletionState.completedReceiptUnverified);
      expect(bodies, hasLength(1));
    });
  }

  test(
      'revocation after RPC dispatch suppresses success and preserves evidence',
      () async {
    boundary = (p) async {
      if (p.endsWith('/driver_transition_trip')) auth.revokeSession();
    };
    final controller = container().read(driverCashCompletionProvider)!;
    await controller.prepare();
    await controller.complete();
    expect(controller.state, DriverCashCompletionState.authorizationLost);
    expect(bodies, hasLength(1));
    expect(
        await store.inspect(
            backendNamespace: namespace,
            driverId: fixture.driver,
            tripId: trip),
        isA<CompletionValid>());
  });

  test('network read failure is bounded and never authorizes staging',
      () async {
    failReads = true;
    final controller = container().read(driverCashCompletionProvider)!;
    await controller.prepare();
    expect(controller.state, DriverCashCompletionState.networkFailure);
    await controller.complete();
    expect(bodies, isEmpty);
  });

  test(
      'network loss after staging retains evidence without reporting authorization loss',
      () async {
    final controller = container(openStore: () async {
      failReads = true;
      return store;
    }).read(driverCashCompletionProvider)!;
    await controller.prepare();
    await controller.complete();
    expect(controller.state, DriverCashCompletionState.networkFailure);
    expect(bodies, isEmpty);
    expect(
        await store.inspect(
            backendNamespace: namespace,
            driverId: fixture.driver,
            tripId: trip),
        isA<CompletionValid>());
    await controller.complete();
    expect(bodies, isEmpty);
  });

  test('native journal uses plugin application support directory', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
      expect(call.method, 'getApplicationSupportDirectory');
      return directory.path;
    });
    final productionStore = await openApplicationCompletionStore();
    final command = DriverCompleteTripCommand(
        tripId: trip,
        expectedTripVersion: 4,
        idempotencyKey: 'storage-location-test');
    expect(
        await productionStore.stage(
            backendNamespace: namespace,
            driverId: fixture.driver,
            command: command),
        isA<CompletionCreated>());
    expect(
        await Directory.fromUri(
                directory.uri.resolve('driver_cash_completion/'))
            .exists(),
        isTrue);
  });

  test('UUID-shaped mock Trip never supplies missing canonical authority',
      () async {
    availabilityState = 'offline';
    final c = container();
    final mock = MockData.sampleTrip(status: TripStatus.inProgress);
    c.read(activeTripControllerProvider.notifier).setTrip(MockTrip(
        id: trip,
        booking: mock.booking,
        status: mock.status,
        driver: mock.driver,
        finalFare: mock.finalFare));
    final controller = c.read(driverCashCompletionProvider)!;
    await controller.prepare();
    await controller.complete();
    expect(controller.state, DriverCashCompletionState.unavailable);
    expect(bodies, isEmpty);
    expect(
        await store.inspect(
            backendNamespace: namespace,
            driverId: fixture.driver,
            tripId: trip),
        isA<CompletionAbsent>());
  });

  test('invalid journal namespace is rejected before opening storage',
      () async {
    var opened = false;
    final gateway = JournalDriverCompletionStagingGateway(
        backendNamespace: 'not/a/namespace',
        driverId: fixture.driver,
        openStore: () async {
          opened = true;
          return store;
        });
    final context = (await source().load())!;
    expect(await gateway.stage(context), isA<StagingBlocked>());
    expect(opened, isFalse);
    expect(bodies, isEmpty);
  });

  test('active Trip replacement during context read blocks staging', () async {
    var availabilityReads = 0;
    boundary = (p) async {
      if (p.endsWith('/driver_availability') && ++availabilityReads == 2) {
        activeTrip = fixture.other;
      }
    };
    final controller = container().read(driverCashCompletionProvider)!;
    await controller.prepare();
    expect(controller.state, DriverCashCompletionState.unresolved);
    await controller.complete();
    expect(bodies, isEmpty);
  });

  test(
      'new version during durable staging is rejected without rotating original evidence',
      () async {
    final controller = container(openStore: () async {
      version = 10;
      return store;
    }).read(driverCashCompletionProvider)!;
    await controller.prepare();
    await controller.complete();
    expect(controller.state, DriverCashCompletionState.unresolved);
    expect(bodies, isEmpty);
    final evidence = await store.inspect(
        backendNamespace: namespace,
        driverId: fixture.driver,
        tripId: trip) as CompletionValid;
    expect(evidence.command.expectedTripVersion, 4);
    await controller.complete();
    expect(bodies, isEmpty);
  });

  testWidgets('unconfigured canonical panel has no completion action',
      (tester) async {
    final c = container(approved: false);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
            home: Scaffold(body: DriverCashCompletionPanel()))));
    expect(
        find.text('Canonical Cash completion is unavailable.'), findsOneWidget);
    expect(find.text('Complete Cash trip'), findsNothing);
    expect(requests, isEmpty);
  });

  testWidgets(
      'canonical seam shows bounded ready, processing and verified receipt',
      (tester) async {
    final c = container();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
            home: Scaffold(body: DriverCashCompletionPanel()))));
    await tester.runAsync(() async {
      await c.read(driverCashCompletionProvider)!.prepare();
    });
    await tester.pump();
    expect(find.text('Ready to complete'), findsOneWidget);
    await tester.runAsync(() async {
      final pending = c.read(driverCashCompletionProvider)!.complete();
      expect(c.read(driverCashCompletionProvider)!.state,
          DriverCashCompletionState.processing);
      await pending;
    });
    await tester.pump();
    expect(find.text('Trip completed. Receipt verified.'), findsOneWidget);
    expect(find.text('Complete Cash trip'), findsNothing);
  });
}
