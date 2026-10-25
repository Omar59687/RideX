import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';

/// Trusted I/O seam for deterministic fault tests. Production defaults to
/// [NativeCompletionJournalIo]. A replacement must honor exclusive creation,
/// append-only writes and flush semantics; an in-memory fake proves no durability.
class NativeCompletionJournalIo {
  const NativeCompletionJournalIo();

  Future<String> prepare(Directory directory) async {
    await directory.create(recursive: true);
    return directory.resolveSymbolicLinks();
  }

  Future<void> acquire(File lock) async {
    await lock.create(exclusive: true);
  }

  /// Deletes only an acquired synchronization sentinel, never command evidence.
  Future<void> release(File lock) async {
    await lock.delete();
  }

  Future<Uint8List?> read(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      // Dart's type() collapses lookup errors into notFound. Require a
      // successful parent enumeration before declaring absence; an entry
      // whose type could not be inspected is unavailable, never absent.
      final name = file.uri.pathSegments.last;
      await for (final entry in file.parent.list(followLinks: false)) {
        final candidate =
            entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (Platform.isWindows
            ? candidate.toLowerCase() == name.toLowerCase()
            : candidate == name) {
          throw const FileSystemException('Journal entry is unreadable.');
        }
      }
      return null;
    }
    if (type != FileSystemEntityType.file ||
        await file.length() >
            FileDriverCompletionCommandStore.maxJournalBytes) {
      throw const FileSystemException('Journal cannot be read safely.');
    }
    return file.readAsBytes();
  }

  Future<RandomAccessFile> openAppend(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FileSystemException('Journal is not a regular file.');
    }
    return file.open(mode: FileMode.append);
  }

  Future<void> write(RandomAccessFile handle, List<int> bytes) async {
    await handle.writeFrom(bytes);
  }

  Future<void> flush(RandomAccessFile handle) => handle.flush();
  Future<void> close(RandomAccessFile handle) => handle.close();
}

/// Native, append-only account journal. No Flutter, provider or backend I/O.
///
/// Scope: same-isolate callers queue by resolved account-directory path
/// (case-folded on Windows), including different instances and directory aliases.
/// All cooperating callers also require an exclusively CREATED lock file.
/// Other isolates/processes fail closed while that sentinel exists; they do
/// not wait or steal it. A crash can leave a stale sentinel, which blocks until
/// a separately authorized recovery procedure exists. No automatic cleanup.
/// Assumes a private, local filesystem honoring exclusive file creation; no
/// network filesystem or adversarial concurrent directory mutation support.
/// This serializes STORAGE only, not completion RPCs or provider lifecycles.
///
/// Protocol: `RXCJ1\n`, followed by frames `byteLength:CRC32hex:JSON\n`.
/// JSON includes schema, sequence, namespace, Driver and exact command triple.
/// CRC32 detects accidental damage, not malicious edits. Every frame, sequence,
/// identity and uniqueness constraint is checked before any record is returned.
/// A partial tail, empty existing file or unsupported schema blocks the entire
/// account journal without repair. Complete-tail deletion/rollback cannot be
/// detected without an external durable anchor.
///
/// Acknowledgement requires append (if new), flush, close, exact readback, and
/// successful sentinel release. Existing evidence is flushed again before
/// acknowledgement, including after a previous lost acknowledgement. Any
/// ambiguous operation returns unavailable/blocked. No evidence is truncated.
/// File flush is NOT directory fsync or a universal power-loss guarantee:
/// filesystem/device caches, directory-entry loss, app-data loss and backup
/// rollback remain limitations. Host tests establish bounded persistence, not
/// production-ready crash recovery, web support or cross-device coordination.
class FileDriverCompletionCommandStore implements DriverCompletionCommandStore {
  FileDriverCompletionCommandStore({
    required Directory directory,
    NativeCompletionJournalIo io = const NativeCompletionJournalIo(),
  })  : _directory = directory,
        _io = io;

  static const maxJournalBytes = 4 * 1024 * 1024;
  static const maxJournalCommands = 1024;
  static const _magic = 'RXCJ1\n';
  static final Map<String, Future<void>> _queues = {};
  final Directory _directory;
  final NativeCompletionJournalIo _io;

