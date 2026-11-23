import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/canonical_trip_reconciliation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/services/trips/driver_completion_staging_gateway.dart';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'package:ridex/features/trips/application/driver_completion_recovery_coordinator.dart';
import 'driver_readonly_recovery_test.dart' as f;

class ProtocolIo extends NativeCompletionJournalIo {
  ProtocolIo(this.events, {this.fault});
  final List<String> events;
  final String? fault;
  int reads = 0;
  @override
  Future<void> write(RandomAccessFile handle, List<int> bytes) async {
    events.add('write');
    if (fault == 'write') throw StateError('write');
    await super.write(handle, bytes);
  }

  @override
  Future<void> flush(RandomAccessFile handle) async {
    events.add('flush');
    if (fault == 'flush') throw StateError('flush');
    await super.flush(handle);
  }

  @override
  Future<void> close(RandomAccessFile handle) async {
    await super.close(handle);
    events.add('close');
    if (fault == 'close') throw StateError('close acknowledgement');
  }

  @override
  Future<Uint8List?> read(File file) async {
    events.add(++reads == 1 ? 'read' : 'readback');
    if (reads > 1 && fault == 'readback') throw StateError('readback');
    return super.read(file);
  }

  @override
  Future<void> release(File lock) async {
    events.add('release');
    await super.release(lock);
    if (fault == 'release') throw StateError('release acknowledgement');
  }
}

