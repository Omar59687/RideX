import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';

/// Slice 1: pending fare-lock ownership and safe local persistence.
///
/// The command's booking/quote identity is immutable, bound to its rider,
/// persisted before any lock RPC may be dispatched, and isolated across
/// users. Cold-start gating and canonical reconciliation belong to later
/// slices and are explicitly NOT verified here.
///
/// Slice 1 remediation (SOL Medium): exclusive pending-command ownership
/// (F1), atomic async ordering (F2), session/lifecycle isolation (F3), and
/// corrupt-evidence handling (F4). SharedPreferences remains a best-effort
/// recovery hint, never authoritative server truth.
void main() {
  PendingFareLock testCommand({String riderId = 'rider-1'}) {
    return PendingFareLock(
      bookingRequestId: 'booking-1',
      expectedBookingVersion: 2,
      fareQuoteId: 'quote-1',
      expectedQuoteVersion: 3,
      riderId: riderId,
      status: PendingLockRecoveryStatus.uncertain,
      createdAt: DateTime.utc(2026, 10, 10, 12),
    );
  }

  PendingFareLock competingCommand({String riderId = 'rider-1'}) {
    return PendingFareLock(
      bookingRequestId: 'booking-other',
      expectedBookingVersion: 2,
      fareQuoteId: 'quote-1',
      expectedQuoteVersion: 3,
      riderId: riderId,
      status: PendingLockRecoveryStatus.uncertain,
      createdAt: DateTime.utc(2026, 10, 10, 12, 1),
    );
  }

  const riderTwo = AppUser(
    id: 'rider-2',
    name: 'Rider Two',
    email: 'rider-two@ridex.demo',
    role: RideRole.rider,
  );

  group('PendingFareLock model', () {
    test('carries immutable identity with value equality', () {
      final first = testCommand();
      final second = testCommand();
      expect(second, first);
      expect(
        testCommand().copyWithVersion(expectedBookingVersion: 9),
        isNot(first),
      );
    });

    test('serializes and restores without loss', () {
      final restored = PendingFareLock.fromJson(testCommand().toJson());
      expect(restored, testCommand());
      expect(restored.createdAt.isUtc, isTrue);
    });

    test('rejects empty identities and non-positive versions', () {
      expect(() => testCommand(riderId: '  '), throwsArgumentError);
      expect(
        () => PendingFareLock.fromJson({
          ...testCommand().toJson(),
          'booking_request_id': '',
        }),
        throwsArgumentError,
      );
      expect(
        () => PendingFareLock.fromJson({
          ...testCommand().toJson(),
          'expected_booking_version': 0,
        }),
        throwsArgumentError,
      );
      expect(
        () => PendingFareLock.fromJson({'not': 'a-command'}),
        throwsArgumentError,
      );
    });

    test('tryParse degrades malformed records to null', () {
      expect(PendingFareLock.tryParse({'not': 'a-command'}), isNull);
      expect(
        PendingFareLock.tryParse({
          ...testCommand().toJson(),
          'status': 'locked',
        }),
        isNull,
      );
      expect(
        PendingFareLock.tryParse({
          ...testCommand().toJson(),
          'expected_quote_version': 'three',
        }),
        isNull,
      );
      expect(
        PendingFareLock.tryParse({
          ...testCommand().toJson(),
          'created_at': 'not-a-date',
        }),
        isNull,
      );
      expect(
        PendingFareLock.tryParse(testCommand().toJson()),
        testCommand(),
      );
    });

    test('hasSameLockIdentity ignores createdAt, compares the tuple', () {
      final first = testCommand();
      final replay = PendingFareLock(
        bookingRequestId: first.bookingRequestId,
        expectedBookingVersion: first.expectedBookingVersion,
        fareQuoteId: first.fareQuoteId,
        expectedQuoteVersion: first.expectedQuoteVersion,
        riderId: first.riderId,
        status: PendingLockRecoveryStatus.uncertain,
        createdAt: DateTime.utc(2026, 10, 11, 9),
      );
      expect(first.hasSameLockIdentity(replay), isTrue);
      expect(
        first.hasSameLockIdentity(competingCommand()),
        isFalse,
      );
      expect(
        first.hasSameLockIdentity(
          testCommand().copyWithVersion(expectedBookingVersion: 9),
        ),
        isFalse,
      );
      expect(
        first.hasSameLockIdentity(testCommand(riderId: 'rider-2')),
        isFalse,
      );
    });
  });

  group('PendingFareLockController', () {
    test('stage persists before publishing to memory', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);

      // Persistence-first ordering is structural: stage awaits the store
      // write before assigning state, so a completed stage always has a
      // durable record.
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      expect(
        container.read(pendingFareLockControllerProvider),
        testCommand(),
      );
      expect(await store.loadForRider('rider-1'), testCommand());
    });

    test('stage failure propagates with memory untouched', () async {
      final store = _MemoryPendingFareLockStore()
        ..failNextSave = StateError('disk unavailable');
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);

      await expectLater(
        container
            .read(pendingFareLockControllerProvider.notifier)
            .stageForDispatch(testCommand()),
        throwsStateError,
      );
      expect(container.read(pendingFareLockControllerProvider), isNull);
    });

    test('stage without an authenticated rider fails closed', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(store: store);
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(pendingFareLockControllerProvider.notifier)
            .stageForDispatch(testCommand()),
        throwsA(isA<PendingFareLockOwnershipException>()),
      );
      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(await store.loadForRider('rider-1'), isNull);
    });

    test('stage for another rider fails without touching storage', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);

      await expectLater(
        container
            .read(pendingFareLockControllerProvider.notifier)
            .stageForDispatch(testCommand(riderId: 'rider-2')),
        throwsA(isA<PendingFareLockOwnershipException>()),
      );
      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(await store.loadForRider('rider-2'), isNull);
    });

    test('same-user restoration re-hydrates evicted memory', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);

      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());

      // Simulate disposal/redirect: memory is gone, the slot survives.
      container.invalidate(pendingFareLockControllerProvider);
      expect(container.read(pendingFareLockControllerProvider), isNull);

      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      expect(
        container.read(pendingFareLockControllerProvider),
        testCommand(),
      );
    });

    test('different users never see each other commands', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());

      // Another rider signs in on the same device.
      await _signInAs(container, MockData.demoDriver);
      expect(container.read(pendingFareLockControllerProvider), isNull);

      // Explicit restore as the other rider still resolves to null while
      // the original slot is preserved untouched.
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(await store.loadForRider('rider-1'), testCommand());
    });

    test('signed-out sessions restore nothing and keep storage', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(store: store);
      addTearDown(container.dispose);

      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(store.loads, isEmpty);
    });

    test('clear removes memory and the rider slot', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);

      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .clear(testCommand());

      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(await store.loadForRider('rider-1'), isNull);
    });

    test('sign-out clears memory but retains recovery evidence', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      expect(container.read(pendingFareLockControllerProvider), isNotNull);

      await container.read(sessionControllerProvider.notifier).signOut();

      // Visible in-memory state is gone for the signed-out user...
      expect(container.read(pendingFareLockControllerProvider), isNull);
      // ...but the unresolved recovery evidence is not destroyed.
      expect(await store.loadForRider('rider-1'), testCommand());
    });

    test('same-user re-login restores the retained evidence', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      await container.read(sessionControllerProvider.notifier).signOut();
      expect(container.read(pendingFareLockControllerProvider), isNull);

      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      expect(
        container.read(pendingFareLockControllerProvider),
        testCommand(),
      );
    });
  });

  group('F1 exclusive pending-command ownership (controller-enforced)', () {
    test('competing commands never overwrite memory or storage', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());

      await expectLater(
        container
            .read(pendingFareLockControllerProvider.notifier)
            .stageForDispatch(competingCommand()),
        throwsA(isA<PendingFareLockConflictException>()),
      );
      expect(
        container.read(pendingFareLockControllerProvider),
        testCommand(),
      );
      expect(await store.loadForRider('rider-1'), testCommand());
    });

    test('each tuple field is exclusive', () async {
      final variants = <String, PendingFareLock>{
        'booking id': competingCommand(),
        'booking version':
            testCommand().copyWithVersion(expectedBookingVersion: 99),
        'quote id': PendingFareLock(
          bookingRequestId: 'booking-1',
          expectedBookingVersion: 2,
          fareQuoteId: 'quote-other',
          expectedQuoteVersion: 3,
          riderId: 'rider-1',
          status: PendingLockRecoveryStatus.uncertain,
          createdAt: DateTime.utc(2026, 10, 10, 12),
        ),
        'quote version': PendingFareLock(
          bookingRequestId: 'booking-1',
          expectedBookingVersion: 2,
          fareQuoteId: 'quote-1',
          expectedQuoteVersion: 99,
          riderId: 'rider-1',
          status: PendingLockRecoveryStatus.uncertain,
          createdAt: DateTime.utc(2026, 10, 10, 12),
        ),
      };
      for (final entry in variants.entries) {
        final store = _MemoryPendingFareLockStore();
        final container = _container(
          store: store,
          sessionUser: MockData.demoRider,
        );
        addTearDown(container.dispose);
        await _signInAs(container, MockData.demoRider);
        await container
            .read(pendingFareLockControllerProvider.notifier)
            .stageForDispatch(testCommand());
        await expectLater(
          container
              .read(pendingFareLockControllerProvider.notifier)
              .stageForDispatch(entry.value),
          throwsA(isA<PendingFareLockConflictException>()),
          reason: entry.key,
        );
        expect(
          container.read(pendingFareLockControllerProvider),
          testCommand(),
          reason: entry.key,
        );
        expect(
          await store.loadForRider('rider-1'),
          testCommand(),
          reason: entry.key,
        );
      }
    });

    test('exact replay of the same tuple is permitted', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      final first = testCommand();
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(first);

      // Same tuple with a fresh timestamp is still the same lineage.
      final replay = PendingFareLock(
        bookingRequestId: first.bookingRequestId,
        expectedBookingVersion: first.expectedBookingVersion,
        fareQuoteId: first.fareQuoteId,
        expectedQuoteVersion: first.expectedQuoteVersion,
        riderId: first.riderId,
        status: PendingLockRecoveryStatus.uncertain,
        createdAt: DateTime.utc(2026, 10, 10, 13),
      );
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(replay);
      expect(
        container
            .read(pendingFareLockControllerProvider)!
            .hasSameLockIdentity(first),
        isTrue,
      );
      expect(
        (await store.loadForRider('rider-1'))!.hasSameLockIdentity(first),
        isTrue,
      );
      expect(container.read(pendingFareLockControllerProvider), first);
      expect(await store.loadForRider('rider-1'), first);
    });

    test('persisted commands block competing stages after eviction', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());

      // Memory is evicted (redirect/disposal) while the slot survives.
      container.invalidate(pendingFareLockControllerProvider);
      expect(container.read(pendingFareLockControllerProvider), isNull);

      await expectLater(
        container
            .read(pendingFareLockControllerProvider.notifier)
            .stageForDispatch(competingCommand()),
        throwsA(isA<PendingFareLockConflictException>()),
      );
      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(await store.loadForRider('rider-1'), testCommand());
    });

    test('overlapping stages accept only the first lineage', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      // Drain the build-time restore so it cannot consume the test gate.
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();

      final saveGate = Completer<void>();
      store.saveGate = saveGate;
      // Two stages overlap on the persistence boundary. Serialization
      // forces the second to observe the first instead of overwriting it.
      final first = container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      final second = container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(competingCommand());
      saveGate.complete();
      await first;
      await expectLater(
          second, throwsA(isA<PendingFareLockConflictException>()));
      expect(
        container.read(pendingFareLockControllerProvider),
        testCommand(),
      );
      expect(await store.loadForRider('rider-1'), testCommand());
    });
  });

  group('F2 atomic async operation ordering', () {
    test('retained clear targets only its confirmed command', () async {
      final store = _MemoryPendingFareLockStore();
      final container =
          _container(store: store, sessionUser: MockData.demoRider);
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      final controller =
          container.read(pendingFareLockControllerProvider.notifier);
      await controller.stageForDispatch(testCommand());
      await controller.clear(testCommand());
      await controller.stageForDispatch(competingCommand());
      await controller.clear(testCommand());
      expect(container.read(pendingFareLockControllerProvider),
          competingCommand());
      expect(await store.loadForRider('rider-1'), competingCommand());
    });

    test('stale restore never replaces newer staged state', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();

      final loadGate = Completer<void>();
      store.loadGate = loadGate;
      // Restore starts first and hangs on its persistence read.
      final restore = container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      // A newer stage queues behind it.
      final stage = container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      loadGate.complete();
      await restore;
      await stage;
      expect(
        container.read(pendingFareLockControllerProvider),
        testCommand(),
      );
      expect(await store.loadForRider('rider-1'), testCommand());
    });

    test('old clear never deletes a newer command', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());

      // A newer persisted lineage appears (external race). An old clear for
      // the in-memory lineage must preserve it, not delete it.
      store.slots['rider-1'] = competingCommand();
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .clear(testCommand());
      expect(
        container.read(pendingFareLockControllerProvider),
        testCommand(),
      );
      expect(
        (await store.loadForRider('rider-1'))!.hasSameLockIdentity(
          competingCommand(),
        ),
        isTrue,
      );
    });

    test('clear over corrupt evidence preserves everything', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());

      store.malformedSlots.add('rider-1');
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .clear(testCommand());
      expect(
        container.read(pendingFareLockControllerProvider),
        testCommand(),
      );
      expect(container.read(pendingFareLockStorageBlockedProvider), isTrue);
    });

    test('failed deletion preserves memory and persisted evidence', () async {
      final store = _MemoryPendingFareLockStore()
        ..failNextClear = StateError('delete failed');
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());

      await container
          .read(pendingFareLockControllerProvider.notifier)
          .clear(testCommand());
      expect(
        container.read(pendingFareLockControllerProvider),
        testCommand(),
      );
      expect(await store.loadForRider('rider-1'), testCommand());
    });

    test('concurrent stage/restore/clear converge without out-of-order loss',
        () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();

      final saveGate = Completer<void>();
      final loadGate = Completer<void>();
      final clearGate = Completer<void>();
      store.saveGate = saveGate;
      store.loadGate = loadGate;
      store.clearGate = clearGate;

      final stage = container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      final restore = container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      final clear = container
          .read(pendingFareLockControllerProvider.notifier)
          .clear(testCommand());
      saveGate.complete();
      loadGate.complete();
      clearGate.complete();
      await stage;
      await restore;
      await clear;
      // Queued in call order: stage, then restore (same lineage), then an
      // exact clear for that lineage. Nothing is lost out of order.
      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(await store.loadForRider('rider-1'), isNull);
    });
  });

  group('F3 session and lifecycle isolation', () {
    test('queued stages cannot survive session invalidation', () async {
      final store = _MemoryPendingFareLockStore();
      final container =
          _container(store: store, sessionUser: MockData.demoRider);
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      final controller =
          container.read(pendingFareLockControllerProvider.notifier);
      await controller.restorePendingLock();
      final gate = Completer<void>();
      store.loadGate = gate;
      final restore = controller.restorePendingLock();
      await Future<void>.delayed(Duration.zero);
      final stage = controller.stageForDispatch(testCommand());
      final rejected =
          expectLater(stage, throwsA(isA<PendingFareLockOwnershipException>()));
      await _signInAs(container, riderTwo);
      await _signInAs(container, MockData.demoRider);
      gate.complete();
      await restore;
      await rejected;
      expect(store.saves, isEmpty);
    });

    test('delayed read errors cannot block another rider', () async {
      final store = _MemoryPendingFareLockStore();
      final container =
          _container(store: store, sessionUser: MockData.demoRider);
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      final controller =
          container.read(pendingFareLockControllerProvider.notifier);
      await controller.restorePendingLock();
      final gate = Completer<void>();
      store.loadGate = gate;
      store.failNextInspect = StateError('storage unavailable');
      final restore = controller.restorePendingLock();
      await Future<void>.delayed(Duration.zero);
      await _signInAs(container, riderTwo);
      gate.complete();
      await restore;
      expect(container.read(pendingFareLockStorageBlockedProvider), isFalse);
      expect(container.read(pendingFareLockControllerProvider), isNull);
    });

    test('disposal during save preserves evidence without publishing',
        () async {
      final store = _MemoryPendingFareLockStore();
      final container =
          _container(store: store, sessionUser: MockData.demoRider);
      await _signInAs(container, MockData.demoRider);
      final controller =
          container.read(pendingFareLockControllerProvider.notifier);
      await controller.restorePendingLock();
      final gate = Completer<void>();
      store.saveGate = gate;
      final stage = controller.stageForDispatch(testCommand());
      final rejected =
          expectLater(stage, throwsA(isA<PendingFareLockOwnershipException>()));
      await Future<void>.delayed(Duration.zero);
      container.dispose();
      gate.complete();
      await rejected;
      expect(await store.loadForRider('rider-1'), testCommand());
    });

    for (final user in [
      const AppUser(
          id: 'rider-1',
          name: 'Blocked',
          email: 'blocked@test.demo',
          role: RideRole.rider,
          isBlocked: true),
      MockData.demoDriver,
    ]) {
      test('incompatible session ${user.role}/${user.isBlocked} cannot stage',
          () async {
        final store = _MemoryPendingFareLockStore();
        final container = _container(store: store, sessionUser: user);
        addTearDown(container.dispose);
        await _signInAs(container, user);
        await expectLater(
            container
                .read(pendingFareLockControllerProvider.notifier)
                .stageForDispatch(testCommand(riderId: user.id)),
            throwsA(isA<PendingFareLockOwnershipException>()));
        expect(store.saves, isEmpty);
        expect(store.loads, isEmpty);
      });
    }

    test('rider A to rider B never leaks the command', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      expect(container.read(pendingFareLockControllerProvider), isNotNull);

      await _signInAs(container, riderTwo);
      expect(container.read(pendingFareLockControllerProvider), isNull);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      expect(container.read(pendingFareLockControllerProvider), isNull);
      // Original evidence survives for same-user recovery.
      expect(await store.loadForRider('rider-1'), testCommand());
      expect(await store.loadForRider('rider-2'), isNull);
    });

    test('sign-out during delayed save publishes nothing', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();

      final saveGate = Completer<void>();
      store.saveGate = saveGate;
      final stage = container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      await container.read(sessionControllerProvider.notifier).signOut();
      saveGate.complete();
      await expectLater(
        stage,
        throwsA(isA<PendingFareLockOwnershipException>()),
      );
      // Nothing is published into the signed-out session, while the
      // per-rider evidence remains for same-user recovery.
      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(await store.loadForRider('rider-1'), testCommand());
    });

    test('session change during delayed load publishes nothing', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      // Drain the post-stage queue so the test gate is not consumed by a
      // stale build-time restore.
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      container.invalidate(pendingFareLockControllerProvider);
      // Let the fresh controller finish its build-time restore (absent gate)
      // before installing the test gate.
      await Future<void>.delayed(Duration.zero);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();

      final loadGate = Completer<void>();
      store.loadGate = loadGate;
      final restore = container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      await _signInAs(container, riderTwo);
      loadGate.complete();
      await restore;
      // Rider B must never receive rider A's command.
      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(await store.loadForRider('rider-1'), testCommand());
    });

    test('late completion after disposal is a safe no-op', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      container.invalidate(pendingFareLockControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();

      final loadGate = Completer<void>();
      store.loadGate = loadGate;
      final restore = container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      container.dispose();
      loadGate.complete();
      // Restore never throws, even when its completion races disposal.
      await restore;
    });

    test('staged command is unusable after ownership loss (no RPC)', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();

      final saveGate = Completer<void>();
      store.saveGate = saveGate;
      var rpcDispatched = false;
      Future<void> dispatchIfStaged() async {
        try {
          await container
              .read(pendingFareLockControllerProvider.notifier)
              .stageForDispatch(testCommand());
        } on Object {
          return;
        }
        // Screen-equivalent guard: recheck ownership immediately before the
        // Lock RPC. Ownership was lost, so this must never run.
        final session = container.read(sessionControllerProvider);
        if (session.user?.id != 'rider-1') return;
        rpcDispatched = true;
      }

      final dispatch = dispatchIfStaged();
      await _signInAs(container, riderTwo);
      saveGate.complete();
      await dispatch;
      expect(rpcDispatched, isFalse);
      expect(container.read(pendingFareLockControllerProvider), isNull);
    });
  });

  group('F4 corrupt persistent evidence', () {
    test('store distinguishes absent, valid, and corrupt', () {
      expect(
        SharedPreferencesPendingFareLockStore.inspectRaw('rider-1', null),
        predicate<PendingFareLockSlot>((slot) => slot.isAbsent),
      );
      expect(
        SharedPreferencesPendingFareLockStore.inspectRaw('rider-1', ''),
        predicate<PendingFareLockSlot>((slot) => slot.isCorrupt),
      );
      expect(
        SharedPreferencesPendingFareLockStore.inspectRaw('', null).isCorrupt,
        isTrue,
      );

      final valid = SharedPreferencesPendingFareLockStore.inspectRaw(
        'rider-1',
        jsonEncode(testCommand().toJson()),
      );
      expect(valid.isValid, isTrue);
      expect(valid.command, testCommand());

      final malformed = SharedPreferencesPendingFareLockStore.inspectRaw(
        'rider-1',
        '{not-valid-json',
      );
      expect(malformed.isCorrupt, isTrue);
      expect(malformed.command, isNull);
      expect(malformed.detail, isNotNull);

      final mismatch = SharedPreferencesPendingFareLockStore.inspectRaw(
        'rider-1',
        jsonEncode(testCommand(riderId: 'rider-2').toJson()),
      );
      expect(mismatch.isCorrupt, isTrue);
      expect(mismatch.detail, 'rider-mismatch');

      // Invalid shapes (wrong status, bad versions) are corrupt, not absent.
      final badStatus = SharedPreferencesPendingFareLockStore.inspectRaw(
        'rider-1',
        jsonEncode({
          ...testCommand().toJson(),
          'status': 'locked',
        }),
      );
      expect(badStatus.isCorrupt, isTrue);

      final notAMap = SharedPreferencesPendingFareLockStore.inspectRaw(
        'rider-1',
        jsonEncode(['not', 'a', 'map']),
      );
      expect(notAMap.isCorrupt, isTrue);
    });

    test('staging over corrupt evidence throws and preserves it', () async {
      final store = _MemoryPendingFareLockStore()
        ..malformedSlots.add('rider-1');
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);

      await expectLater(
        container
            .read(pendingFareLockControllerProvider.notifier)
            .stageForDispatch(testCommand()),
        throwsA(isA<PendingFareLockCorruptException>()),
      );
      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(container.read(pendingFareLockStorageBlockedProvider), isTrue);
      // The suspicious record is preserved, never overwritten.
      expect(store.saves, isEmpty);
      expect(
        (await store.inspectForRider('rider-1')).isCorrupt,
        isTrue,
      );
    });

    test('wrong-rider records never stage or restore as valid', () async {
      final store = _MemoryPendingFareLockStore();
      // Plant a rider-2 record under rider-1's namespace.
      store.slots['rider-1'] = testCommand(riderId: 'rider-2');
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);

      final slot = await store.inspectForRider('rider-1');
      expect(slot.isCorrupt, isTrue);
      expect(slot.detail, 'rider-mismatch');

      await expectLater(
        container
            .read(pendingFareLockControllerProvider.notifier)
            .stageForDispatch(testCommand()),
        throwsA(isA<PendingFareLockCorruptException>()),
      );
      await container
          .read(pendingFareLockControllerProvider.notifier)
          .restorePendingLock();
      expect(container.read(pendingFareLockControllerProvider), isNull);
      expect(container.read(pendingFareLockStorageBlockedProvider), isTrue);
      // Preserved for diagnosis, never exposed as a valid command.
      expect(store.slots['rider-1']!.riderId, 'rider-2');
    });

    test('absent records stage normally and clear the blocked flag', () async {
      final store = _MemoryPendingFareLockStore();
      final container = _container(
        store: store,
        sessionUser: MockData.demoRider,
      );
      addTearDown(container.dispose);
      await _signInAs(container, MockData.demoRider);
      expect(
        (await store.inspectForRider('rider-1')).isAbsent,
        isTrue,
      );

      await container
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(testCommand());
      expect(
        container.read(pendingFareLockControllerProvider),
        testCommand(),
      );
      expect(container.read(pendingFareLockStorageBlockedProvider), isFalse);
    });
  });
}

