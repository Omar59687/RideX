import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';

const driver = 'a7000000-0000-0000-0000-000000000001';
const otherDriver = 'a7000000-0000-0000-0000-000000000002';
const trip = 'c7000000-0000-0000-0000-000000000001';
const otherTrip = 'c7000000-0000-0000-0000-000000000002';

DriverCompleteTripCommand command(
        {String id = trip, int version = 7, String key = 'original-key'}) =>
    DriverCompleteTripCommand(
        tripId: id, expectedTripVersion: version, idempotencyKey: key);

/// Real disk I/O with deterministic faults, not an in-memory persistence fake.
class FaultIo extends NativeCompletionJournalIo {
  int reads = 0;
  int? failReadAt;
  bool failPrepare = false;
  bool failAcquire = false;
  bool failRelease = false;
  bool lostReleaseAck = false;
  bool failOpen = false;
  bool failWrite = false;
  bool partialWrite = false;
  bool lostWriteAck = false;
  bool failFlush = false;
  bool failClose = false;
  bool changeReadback = false;
  Completer<void>? writeGate;
  Completer<void>? entered;
  File? journal;

  @override
  Future<String> prepare(Directory directory) {
    if (failPrepare) {
      throw StateError('private path and secret backend details');
    }
    return super.prepare(directory);
  }

  @override
  Future<void> acquire(File lock) async {
    if (failAcquire) throw StateError('lock failed');
    await super.acquire(lock);
  }

  @override
  Future<void> release(File lock) async {
    if (failRelease) throw StateError('release failed');
    await super.release(lock);
    if (lostReleaseAck) throw StateError('release acknowledgement lost');
  }

  @override
  Future<Uint8List?> read(File file) async {
    journal = file;
    reads++;
    if (reads == failReadAt) throw StateError('read failed with private data');
    final bytes = await super.read(file);
    if (changeReadback && reads > 1 && bytes != null) {
      return Uint8List.fromList([...bytes, 0]);
    }
    return bytes;
  }

  @override
  Future<RandomAccessFile> openAppend(File file) {
    if (failOpen) throw StateError('open failed');
    return super.openAppend(file);
  }

  @override
  Future<void> write(RandomAccessFile handle, List<int> bytes) async {
    entered?.complete();
    await writeGate?.future;
    if (failWrite) throw StateError('write failed');
    if (partialWrite) {
      await super.write(handle, bytes.sublist(0, bytes.length ~/ 2));
      throw StateError('torn write');
    }
    await super.write(handle, bytes);
    if (lostWriteAck) throw StateError('write applied but reply lost');
  }

  @override
  Future<void> flush(RandomAccessFile handle) async {
    if (failFlush) throw StateError('flush failed');
    await super.flush(handle);
  }

  @override
  Future<void> close(RandomAccessFile handle) async {
    await super.close(handle);
    if (failClose) throw StateError('close acknowledgement lost');
  }
}

// Independent reference CRC with multiplication/division instead of shifts.
String crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc ~/ 2) ^ (crc.isOdd ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff).toRadixString(16).padLeft(8, '0');
}

List<int> framed(Map<String, Object?> record, {bool header = true}) {
  final payload = utf8.encode(jsonEncode(record));
  return [
    if (header) ...ascii.encode('RXCJ1\n'),
    ...ascii.encode('${payload.length}:${crc32(payload)}:'),
    ...payload,
    10
  ];
}

Map<String, Object?> record() => {
      'schema': 1,
      'sequence': 0,
      'backendNamespace': 'prod',
      'driverId': driver,
      'tripId': trip,
      'expectedTripVersion': 7,
      'idempotencyKey': 'original-key',
    };

// Top-level helpers keep non-sendable test gates out of isolate captures.
Future<CompletionJournalIssue> independentStage(String path) =>
    Isolate.run(() async {
      final store =
          FileDriverCompletionCommandStore(directory: Directory(path));
      final result = await store.stage(
          backendNamespace: 'prod', driverId: driver, command: command());
      return (result as CompletionBlocked).issue;
    });

