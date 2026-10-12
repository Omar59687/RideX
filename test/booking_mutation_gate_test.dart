import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _location = FareRouteLocation(latitude: 31.95, longitude: 35.92);
final _command = PendingFareLock(
  bookingRequestId: 'booking-1',
  expectedBookingVersion: 1,
  fareQuoteId: 'quote-1',
  expectedQuoteVersion: 1,
  riderId: 'rider-1',
  status: PendingLockRecoveryStatus.uncertain,
  createdAt: DateTime.utc(2026, 10, 10),
);
final _blocked = throwsA(isA<FareException>()
    .having((error) => error.failure, 'failure', FareFailure.mutationBlocked));

class _Auth extends MockAuthRepository {
  AppUser? user = MockData.demoRider;
  @override
  Future<AppUser?> restoreSession() async => user;
}

class _Store implements PendingFareLockStore {
  final slots = <String, PendingFareLock>{};
  bool corrupt = false;
  bool failRead = false;
  Completer<PendingFareLockSlot>? readGate;
  @override
  Future<PendingFareLockSlot> inspectForRider(String riderId) async {
    if (failRead) throw StateError('storage unavailable');
    if (readGate != null) return readGate!.future;
    if (corrupt) return const PendingFareLockSlot.corrupt();
    final command = slots[riderId];
    return command == null
        ? const PendingFareLockSlot.absent()
        : PendingFareLockSlot.valid(command);
  }

  @override
  Future<void> save(PendingFareLock command) async {
    slots[command.riderId] = command;
  }

  @override
  Future<PendingFareLock?> loadForRider(String riderId) async => slots[riderId];
  @override
  Future<void> clearForRider(String riderId) async {
    slots.remove(riderId);
  }
}

class _Harness {
  _Harness({_Store? persisted, SupabaseClient? client})
      : store = persisted ?? _Store() {
    repository = SupabaseFareRepository(
      bookingMutationGate: (dispatch) => pending.runBookingMutation(dispatch),
      rpc: ({required name, required params}) async {
        calls.add(name);
        if (rpcGate != null) await rpcGate!.future;
        return {'id': 'booking-1', 'version': calls.length};
      },
      quoteEdge: (_) async => throw StateError('unexpected quote'),
    );
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      if (client == null) fareRepositoryProvider.overrideWithValue(repository),
      if (client != null) supabaseClientProvider.overrideWithValue(client),
      pendingFareLockStoreProvider.overrideWithValue(store),
      appErrorReporterProvider.overrideWithValue(const NoopAppErrorReporter()),
    ]);
  }
  final _Auth auth = _Auth();
  final _Store store;
  final calls = <String>[];
  Completer<void>? rpcGate;
  late final ProviderContainer container;
  late final SupabaseFareRepository repository;
  PendingFareLockController get pending =>
      container.read(pendingFareLockControllerProvider.notifier);
  Future<void> authenticate() async {
    await container.read(sessionControllerProvider.notifier).refreshSession();
  }

  Future<void> ready() async {
    await authenticate();
    await pending.restorePendingLock();
  }

  Future<FareBookingRef> mutate({bool update = false}) {
    // Any route/client holding the shared repository reaches the same gate.
    final fare = container.read(fareRepositoryProvider);
    if (update) {
      return fare.updateBookingDraft(
          bookingRequestId: 'booking-1',
          expectedBookingVersion: 1,
          pickup: _location,
          destination: _location,
          vehicleTypeCode: 'economy',
          paymentMethod: 'cash');
    }
    return fare.createBookingDraft(
        pickup: _location,
        destination: _location,
        vehicleTypeCode: 'economy',
        paymentMethod: 'cash');
  }
}

class _LoopbackHttpOverrides extends HttpOverrides {}

Future<void> _setSdkRider(SupabaseClient client, String id) =>
    client.auth.setInitialSession(jsonEncode({
      'access_token': 'offline-test-session',
      'token_type': 'bearer',
      'user': {'id': id, 'aud': 'authenticated'},
    }));