extension on PendingFareLock {
  PendingFareLock copyWithVersion({required int expectedBookingVersion}) {
    return PendingFareLock(
      bookingRequestId: bookingRequestId,
      expectedBookingVersion: expectedBookingVersion,
      fareQuoteId: fareQuoteId,
      expectedQuoteVersion: expectedQuoteVersion,
      riderId: riderId,
      status: status,
      createdAt: createdAt,
    );
  }
}

ProviderContainer _container({
  PendingFareLockStore? store,
  AppUser? sessionUser,
}) {
  final auth = _FixedUserAuthRepository(sessionUser);
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((ref) => auth),
      if (store != null) pendingFareLockStoreProvider.overrideWithValue(store),
    ],
  );
}

Future<void> _signInAs(ProviderContainer container, AppUser user) async {
  final auth = container.read(authRepositoryProvider);
  assert(auth is _FixedUserAuthRepository, 'test auth override missing');
  (auth as _FixedUserAuthRepository).sessionUser = user;
  await container.read(sessionControllerProvider.notifier).refreshSession();
  final session = container.read(sessionControllerProvider);
  assert(
    session.user?.id == user.id,
    'session did not authenticate as ${user.id}',
  );
}

/// Auth double with a switchable session user for isolation tests.
class _FixedUserAuthRepository extends MockAuthRepository {
  _FixedUserAuthRepository(this.sessionUser);

