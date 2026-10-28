import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/app.dart';
import 'package:ridex/app/bootstrap.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/sdk_disposal_socket.dart';

const fixtureEnvironment = SupabaseEnvironment(
  url: 'https://provenance.unit-test.invalid',
  publishableKey: 'sb_publishable_local_provenance_fixture_000000000',
);
const foreignEnvironment = SupabaseEnvironment(
  url: 'https://foreign.unit-test.invalid',
  publishableKey: 'sb_publishable_other_provenance_fixture_000000000',
);

DriverBackendRegistry approvedRegistry() => DriverBackendRegistry([
      DriverBackendIdentity(
          endpoint: Uri.parse(fixtureEnvironment.url),
          namespace: 'ridex-provenance-fixture'),
    ]);

class ForbidNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      BlockedHttpClient(this);
}

class BlockedHttpClient implements HttpClient {
  BlockedHttpClient(this.guard);
  final ForbidNetwork guard;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    guard.attempts++;
    throw StateError('Hosted operations forbidden in provenance tests.');
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GatedPreferences extends InMemorySharedPreferencesStore {
  GatedPreferences() : super.empty();
  final entered = Completer<void>();
  final gate = Completer<void>();
  bool fail = false;
  @override
  Future<Map<String, Object>> getAll() async {
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    if (fail) throw StateError('local initialization failure fixture');
    return super.getAll();
  }
}

/// Test-only wrapper cleanup after its real client has already been disposed.
/// No SDK client is constructed, authenticated, or admitted to provenance.
class AlreadyDisposedClientCleanup implements SupabaseClient {
  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Supabase? currentSdk() {
  try {
    final sdk = Supabase.instance;
    return sdk.isInitialized ? sdk : null;
  } on AssertionError {
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseInitializationProvenance provenance;
  late ForbidNetwork network;
  HttpOverrides? previousHttp;
  SharedPreferencesAsyncPlatform? previousAsyncPreferences;

  setUp(() {
    expect(currentSdk(), isNull);
    provenance = SupabaseInitializationProvenance();
    previousAsyncPreferences = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({'existing-evidence': 'preserved'});
    previousHttp = HttpOverrides.current;
    network = ForbidNetwork();
    HttpOverrides.global = network;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.app_links/events'),
            (_) async => null);
  });
  tearDown(() async {
    await currentSdk()?.dispose();
    HttpOverrides.global = previousHttp;
    SharedPreferencesAsyncPlatform.instance = previousAsyncPreferences;
    expect(network.attempts, 0);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.app_links/events'), null);
  });

  test('real first SDK initialization captures exact application client',
      () async {
    expect(provenance.snapshot.state, SupabaseProvenanceState.notStarted);
    final initialization = provenance.initialize(fixtureEnvironment);
    final original = currentSdk()!.client;
    expect(provenance.snapshot.state, SupabaseProvenanceState.initializing);
    expect(provenance.driverAccess(approvedRegistry()), isNull);
    await initialization;
    expect(provenance.snapshot.state, SupabaseProvenanceState.trusted);
    expect(provenance.snapshot.endpoint, Uri.parse(fixtureEnvironment.url));
    final access = provenance.driverAccess(approvedRegistry())!;
    expect(access.client, same(original));
    expect(currentSdk()!.client, same(original));
    expect(access.backend.namespace, 'ridex-provenance-fixture');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'existing-evidence'});
    expect(prefs.getString('existing-evidence'), 'preserved');
  });

  test('missing backend configuration preserves demo and creates no client',
      () async {
    await provenance.initialize(null);
    expect(provenance.snapshot.state, SupabaseProvenanceState.demo);
    expect(provenance.snapshot.endpoint, isNull);
    expect(currentSdk(), isNull);
    expect(provenance.driverAccess(approvedRegistry()), isNull);
  });

  for (final environment in [
    SupabaseEnvironment(url: fixtureEnvironment.url, publishableKey: ''),
    const SupabaseEnvironment(
        url: 'http://insecure.unit-test.invalid',
        publishableKey: 'sb_publishable_invalid_fixture_000000'),
    const SupabaseEnvironment(
        url: 'https://valid.unit-test.invalid',
        publishableKey: 'sb_secret_rejected_fixture_000000000'),
  ]) {
    test('invalid configuration fails without initializing SDK', () {
      expect(() => provenance.initialize(environment),
          throwsA(isA<EnvConfigException>()));
      expect(provenance.snapshot.state, SupabaseProvenanceState.failed);
      expect(currentSdk(), isNull);
      expect(provenance.driverAccess(approvedRegistry()), isNull);
    });
  }