void main() {
  test(
      'production provider rejects SDK owner change during the RPC',
      () => HttpOverrides.runWithHttpOverrides(() async {
            late SupabaseClient client;
            final server =
                await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
            addTearDown(() => server.close(force: true));
            server.listen((request) async {
              await _setSdkRider(client, 'rider-2');
              request.response.headers.contentType = ContentType.json;
              request.response
                  .write(jsonEncode({'id': 'booking-1', 'version': 1}));
              await request.response.close();
            });
            client = SupabaseClient(
                'http://127.0.0.1:${server.port}', 'offline-publishable');
            addTearDown(client.dispose);
            await _setSdkRider(client, 'rider-1');
            final h = _Harness(client: client);
            addTearDown(h.container.dispose);
            await h.ready();
            await expectLater(h.mutate(), _blocked);
          }, _LoopbackHttpOverrides()));
  test('production provider rejects SDK/session owner mismatch before HTTP',
      () async {
    final client = SupabaseClient('http://127.0.0.1:1', 'offline-publishable');
    addTearDown(client.dispose);
    await _setSdkRider(client, 'rider-2');
    final h = _Harness(client: client);
    addTearDown(h.container.dispose);
    await h.ready();
    await expectLater(h.mutate(), _blocked);
    await expectLater(h.mutate(update: true), _blocked);
  });
  test(
      'production provider dispatches only after matching owner and safe restore',
      () => HttpOverrides.runWithHttpOverrides(() async {
            int requests = 0;
            final server =
                await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
            addTearDown(() => server.close(force: true));
            server.listen((request) async {
              requests++;
              expect(
                  request.uri.path, '/rest/v1/rpc/rider_create_booking_draft');
              request.response.headers.contentType = ContentType.json;
              request.response
                  .write(jsonEncode({'id': 'booking-1', 'version': 1}));
              await request.response.close();
            });
            final client = SupabaseClient(
                'http://127.0.0.1:${server.port}', 'offline-publishable');
            addTearDown(client.dispose);
            await _setSdkRider(client, 'rider-1');
            final h = _Harness(client: client);
            addTearDown(h.container.dispose);
            await h.ready();
            h.store.readGate = Completer<PendingFareLockSlot>();
            final creation = h.mutate();
            await Future<void>.delayed(Duration.zero);
            expect(requests, 0);
            h.store.readGate!.complete(const PendingFareLockSlot.absent());
            expect((await creation).bookingRequestId, 'booking-1');
            expect(requests, 1);
            h.store.readGate = null;
            h.store.slots['rider-1'] = _command;
            await expectLater(h.mutate(update: true), _blocked);
            expect(requests, 1);
          }, _LoopbackHttpOverrides()));
  for (final update in [false, true]) {
    final operation = update ? 'update' : 'create';
    test('$operation waits for persistence readiness before dispatch',
        () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      await h.authenticate();
      // Let the SessionController's initial restoration finish before
      // delaying persistence; session loading itself must also fail closed.
      await Future<void>.delayed(Duration.zero);
      h.store.readGate = Completer<PendingFareLockSlot>();
      final mutation = h.mutate(update: update);
      await Future<void>.delayed(Duration.zero);
      expect(h.calls, isEmpty);
      h.store.readGate!.complete(const PendingFareLockSlot.absent());
      expect((await mutation).bookingRequestId, 'booking-1');
      expect(h.calls, hasLength(1));
    });
    for (final evidence in ['pending', 'corrupt', 'read failure']) {
      test('$operation blocks $evidence at actual repository boundary',
          () async {
        final h = _Harness();
        addTearDown(h.container.dispose);
        await h.ready();
        if (evidence == 'pending') h.store.slots['rider-1'] = _command;
        if (evidence == 'corrupt') h.store.corrupt = true;
        if (evidence == 'read failure') h.store.failRead = true;
        await expectLater(h.mutate(update: update), _blocked);
        expect(h.calls, isEmpty);
        if (evidence == 'pending') expect(h.store.slots['rider-1'], _command);
      });
    }
  }
  test('legitimate create and update work after safe absence is established',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.ready();
    await h.mutate();
    await h.mutate(update: true);
    expect(
        h.calls, ['rider_create_booking_draft', 'rider_update_booking_draft']);
  });
  test('cold start restores evidence before any cross-route mutation',
      () async {
    final store = _Store()..slots['rider-1'] = _command;
    final h = _Harness(persisted: store);
    addTearDown(h.container.dispose);
    await h.authenticate();
    await expectLater(h.mutate(), _blocked);
    h.container
        .invalidate(bookingControllerProvider); // Rider Home new booking.
    await expectLater(h.mutate(update: true), _blocked);
    h.container.invalidate(pendingFareLockControllerProvider); // recreation.
    await expectLater(h.mutate(), _blocked);
    expect(h.calls, isEmpty);
    expect(store.slots['rider-1'], _command);
    final restarted = _Harness(persisted: store);
    addTearDown(restarted.container.dispose);
    await restarted.ready();
    await expectLater(restarted.mutate(), _blocked);
    expect(restarted.calls, isEmpty);
  });
  test('same Rider refresh invalidates a delayed readiness completion',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.ready();
    h.store.readGate = Completer<PendingFareLockSlot>();
    final result = h.mutate();
    final expectation = expectLater(result, _blocked);
    await Future<void>.delayed(Duration.zero);
    await h.authenticate();
    h.store.readGate!.complete(const PendingFareLockSlot.absent());
    await expectation;
    expect(h.calls, isEmpty);
    h.store.readGate = null;
    await h.mutate();
    expect(h.calls, hasLength(1));
  });
  test(
      'different Rider gets own safe restore without clearing original evidence',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.ready();
    h.store.slots['rider-1'] = _command;
    await expectLater(h.mutate(), _blocked);
    h.auth.user = const AppUser(
        id: 'rider-2',
        name: 'Other',
        email: 'other@test.example',
        role: RideRole.rider);
    await h.authenticate();
    await h.mutate();
    expect(h.store.slots['rider-1'], _command);
    h.auth.user = MockData.demoRider;
    await h.authenticate();
    await expectLater(h.mutate(), _blocked);
  });
  test('concurrent mutations serialize dispatch and recheck persisted evidence',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.ready();
    h.rpcGate = Completer<void>();
    final first = h.mutate();
    await Future<void>.delayed(Duration.zero);
    final second = h.mutate(update: true);
    final secondExpectation = expectLater(second, _blocked);
    expect(h.calls, hasLength(1));
    h.store.slots['rider-1'] = _command;
    h.rpcGate!.complete();
    await first;
    await secondExpectation;
    expect(h.calls, hasLength(1));
  });
  test('queued staging cannot race a mutation into an unresolved lock',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.ready();
    h.rpcGate = Completer<void>();
    final first = h.mutate();
    await Future<void>.delayed(Duration.zero);
    final stage = h.pending.stageForDispatch(_command);
    final second = h.mutate();
    final blocked = expectLater(second, _blocked);
    h.rpcGate!.complete();
    await first;
    await stage;
    await blocked;
    expect(h.calls, hasLength(1));
  });
  test('signed out and disposed owners never dispatch late mutations',
      () async {
    final h = _Harness();
    await h.ready();
    h.store.readGate = Completer<PendingFareLockSlot>();
    final mutation = h.mutate();
    final blocked = expectLater(mutation, _blocked);
    await Future<void>.delayed(Duration.zero);
    h.container.dispose();
    h.store.readGate!.complete(const PendingFareLockSlot.absent());
    await blocked;
    expect(h.calls, isEmpty);
    final other = _Harness();
    addTearDown(other.container.dispose);
    other.auth.user = null;
    await other.authenticate();
    await expectLater(other.mutate(), _blocked);
    expect(other.calls, isEmpty);
  });
  test('late RPC result is withheld after Rider session change', () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.ready();
    h.rpcGate = Completer<void>();
    final mutation = h.mutate();
    final blocked = expectLater(mutation, _blocked);
    await Future<void>.delayed(Duration.zero);
    h.auth.user = null;
    await h.authenticate();
    h.rpcGate!.complete();
    await blocked;
    expect(h.calls, hasLength(1));
  });
  test('storage recovery permits retry only after a fresh safe read', () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.ready();
    h.store.failRead = true;
    await expectLater(h.mutate(), _blocked);
    h.store.failRead = false;
    await h.mutate();
    expect(h.calls, hasLength(1));
  });
  test('Mock fare repository retains deterministic behavior', () async {
    final fake = FakeFareRepository();
    final booking = await fake.createBookingDraft(
        pickup: _location,
        destination: _location,
        vehicleTypeCode: 'economy',
        paymentMethod: 'cash');
    expect(booking.version, 1);
    expect(
        (await fake.updateBookingDraft(
                bookingRequestId: booking.bookingRequestId,
                expectedBookingVersion: 1,
                pickup: _location,
                destination: _location,
                vehicleTypeCode: 'economy',
                paymentMethod: 'cash'))
            .version,
        2);
  });
  test('foreign namespace evidence and non-Rider sessions fail closed',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.ready();
    h.store.slots['rider-1'] = PendingFareLock(
        bookingRequestId: _command.bookingRequestId,
        expectedBookingVersion: 1,
        fareQuoteId: _command.fareQuoteId,
        expectedQuoteVersion: 1,
        riderId: 'rider-2',
        status: PendingLockRecoveryStatus.uncertain,
        createdAt: _command.createdAt);
    await expectLater(h.mutate(), _blocked);
    expect(h.store.slots['rider-1']!.riderId, 'rider-2');
    h.auth.user = const AppUser(
        id: 'driver-1',
        name: 'Driver',
        email: 'driver@test.example',
        role: RideRole.driver);
    await h.authenticate();
    await expectLater(h.mutate(), _blocked);
    expect(h.calls, isEmpty);
  });
}