  @override
  Future<CompletionDriverSnapshot> inspectDriver({
    required String backendNamespace,
    required String driverId,
  }) async {
    if (!isCompletionJournalIdentityValid(
      backendNamespace: backendNamespace,
      driverId: driverId,
      tripId: driverId,
    )) {
      return const CompletionDriverUnavailable(
          CompletionJournalIssue.invalidIdentity);
    }
    try {
      // Recovery reads the command journal without creating directories or
      // lock sentinels, flushing, appending, repairing or retiring evidence.
      // A concurrent partial append fails closed and can be read again later.
      final root = _directory.absolute;
      final rootExists = await _directoryExistsSafely(root);
      if (rootExists == null) {
        return const CompletionDriverUnavailable(
            CompletionJournalIssue.storageUnavailable);
      }
      if (!rootExists) return const CompletionDriverCommands([]);
      final rootPath = await root.resolveSymbolicLinks();
      final rootKey = _pathKey(rootPath);
      final encoded = utf8
          .encode(backendNamespace)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final backendDir = Directory.fromUri(
          Directory(rootPath).uri.resolve('backend-$encoded/'));
      final backendExists = await _directoryExistsSafely(backendDir);
      if (backendExists == null) {
        return const CompletionDriverUnavailable(
            CompletionJournalIssue.storageUnavailable);
      }
      if (!backendExists) return const CompletionDriverCommands([]);
      final backendPath = await backendDir.resolveSymbolicLinks();
      if (!_pathKey(backendPath).startsWith('$rootKey/')) {
        return const CompletionDriverUnavailable(
            CompletionJournalIssue.storageUnavailable);
      }
      final accountDir = Directory.fromUri(Directory(backendPath)
          .uri
          .resolve('driver-${driverId.toLowerCase()}/'));
      final accountExists = await _directoryExistsSafely(accountDir);
      if (accountExists == null) {
        return const CompletionDriverUnavailable(
            CompletionJournalIssue.storageUnavailable);
      }
      if (!accountExists) return const CompletionDriverCommands([]);
      final accountPath = await accountDir.resolveSymbolicLinks();
      if (!_pathKey(accountPath).startsWith('$rootKey/')) {
        return const CompletionDriverUnavailable(
            CompletionJournalIssue.storageUnavailable);
      }
      final file =
          File.fromUri(Directory(accountPath).uri.resolve('commands.rxcj'));
      const lockName = 'writer.lock';
      var lockPresent = false;
      await for (final entry
          in Directory(accountPath).list(followLinks: false)) {
        final candidate =
            entry.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
        if (Platform.isWindows
            ? candidate.toLowerCase() == lockName.toLowerCase()
            : candidate == lockName) {
          lockPresent = true;
          break;
        }
      }
      if (lockPresent) {
        return const CompletionDriverUnavailable(
            CompletionJournalIssue.synchronizationUnavailable);
      }
      final records = _decode(await _io.read(file), backendNamespace, driverId);
      if (records.length > maxJournalCommands) {
        return const CompletionDriverUnavailable(
            CompletionJournalIssue.sizeLimit);
      }
      return CompletionDriverCommands(List.unmodifiable(records.values));
    } on _Corrupt catch (error) {
      return CompletionDriverUnavailable(error.issue);
    } on Object {
      return const CompletionDriverUnavailable(
          CompletionJournalIssue.storageUnavailable);
    }
  }

  Future<bool?> _directoryExistsSafely(Directory directory) async {
    final type =
        await FileSystemEntity.type(directory.path, followLinks: false);
    if (type == FileSystemEntityType.directory) return true;
    if (type != FileSystemEntityType.notFound) return null;
    final name =
        directory.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
    await for (final entry in directory.parent.list(followLinks: false)) {
      final candidate =
          entry.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
      if (Platform.isWindows
          ? candidate.toLowerCase() == name.toLowerCase()
          : candidate == name) {
        return null;
      }
    }
    return false;
  }

  @override
  Future<CompletionSlot> inspect({
    required String backendNamespace,
    required String driverId,
    required String tripId,
  }) async {
    if (!_valid(backendNamespace, driverId, tripId)) {
      return const CompletionUnavailable(
          CompletionJournalIssue.invalidIdentity);
    }
    return _access<CompletionSlot>(
        backendNamespace, driverId, (issue) => CompletionUnavailable(issue),
        (file) async {
      final bytes = await _io.read(file);
      final records = _decode(bytes, backendNamespace, driverId);
      await _acknowledge(file, bytes);
      final command = records[tripId.toLowerCase()];
      return command == null
          ? const CompletionAbsent()
          : CompletionValid(command);
    }, corrupt: (issue) => CompletionCorrupt(issue));
  }