  test(
      'repeated owned initialization does not construct another client or retain trust',
      () async {
    await provenance.initialize(fixtureEnvironment);
    final original = currentSdk()!.client;
    final access = provenance.driverAccess(approvedRegistry())!;
    await provenance.initialize(fixtureEnvironment);
    expect(currentSdk()!.client, same(original));
    expect(provenance.snapshot.state, SupabaseProvenanceState.unverified);
    expect(provenance.snapshot.endpoint, isNull);
    expect(access.client, isNull);
    expect(provenance.driverAccess(approvedRegistry()), isNull);
  });

  test('real SDK repeated initialization returns existing mismatched singleton',
      () async {
    final original = await Supabase.initialize(
        url: foreignEnvironment.url,
        publishableKey: foreignEnvironment.publishableKey,
        debug: false);
    final originalClient = original.client;
    final repeated = await Supabase.initialize(
        url: fixtureEnvironment.url,
        publishableKey: fixtureEnvironment.publishableKey,
        debug: false);
    expect(repeated, same(original));
    expect(repeated.client, same(originalClient));
    expect(repeated.client.rest.url, '${foreignEnvironment.url}/rest/v1');
    await provenance.initialize(fixtureEnvironment);
    expect(provenance.snapshot.state, SupabaseProvenanceState.unverified);
    expect(currentSdk()!.client, same(originalClient));
    expect(provenance.driverAccess(approvedRegistry()), isNull);
  });

  test('separate boundary cannot attest to an already initialized matching SDK',
      () async {
    await provenance.initialize(fixtureEnvironment);
    final otherBoundary = SupabaseInitializationProvenance();
    await otherBoundary.initialize(fixtureEnvironment);
    expect(otherBoundary.snapshot.state, SupabaseProvenanceState.unverified);
    expect(otherBoundary.driverAccess(approvedRegistry()), isNull);
    expect(provenance.driverAccess(approvedRegistry())!.client,
        same(currentSdk()!.client));
  });

  test('client replacement invalidates retained access permanently', () async {
    await provenance.initialize(fixtureEnvironment);
    final sdk = currentSdk()!;
    final original = sdk.client;
    final access = provenance.driverAccess(approvedRegistry())!;
    final replacement = SupabaseClient(
        foreignEnvironment.url, foreignEnvironment.publishableKey);
    try {
      sdk.client = replacement;
      expect(access.client, isNull);
      expect(provenance.snapshot.state, SupabaseProvenanceState.invalidated);
      expect(provenance.driverAccess(approvedRegistry()), isNull);
      sdk.client = original;
      expect(access.client, isNull);
      expect(provenance.driverAccess(approvedRegistry()), isNull);
    } finally {
      sdk.client = original;
      await replacement.dispose();
    }
  });

  test('direct SDK client disposal revokes all provenance access', () async {
    await provenance.initialize(fixtureEnvironment);
    final sdk = currentSdk()!;
    final original = sdk.client;
    final access = provenance.driverAccess(approvedRegistry())!;
    expect(access.client, same(original));
    expect(provenance.snapshot.state, SupabaseProvenanceState.trusted);

    // Preserve the original regression's isolated wrapper cleanup. This runs
    // only after all assertions; disposal protection must come from the SDK.
    addTearDown(() {
      sdk.client = AlreadyDisposedClientCleanup();
    });
    final disposal = original.dispose();
    expect(original.isDisposingOrDisposed, isTrue);
    expect(provenance.snapshot.state, SupabaseProvenanceState.invalidated);
    expect(access.client, isNull);
    expect(provenance.driverAccess(approvedRegistry()), isNull);
    await disposal;

    // Real SDK behavior: direct client disposal does not dispose its wrapper
    // or replace its client. Neither flag nor identity proves client liveness.
    expect(sdk.isInitialized, isTrue);
    expect(currentSdk(), same(sdk));
    expect(sdk.client, same(original));
    expect(
      {
        'retainedClient': access.client,
        'newDriverAccess': provenance.driverAccess(approvedRegistry()),
        'snapshotState': provenance.snapshot.state,
        'snapshotEndpoint': provenance.snapshot.endpoint,
      },
      {
        'retainedClient': null,
        'newDriverAccess': null,
        'snapshotState': SupabaseProvenanceState.invalidated,
        'snapshotEndpoint': null,
      },
      reason: 'A disposed client must not retain or issue Driver provenance.',
    );
  });

  test('SDK disposal invalidates provenance instead of creating a replacement',
      () async {
    await provenance.initialize(fixtureEnvironment);
    final access = provenance.driverAccess(approvedRegistry())!;
    await currentSdk()!.dispose();
    expect(access.client, isNull);
    expect(provenance.snapshot.state, SupabaseProvenanceState.invalidated);
    expect(currentSdk(), isNull);
  });

