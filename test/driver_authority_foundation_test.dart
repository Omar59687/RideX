import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const driver = 'a7000000-0000-0000-0000-000000000001';
const other = 'a7000000-0000-0000-0000-000000000002';
const environment = SupabaseEnvironment(
  url: 'https://authority.unit-test.invalid',
  publishableKey: 'sb_publishable_local_fixture_000000000000',
);

DriverBackendIdentity backend([String namespace = 'driver-authority-test']) =>
    DriverBackendIdentity(
        endpoint: Uri.parse(environment.url), namespace: namespace);

Map<String, Object?> user() =>
    {'id': driver, 'role': 'driver', 'is_blocked': false};
Map<String, Object?> profile() =>
    {'user_id': driver, 'approval_status': 'approved'};

class Transport implements DriverEligibilityTransport {
  Transport() : identity = backend();
  final DriverBackendIdentity identity;
  String? id = driver;
  int epoch = 7;
  bool valid = true;
  Map<String, Object?>? userRow = user();
  Map<String, Object?>? profileRow = profile();
  Future<void> Function(String)? boundary;
  final reads = <String>[];

  @override
  DriverAuthorityOwner get currentOwner => DriverAuthorityOwner(
      driverId: id, backend: identity, epoch: epoch, hasValidSession: valid);
  @override
  Future<Map<String, Object?>?> readUser(String driverId) async {
    reads.add('users:$driverId');
    await boundary?.call('user');
    return userRow;
  }

  @override
  Future<Map<String, Object?>?> readDriverProfile(String driverId) async {
    reads.add('driver_profiles:$driverId');
    await boundary?.call('profile');
    return profileRow;
  }
}

void failed(
    DriverEligibilityOutcome outcome, DriverEligibilityFailure expected) {
  expect(outcome, isA<DriverIneligible>());
  expect((outcome as DriverIneligible).failure, expected);
}

/// Routes SDK HTTP to a loopback server, preserving the SDK's original URL for
/// assertions. Any unexpected host fails instead of reaching a hosted service.
class LocalHttp extends HttpOverrides {
  LocalHttp(this.port);
  final int port;
  final requests = <(String, Uri)>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      RedirectClient(super.createHttpClient(context), port, requests);
}