void main() {
  group('C03 recovery evidence guards', () {
    late CanonicalTripReadSession current;
    late f.Journal journal;
    late f.Reader reader;
    late DriverCompletionRecoveryCoordinator recovery;
    setUp(() {
      current = f.session();
      journal = f.Journal();
      reader = f.Reader(current);
      recovery = DriverCompletionRecoveryCoordinator(
          tripId: f.trip,
          owner: current,
          journal: journal,
          repository: reader,
          sessionReader: () => current);
    });
    tearDown(() {
      recovery.dispose();
      expect(journal.stages, 0);
    });
    for (final change in ['logout', 'B', 'A-B-A', 'revoked']) {
      test(
          'cached current cannot survive $change without another recovery call',
          () async {
        await recovery.recover();
        expect(recovery.current, isNotNull);
        switch (change) {
          case 'logout':
            current = f.session(id: null, epoch: 2);
          case 'B':
            current = f.session(id: f.otherDriver, epoch: 2);
          case 'A-B-A':
            current = f.session(epoch: 3);
          case 'revoked':
            current = f.session(approved: false);
        }
        expect(recovery.current, isNull);
        expect(reader.commands, hasLength(1));
      });
    }
    test('completed at original inProgress version is conflicting, not success',
        () async {
      reader.handler = () async => f.visible(current, version: 4);
      final result = await recovery.recover();
      expect(result.disposition,
          DriverReadOnlyRecoveryDisposition.conflictingEvidence);
      expect(result.strongestTrip, isNull);
    });
    for (final terminal in [
      DriverTripLifecycleStatus.completed,
      DriverTripLifecycleStatus.cancelledByRider,
      DriverTripLifecycleStatus.cancelledByDriver,
      DriverTripLifecycleStatus.cancelledByAdmin,
      DriverTripLifecycleStatus.failed
    ]) {
      test('terminal $terminal cannot change status at a newer version',
          () async {
        reader.handler =
            () async => f.visible(current, status: terminal, version: 5);
        final first = await recovery.recover();
        reader.handler = () async => f.visible(current,
            status: terminal == DriverTripLifecycleStatus.completed
                ? DriverTripLifecycleStatus.inProgress
                : DriverTripLifecycleStatus.completed,
            version: 6);
        final next = await recovery.recover();
        expect(next.disposition,
            DriverReadOnlyRecoveryDisposition.conflictingEvidence);
        expect(next.strongestTrip, same(first.strongestTrip));
      });
    }
  });

  group('C03 native journal to coordinator protocol', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ridex-c03-protocol-');
    });
    tearDown(() async {
      expect(directory.absolute.path, contains('ridex-c03-protocol-'));
      await directory.delete(recursive: true);
    });
    DriverCompletionCoordinator coordinator(
            FileDriverCompletionCommandStore store, f.CompletionRepo repository,
            {Future<DriverCompletionSessionSnapshot> Function()? session}) =>
        DriverCompletionCoordinator(
            canonicalSource: f.Source(),
            stagingGateway: JournalDriverCompletionStagingGateway(
                backendNamespace: f.backend,
                driverId: f.driver,
                openStore: () async => store),
            repository: repository,
            sessionReader: session ??
                () async => const DriverCompletionSessionSnapshot(
                    driverId: f.driver, epoch: 1, isApprovedDriver: true));

    for (final fault in ['write', 'flush', 'close', 'readback', 'release']) {
      test('$fault failure prevents dispatch through the actual gateway',
          () async {
        final repo = f.CompletionRepo();
        final store = FileDriverCompletionCommandStore(
            directory: directory, io: ProtocolIo([], fault: fault));
        final owner = coordinator(store, repo);
        expect(await owner.complete(), isA<CoordinatorBlocked>());
        expect(repo.calls, 0);
        owner.dispose();
      });
    }
    test(
        'actual write flush close readback release all precede dispatch and duplicate calls',
        () async {
      final events = <String>[];
      final store = FileDriverCompletionCommandStore(
          directory: directory, io: ProtocolIo(events));
      final repo = _RecordingRepo(events);
      final owner = coordinator(store, repo);
      final one = owner.complete();
      expect(identical(one, owner.complete()), isTrue);
      expect(await one, isA<CoordinatorCompleted>());
      expect(events, [
        'read',
        'write',
        'flush',
        'close',
        'readback',
        'release',
        'dispatch'
      ]);
      expect(repo.calls, 1);
      owner.dispose();
    });

    for (final switchBack in [false, true]) {
      test(
          'native UNKNOWN survives A-to-B${switchBack ? '-to-A' : ''} and late success',
          () async {
        var session = const DriverCompletionSessionSnapshot(
            driverId: f.driver, epoch: 1, isApprovedDriver: true);
        final store = FileDriverCompletionCommandStore(directory: directory);
        final repo = _PendingRepo();
        final old = coordinator(store, repo, session: () async => session);
        final pending = old.complete();
        await repo.entered.future;
        session = const DriverCompletionSessionSnapshot(
            driverId: f.otherDriver, epoch: 2, isApprovedDriver: true);
        if (switchBack) {
          session = const DriverCompletionSessionSnapshot(
              driverId: f.driver, epoch: 3, isApprovedDriver: true);
        }
        final readOwner = f.session(id: session.driverId, epoch: session.epoch);
        final reader = f.Reader(readOwner);
        final recovery = DriverCompletionRecoveryCoordinator(
            tripId: f.trip,
            owner: readOwner,
            journal: FileDriverCompletionCommandStore(directory: directory),
            repository: reader,
            sessionReader: () => readOwner);
        final recovered = await recovery.recover();
        expect(
            recovered.disposition,
            switchBack
                ? DriverReadOnlyRecoveryDisposition.completedTrip
                : DriverReadOnlyRecoveryDisposition.noJournalEvidence);
        expect(reader.commands.length, switchBack ? 1 : 0);
        repo.response.complete(f.completed(version: 99));
        expect(await pending, isA<CoordinatorInvalidated>());
        expect(old.current, isNull);
        expect(recovery.current, same(recovered));
        if (switchBack) {
          expect(recovery.current!.strongestTrip!.backendVersion, 9);
        }
        expect(repo.calls, 1);
        final replacement = coordinator(
            FileDriverCompletionCommandStore(directory: directory), repo,
            session: () async => const DriverCompletionSessionSnapshot(
                driverId: f.driver, epoch: 3, isApprovedDriver: true));
        expect(await replacement.complete(), isA<CoordinatorUnresolved>());
        expect(repo.calls, 1);
        old.dispose();
        recovery.dispose();
        replacement.dispose();
      });
    }

    for (final mode in ['flush-exit', 'staged-exit', 'lost-response']) {
      test('abrupt child $mode preserves evidence and restart never dispatches',
          () async {
        final packages = File('.dart_tool/package_config.json').absolute;
        final config =
            jsonDecode(await packages.readAsString()) as Map<String, dynamic>;
        final flutter = (config['packages'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((p) => p['name'] == 'flutter');
        final sdk = Directory.fromUri(
                packages.uri.resolve(flutter['rootUri'] as String))
            .parent
            .parent;
        final dart = File.fromUri(sdk.uri.resolve(
            'bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}'));
        final result = await Process.run(dart.path, [
          '--packages=${File('.dart_tool/package_config.json').absolute.path}',
          File('test/helpers/driver_completion_crash_worker.dart')
              .absolute
              .path,
          directory.path,
          mode,
        ]).timeout(const Duration(seconds: 30));
        expect(
            result.exitCode,
            mode == 'flush-exit'
                ? 74
                : mode == 'staged-exit'
                    ? 73
                    : 75,
            reason: '${result.stdout} ${result.stderr}');
        final files = await directory
            .list(recursive: true)
            .where((e) => e.path.endsWith('commands.rxcj'))
            .toList();
        final evidence = files.single as File;
        final before = await evidence.readAsBytes();
        final marker =
            File.fromUri(directory.uri.resolve('fake-dispatch.marker'));
        expect(await marker.exists(), mode == 'lost-response');
        final repo = f.CompletionRepo();
        final freshStore =
            FileDriverCompletionCommandStore(directory: directory);
        final fresh = coordinator(freshStore, repo);
        final outcome = await fresh.complete();
        expect(
            outcome,
            mode == 'flush-exit'
                ? isA<CoordinatorBlocked>()
                : isA<CoordinatorUnresolved>());
        expect(repo.calls, 0);
        final reader = f.Reader(f.session())
          ..handler = () async => f.visible(f.session(),
              status: mode == 'lost-response'
                  ? DriverTripLifecycleStatus.completed
                  : DriverTripLifecycleStatus.inProgress,
              version: mode == 'lost-response' ? 5 : 4);
        final recovery = DriverCompletionRecoveryCoordinator(
            tripId: f.trip,
            owner: f.session(),
            journal: freshStore,
            repository: reader,
            sessionReader: f.session);
        final recovered = await recovery.recover();
        expect(
            recovered.disposition,
            mode == 'flush-exit'
                ? DriverReadOnlyRecoveryDisposition.journalBlocked
                : mode == 'lost-response'
                    ? DriverReadOnlyRecoveryDisposition.completedTrip
                    : DriverReadOnlyRecoveryDisposition.nonterminalTrip);
        expect(reader.commands.length, mode == 'flush-exit' ? 0 : 1);
        expect(recovered.retainedCompletion, isNull);
        expect(recovered.attempt, isNull);
        if (mode != 'flush-exit') {
          expect(recovered.command!.isExactReplayOf(f.command()), isTrue);
        }
        expect(await evidence.readAsBytes(), before);
        expect(await marker.exists(), mode == 'lost-response');
        recovery.dispose();
        fresh.dispose();
      });
    }
  });
}

class _RecordingRepo extends f.CompletionRepo {
  _RecordingRepo(this.events);
  final List<String> events;
  @override
  Future<DriverCompleteTripResult> completeTrip(
      DriverCompleteTripCommand command) {
    events.add('dispatch');
    return super.completeTrip(command);
  }
}

class _PendingRepo extends f.CompletionRepo {
  final entered = Completer<void>();
  final response = Completer<DriverCompleteTripResult>();
  @override
  Future<DriverCompleteTripResult> completeTrip(
      DriverCompleteTripCommand command) {
    calls++;
    entered.complete();
    return response.future;
  }
}