  AppUser? sessionUser;

  @override
  Future<AppUser?> restoreSession() async => sessionUser;
}

/// In-memory store double with corruption, failure, and gate controls for
/// deterministic race tests. Inspect validates the rider namespace like the
/// real SharedPreferences store; malformed slots model unreadable JSON.
class _MemoryPendingFareLockStore implements PendingFareLockStore {
  final slots = <String, PendingFareLock>{};
  final loads = <String>[];
  final saves = <PendingFareLock>[];
  final malformedSlots = <String>{};
  Error? failNextSave;
  Error? failNextClear;
  Error? failNextInspect;
  Completer<void>? saveGate;
  Completer<void>? loadGate;
  Completer<void>? clearGate;

  @override
  Future<void> save(PendingFareLock command) async {
    final gate = saveGate;
    if (gate != null) {
      saveGate = null;
      await gate.future;
    }
    final failure = failNextSave;
    if (failure != null) {
      failNextSave = null;
      throw failure;
    }
    saves.add(command);
    slots[command.riderId] = command;
  }

  @override
  Future<PendingFareLock?> loadForRider(String riderId) async {
    final slot = await inspectForRider(riderId);
    return slot.command;
  }

  @override
  Future<PendingFareLockSlot> inspectForRider(String riderId) async {
    final gate = loadGate;
    if (gate != null) {
      loadGate = null;
      await gate.future;
    }
    loads.add(riderId);
    final failure = failNextInspect;
    if (failure != null) {
      failNextInspect = null;
      throw failure;
    }
    if (malformedSlots.contains(riderId)) {
      return const PendingFareLockSlot.corrupt('malformed-json');
    }
    final stored = slots[riderId];
    if (stored == null) {
      return const PendingFareLockSlot.absent();
    }
    if (stored.riderId != riderId) {
      return const PendingFareLockSlot.corrupt('rider-mismatch');
    }
    return PendingFareLockSlot.valid(stored);
  }

  @override
  Future<void> clearForRider(String riderId) async {
    final gate = clearGate;
    if (gate != null) {
      clearGate = null;
      await gate.future;
    }
    final failure = failNextClear;
    if (failure != null) {
      failNextClear = null;
      throw failure;
    }
    slots.remove(riderId);
    malformedSlots.remove(riderId);
  }
}