  @override
  Future<CompletionStageResult> stage({
    required String backendNamespace,
    required String driverId,
    required DriverCompleteTripCommand command,
  }) async {
    if (!_valid(backendNamespace, driverId, command.tripId)) {
      return const CompletionBlocked(CompletionJournalIssue.invalidIdentity);
    }
    return _access<CompletionStageResult>(
        backendNamespace, driverId, (issue) => CompletionBlocked(issue),
        (file) async {
      final bytes = await _io.read(file);
      final records = _decode(bytes, backendNamespace, driverId);
      final existing = records[command.tripId.toLowerCase()];
      if (existing != null) {
        if (!existing.isExactReplayOf(command)) {
          return const CompletionConflict(CompletionConflictKind.tripOccupied);
        }
        await _acknowledge(file, bytes);
        return CompletionExisting(existing);
      }
      if (records.values
          .any((c) => c.idempotencyKey == command.idempotencyKey)) {
        return const CompletionConflict(CompletionConflictKind.keyReused);
      }
      final frame =
          _encode(backendNamespace, driverId, command, records.length);
      final expected = <int>[
        ...?bytes,
        if (bytes == null) ...utf8.encode(_magic),
        ...frame
      ];
      if (expected.length > maxJournalBytes) {
        return const CompletionBlocked(CompletionJournalIssue.sizeLimit);
      }
      try {
        await _sync(file,
            bytes: [if (bytes == null) ...utf8.encode(_magic), ...frame]);
        if (!_same(await _io.read(file), expected)) {
          return const CompletionBlocked(
              CompletionJournalIssue.persistenceUncertain);
        }
      } on Object {
        return const CompletionBlocked(
            CompletionJournalIssue.persistenceUncertain);
      }
      return CompletionCreated(command);
    }, corrupt: (issue) => CompletionBlocked(issue));
  }

  bool _valid(String namespace, String driver, String trip) =>
      isCompletionJournalIdentityValid(
          backendNamespace: namespace, driverId: driver, tripId: trip);

  Future<T> _access<T>(
      String namespace,
      String driver,
      T Function(CompletionJournalIssue) blocked,
      Future<T> Function(File) action,
      {required T Function(CompletionJournalIssue) corrupt}) async {
    final String account;
    try {
      final root = await _io.prepare(_directory);
      // Hex encoding is injective and contains no separators or reserved names.
      final encoded = utf8
          .encode(namespace)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final rootKey = _pathKey(root);
      final backend = await _io.prepare(
          Directory.fromUri(Directory(root).uri.resolve('backend-$encoded/')));
      if (!_pathKey(backend).startsWith('$rootKey/')) {
        return blocked(CompletionJournalIssue.storageUnavailable);
      }
      account = await _io.prepare(Directory.fromUri(
          Directory(backend).uri.resolve('driver-${driver.toLowerCase()}/')));
      if (!_pathKey(account).startsWith('$rootKey/')) {
        return blocked(CompletionJournalIssue.storageUnavailable);
      }
    } on Object {
      return blocked(CompletionJournalIssue.storageUnavailable);
    }
    final key = _pathKey(account);
    final previous = _queues[key] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[key] = done.future;
    await previous;
    try {
      final lock = File.fromUri(Directory(account).uri.resolve('writer.lock'));
      try {
        await _io.acquire(lock);
      } on Object {
        return blocked(CompletionJournalIssue.synchronizationUnavailable);
      }
      T result;
      try {
        result = await action(
            File.fromUri(Directory(account).uri.resolve('commands.rxcj')));
      } on _Corrupt catch (error) {
        result = corrupt(error.issue);
      } on _Uncertain {
        result = blocked(CompletionJournalIssue.persistenceUncertain);
      } on Object {
        result = blocked(CompletionJournalIssue.storageUnavailable);
      }
      try {
        await _io.release(lock);
      } on Object {
        return blocked(CompletionJournalIssue.synchronizationUnavailable);
      }
      return result;
    } finally {
      done.complete();
      if (identical(_queues[key], done.future)) _queues.remove(key);
    }
  }

