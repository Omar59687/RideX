import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/services/driver_completion/pending_completion_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _driverId = 'driver-1';
const _otherDriverId = 'driver-2';
const _tripId = 'c7f00000-0000-0000-0000-000000000001';
const _otherTripId = 'c7f00000-0000-0000-0000-000000000002';
final _createdAt = DateTime.utc(2026, 10, 16, 12);

PendingCompletionCommand record({
  String driverId = _driverId,
  String tripId = _tripId,
  int version = 4,
  String key = 'complete-key-1',
  DateTime? createdAt,
}) =>
    PendingCompletionCommand(
      driverId: driverId,
      tripId: tripId,
      expectedTripVersion: version,
      idempotencyKey: key,
      createdAt: createdAt ?? _createdAt,
    );

DriverCompleteTripCommand originalCommand() => DriverCompleteTripCommand(
      tripId: _tripId,
      expectedTripVersion: 4,
      idempotencyKey: 'complete-key-1',
    );

SharedPreferencesCompletionCommandStore store({DateTime? now}) =>
    SharedPreferencesCompletionCommandStore(
      SharedPreferencesAsync(),
      // Keep ordinary fixtures fresh regardless of the calendar date. Expiry
      // boundary tests below explicitly supply their own later clock.
      clock: () => now ?? _createdAt,
    );

String slotKey([String driverId = _driverId]) =>
    SharedPreferencesCompletionCommandStore.keyForDriver(driverId);

Future<void> expectConflict(Future<void> Function() run) {
  return expectLater(
    run(),
    throwsA(isA<CompletionCommandConflictException>()),
  );
}

Future<void> expectCorrupt(Future<void> Function() run) {
  return expectLater(
    run(),
    throwsA(isA<CompletionCommandCorruptException>()),
  );
}

// Fake only the platform IO, so all envelope logic is production code.
// Mutable IO fault injection deliberately implements the immutable SDK facade.
// ignore: must_be_immutable
class _FailingPreferences implements SharedPreferencesAsync {
  bool failRead = false;
  bool failWrite = false;
  bool failRemove = false;
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async {
    if (failRead) throw StateError('read interrupted');
    return values[key];
  }