class RedirectClient implements HttpClient {
  RedirectClient(this.delegate, this.port, this.requests);
  final HttpClient delegate;
  final int port;
  final List<(String, Uri)> requests;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (url.origin != environment.url) {
      throw StateError('Hosted HTTP forbidden');
    }
    requests.add((method, url));
    return delegate.openUrl(
        method, url.replace(scheme: 'http', host: '127.0.0.1', port: port));
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class PreferencesGuard extends InMemorySharedPreferencesAsync {
  PreferencesGuard() : super.empty();
  int mutations = 0;
  @override
  Future<bool> setString(
      String key, String value, SharedPreferencesOptions options) async {
    mutations++;
    throw StateError('Preferences writes forbidden');
  }

  @override
  Future<bool> setBool(
      String key, bool value, SharedPreferencesOptions options) async {
    mutations++;
    throw StateError('Preferences writes forbidden');
  }

  @override
  Future<bool> setInt(
      String key, int value, SharedPreferencesOptions options) async {
    mutations++;
    throw StateError('Preferences writes forbidden');
  }

  @override
  Future<bool> setDouble(
      String key, double value, SharedPreferencesOptions options) async {
    mutations++;
    throw StateError('Preferences writes forbidden');
  }

  @override
  Future<bool> setStringList(
      String key, List<String> value, SharedPreferencesOptions options) async {
    mutations++;
    throw StateError('Preferences writes forbidden');
  }

  @override
  Future<bool> clear(ClearPreferencesParameters parameters,
      SharedPreferencesOptions options) async {
    mutations++;
    throw StateError('Preferences clearing forbidden');
  }
}

Map<String, Object?> authResponse({String id = driver, bool expired = false}) {
  final expires =
      DateTime.now().millisecondsSinceEpoch ~/ 1000 + (expired ? -600 : 3600);
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': id, 'exp': expires})))
      .replaceAll('=', '');
  return {
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.local-test-signature',
    'refresh_token': 'local-fixture-refresh',
    'expires_in': expired ? -600 : 3600,
    'expires_at': expires,
    'token_type': 'bearer',
    'user': {
      'id': id,
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{}
    },
  };
}

void main() {
  group('strict eligibility contract', () {
    late Transport transport;
    late DriverEligibilityRepository repository;
    setUp(() {
      transport = Transport();
      repository = DriverEligibilityRepository(transport);
    });

    test('approved Driver returns captured SDK owner, never a created epoch',
        () async {
      final result = await repository.validate() as DriverEligible;
      expect(result.owner.driverId, driver);
      expect(result.owner.epoch, 7);
      expect(transport.reads, ['users:$driver', 'driver_profiles:$driver']);
    });
    for (final entry in <String, void Function(Transport)>{
      'signed out': (t) => t.id = null,
      'expired': (t) => t.valid = false,
      'invalid UUID': (t) => t.id = 'mock-driver',
      'invalid epoch': (t) => t.epoch = -1,
    }.entries) {
      test('${entry.key} prevents profile I/O', () async {
        entry.value(transport);
        failed(await repository.validate(),
            DriverEligibilityFailure.sessionInvalidated);
        expect(transport.reads, isEmpty);
      });
    }
    for (final role in ['rider', 'admin', 'Driver', 'owner', null, 1]) {
      test('role $role cannot grant Driver eligibility', () async {
        transport.userRow!['role'] = role;
        failed(
            await repository.validate(),
            role == 'rider' || role == 'admin'
                ? DriverEligibilityFailure.notDriver
                : DriverEligibilityFailure.malformedProfile);
        expect(transport.reads, hasLength(1));
      });
    }
    for (final block in [true, null, 'false', 0]) {
      test('block value $block fails closed', () async {
        transport.userRow!['is_blocked'] = block;
        failed(
            await repository.validate(),
            block == true
                ? DriverEligibilityFailure.blocked
                : DriverEligibilityFailure.malformedProfile);
        expect(transport.reads, hasLength(1));
      });
    }
    test('missing block field is not false', () async {
      transport.userRow!.remove('is_blocked');
      failed(await repository.validate(),
          DriverEligibilityFailure.malformedProfile);
    });
    for (final approval in ['pending', 'rejected', 'Approved', null, true]) {
      test('approval $approval fails closed', () async {
        transport.profileRow!['approval_status'] = approval;
        failed(
            await repository.validate(),
            approval == 'pending' || approval == 'rejected'
                ? DriverEligibilityFailure.notApproved
                : DriverEligibilityFailure.malformedProfile);
      });
    }
    for (final table in ['user', 'profile']) {
      test('missing $table profile stays ineligible', () async {
        if (table == 'user') {
          transport.userRow = null;
        } else {
          transport.profileRow = null;
        }
        failed(await repository.validate(),
            DriverEligibilityFailure.profileMissing);
      });
      for (final identity in [other, null, 'mock', 10]) {
        test('$table identity $identity fails closed', () async {
          if (table == 'user') {
            transport.userRow!['id'] = identity;
          } else {
            transport.profileRow!['user_id'] = identity;
          }
          failed(
              await repository.validate(),
              identity == other
                  ? DriverEligibilityFailure.foreignIdentity
                  : DriverEligibilityFailure.malformedProfile);
        });
      }
      for (final change in ['account', 'A-B-A', 'inactive', 'epoch']) {
        for (final throws in [false, true]) {
          test(
              '$change during $table ${throws ? 'error' : 'success'} invalidates',
              () async {
            transport.boundary = (boundary) async {
              if (boundary != table) return;
              if (change == 'account') transport.id = other;
              if (change == 'A-B-A') {
                transport.id = other;
                transport.epoch++;
                transport.id = driver;
              }
              if (change == 'inactive') transport.valid = false;
              if (change == 'epoch') transport.epoch++;
              if (throws) throw StateError('untrusted raw details');
            };
            failed(await repository.validate(),
                DriverEligibilityFailure.sessionInvalidated);
          });
        }
      }
    }
    for (final failure in [
      DriverEligibilityFailure.authorizationDenied,
      DriverEligibilityFailure.transportUnavailable
    ]) {
      test('typed $failure is preserved without raw error', () async {
        transport.boundary =
            (_) async => throw DriverEligibilityReadException(failure);
        failed(await repository.validate(), failure);
      });
    }
    test('unexpected error fails closed', () async {
      transport.boundary = (_) async => throw StateError('secret');
      failed(await repository.validate(),
          DriverEligibilityFailure.transportUnavailable);
    });
  });

  group('backend registry', () {
    test('unknown endpoint and namespace/client mismatch cannot resolve', () {
      final registry = DriverBackendRegistry([backend()]);
      expect(registry.resolve(Uri.parse('https://other.unit-test.invalid')),
          isNull);
    });
    for (final namespace in ['', '../prod', 'a' * 65, ' key', 'a/b']) {
      test('invalid namespace $namespace is rejected', () {
        expect(() => backend(namespace), throwsArgumentError);
      });
    }
    test('duplicate namespace across endpoints is rejected', () {
      expect(
          () => DriverBackendRegistry([
                backend(),
                DriverBackendIdentity(
                    endpoint: Uri.parse('https://other.unit-test.invalid'),
                    namespace: backend().namespace)
              ]),
          throwsArgumentError);
    });
    test('duplicate endpoint under another namespace is rejected', () {
      expect(() => DriverBackendRegistry([backend(), backend('other')]),
          throwsArgumentError);
    });
    for (final key in [
      'sb_secret_do_not_use_000000000000',
      '',
      'service_role_00000000000000'
    ]) {
      test('invalid or privileged configuration fails before client creation',
          () {
        expect(
            () => SupabaseDriverAuthorityBinding.create(
                environment: SupabaseEnvironment(
                    url: environment.url, publishableKey: key),
                approvedBackends: DriverBackendRegistry([backend()]),
                lifecycleReader: () => throw StateError('must not be read')),
            throwsA(isA<DriverBindingException>().having((e) => e.failure,
                'failure', DriverBindingFailure.invalidConfiguration)));
      });
    }
    test('valid but unapproved environment fails before client creation', () {
      expect(
          () => SupabaseDriverAuthorityBinding.create(
              environment: environment,
              approvedBackends: DriverBackendRegistry([]),
              lifecycleReader: () => throw StateError('unused')),
          throwsA(isA<DriverBindingException>().having((e) => e.failure,
              'failure', DriverBindingFailure.unknownBackend)));
    });
    test('configuration for another client endpoint cannot use this namespace',
        () {
      expect(
          () => SupabaseDriverAuthorityBinding.create(
              environment: SupabaseEnvironment(
                  url: 'https://foreign.unit-test.invalid',
                  publishableKey: environment.publishableKey),
              approvedBackends: DriverBackendRegistry([backend()]),
              lifecycleReader: () => throw StateError('unused')),
          throwsA(isA<DriverBindingException>().having((e) => e.failure,
              'failure', DriverBindingFailure.unknownBackend)));
    });
  });

  group('actual SDK binding through loopback HTTP', () {
    late HttpServer server;
    late LocalHttp http;
    HttpOverrides? previousHttp;
    late SupabaseDriverAuthorityBinding binding;
    late DriverAuthorityLifecycle lifecycle;
    late PreferencesGuard preferences;
    late SharedPreferencesAsyncPlatform? previousPreferences;
    late Directory evidenceDirectory;
    late File journal;
    final requests = <(String, Uri, String?)>[];
    Map<String, Object?>? userRow;
    Map<String, Object?>? profileRow;
    bool expired = false;
    int profileStatus = 200;
    Completer<void>? readGate;
    Completer<void>? readEntered;

    setUp(() async {
      requests.clear();
      userRow = user();
      profileRow = profile();
      profileStatus = 200;
      expired = false;
      readGate = null;
      readEntered = null;
      lifecycle = const DriverAuthorityLifecycle(epoch: 40, isActive: true);
      preferences = PreferencesGuard();
      previousPreferences = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance = preferences;
      evidenceDirectory =
          await Directory.systemTemp.createTemp('ridex-authority-');
      journal = File('${evidenceDirectory.path}/commands.rxcj');
      await journal.writeAsString('unchanged journal evidence');
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
          request.response.write(jsonEncode(authResponse(expired: expired)));
        } else if (request.uri.path == '/auth/v1/logout') {
          request.response.statusCode = 204;
        } else {
          if (readEntered != null && !readEntered!.isCompleted) {
            readEntered!.complete();
          }
          await readGate?.future;
          request.response.statusCode = profileStatus;
          request.response.write(jsonEncode(profileStatus == 200
              ? (request.uri.path == '/rest/v1/users' ? userRow : profileRow)
              : {
                  'code': '42501',
                  'message': 'not exposed',
                  'details': '',
                  'hint': ''
                }));
        }
        await request.response.close();
      });
      http = LocalHttp(server.port);
      previousHttp = HttpOverrides.current;
      HttpOverrides.global = http;
      binding = HttpOverrides.runWithHttpOverrides(
          () => SupabaseDriverAuthorityBinding.create(
              environment: environment,
              approvedBackends: DriverBackendRegistry([backend()]),
              lifecycleReader: () => lifecycle),
          http);
    });
    tearDown(() async {
      expect(preferences.mutations, 0);
      expect(await journal.readAsString(), 'unchanged journal evidence');
      expect(await evidenceDirectory.list().length, 1);
      await binding.dispose();
      await server.close(force: true);
      HttpOverrides.global = previousHttp;
      SharedPreferencesAsyncPlatform.instance = previousPreferences;
      await evidenceDirectory.delete(recursive: true);
    });
    Future<void> login() async {
      await binding.authService
          .signIn(email: 'fixture@unit-test.invalid', password: 'local-only');
      requests.clear();
      http.requests.clear();
    }