  for (final wrapper in [false, true]) {
    for (final fails in [false, true]) {
      test(
          'real gated disposal revokes before await: wrapper=$wrapper, '
          'failure=$fails', () async {
        await provenance.initialize(fixtureEnvironment);
        final sdk = currentSdk()!;
        final original = sdk.client;
        final marker = sdk.disposalState;
        final access = provenance.driverAccess(approvedRegistry())!;
        final socket = DisposalSocket()..attach(original);

        final disposal = wrapper ? sdk.dispose() : original.dispose();
        // No await: wrapper revocation must precede even its client cleanup.
        expect(wrapper ? marker.hasStarted : original.isDisposingOrDisposed,
            isTrue);
        expect(access.client, isNull);
        expect(provenance.driverAccess(approvedRegistry()), isNull);
        expect(provenance.snapshot.state, SupabaseProvenanceState.invalidated);
        expect(provenance.snapshot.endpoint, isNull);
        expect(wrapper ? sdk.dispose() : original.dispose(), same(disposal));
        await socket.entered.future;
        expect(socket.closeCalls, 1);
        expect(sdk.isInitialized, isTrue);

        final assertion = fails
            ? expectLater(disposal, throwsStateError)
            : expectLater(disposal, completes);
        if (fails) {
          socket.gate
              .completeError(StateError('local cleanup failure fixture'));
        } else {
          socket.gate.complete();
        }
        await assertion;
        expect(wrapper ? sdk.dispose() : original.dispose(), same(disposal));
        expect(original.isDisposingOrDisposed, isTrue);
        expect(access.client, isNull);
        expect(provenance.driverAccess(approvedRegistry()), isNull);
        expect(socket.closeCalls, 1);
        if (!wrapper) {
          if (fails) {
            await expectLater(sdk.dispose(), throwsStateError);
          } else {
            await sdk.dispose();
          }
        }
        expect(currentSdk(), isNull);
        expect(marker.hasStarted, isTrue);
        await Supabase.initialize(
          url: fixtureEnvironment.url,
          publishableKey: fixtureEnvironment.publishableKey,
          debug: false,
        );
        expect(currentSdk()!.disposalState, isNot(same(marker)));
        expect(currentSdk()!.isDisposingOrDisposed, isFalse);
        expect(marker.hasStarted, isTrue);
        expect(access.client, isNull);
        await provenance.initialize(fixtureEnvironment);
        expect(provenance.driverAccess(approvedRegistry()), isNull);
      });
    }
  }

  for (final wrapper in [false, true]) {
    test(
        'disposal during real SDK initialization denies trust: wrapper=$wrapper',
        () async {
      final storage = GatedPreferences();
      SharedPreferencesStorePlatform.instance = storage;
      final initialization = provenance.initialize(fixtureEnvironment);
      await storage.entered.future;
      final sdk = currentSdk()!;
      final original = sdk.client;
      final socket = DisposalSocket()..attach(original);
      final disposal = wrapper ? sdk.dispose() : original.dispose();
      expect(provenance.driverAccess(approvedRegistry()), isNull);
      await socket.entered.future;
      // Allow initialization to finish while cleanup remains gated. Auth has
      // not been torn down yet, so this tests the provenance guard itself.
      storage.gate.complete();
      await initialization;
      expect(provenance.snapshot.state, SupabaseProvenanceState.invalidated);
      expect(provenance.snapshot.endpoint, isNull);
      expect(provenance.driverAccess(approvedRegistry()), isNull);
      socket.gate.complete();
      await disposal;
      expect(provenance.driverAccess(approvedRegistry()), isNull);
    });
  }

  test('unknown or missing approved namespaces grant no Driver access',
      () async {
    await provenance.initialize(fixtureEnvironment);
    expect(provenance.driverAccess(DriverBackendRegistry([])), isNull);
    expect(
        provenance.driverAccess(DriverBackendRegistry([
          DriverBackendIdentity(
              endpoint: Uri.parse(foreignEnvironment.url),
              namespace: 'other-approved-fixture'),
        ])),
        isNull);
    expect(
        () => DriverBackendIdentity(
            endpoint: Uri.parse(fixtureEnvironment.url), namespace: ''),
        throwsArgumentError);
    expect(provenance.snapshot.state, SupabaseProvenanceState.trusted);
    expect(provenance.driverAccess(approvedRegistry())!.client,
        same(currentSdk()!.client));
  });

  test('public diagnostics contain endpoint/state, not configuration secrets',
      () async {
    await provenance.initialize(fixtureEnvironment);
    final snapshot = provenance.snapshot;
    expect(snapshot.endpoint.toString(), fixtureEnvironment.url);
    expect(snapshot.toString(),
        isNot(contains(fixtureEnvironment.publishableKey)));
    expect(snapshot.toString(), isNot(contains('Bearer')));
    expect(currentSdk()!.client.auth.currentSession, isNull);
  });