  @override
  Future<void> setString(String key, String value) async {
    if (failWrite) throw StateError('write interrupted');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    if (failRemove) throw StateError('remove interrupted');
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySharedPreferencesAsync backend;
  SharedPreferencesAsyncPlatform? previousPlatform;
  setUp(() {
    previousPlatform = SharedPreferencesAsyncPlatform.instance;
    backend = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = backend;
    addTearDown(() {
      SharedPreferencesAsyncPlatform.instance = previousPlatform;
    });
  });

  group('record model', () {
    test('round-trips the exact command through JSON', () {
      final restored = PendingCompletionCommand.fromJson(record().toJson());
      expect(restored, record());
      expect(
        restored.asCommand.isExactReplayOf(originalCommand()),
        isTrue,
      );
    });

    test('bridges the approved contract without mutation', () {
      final bridged = PendingCompletionCommand.fromCommand(
        command: originalCommand(),
        driverId: _driverId,
        createdAt: _createdAt,
      );
      expect(bridged, record());
    });

    test('rejects invalid identities at construction', () {
      expect(() => record(driverId: '  '), throwsArgumentError);
      expect(() => record(tripId: 'trip-1'), throwsArgumentError);
      expect(() => record(version: 0), throwsArgumentError);
      expect(() => record(key: '   '), throwsArgumentError);
      expect(
          () => record(key: List.filled(129, 'k').join()), throwsArgumentError);
      expect(
        () => PendingCompletionCommand.tryParse(const {}),
        returnsNormally,
      );
      expect(PendingCompletionCommand.tryParse(const {}), isNull);
    });

    test('identity ignores creation timestamp', () {
      final first = record();
      final replay =
          record(createdAt: _createdAt.add(const Duration(hours: 1)));
      expect(first.hasSameCommandIdentity(replay), isTrue);
      expect(first, isNot(replay));
    });
  });

  group('save and restore', () {
    test('saves before dispatch and restores the exact command', () async {
      final writer = store();
      await writer.savePending(record());

      final restored = await store().loadPendingForDriver(_driverId);
      expect(restored, record());
      expect(
        restored!.asCommand.isExactReplayOf(originalCommand()),
        isTrue,
      );
    });

    test('survives app restart with the exact command', () async {
      await store().savePending(record());

      final restarted = store();
      final slot = await restarted.inspectForDriver(_driverId);
      expect(slot.isValid, isTrue);
      expect(slot.command, record());
      expect(
        slot.command!.asCommand.isExactReplayOf(originalCommand()),
        isTrue,
      );
    });

    test('persists only recovery fields, never payment state', () async {
      await store().savePending(record());

      final raw = await SharedPreferencesAsync().getString(slotKey());
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), {'schema', 'command'});
      final command = Map<String, dynamic>.from(decoded['command'] as Map);
      expect(
        command.keys.toSet(),
        {
          'driver_id',
          'trip_id',
          'expected_version',
          'idempotency_key',
          'created_at',
        },
      );
    });

    test('absent slot loads as null', () async {
      expect(await store().loadPendingForDriver(_driverId), isNull);
      final slot = await store().inspectForDriver(_driverId);
      expect(slot.isAbsent, isTrue);
      expect(slot.command, isNull);
    });

    test('exact duplicate save is a no-op preserving the timestamp', () async {
      final writer = store();
      await writer.savePending(record());
      await writer.savePending(record(
          createdAt: _createdAt.add(
        const Duration(hours: 3),
      )));

      final restored = await store().loadPendingForDriver(_driverId);
      expect(restored!.createdAt, _createdAt);
    });
  });

  group('conflicting intents', () {
    test('rejects a changed trip id', () async {
      final writer = store();
      await writer.savePending(record());
      await expectConflict(() => writer.savePending(record(
            tripId: _otherTripId,
          )));
      expect(await writer.loadPendingForDriver(_driverId), record());
    });

    test('never changes the expected version for an unresolved command',
        () async {
      final writer = store();
      await writer.savePending(record(version: 4));
      await expectConflict(() => writer.savePending(record(version: 5)));
      expect(
        (await writer.loadPendingForDriver(_driverId))!.expectedTripVersion,
        4,
      );
    });

    test('rejects a rotated idempotency key', () async {
      final writer = store();
      await writer.savePending(record());
      await expectConflict(() => writer.savePending(record(key: 'key-2')));
      expect(
        (await writer.loadPendingForDriver(_driverId))!.idempotencyKey,
        'complete-key-1',
      );
    });
  });

  group('driver isolation', () {
    test('one driver never sees another driver command', () async {
      await store().savePending(record(driverId: _otherDriverId));

      expect(await store().loadPendingForDriver(_driverId), isNull);
      final restored = await store().loadPendingForDriver(_otherDriverId);
      expect(restored, record(driverId: _otherDriverId));
    });

    test('cross-namespace records degrade to corrupt, never valid', () async {
      await SharedPreferencesAsync().setString(
        slotKey(),
        jsonEncode({
          'schema': 1,
          'command': record(driverId: _otherDriverId).toJson(),
        }),
      );

      final slot = await store().inspectForDriver(_driverId);
      expect(slot.isCorrupt, isTrue);
      expect(slot.detail, 'driver-mismatch');
      expect(await store().loadPendingForDriver(_driverId), isNull);
    });

    test('conditional clear cannot touch another driver evidence', () async {
      final writer = store();
      final foreign = record(driverId: _otherDriverId);
      await writer.savePending(foreign);

      // Clearing driver-1's (absent) namespace is a no-op that leaves the
      // other driver's evidence untouched.
      await writer.clearPending(record(driverId: _driverId));
      expect(await writer.loadPendingForDriver(_otherDriverId), foreign);

      // A mismatched identity inside the foreign namespace is rejected.
      await expectConflict(
        () => writer.clearPending(record(driverId: _otherDriverId, key: 'x')),
      );
      expect(await writer.loadPendingForDriver(_otherDriverId), foreign);
    });
  });

  group('concurrency', () {
    test('concurrent conflicting saves resolve to exactly one winner',
        () async {
      final writer = store();
      final outcomes = await Future.wait([
        writer
            .savePending(record(key: 'key-a'))
            .then((_) => 'a-ok')
            .catchError((Object error) => 'a-${error.runtimeType}'),
        writer
            .savePending(record(key: 'key-b'))
            .then((_) => 'b-ok')
            .catchError((Object error) => 'b-${error.runtimeType}'),
      ]);

      expect(outcomes, ['a-ok', 'b-CompletionCommandConflictException']);
      expect(
        (await writer.loadPendingForDriver(_driverId))!.idempotencyKey,
        'key-a',
      );
    });

    test('concurrent duplicate saves both succeed once', () async {
      final writer = store();
      await Future.wait([
        writer.savePending(record()),
        writer.savePending(record()),
      ]);

      final restored = await writer.loadPendingForDriver(_driverId);
      expect(restored, record());
    });

    test('concurrent save then clear resolves in call order', () async {
      final writer = store();
      await Future.wait([
        writer.savePending(record()),
        writer.clearPending(record()),
      ]);
      expect(await writer.loadPendingForDriver(_driverId), isNull);
    });

    test('concurrent clear then save resolves in call order', () async {
      final writer = store();
      await Future.wait([
        writer.clearPending(record()),
        writer.savePending(record()),
      ]);
      expect(await writer.loadPendingForDriver(_driverId), record());
    });

    test('stale cleanup preserves newer evidence', () async {
      final writer = store();
      final stale = record(key: 'key-old');
      await writer.savePending(stale);
      await writer.clearPending(stale);
      await writer.savePending(record(key: 'key-new'));

      await expectConflict(() => writer.clearPending(stale));
      expect(
        (await writer.loadPendingForDriver(_driverId))!.idempotencyKey,
        'key-new',
      );
    });
  });

  group('conditional clearing', () {
    test('clears only for the exact stored identity', () async {
      final writer = store();
      await writer.savePending(record());

      await expectConflict(
        () => writer.clearPending(record(version: 9)),
      );
      expect(await writer.loadPendingForDriver(_driverId), record());

      await writer.clearPending(record());
      expect(await writer.loadPendingForDriver(_driverId), isNull);
    });

    test('clearing an absent slot is an idempotent success', () async {
      await store().clearPending(record());
      expect(await store().loadPendingForDriver(_driverId), isNull);
    });
  });

  group('corrupt evidence', () {
    test('classifies malformed and incompatible records safely', () async {
      const rider = _driverId;
      expect(
        SharedPreferencesCompletionCommandStore.inspectRaw(rider, null,
            now: _createdAt),
        predicate<CompletionCommandSlot>((slot) => slot.isAbsent),
      );
      expect(
        SharedPreferencesCompletionCommandStore.inspectRaw(rider, '{bad',
                now: _createdAt)
            .detail,
        'malformed-json',
      );
      expect(
        SharedPreferencesCompletionCommandStore.inspectRaw(rider, '[1,2]',
                now: _createdAt)
            .detail,
        'invalid-shape',
      );
      expect(
        SharedPreferencesCompletionCommandStore.inspectRaw(
          rider,
          jsonEncode({
            'schema': 99,
            'command': record().toJson(),
          }),
          now: _createdAt,
        ).detail,
        'invalid-envelope',
      );
      expect(
        SharedPreferencesCompletionCommandStore.inspectRaw(
          rider,
          jsonEncode({'schema': 1}),
          now: _createdAt,
        ).detail,
        'invalid-envelope',
      );
      expect(
        SharedPreferencesCompletionCommandStore.inspectRaw(
          rider,
          jsonEncode({
            'schema': 1,
            'command': {'trip_id': _tripId},
          }),
          now: _createdAt,
        ).detail,
        'invalid-shape',
      );
      expect(
        SharedPreferencesCompletionCommandStore.inspectRaw('', null,
                now: _createdAt)
            .detail,
        'invalid-driver-namespace',
      );
    });

    test('never overwrites or clears corrupt slots', () async {
      await SharedPreferencesAsync().setString(slotKey(), '{bad json');
      final writer = store();

      final slot = await writer.inspectForDriver(_driverId);
      expect(slot.isCorrupt, isTrue);
      expect(await writer.loadPendingForDriver(_driverId), isNull);

      await expectCorrupt(() => writer.savePending(record()));
      await expectCorrupt(() => writer.clearPending(record()));
      expect(
        await SharedPreferencesAsync().getString(slotKey()),
        '{bad json',
      );
    });

    test('unreadable storage degrades to corrupt, never absent', () async {
      final preferences = _FailingPreferences()..failRead = true;
      final writer = SharedPreferencesCompletionCommandStore(preferences);

      final slot = await writer.inspectForDriver(_driverId);
      expect(slot.isCorrupt, isTrue);
      expect(slot.detail, 'unreadable-storage');
      expect(await writer.loadPendingForDriver(_driverId), isNull);
    });
  });

  group('storage failures', () {
    test('write failures propagate and preserve the slot', () async {
      final preferences = _FailingPreferences()..failWrite = true;
      final writer = SharedPreferencesCompletionCommandStore(preferences);

      await expectLater(
        () => writer.savePending(record()),
        throwsA(isA<StateError>()),
      );
      preferences.failWrite = false;
      expect(await writer.loadPendingForDriver(_driverId), isNull);
    });
  });

  group('backend key expiry', () {
    test('flags the seven-day boundary without discarding evidence', () async {
      final savedAt = DateTime.utc(2026, 10, 9, 12);
      await store(now: savedAt).savePending(record(createdAt: savedAt));

      final fresh = store(now: savedAt.add(const Duration(days: 7)));
      final slot = await fresh.inspectForDriver(_driverId);
      expect(slot.isExpired, isTrue);
      expect(slot.command, record(createdAt: savedAt));

      final justBefore = store(
        now: savedAt.add(const Duration(days: 7) - const Duration(seconds: 1)),
      );
      expect((await justBefore.inspectForDriver(_driverId)).isValid, isTrue);
    });

    test('retains expired commands instead of auto-discarding', () async {
      final savedAt = DateTime.utc(2026, 10, 1, 12);
      await store(now: savedAt).savePending(record(createdAt: savedAt));

      final aged = store(now: savedAt.add(const Duration(days: 30)));
      expect(
        await aged.loadPendingForDriver(_driverId),
        record(createdAt: savedAt),
      );
      final raw = await SharedPreferencesAsync().getString(slotKey());
      expect(raw, isNotNull);
    });

    test('blocks saves over expired evidence until explicit clear', () async {
      final savedAt = DateTime.utc(2026, 10, 1, 12);
      final writer = store(now: savedAt);
      final agedRecord = record(createdAt: savedAt);
      await writer.savePending(agedRecord);

      final aged = store(now: savedAt.add(const Duration(days: 8)));
      await expectConflict(() => aged.savePending(agedRecord));
      await expectConflict(
        () => aged.savePending(record(createdAt: savedAt, key: 'key-2')),
      );

      await aged.clearPending(agedRecord);
      expect(await aged.loadPendingForDriver(_driverId), isNull);

      final renewed = record(
        createdAt: savedAt.add(const Duration(days: 8)),
        key: 'key-2',
      );
      await aged.savePending(renewed);
      expect(await aged.loadPendingForDriver(_driverId), renewed);
    });
  });
}