Future<DriverCompleteTripCommand> independentInspect(String path) =>
    Isolate.run(() async {
      final store =
          FileDriverCompletionCommandStore(directory: Directory(path));
      final result = await store.inspect(
          backendNamespace: 'prod',
          driverId: driver,
          tripId: trip) as CompletionValid;
      return result.command;
    });

void main() {
  late Directory directory;
  late FileDriverCompletionCommandStore store;
  late FaultIo io;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ridex-journal-test-');
    io = FaultIo();
    store = FileDriverCompletionCommandStore(directory: directory, io: io);
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<CompletionStageResult> stage([DriverCompleteTripCommand? value]) =>
      store.stage(
          backendNamespace: 'prod',
          driverId: driver,
          command: value ?? command());
  Future<CompletionSlot> inspect([String id = trip]) =>
      store.inspect(backendNamespace: 'prod', driverId: driver, tripId: id);
  Future<File> journalFile() async => (await directory
          .list(recursive: true)
          .where((e) => e.path.endsWith('commands.rxcj'))
          .toList())
      .single as File;
  Future<File> seed(List<int> bytes) async {
    await stage();
    final file = await journalFile();
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  test('reference integrity checksum matches standard check vector', () {
    expect(crc32(ascii.encode('123456789')), 'cbf43926');
  });

  test('absent is distinct from a created and inspectable exact command',
      () async {
    expect(await inspect(), isA<CompletionAbsent>());
    final value = command(key: ' مفتاح🔑 ');
    expect((await stage(value) as CompletionCreated).command, value);
    expect((await inspect() as CompletionValid).command, value);
    final bytes = await (await journalFile()).readAsBytes();
    final expectedRecord = record()..['idempotencyKey'] = 'مفتاح🔑';
    expect(bytes, framed(expectedRecord));
  });

  test('recreation recovers original identity and creates no replacement key',
      () async {
    final value = command(key: 'caller-chosen-key');
    await stage(value);
    final before = await (await journalFile()).readAsBytes();
    final recreated = FileDriverCompletionCommandStore(directory: directory);
    final slot = await recreated.inspect(
        backendNamespace: 'prod',
        driverId: driver,
        tripId: trip) as CompletionValid;
    expect(slot.command.isExactReplayOf(value), isTrue);
    expect(
        await recreated.stage(
            backendNamespace: 'prod', driverId: driver, command: value),
        isA<CompletionExisting>());
    expect(await (await journalFile()).readAsBytes(), before);
  });

  test('duplicate staging does not append', () async {
    expect(await stage(), isA<CompletionCreated>());
    final before = await (await journalFile()).readAsBytes();
    expect(await stage(), isA<CompletionExisting>());
    expect(await (await journalFile()).readAsBytes(), before);
  });

  test('concurrent exact staging across instances acknowledges one creation',
      () async {
    final other = FileDriverCompletionCommandStore(
        directory: Directory('${directory.path}${Platform.pathSeparator}.'));
    final results = await Future.wait(List.generate(
        20,
        (i) => (i.isEven ? store : other).stage(
            backendNamespace: 'prod', driverId: driver, command: command())));
    expect(results.whereType<CompletionCreated>(), hasLength(1));
    expect(results.whereType<CompletionExisting>(), hasLength(19));
    expect(await (await journalFile()).readAsBytes(), framed(record()));
  });

  for (final candidate in [command(version: 8), command(key: 'other')]) {
    test(
        'occupied Trip rejects ${candidate.expectedTripVersion}/${candidate.idempotencyKey}',
        () async {
      await stage();
      final before = await (await journalFile()).readAsBytes();
      final result = await stage(candidate) as CompletionConflict;
      expect(result.kind, CompletionConflictKind.tripOccupied);
      expect(await (await journalFile()).readAsBytes(), before);
    });
  }

  test('competing instances never overwrite a winner', () async {
    final other = FileDriverCompletionCommandStore(directory: directory);
    final results = await Future.wait([
      stage(),
      other.stage(
          backendNamespace: 'prod',
          driverId: driver,
          command: command(version: 9))
    ]);
    expect(results.whereType<CompletionCreated>(), hasLength(1));
    expect(results.whereType<CompletionConflict>(), hasLength(1));
    final recovered = (await inspect() as CompletionValid).command;
    expect(recovered, results.whereType<CompletionCreated>().single.command);
  });

  test('same account key cannot identify a second Trip', () async {
    await stage();
    expect((await stage(command(id: otherTrip)) as CompletionConflict).kind,
        CompletionConflictKind.keyReused);
    expect(await inspect(otherTrip), isA<CompletionAbsent>());
    expect(await stage(command(id: otherTrip, key: 'second-key')),
        isA<CompletionCreated>());
    expect((await inspect(otherTrip) as CompletionValid).command.tripId,
        otherTrip);
  });

  test('account and backend namespaces isolate identical keys and Trip IDs',
      () async {
    await stage();
    for (final identity in [
      ('prod', otherDriver),
      ('test', driver),
      ('Prod', driver)
    ]) {
      expect(
          await store.inspect(
              backendNamespace: identity.$1,
              driverId: identity.$2,
              tripId: trip),
          isA<CompletionAbsent>());
      expect(
          await store.stage(
              backendNamespace: identity.$1,
              driverId: identity.$2,
              command: command(version: 9)),
          isA<CompletionCreated>());
    }
    expect((await inspect() as CompletionValid).command.expectedTripVersion, 7);
  });

  test('UUID aliases share ownership but do not rewrite exact command identity',
      () async {
    await stage();
    expect(
        await store.stage(
            backendNamespace: 'prod',
            driverId: driver.toUpperCase(),
            command: command()),
        isA<CompletionExisting>());
    expect(await stage(command(id: trip.toUpperCase())),
        isA<CompletionConflict>());
    expect(
        (await inspect(trip.toUpperCase()) as CompletionValid).command.tripId,
        trip);
  });

  test('invalid identities and traversal fail before any filesystem access',
      () async {
    for (final identity in [
      ('../prod', driver),
      ('prod', '../$driver'),
      ('prod\\test', driver),
      ('prod', 'driver-1')
    ]) {
      expect(
          await store.stage(
              backendNamespace: identity.$1,
              driverId: identity.$2,
              command: command()),
          isA<CompletionBlocked>());
      expect(
          await store.inspect(
              backendNamespace: identity.$1,
              driverId: identity.$2,
              tripId: trip),
          isA<CompletionUnavailable>());
    }
    expect(await inspect('../$trip'), isA<CompletionUnavailable>());
    expect(await directory.list().toList(), isEmpty);
  });

  final damaged = <String, List<int>>{
    'empty': [],
    'magic only': ascii.encode('RXCJ1\n'),
    'malformed': ascii.encode('arbitrary raw private data'),
    'truncated': framed(record()).sublist(0, framed(record()).length - 3),
    'trailing garbage': [...framed(record()), 99],
    'checksum mismatch': [
      ...framed(record()).take(framed(record()).length - 2),
      88,
      10
    ],
    'invalid length': ascii.encode('RXCJ1\n999999:00000000:{}\n'),
  };
  for (final entry in damaged.entries) {
    test('${entry.key} evidence remains corrupt, preserved, and never absent',
        () async {
      final file = await seed(entry.value);
      expect(await inspect(), isA<CompletionCorrupt>());
      expect(await stage(), isA<CompletionBlocked>());
      expect(await file.readAsBytes(), entry.value);
    });
  }

  final invalidRecords =
      <String, (Map<String, Object?>, CompletionJournalIssue)>{
    'schema': (
      record()..['schema'] = 2,
      CompletionJournalIssue.unsupportedSchema
    ),
    'driver': (
      record()..['driverId'] = otherDriver,
      CompletionJournalIssue.ownershipMismatch
    ),
    'backend': (
      record()..['backendNamespace'] = 'test',
      CompletionJournalIssue.ownershipMismatch
    ),
    'sequence': (
      record()..['sequence'] = 1,
      CompletionJournalIssue.invalidRecord
    ),
    'version': (
      record()..['expectedTripVersion'] = 0,
      CompletionJournalIssue.invalidRecord
    ),
    'trimmed key': (
      record()..['idempotencyKey'] = ' key ',
      CompletionJournalIssue.invalidRecord
    ),
    'extra field': (
      record()..['paymentStatus'] = 'paid',
      CompletionJournalIssue.invalidRecord
    ),
  };
  for (final entry in invalidRecords.entries) {
    test('${entry.key} rejected even with a valid checksum', () async {
      final bytes = framed(entry.value.$1);
      final file = await seed(bytes);
      expect((await inspect() as CompletionCorrupt).issue, entry.value.$2);
      expect(await stage(), isA<CompletionBlocked>());
      expect(await file.readAsBytes(), bytes);
    });
  }

  test(
      'duplicate or conflicting on-disk records invalidate the account journal',
      () async {
    for (final second in [
      record()..['sequence'] = 1,
      record()
        ..['sequence'] = 1
        ..['tripId'] = otherTrip
    ]) {
      final bytes = [...framed(record()), ...framed(second, header: false)];
      final file = await seed(bytes);
      expect((await inspect() as CompletionCorrupt).issue,
          CompletionJournalIssue.conflictingEvidence);
      expect(await file.readAsBytes(), bytes);
      // Test-only reset; production exposes no repair/delete capability.
      await file.writeAsBytes(framed(record()), flush: true);
    }
  });

  test('read errors never become absence or expose raw errors', () async {
    await stage();
    io.failReadAt = io.reads + 1;
    final slot = await inspect() as CompletionUnavailable;
    expect(slot.issue, CompletionJournalIssue.storageUnavailable);
    io.failReadAt = io.reads + 1;
    expect(await stage(), isA<CompletionBlocked>());
    expect((await inspect() as CompletionValid).command, command());
  });

  test('partial append preserves the prior prefix and blocks the whole account',
      () async {
    await stage();
    final file = await journalFile();
    final before = await file.readAsBytes();
    io.partialWrite = true;
    expect(await stage(command(id: otherTrip, key: 'second-key')),
        isA<CompletionBlocked>());
    final after = await file.readAsBytes();
    expect(after.take(before.length), before);
    expect(after.length, greaterThan(before.length));
    expect(await inspect(), isA<CompletionCorrupt>());
    expect(await inspect(otherTrip), isA<CompletionCorrupt>());
    expect(await file.readAsBytes(), after);
  });

  test('non-regular journal evidence is unavailable and never replaced',
      () async {
    await inspect();
    final file = io.journal!;
    await Directory(file.path).create();
    expect(await inspect(), isA<CompletionUnavailable>());
    expect(await stage(), isA<CompletionBlocked>());
    expect(await Directory(file.path).exists(), isTrue);
  });

  test(
      'oversized evidence blocks without overwriting or loading an unbounded file',
      () async {
    final bytes = List<int>.filled(
        FileDriverCompletionCommandStore.maxJournalBytes + 1, 0);
    final file = await seed(bytes);
    expect(await inspect(), isA<CompletionUnavailable>());
    expect(await stage(), isA<CompletionBlocked>());
    expect(await file.length(), bytes.length);
  });

  test('checksum-valid non-JSON and non-object payloads remain corrupt',
      () async {
    for (final payload in [
      ascii.encode('{broken'),
      ascii.encode('[]'),
      [255]
    ]) {
      final bytes = [
        ...ascii.encode('RXCJ1\n${payload.length}:${crc32(payload)}:'),
        ...payload,
        10
      ];
      final file = await seed(bytes);
      expect((await inspect() as CompletionCorrupt).issue,
          CompletionJournalIssue.invalidRecord);
      expect(await file.readAsBytes(), bytes);
      await file.writeAsBytes(framed(record()), flush: true);
    }
  });

  test('directory and synchronization failures block, without raw errors',
      () async {
    io.failPrepare = true;
    expect((await inspect() as CompletionUnavailable).issue,
        CompletionJournalIssue.storageUnavailable);
    expect(await stage(), isA<CompletionBlocked>());
    io.failPrepare = false;
    io.failAcquire = true;
    expect((await stage() as CompletionBlocked).issue,
        CompletionJournalIssue.synchronizationUnavailable);
    expect(await inspect(), isA<CompletionUnavailable>());
    expect(
        await directory.list(recursive: true).where((e) => e is File).toList(),
        isEmpty);
  });

  for (final fault in [
    'open',
    'write',
    'partial',
    'ack',
    'flush',
    'close',
    'readback',
    'changed'
  ]) {
    test('$fault failure cannot acknowledge persistence', () async {
      switch (fault) {
        case 'open':
          io.failOpen = true;
        case 'write':
          io.failWrite = true;
        case 'partial':
          io.partialWrite = true;
        case 'ack':
          io.lostWriteAck = true;
        case 'flush':
          io.failFlush = true;
        case 'close':
          io.failClose = true;
        case 'readback':
          io.failReadAt = 2;
        case 'changed':
          io.changeReadback = true;
      }
      final result = await stage() as CompletionBlocked;
      expect(result.issue, CompletionJournalIssue.persistenceUncertain);
      final recreated = FileDriverCompletionCommandStore(directory: directory);
      final slot = await recreated.inspect(
          backendNamespace: 'prod', driverId: driver, tripId: trip);
      if (fault == 'partial' || fault == 'write') {
        expect(slot, isA<CompletionCorrupt>());
      } else if (fault == 'open') {
        expect(slot, isA<CompletionAbsent>());
      } else {
        expect((slot as CompletionValid).command, command());
        expect(
            await recreated.stage(
                backendNamespace: 'prod', driverId: driver, command: command()),
            isA<CompletionExisting>());
      }
    });
  }

  test('existing-record flush or acknowledgement failure remains blocked',
      () async {
    await stage();
    io.failFlush = true;
    expect((await stage() as CompletionBlocked).issue,
        CompletionJournalIssue.persistenceUncertain);
    expect(await inspect(), isA<CompletionUnavailable>());
    io.failFlush = false;
    expect(await stage(), isA<CompletionExisting>());
  });

  test('release failure retains lock and blocks recreated stores', () async {
    io.failRelease = true;
    expect((await stage() as CompletionBlocked).issue,
        CompletionJournalIssue.synchronizationUnavailable);
    final recreated = FileDriverCompletionCommandStore(directory: directory);
    expect(
        await recreated.inspect(
            backendNamespace: 'prod', driverId: driver, tripId: trip),
        isA<CompletionUnavailable>());
    expect(
        await recreated.stage(
            backendNamespace: 'prod', driverId: driver, command: command()),
        isA<CompletionBlocked>());
    expect(await (await journalFile()).readAsBytes(), framed(record()));
  });

  test('lost release acknowledgement is uncertain even if the sentinel is gone',
      () async {
    io.lostReleaseAck = true;
    expect((await stage() as CompletionBlocked).issue,
        CompletionJournalIssue.synchronizationUnavailable);
    io.lostReleaseAck = false;
    expect(await stage(), isA<CompletionExisting>());
  });

  test('separate-isolate writer fails closed while another owns the sentinel',
      () async {
    io.entered = Completer<void>();
    io.writeGate = Completer<void>();
    final pending = stage();
    await io.entered!.future;
    final path = directory.path;
    try {
      expect(await independentStage(path),
          CompletionJournalIssue.synchronizationUnavailable);
    } finally {
      io.writeGate!.complete();
      expect(await pending, isA<CompletionCreated>());
    }
    final recovered = await independentInspect(path);
    expect(recovered.isExactReplayOf(command()), isTrue);
  });
}
