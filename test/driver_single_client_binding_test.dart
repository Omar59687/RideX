import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/errors/auth_exception.dart' as domain;
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
import 'package:ridex/core/repositories/supabase_auth_repository.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/profile_service.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_authority_foundation_test.dart' as fixture;
import 'helpers/sdk_disposal_socket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late Supabase sdk;
  late SupabaseClient original;
  late SupabaseInitializationProvenance provenance;
  late VerifiedSupabaseDriverAccess access;
  late SupabaseDriverAuthorityBinding binding;
  late DriverBackendIdentity backend;
  late DriverAuthorityLifecycle lifecycle;
  HttpOverrides? previousHttp;
  final requests = <(String, Uri, String?)>[];
  Completer<void>? entered;
  Completer<void>? gate;
  String gatedTable = 'users';
  int readStatus = 200;
  bool cleanupFails = false;
  String authId = fixture.driver;
  Completer<void>? authEntered;
  Completer<void>? authGate;
  int authStatus = 200;

  setUp(() async {
    requests.clear();
    entered = null;
    gate = null;
    gatedTable = 'users';
    readStatus = 200;
    cleanupFails = false;
    authId = fixture.driver;
    authEntered = null;
    authGate = null;
    authStatus = 200;
    lifecycle = const DriverAuthorityLifecycle(epoch: 50, isActive: true);
    SharedPreferences.setMockInitialValues({'evidence': 'preserved'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.app_links/events'),
            (_) async => null);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add((
        request.method,
        request.uri,
        request.headers.value('authorization')
      ));
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/auth/v1/token') {
        authEntered?.complete();
        await authGate?.future;
        request.response.statusCode = authStatus;
        request.response.write(jsonEncode(authStatus == 200
            ? fixture.authResponse(id: authId)
            : {
                'error': 'invalid_grant',
                'error_description': 'private-canary'
              }));
      } else if (request.uri.path == '/auth/v1/logout') {
        request.response.statusCode = 204;
      } else {
        if (request.uri.path == '/rest/v1/$gatedTable') {
          if (entered != null && !entered!.isCompleted) entered!.complete();
          await gate?.future;
        }
        request.response.statusCode = readStatus;
        request.response.write(jsonEncode(readStatus == 200
            ? (request.uri.path == '/rest/v1/users'
                ? fixture.user()
                : fixture.profile())
            : {'code': '42501', 'message': 'private backend detail'}));
      }
      await request.response.close();
    });
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = fixture.LocalHttp(server.port);
    provenance = SupabaseInitializationProvenance();
    await provenance.initialize(fixture.environment);
    sdk = Supabase.instance;
    original = sdk.client;
    original.auth.stopAutoRefresh();
    // Authentication belongs to the application, before binding construction.
    await AuthService(original)
        .signIn(email: 'fixture@unit-test.invalid', password: 'local-only');
    backend = fixture.backend();
    access = provenance.driverAccess(DriverBackendRegistry([backend]))!;
    binding = SupabaseDriverAuthorityBinding.create(
        access: access, lifecycleReader: () => lifecycle);
  });

  tearDown(() async {
    if (authGate != null && !authGate!.isCompleted) authGate!.complete();
    if (gate != null && !gate!.isCompleted) gate!.complete();
    await binding.dispose();
    // A failed real SDK cleanup remains failed and idempotent.
    if (cleanupFails) {
      await expectLater(sdk.dispose(), throwsStateError);
    } else {
      await sdk.dispose();
    }
    await server.close(force: true);
    HttpOverrides.global = previousHttp;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.app_links/events'), null);
  });

  Future<void> denied() async {
    fixture.failed(await DriverEligibilityRepository(binding).validate(),
        DriverEligibilityFailure.sessionInvalidated);
    await expectLater(
        binding.readUser(fixture.driver),
        throwsA(isA<DriverEligibilityReadException>().having((e) => e.failure,
            'failure', DriverEligibilityFailure.sessionInvalidated)));
  }

  test('borrows exact already authenticated singleton without auth or copying',
      () async {
    final session = original.auth.currentSession!;
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    expect(requests.map((r) => r.$2.path), ['/auth/v1/token']);
    requests.clear();
    final result =
        await DriverEligibilityRepository(binding).validate() as DriverEligible;
    expect(access.client, same(original));
    expect(sdk.client, same(original));
    expect(original.auth.currentSession, same(session));
    expect(result.owner.backend, same(backend));
    expect(result.owner.driverId, session.user.id);
    expect(requests.map((r) => (r.$1, r.$2.path)),
        [('GET', '/rest/v1/users'), ('GET', '/rest/v1/driver_profiles')]);
    expect(
        requests.every((r) => r.$3 == 'Bearer ${session.accessToken}'), isTrue);
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
  });

  test('unknown namespace and untrusted provenance cannot supply access',
      () async {
    expect(provenance.driverAccess(DriverBackendRegistry([])), isNull);
    final foreign = DriverBackendIdentity(
        endpoint: Uri.parse('https://foreign.unit-test.invalid'),
        namespace: backend.namespace);
    expect(provenance.driverAccess(DriverBackendRegistry([foreign])), isNull);
    final unverified = SupabaseInitializationProvenance();
    expect(unverified.driverAccess(DriverBackendRegistry([backend])), isNull);
    await unverified.initialize(fixture.environment);
    expect(unverified.snapshot.state, SupabaseProvenanceState.unverified);
    expect(unverified.driverAccess(DriverBackendRegistry([backend])), isNull);
    expect(access.client, same(original));
  });

  test('binding disposal immediately denies reads and preserves SDK session',
      () async {
    final session = original.auth.currentSession;
    requests.clear();
    final disposal = binding.dispose();
    expect(binding.currentOwner.isUsable, isFalse); // No await before checking.
    expect(original.isDisposingOrDisposed, isFalse);
    expect(sdk.disposalState.hasStarted, isFalse);
    expect(original.auth.currentSession, same(session));
    await disposal;
    await binding.dispose();
    await denied();
    expect(requests, isEmpty);
    final another = SupabaseDriverAuthorityBinding.create(
        access: access, lifecycleReader: () => lifecycle);
    try {
      expect(await DriverEligibilityRepository(another).validate(),
          isA<DriverEligible>());
      expect(original.auth.currentSession, same(session));
    } finally {
      await another.dispose();
    }
  });

  test('wrong Driver identity is rejected before I/O', () async {
    requests.clear();
    await expectLater(binding.readUser(fixture.other),
        throwsA(isA<DriverEligibilityReadException>()));
    await expectLater(binding.readDriverProfile(fixture.other),
        throwsA(isA<DriverEligibilityReadException>()));
    expect(requests, isEmpty);
  });

  test(
      'replacement permanently invalidates retained binding and factory access',
      () async {
    final replacement = SupabaseClient('https://foreign.unit-test.invalid',
        fixture.environment.publishableKey);
    requests.clear();
    try {
      sdk.client = replacement;
      await denied();
      sdk.client = original;
      await denied();
      expect(access.client, isNull);
      expect(
          () => SupabaseDriverAuthorityBinding.create(
              access: access, lifecycleReader: () => lifecycle),
          throwsA(isA<DriverBindingException>().having((e) => e.failure,
              'failure', DriverBindingFailure.untrustedAccess)));
      expect(requests, isEmpty);
    } finally {
      sdk.client = original;
      await replacement.dispose();
    }
  });

  for (final wrapper in [false, true]) {
    for (final fails in [false, true]) {
      test('SDK disposal denies before cleanup: wrapper=$wrapper fails=$fails',
          () async {
        final socket = DisposalSocket()..attach(original);
        requests.clear();
        final disposal = wrapper ? sdk.dispose() : original.dispose();
        final assertion = fails
            ? expectLater(disposal, throwsStateError)
            : expectLater(disposal, completes);
        cleanupFails = fails;
        expect(binding.currentOwner.isUsable, isFalse);
        await denied();
        expect(requests, isEmpty);
        await socket.entered.future;
        if (fails) {
          socket.gate.completeError(StateError('local cleanup fixture'));
        } else {
          socket.gate.complete();
        }
        await assertion;
        await denied();
        expect(access.client, isNull);
        expect(
            () => SupabaseDriverAuthorityBinding.create(
                access: access, lifecycleReader: () => lifecycle),
            throwsA(isA<DriverBindingException>()));
      });
    }
  }

  for (final table in ['users', 'driver_profiles']) {
    for (final fails in [false, true]) {
      for (final invalidation in [
        'binding',
        'client',
        'wrapper',
        'replacement',
        'identity',
        'signedOut',
        'lifecycle'
      ]) {
        test('late $table fails=$fails after $invalidation is invalidated',
            () async {
          gatedTable = table;
          entered = Completer<void>();
          gate = Completer<void>();
          requests.clear();
          final pending = DriverEligibilityRepository(binding).validate();
          await entered!.future;
          Future<void>? cleanup;
          SupabaseClient? replacement;
          switch (invalidation) {
            case 'binding':
              cleanup = binding.dispose();
            case 'client':
              cleanup = original.dispose();
            case 'wrapper':
              cleanup = sdk.dispose();
            case 'replacement':
              replacement = SupabaseClient('https://foreign.unit-test.invalid',
                  fixture.environment.publishableKey);
              sdk.client = replacement;
              // Observe the replacement, then restore A: trust stays revoked.
              expect(binding.currentOwner.isUsable, isFalse);
              sdk.client = original;
            case 'identity':
              authId = fixture.other;
              await AuthService(original).signIn(
                  email: 'other@unit-test.invalid', password: 'local-only');
            case 'signedOut':
              await AuthService(original).signOut();
            case 'lifecycle':
              lifecycle =
                  const DriverAuthorityLifecycle(epoch: 51, isActive: false);
          }
          try {
            if (fails) readStatus = 403;
            gate!.complete();
            fixture.failed(
                await pending, DriverEligibilityFailure.sessionInvalidated);
            await cleanup;
            expect(requests.where((r) => r.$2.path.startsWith('/rest/v1/')),
                hasLength(table == 'users' ? 1 : 2));
          } finally {
            sdk.client = original;
            await replacement?.dispose();
          }
        });
      }
    }
  }

  group('B1-B application-owned epoch', () {
    late AuthService service;
    setUp(() async {
      await binding.dispose();
      service = AuthService(original);
      binding = service.driverBinding(access);
    });

    test('unknown authentication details never enter domain/UI errors',
        () async {
      authStatus = 400;
      final repository = SupabaseAuthRepository(
          authService: service, profileService: ProfileService(original));
      await expectLater(
          repository.signIn(
              email: 'fixture@unit-test.invalid', password: 'local-only'),
          throwsA(isA<domain.AuthException>().having(
              (error) => error.message,
              'sanitized message',
              'Authentication is unavailable. Please try again.')));
      expect(binding.currentOwner.isUsable, isFalse);
    });

    test('overlapping SDK login fails closed, then explicit retry succeeds',
        () async {
      authEntered = Completer<void>();
      authGate = Completer<void>();
      final first = service.signIn(
          email: 'fixture@unit-test.invalid', password: 'local-only');
      final rejected = expectLater(first, throwsA(isA<AuthException>()));
      await authEntered!.future;
      await expectLater(
          service.signIn(
              email: 'other@unit-test.invalid', password: 'local-only'),
          throwsA(isA<AuthException>()));
      expect(binding.currentOwner.isUsable, isFalse);
      authGate!.complete();
      await rejected;
      expect(original.auth.currentSession, isNull);
      authEntered = null;
      authGate = null;
      await service.signIn(
          email: 'fixture@unit-test.invalid', password: 'local-only');
      expect(await DriverEligibilityRepository(binding).validate(),
          isA<DriverEligible>());
    });

    for (final fails in [false, true]) {
      test('logout rejects late SDK authentication fails=$fails', () async {
        authEntered = Completer<void>();
        authGate = Completer<void>();
        final login = service.signIn(
            email: 'fixture@unit-test.invalid', password: 'local-only');
        final rejected = expectLater(login, throwsA(isA<AuthException>()));
        await authEntered!.future;
        await service.signOut();
        expect(binding.currentOwner.isUsable, isFalse);
        if (fails) authStatus = 400;
        authGate!.complete();
        await rejected;
        await Future<void>.delayed(Duration.zero);
        expect(original.auth.currentSession, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('sb-authority-auth-token'), isFalse);
        await denied();
      });
    }

    test(
        'startup accepts restored SDK session once, wrapper recreation cannot restore logout',
        () async {
      final restoredClient = SupabaseClient(
          fixture.environment.url, fixture.environment.publishableKey);
      try {
        await restoredClient.auth.signInWithPassword(
            email: 'fixture@unit-test.invalid', password: 'local-only');
        final restored = AuthService(restoredClient);
        expect(restored.driverLifecycle.isActive, isTrue);
        restored.revokeSession();
        expect(AuthService(restoredClient).driverLifecycle.isActive, isFalse);
        await restored.dispose();
        final before = requests.length;
        await expectLater(
            restored.signIn(
                email: 'fixture@unit-test.invalid', password: 'local-only'),
            throwsA(isA<AuthException>()));
        expect(requests.length, before);
      } finally {
        await restoredClient.dispose();
      }
    });

    for (final logout in [false, true]) {
      test('delayed expired SDK startup restoration logout=$logout', () async {
        final restoredClient = SupabaseClient(
            fixture.environment.url, fixture.environment.publishableKey);
        try {
          await restoredClient.auth.setInitialSession(
              jsonEncode(fixture.authResponse(expired: true)));
          final restored = AuthService(restoredClient);
          expect(restored.driverLifecycle.isActive, isFalse);
          authEntered = Completer<void>();
          authGate = Completer<void>();
          final refresh = restoredClient.auth.refreshSession();
          await authEntered!.future;
          if (logout) await restored.signOut();
          authGate!.complete();
          await refresh;
          await Future<void>.delayed(Duration.zero);
          expect(restored.driverLifecycle.isActive, !logout);
          if (logout) expect(restoredClient.auth.currentSession, isNull);
          await restored.dispose();
        } finally {
          await restoredClient.dispose();
        }
      });
    }

    test('wrappers share one owner; refresh preserves legitimate ownership',
        () async {
      expect(AuthService(original), same(service));
      final epoch = binding.currentOwner.epoch;
      expect(await DriverEligibilityRepository(binding).validate(),
          isA<DriverEligible>());
      await original.auth.refreshSession();
      await Future<void>.delayed(Duration.zero);
      expect(binding.currentOwner.epoch, epoch);
      expect(await DriverEligibilityRepository(binding).validate(),
          isA<DriverEligible>());
    });

    test('expiry during owned SDK refresh suspends, then renews a fresh epoch',
        () async {
      final before = binding.currentOwner;
      await original.auth
          .setInitialSession(jsonEncode(fixture.authResponse(expired: true)));
      expect(binding.currentOwner.isUsable, isFalse);
      expect(binding.currentOwner.epoch, greaterThan(before.epoch));
      authEntered = Completer<void>();
      authGate = Completer<void>();
      final refresh = original.auth.refreshSession();
      await authEntered!.future;
      expect(binding.currentOwner.isUsable, isFalse);
      authGate!.complete();
      await refresh;
      await Future<void>.delayed(Duration.zero);
      expect(binding.currentOwner.isUsable, isTrue);
      expect(before.sameOwner(binding.currentOwner), isFalse);
      expect(await DriverEligibilityRepository(binding).validate(),
          isA<DriverEligible>());
    });

    test('synchronous logout and repeated logout cannot be undone by refresh',
        () async {
      final old = binding.currentOwner;
      final first = service.signOut();
      expect(binding.currentOwner.isUsable, isFalse);
      final second = service.signOut();
      expect(second, same(first));
      expect(binding.currentOwner.epoch, greaterThan(old.epoch));
      await first;
      await second;
      await denied();
    });

    test('same account reauthentication owns a fresh epoch', () async {
      final old = binding.currentOwner;
      final login = service.signIn(
          email: 'fixture@unit-test.invalid', password: 'local-only');
      expect(binding.currentOwner.isUsable, isFalse);
      await login;
      final fresh = binding.currentOwner;
      expect(fresh.driverId, old.driverId);
      expect(fresh.epoch, greaterThan(old.epoch));
      expect(old.sameOwner(fresh), isFalse);
      expect(await DriverEligibilityRepository(binding).validate(),
          isA<DriverEligible>());
    });

    test('binding rejects another client even for the same configured endpoint',
        () async {
      final foreign = SupabaseClient(
          fixture.environment.url, fixture.environment.publishableKey);
      try {
        expect(() => AuthService(foreign).driverBinding(access),
            throwsA(isA<DriverBindingException>()));
      } finally {
        await foreign.dispose();
      }
    });

    for (final table in ['users', 'driver_profiles']) {
      for (final fails in [false, true]) {
        for (final invalidation in [
          'logout',
          'reauthenticate',
          'switch',
          'dispose',
          'client',
          'provenance'
        ]) {
          test(
              'late $table fails=$fails after $invalidation cannot restore authority',
              () async {
            gatedTable = table;
            entered = Completer<void>();
            gate = Completer<void>();
            final before = binding.currentOwner;
            final pending = DriverEligibilityRepository(binding).validate();
            await entered!.future;
            switch (invalidation) {
              case 'logout':
                final logout = service.signOut();
                expect(binding.currentOwner.isUsable, isFalse);
                await logout;
              case 'reauthenticate':
                final login = service.signIn(
                    email: 'fixture@unit-test.invalid', password: 'local-only');
                expect(binding.currentOwner.isUsable, isFalse);
                await login;
              case 'switch':
                authId = fixture.other;
                final login = service.signIn(
                    email: 'other@unit-test.invalid', password: 'local-only');
                expect(binding.currentOwner.isUsable, isFalse);
                await login;
              case 'dispose':
                final disposal = service.dispose();
                expect(binding.currentOwner.isUsable, isFalse);
                await disposal;
                await service.dispose();
              case 'client':
                final disposal = original.dispose();
                expect(binding.currentOwner.isUsable, isFalse);
                await disposal;
              case 'provenance':
                await provenance.initialize(fixture.environment);
                expect(binding.currentOwner.isUsable, isFalse);
            }
            expect(before.sameOwner(binding.currentOwner), isFalse);
            if (fails) readStatus = 403;
            gate!.complete();
            fixture.failed(
                await pending, DriverEligibilityFailure.sessionInvalidated);
            if (invalidation != 'reauthenticate' && invalidation != 'switch') {
              await denied();
            }
          });
        }
      }
    }
  });
}