  static String _pathKey(String path) {
    final value = path.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  Future<void> _sync(File file, {List<int>? bytes}) async {
    final handle = await _io.openAppend(file);
    try {
      if (bytes != null) await _io.write(handle, bytes);
      await _io.flush(handle);
    } finally {
      await _io.close(handle);
    }
  }

  Future<void> _acknowledge(File file, List<int>? bytes) async {
    if (bytes == null) return;
    try {
      await _sync(file);
      if (!_same(await _io.read(file), bytes)) throw const _Uncertain();
    } on Object {
      throw const _Uncertain();
    }
  }

  static bool _same(List<int>? a, List<int> b) =>
      a != null &&
      a.length == b.length &&
      Iterable<int>.generate(b.length).every((i) => a[i] == b[i]);

  static List<int> _encode(String namespace, String driver,
      DriverCompleteTripCommand command, int sequence) {
    final payload = utf8.encode(jsonEncode({
      'schema': 1,
      'sequence': sequence,
      'backendNamespace': namespace,
      'driverId': driver.toLowerCase(),
      'tripId': command.tripId,
      'expectedTripVersion': command.expectedTripVersion,
      'idempotencyKey': command.idempotencyKey,
    }));
    return [
      ...ascii.encode('${payload.length}:${_crc(payload)}:'),
      ...payload,
      10
    ];
  }

  static Map<String, DriverCompleteTripCommand> _decode(
      List<int>? bytes, String namespace, String driver) {
    if (bytes == null) return {};
    Never bad(CompletionJournalIssue issue) => throw _Corrupt(issue);
    if (bytes.length > maxJournalBytes) bad(CompletionJournalIssue.sizeLimit);
    final magic = ascii.encode(_magic);
    if (bytes.length <= magic.length ||
        !_same(bytes.take(magic.length).toList(), magic)) {
      bad(CompletionJournalIssue.invalidFrame);
    }
    final records = <String, DriverCompleteTripCommand>{};
    final keys = <String>{};
    var offset = magic.length;
    while (offset < bytes.length) {
      final start = offset;
      while (
          offset < bytes.length && bytes[offset] != 58 && offset - start < 6) {
        offset++;
      }
      if (offset == bytes.length || bytes[offset] != 58) {
        bad(CompletionJournalIssue.invalidFrame);
      }
      final lengthText = String.fromCharCodes(bytes.sublist(start, offset));
      final length = int.tryParse(lengthText);
      if (length == null ||
          length <= 0 ||
          length > 4096 ||
          length.toString() != lengthText) {
        bad(CompletionJournalIssue.invalidFrame);
      }
      offset++;
      if (offset + 9 + length + 1 > bytes.length || bytes[offset + 8] != 58) {
        bad(CompletionJournalIssue.invalidFrame);
      }
      final crc = String.fromCharCodes(bytes.sublist(offset, offset + 8));
      offset += 9;
      final payload = bytes.sublist(offset, offset + length);
      offset += length;
      if (bytes[offset++] != 10 || crc != _crc(payload)) {
        bad(CompletionJournalIssue.invalidFrame);
      }
      try {
        final json = jsonDecode(utf8.decode(payload));
        if (json is! Map<String, dynamic>) {
          bad(CompletionJournalIssue.invalidRecord);
        }
        if (json['schema'] != 1 || json['schema'] is! int) {
          bad(CompletionJournalIssue.unsupportedSchema);
        }
        if (json.length != 7 ||
            json['sequence'] is! int ||
            json['sequence'] != records.length ||
            json['tripId'] is! String ||
            json['expectedTripVersion'] is! int ||
            json['idempotencyKey'] is! String) {
          bad(CompletionJournalIssue.invalidRecord);
        }
        if (json['backendNamespace'] != namespace ||
            json['driverId'] != driver.toLowerCase()) {
          bad(CompletionJournalIssue.ownershipMismatch);
        }
        final command = DriverCompleteTripCommand(
            tripId: json['tripId'],
            expectedTripVersion: json['expectedTripVersion'],
            idempotencyKey: json['idempotencyKey']);
        if (command.tripId != json['tripId'] ||
            command.idempotencyKey != json['idempotencyKey']) {
          bad(CompletionJournalIssue.invalidRecord);
        }
        if (records.containsKey(command.tripId.toLowerCase()) ||
            !keys.add(command.idempotencyKey)) {
          bad(CompletionJournalIssue.conflictingEvidence);
        }
        records[command.tripId.toLowerCase()] = command;
      } on _Corrupt {
        rethrow;
      } on Object {
        bad(CompletionJournalIssue.invalidRecord);
      }
    }
    return records;
  }

  static String _crc(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
      }
    }
    return ((crc ^ 0xffffffff) & 0xffffffff).toRadixString(16).padLeft(8, '0');
  }
}

class _Corrupt implements Exception {
  const _Corrupt(this.issue);
  final CompletionJournalIssue issue;
}

class _Uncertain implements Exception {
  const _Uncertain();
}