    test('signed-out actual SDK cannot read, despite active lifecycle',
        () async {
      failed(await DriverEligibilityRepository(binding).validate(),
          DriverEligibilityFailure.sessionInvalidated);
      expect(requests, isEmpty);
    });
    test('approved Driver reads only authenticated identity-filtered profiles',
        () async {
      await login();
      final outcome = await DriverEligibilityRepository(binding).validate()
          as DriverEligible;
      expect(outcome.owner.epoch, 40);
      expect(outcome.owner.backend, same(binding.backend));
      expect(requests.map((r) => (r.$1, r.$2.path)).toList(),
          [('GET', '/rest/v1/users'), ('GET', '/rest/v1/driver_profiles')]);
      expect(requests[0].$2.queryParameters,
          {'select': 'id,role,is_blocked', 'id': 'eq.$driver'});
      expect(requests[1].$2.queryParameters,
          {'select': 'user_id,approval_status', 'user_id': 'eq.$driver'});
      expect(requests.every((r) => r.$3?.startsWith('Bearer eyJ') == true),
          isTrue);
      expect(
          http.requests.every((r) => r.$2.origin == environment.url), isTrue);
    });
    test('expired actual SDK session prevents profile I/O', () async {
      expired = true;
      await login();
      failed(await DriverEligibilityRepository(binding).validate(),
          DriverEligibilityFailure.sessionInvalidated);
      expect(requests, isEmpty);
    });
    test('caller cannot query another Driver through binding', () async {
      await login();
      await expectLater(binding.readUser(other),
          throwsA(isA<DriverEligibilityReadException>()));
      expect(requests, isEmpty);
    });
    test('SDK profile denial stays typed and exposes no raw backend message',
        () async {
      await login();
      profileStatus = 403;
      failed(await DriverEligibilityRepository(binding).validate(),
          DriverEligibilityFailure.authorizationDenied);
    });
    test('late actual SDK read after injected A-B-A is discarded', () async {
      await login();
      readGate = Completer<void>();
      readEntered = Completer<void>();
      final result = DriverEligibilityRepository(binding).validate();
      await readEntered!.future;
      lifecycle = const DriverAuthorityLifecycle(epoch: 42, isActive: true);
      readGate!.complete();
      failed(await result, DriverEligibilityFailure.sessionInvalidated);
      expect(requests, hasLength(1));
    });
    test('typed auth events preserve order and legacy void notifications',
        () async {
      final typed = <DriverAuthEvent>[];
      var legacy = 0;
      final service = binding.authService;
      final typedSub = service.driverAuthEvents().listen(typed.add);
      final legacySub = service.authStateChanges().listen((_) => legacy++);
      final signedIn = service
          .driverAuthEvents()
          .firstWhere((e) => e.kind == DriverAuthEventKind.signedIn);
      await service.signIn(
          email: 'fixture@unit-test.invalid', password: 'local-only');
      expect((await signedIn).userId, driver);
      final signedOut = service
          .driverAuthEvents()
          .firstWhere((e) => e.kind == DriverAuthEventKind.signedOut);
      await service.signOut();
      await signedOut;
      expect(
          typed
              .where((e) => e.kind != DriverAuthEventKind.initialSession)
              .map((e) => e.kind),
          [DriverAuthEventKind.signedIn, DriverAuthEventKind.signedOut]);
      expect(legacy, typed.length);
      expect(typed.last.userId, isNull);
      await typedSub.cancel();
      await legacySub.cancel();
    });
    test('disposed binding cannot grant eligibility or issue reads', () async {
      await login();
      await binding.dispose();
      failed(await DriverEligibilityRepository(binding).validate(),
          DriverEligibilityFailure.sessionInvalidated);
      expect(requests, isEmpty);
    });
    test('actual SDK refresh remains typed and ordered for both event APIs',
        () async {
      final client = SupabaseClient(environment.url, environment.publishableKey,
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      final service = AuthService(client);
      final events = <DriverAuthEvent>[];
      var legacy = 0;
      final subscription = service.driverAuthEvents().listen(events.add);
      final oldSubscription =
          service.authStateChanges().listen((_) => legacy++);
      try {
        final signedIn = service
            .driverAuthEvents()
            .firstWhere((e) => e.kind == DriverAuthEventKind.signedIn);
        await service.signIn(
            email: 'local@unit-test.invalid', password: 'fixture');
        await signedIn;
        final refreshed = service
            .driverAuthEvents()
            .firstWhere((e) => e.kind == DriverAuthEventKind.tokenRefreshed);
        await client.auth.refreshSession();
        expect((await refreshed).userId, driver);
        expect(
            events
                .where((e) => e.kind != DriverAuthEventKind.initialSession)
                .map((e) => e.kind),
            [DriverAuthEventKind.signedIn, DriverAuthEventKind.tokenRefreshed]);
        expect(legacy, events.length);
      } finally {
        await subscription.cancel();
        await oldSubscription.cancel();
        await client.dispose();
      }
    });
  });
}