  test('URL query material is not published as trusted provenance', () async {
    await provenance.initialize(const SupabaseEnvironment(
        url: 'https://provenance.unit-test.invalid?untrusted=material',
        publishableKey: 'sb_publishable_local_query_fixture_00000000'));
    expect(provenance.snapshot.state, SupabaseProvenanceState.unverified);
    expect(provenance.snapshot.endpoint, isNull);
    expect(provenance.driverAccess(approvedRegistry()), isNull);
  });

  test('repeated request during SDK initialization cannot acquire trust',
      () async {
    final storage = GatedPreferences();
    SharedPreferencesStorePlatform.instance = storage;
    final first = provenance.initialize(fixtureEnvironment);
    await storage.entered.future;
    final original = currentSdk()!.client;
    final second = provenance.initialize(foreignEnvironment);
    expect(provenance.driverAccess(approvedRegistry()), isNull);
    storage.gate.complete();
    await Future.wait([first, second]);
    expect(currentSdk()!.client, same(original));
    expect(provenance.snapshot.state, SupabaseProvenanceState.unverified);
  });

  test('replacement while SDK initialization awaits is never captured as owned',
      () async {
    final storage = GatedPreferences();
    SharedPreferencesStorePlatform.instance = storage;
    final initialization = provenance.initialize(fixtureEnvironment);
    await storage.entered.future;
    final sdk = currentSdk()!;
    final original = sdk.client;
    final replacement = SupabaseClient(
        foreignEnvironment.url, foreignEnvironment.publishableKey);
    try {
      sdk.client = replacement;
      storage.gate.complete();
      await initialization;
      expect(provenance.snapshot.state, SupabaseProvenanceState.unverified);
      expect(provenance.driverAccess(approvedRegistry()), isNull);
    } finally {
      sdk.client = original;
      await replacement.dispose();
    }
  });

  test('actual SDK initialization failure never publishes partial trust',
      () async {
    final storage = GatedPreferences()..fail = true;
    SharedPreferencesStorePlatform.instance = storage;
    final finished = Completer<void>();
    final backgroundErrors = <Object>[];
    runZonedGuarded(() async {
      final initialization = provenance.initialize(fixtureEnvironment);
      final assertion = expectLater(
          initialization, throwsA(isA<SupabaseProvenanceException>()));
      await storage.entered.future;
      storage.gate.complete();
      await assertion;
      finished.complete();
    }, (error, stack) {
      backgroundErrors.add(error);
    });
    await finished.future;
    expect(provenance.snapshot.state, SupabaseProvenanceState.failed);
    expect(provenance.snapshot.endpoint, isNull);
    expect(provenance.driverAccess(approvedRegistry()), isNull);
    // The SDK's PKCE helper can also report its failed storage future. It is
    // contained in this fixture zone; provenance never reports the raw error.
    expect(backgroundErrors.every((e) => e is StateError), isTrue);
  });

  test('client provider follows compiled deployment configuration', () async {
    await provenance.initialize(fixtureEnvironment);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    if (EnvConfig.hasBackendConfig) {
      expect(
          container.read(supabaseClientProvider), same(currentSdk()!.client));
    } else {
      expect(container.read(supabaseClientProvider), isNull);
    }
    expect(container.read(supabaseInitializationProvenanceProvider),
        same(SupabaseInitializationProvenance.application));
    expect(currentSdk()!.client,
        same(provenance.driverAccess(approvedRegistry())!.client));
  });

  testWidgets('bootstrap preserves compiled startup mode', (tester) async {
    bool invalidConfiguration = false;
    try {
      EnvConfig.supabaseEnvironment;
    } on EnvConfigException {
      invalidConfiguration = true;
    }
    await tester.runAsync(bootstrap);
    await tester.pump();
    if (invalidConfiguration) {
      expect(find.byType(RideXInitializationFailureApp), findsOneWidget);
      expect(find.text('Unable to start RideX'), findsOneWidget);
      expect(currentSdk(), isNull);
    } else {
      expect(find.byType(RideXApp), findsOneWidget);
      if (EnvConfig.hasBackendConfig) {
        expect(SupabaseInitializationProvenance.application.snapshot.state,
            SupabaseProvenanceState.trusted);
        expect(
            SupabaseInitializationProvenance.application
                .driverAccess(approvedRegistry())!
                .client,
            same(currentSdk()!.client));
      } else {
        expect(currentSdk(), isNull);
        expect(SupabaseInitializationProvenance.application.snapshot.state,
            SupabaseProvenanceState.demo);
      }
    }
  });

  testWidgets('existing sanitized startup failure UI remains renderable',
      (tester) async {
    await tester.pumpWidget(const RideXInitializationFailureApp());
    expect(find.text('Unable to start RideX'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });
}
