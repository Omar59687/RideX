import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/canonical_trip_reconciliation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/canonical_trip_reconciliation_repository.dart';
import 'package:ridex/core/repositories/driver_trip_completion_repository.dart';
import 'package:ridex/core/repositories/supabase_driver_trip_completion_repository.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'package:ridex/features/trips/application/driver_completion_recovery_coordinator.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const driver = 'a7000000-0000-0000-0000-000000000001';
const otherDriver = 'a7000000-0000-0000-0000-000000000002';
const trip = 'c7000000-0000-0000-0000-000000000001';
const otherTrip = 'c7000000-0000-0000-0000-000000000002';
const backend = 'ridex-test';

DriverCompleteTripCommand command(
        {String id = trip, int version = 4, String key = 'original-key'}) =>
    DriverCompleteTripCommand(
        tripId: id, expectedTripVersion: version, idempotencyKey: key);

CanonicalTripReadSession session(
        {String? id = driver,
        int epoch = 1,
        bool approved = true,
        String namespace = backend}) =>
    CanonicalTripReadSession(
        driverId: id,
        backendNamespace: namespace,
        epoch: epoch,
        isApprovedDriver: approved);

DriverCompleteTripResult completed({int? version = 9, bool receipt = false}) =>
    DriverCompleteTripResult(
        tripId: trip,
        status: DriverTripLifecycleStatus.completed,
        backendVersion: version,
        receiptVerified: receipt,
        receiptNumber: receipt ? 'genuine-receipt' : null);

class Source implements CanonicalDriverCompletionSource {
  @override
  Future<CanonicalDriverCompletionContext?> load() async =>
      CanonicalDriverCompletionContext(driverId: driver, command: command());
}

class Gateway implements DriverCompletionStagingGateway {
  Gateway({this.existing = false});
  final bool existing;
  int calls = 0;
  @override
  Future<CoordinatorStagingDecision> stage(
      CanonicalDriverCompletionContext context) async {
    calls++;
    return existing
        ? StagingExistingEvidence(context.command)
        : StagingNewlyCreated(context.command);
  }
}

class CompletionRepo implements DriverTripCompletionRepository {
  Object? error;
  int calls = 0;
  @override
  Future<DriverCompleteTripResult> completeTrip(
      DriverCompleteTripCommand command) async {
    calls++;
    if (error != null) throw error!;
    return completed();
  }
}

DriverCompletionCoordinator completionCoordinator(
        DriverTripCompletionRepository repository,
        {Gateway? gateway}) =>
    DriverCompletionCoordinator(
        canonicalSource: Source(),
        stagingGateway: gateway ?? Gateway(),
        repository: repository,
        sessionReader: () async => const DriverCompletionSessionSnapshot(
            driverId: driver, epoch: 1, isApprovedDriver: true));

class Journal implements DriverCompletionCommandStore {
  CompletionSlot slot = CompletionValid(command());
  Future<CompletionSlot> Function()? handler;
  final inspected = <(String, String, String)>[];
  int stages = 0;
  @override
  Future<CompletionSlot> inspect(
      {required String backendNamespace,
      required String driverId,
      required String tripId}) async {
    inspected.add((backendNamespace, driverId, tripId));
    return handler == null ? slot : await handler!();
  }

  @override
  Future<CompletionStageResult> stage(
      {required String backendNamespace,
      required String driverId,
      required DriverCompleteTripCommand command}) async {
    stages++;
    throw StateError('Recovery must never stage');
  }
}

class Reader implements CanonicalTripReconciliationRepository {
  Reader(this.owner);
  CanonicalTripReadSession owner;
  Future<CanonicalTripReadOutcome> Function()? handler;
  final commands = <DriverCompleteTripCommand>[];
  final scopes = <(String, String)>[];
  @override
  Future<CanonicalTripReadOutcome> readCanonicalTrip(
      {required DriverCompleteTripCommand command,
      required String capturedDriverId,
      required String capturedBackendNamespace}) async {
    commands.add(command);
    scopes.add((capturedDriverId, capturedBackendNamespace));
    return handler == null ? visible(owner) : await handler!();
  }
}

CanonicalTripVisible visible(CanonicalTripReadSession owner,
        {DriverTripLifecycleStatus status = DriverTripLifecycleStatus.completed,
        int version = 9,
        String id = trip,
        String driverId = driver}) =>
    CanonicalTripVisible(
        CanonicalTripEvidence(
            tripId: id,
            driverId: driverId,
            status: status,
            backendVersion: version),
        owner);

final class NoPreferences extends SharedPreferencesAsyncPlatform {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Recovery must never access SharedPreferences');
  }
}

class IoSpy extends NativeCompletionJournalIo {
  int writes = 0;
  File? journal;
  @override
  Future<Uint8List?> read(File file) {
    journal = file;
    return super.read(file);
  }

  @override
  Future<void> write(RandomAccessFile handle, List<int> bytes) {
    writes++;
    return super.write(handle, bytes);
  }
}

void main() {
  late NoPreferences preferences;
  SharedPreferencesAsyncPlatform? previousPreferences;
  setUp(() {
    previousPreferences = SharedPreferencesAsyncPlatform.instance;
    preferences = NoPreferences();
    SharedPreferencesAsyncPlatform.instance = preferences;
  });
  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = previousPreferences;
    expect(preferences.calls, 0,
        reason: 'No SharedPreferences reads or writes');
  });

  group('stage-aware coordination', () {
    final attempts = <String,
        DriverCompletionAttemptException Function(DriverCompleteTripCommand)>{
      'before dispatch': (c) => DriverCompletionAttemptException.beforeDispatch(
          c, DriverCompletionFailure.unauthorized),
      'known rejection': (c) => DriverCompletionAttemptException.rpc(
          c, DriverCompletionFailure.staleVersion,
          rejectionConfirmed: true),
      'unknown dispatch': (c) => DriverCompletionAttemptException.rpc(
          c, DriverCompletionFailure.unknownResult),
      'acknowledged write': (c) => DriverCompletionAttemptException.tripReread(
          c, DriverCompletionFailure.unauthorized),
      'verified Trip and failed receipt': (c) =>
          DriverCompletionAttemptException.receiptReread(
              c, DriverCompletionFailure.unknownResult, completed()),
    };
    for (final entry in attempts.entries) {
      test('preserves ${entry.key} without changing legacy unresolved outcome',
          () async {
        final repo = CompletionRepo();
        final exception = entry.value(command());
        repo.error = exception;
        final coordinator = completionCoordinator(repo);
        final result = await coordinator.complete() as CoordinatorUnresolved;
        expect(result.attempt, same(exception));
        expect(result.attempt!.stage, exception.stage);
        expect(result.attempt!.writeEvidence, exception.writeEvidence);
        expect(result.attempt!.confirmedTrip, same(exception.confirmedTrip));
        expect(result.stagedCommand, command());
        expect(await coordinator.complete(), same(result));
        expect(repo.calls, 1);
      });
    }
    for (final changed in [
      command(id: otherTrip),
      command(version: 5),
      command(key: 'rotated-key')
    ]) {
      test(
          'rejects mismatched exception ${changed.tripId}/${changed.expectedTripVersion}/${changed.idempotencyKey}',
          () async {
        final repo = CompletionRepo()
          ..error = DriverCompletionAttemptException.rpc(
              changed, DriverCompletionFailure.unknownResult);
        final result = await completionCoordinator(repo).complete()
            as CoordinatorUnresolved;
        expect(result.attempt, isNull);
        expect(result.failure, DriverCompletionFailure.malformedResponse);
        expect(result.stagedCommand, command());
      });
    }
    test('legacy exception retains legacy unresolved behavior', () async {
      final repo = CompletionRepo()
        ..error = const DriverTripCompletionException(
            DriverCompletionFailure.unknownResult);
      final result =
          await completionCoordinator(repo).complete() as CoordinatorUnresolved;
      expect(result.attempt, isNull);
      expect(result.failure, DriverCompletionFailure.unknownResult);
    });
  });

  group('read-only recovery', () {
    late CanonicalTripReadSession current;
    late Journal journal;
    late Reader reader;
    DriverCompletionRecoveryCoordinator recovery(
            {DriverCompletionRecoverySeed? seed,
            String id = trip,
            CanonicalTripReadSession? owner}) =>
        DriverCompletionRecoveryCoordinator(
            tripId: id,
            owner: owner ?? session(),
            journal: journal,
            repository: reader,
            sessionReader: () => current,
            seed: seed);

    setUp(() {
      current = session();
      journal = Journal();
      reader = Reader(current);
    });
    tearDown(() => expect(journal.stages, 0));

    for (final invalid in [
      session(id: null),
      session(id: otherDriver),
      session(epoch: -1),
      session(approved: false),
      session(namespace: 'other')
    ]) {
      test(
          'initial unauthorized session ${invalid.driverId}/${invalid.epoch}/${invalid.backendNamespace}/${invalid.isApprovedDriver} prevents I/O',
          () async {
        current = invalid;
        expect((await recovery().recover()).disposition,
            DriverReadOnlyRecoveryDisposition.invalidated);
        expect(journal.inspected, isEmpty);
        expect(reader.commands, isEmpty);
      });
    }

    test('unavailable session boundary prevents I/O', () async {
      final coordinator = DriverCompletionRecoveryCoordinator(
          tripId: trip,
          owner: session(),
          journal: journal,
          repository: reader,
          sessionReader: () => throw StateError('session unavailable'));
      expect((await coordinator.recover()).disposition,
          DriverReadOnlyRecoveryDisposition.invalidated);
      expect(journal.inspected, isEmpty);
    });

    test('subsequent failed reread retains independently recovered completion',
        () async {
      final coordinator = recovery();
      final first = await coordinator.recover();
      reader.handler = () async => const CanonicalTripReadFailed(
          CanonicalTripReadFailure.transportUncertain);
      final next = await coordinator.recover();
      expect(next.disposition, DriverReadOnlyRecoveryDisposition.readFailed);
      expect(next.strongestTrip, same(first.strongestTrip));
      expect(next.retainedCompletion, isNull);
    });

    for (final status in DriverTripLifecycleStatus.values) {
      test('reconciles ${status.name} only as current canonical state',
          () async {
        reader.handler =
            () async => visible(current, status: status, version: 2147483647);
        final result = await recovery().recover();
        final expected = status == DriverTripLifecycleStatus.completed
            ? DriverReadOnlyRecoveryDisposition.completedTrip
            : [
                DriverTripLifecycleStatus.cancelledByRider,
                DriverTripLifecycleStatus.cancelledByDriver,
                DriverTripLifecycleStatus.cancelledByAdmin,
                DriverTripLifecycleStatus.failed
              ].contains(status)
                ? DriverReadOnlyRecoveryDisposition.terminalNonCompletedTrip
                : DriverReadOnlyRecoveryDisposition.nonterminalTrip;
        expect(result.disposition, expected);
        expect(result.observedTrip!.status, status);
        expect(result.strongestTrip!.backendVersion, 2147483647);
        expect(result.retainedCompletion, isNull,
            reason: 'No fabricated completion/receipt result');
        expect(result.command, command());
        expect(reader.commands, [command()]);
        expect(reader.scopes, [(driver, backend)]);
        expect(journal.inspected, [(backend, driver, trip)]);
      });
    }
    test('missing row remains not-visible, without terminal inference',
        () async {
      reader.handler = () async => const CanonicalTripNotVisible();
      final result = await recovery().recover();
      expect(result.disposition, DriverReadOnlyRecoveryDisposition.notVisible);
      expect(result.strongestTrip, isNull);
    });
    for (final failure in CanonicalTripReadFailure.values) {
      test('preserves typed read failure ${failure.name}', () async {
        reader.handler = () async => CanonicalTripReadFailed(failure);
        final coordinator = recovery();
        final result = await coordinator.recover();
        if (failure == CanonicalTripReadFailure.sessionInvalidated) {
          expect(result.disposition,
              DriverReadOnlyRecoveryDisposition.invalidated);
          expect(coordinator.current, isNull);
        } else {
          expect(
              result.disposition, DriverReadOnlyRecoveryDisposition.readFailed);
          expect(result.readFailure, failure);
        }
        expect(result.observedTrip, isNull);
      });
    }
    test('unexpected read exception is uncertain', () async {
      reader.handler = () async => throw TimeoutException('private details');
      final result = await recovery().recover();
      expect(result.readFailure, CanonicalTripReadFailure.transportUncertain);
      expect(result.toString(), isNot(contains('private details')));
    });
    for (final foreign in [
      visible(session(), id: otherTrip),
      visible(session(), driverId: otherDriver)
    ]) {
      test(
          'defends against foreign injected evidence ${foreign.trip.tripId}/${foreign.trip.driverId}',
          () async {
        reader.handler = () async => foreign;
        final result = await recovery().recover();
        expect(result.readFailure, CanonicalTripReadFailure.foreignEvidence);
        expect(result.strongestTrip, isNull);
      });
    }
    test('rejects reader authority mismatch', () async {
      reader.handler = () async => visible(session(epoch: 2));
      expect((await recovery().recover()).disposition,
          DriverReadOnlyRecoveryDisposition.invalidated);
    });
    for (final slot in <CompletionSlot>[
      const CompletionAbsent(),
      const CompletionCorrupt(CompletionJournalIssue.invalidFrame),
      const CompletionUnavailable(CompletionJournalIssue.storageUnavailable),
      CompletionValid(command(id: otherTrip))
    ]) {
      test(
          'blocks absent, corrupt, unavailable or foreign Journal slot ${slot.runtimeType}',
          () async {
        journal.slot = slot;
        final result = await recovery().recover();
        expect(
            result.disposition,
            switch (slot) {
              CompletionAbsent() =>
                DriverReadOnlyRecoveryDisposition.noJournalEvidence,
              CompletionValid() =>
                DriverReadOnlyRecoveryDisposition.conflictingEvidence,
              _ => DriverReadOnlyRecoveryDisposition.journalBlocked
            });
        expect(reader.commands, isEmpty);
      });
    }
    test('Journal exception blocks read', () async {
      journal.handler = () async => throw StateError('private path');
      expect((await recovery().recover()).journalIssue,
          CompletionJournalIssue.storageUnavailable);
      expect(reader.commands, isEmpty);
    });
    test('recreated completion coordinator cannot dispatch existing evidence',
        () async {
      final repo = CompletionRepo();
      final existing =
          await completionCoordinator(repo, gateway: Gateway(existing: true))
              .complete();
      expect(existing, isA<CoordinatorUnresolved>());
      final result = await recovery().recover();
      expect(
          result.disposition, DriverReadOnlyRecoveryDisposition.completedTrip);
      expect(repo.calls, 0);
    });

    for (final change in <String, CanonicalTripReadSession>{
      'logout': session(id: null, epoch: 2, approved: false),
      'A-B-A': session(epoch: 3),
      'account': session(id: otherDriver, epoch: 2),
      'approval': session(approved: false),
      'backend': session(namespace: 'other')
    }.entries) {
      for (final boundary in ['journal', 'read']) {
        for (final throws in [false, true]) {
          test(
              '${change.key} suppresses ${throws ? 'failure' : 'success'} after $boundary await',
              () async {
            final entered = Completer<void>();
            final gate = Completer<void>();
            if (boundary == 'journal') {
              journal.handler = () async {
                entered.complete();
                await gate.future;
                if (throws) throw StateError('failed');
                return CompletionValid(command());
              };
            } else {
              reader.handler = () async {
                entered.complete();
                await gate.future;
                if (throws) throw StateError('failed');
                return visible(session());
              };
            }
            final coordinator = recovery();
            final future = coordinator.recover();
            await entered.future;
            if (change.key == 'A-B-A') {
              current = session(id: otherDriver, epoch: 2);
            }
            current = change.value;
            gate.complete();
            final result = await future;
            expect(result.disposition,
                DriverReadOnlyRecoveryDisposition.invalidated);
            expect(result.strongestTrip, isNull);
            expect(coordinator.current, isNull);
            if (boundary == 'journal') expect(reader.commands, isEmpty);
          });
        }
      }
    }
    for (final boundary in ['journal', 'read']) {
      test('disposal suppresses result after $boundary await', () async {
        final entered = Completer<void>();
        final gate = Completer<void>();
        if (boundary == 'journal') {
          journal.handler = () async {
            entered.complete();
            await gate.future;
            return CompletionValid(command());
          };
        } else {
          reader.handler = () async {
            entered.complete();
            await gate.future;
            return visible(current);
          };
        }
        final coordinator = recovery();
        final future = coordinator.recover();
        await entered.future;
        coordinator.dispose();
        gate.complete();
        expect((await future).disposition,
            DriverReadOnlyRecoveryDisposition.invalidated);
        expect(coordinator.current, isNull);
        expect((await coordinator.recover()).disposition,
            DriverReadOnlyRecoveryDisposition.invalidated);
      });
    }
    for (final lateError in [false, true]) {
      test(
          'late ${lateError ? 'error' : 'success'} cannot replace newer completion',
          () async {
        final pending = Completer<CanonicalTripReadOutcome>();
        final entered = Completer<void>();
        reader.handler = () {
          entered.complete();
          return pending.future;
        };
        final coordinator = recovery();
        final older = coordinator.recover();
        await entered.future;
        reader.handler = () async => visible(current, version: 11);
        final newer = await coordinator.recover();
        if (lateError) {
          pending.completeError(StateError('late'));
        } else {
          pending.complete(visible(current,
              status: DriverTripLifecycleStatus.inProgress, version: 5));
        }
        expect((await older).disposition,
            DriverReadOnlyRecoveryDisposition.invalidated);
        expect(coordinator.current, same(newer));
        expect(newer.strongestTrip!.backendVersion, 11);
      });
    }
    for (final next in <CanonicalTripReadOutcome>[
      const CanonicalTripNotVisible(),
      const CanonicalTripReadFailed(
          CanonicalTripReadFailure.authorizationDenied),
      visible(session(),
          status: DriverTripLifecycleStatus.inProgress, version: 10),
      visible(session(), version: 8)
    ]) {
      test(
          'does not downgrade completion on ${next.runtimeType}/${next is CanonicalTripVisible ? next.trip.status : ''}',
          () async {
        final prior = completed(receipt: true);
        final seed = DriverCompletionRecoverySeed.fromOutcome(
            owner: current,
            outcome: CoordinatorCompleted(prior, stagedCommand: command()));
        reader.handler = () async => next;
        final result = await recovery(seed: seed).recover();
        expect(
            result.strongestTrip!.status, DriverTripLifecycleStatus.completed);
        expect(result.strongestTrip!.backendVersion, 9);
        expect(result.retainedCompletion, same(prior));
        expect(result.retainedCompletion!.receiptVerified, isTrue);
      });
    }
    test(
        'preserves verified Trip after failed receipt read, without receipt success',
        () async {
      final attempt = DriverCompletionAttemptException.receiptReread(
          command(), DriverCompletionFailure.unknownResult, completed());
      final repo = CompletionRepo()..error = attempt;
      final outcome = await completionCoordinator(repo).complete();
      final seed = DriverCompletionRecoverySeed.fromOutcome(
          owner: current, outcome: outcome);
      reader.handler = () async => throw TimeoutException('read failed');
      final result = await recovery(seed: seed).recover();
      expect(result.attempt, same(attempt));
      expect(result.strongestTrip!.backendVersion, 9);
      expect(result.retainedCompletion!.receiptVerified, isFalse);
      expect(result.retainedCompletion!.receiptNumber, isNull);
      expect(repo.calls, 1);
    });
    for (final seedOwner in [
      session(epoch: 2),
      session(id: otherDriver),
      session(namespace: 'other')
    ]) {
      test(
          'rejects foreign/stale seed ${seedOwner.driverId}/${seedOwner.epoch}/${seedOwner.backendNamespace}',
          () async {
        final seed = DriverCompletionRecoverySeed.fromOutcome(
            owner: seedOwner,
            outcome: CoordinatorCompleted(completed(receipt: true),
                stagedCommand: command()));
        final result = await recovery(seed: seed).recover();
        expect(result.disposition,
            DriverReadOnlyRecoveryDisposition.conflictingEvidence);
        expect(result.retainedCompletion, isNull);
        expect(result.strongestTrip, isNull);
        expect(reader.commands, isEmpty);
      });
    }
    test('conflicting seed command blocks without exposing seed', () async {
      final seed = DriverCompletionRecoverySeed.fromOutcome(
          owner: current,
          outcome: CoordinatorUnresolved(stagedCommand: command(version: 5)));
      final result = await recovery(seed: seed).recover();
      expect(result.disposition,
          DriverReadOnlyRecoveryDisposition.conflictingEvidence);
      expect(reader.commands, isEmpty);
    });
    test('rejects malformed handoff attempt', () {
      expect(
          () => DriverCompletionRecoverySeed.fromOutcome(
              owner: current,
              outcome: CoordinatorUnresolved(
                  stagedCommand: command(),
                  attempt: DriverCompletionAttemptException.rpc(
                      command(key: 'other'),
                      DriverCompletionFailure.unknownResult))),
          throwsArgumentError);
    });
    test(
        'unknown real adapter RPC outcome followed by read-only recovery does not redispatch',
        () async {
      int rpcCalls = 0;
      int receiptCalls = 0;
      final adapter = SupabaseDriverTripCompletionRepository(
          rpc: ({required name, required params}) async {
            rpcCalls++;
            throw TimeoutException('lost response');
          },
          readTripRow: (_) async => throw StateError('not reached'),
          readReceiptRows: (_) async {
            receiptCalls++;
            return [];
          });
      final unresolved = await completionCoordinator(adapter).complete()
          as CoordinatorUnresolved;
      expect(unresolved.attempt!.writeEvidence,
          DriverCompletionWriteEvidence.unknown);
      final result = await recovery(
              seed: DriverCompletionRecoverySeed.fromOutcome(
                  owner: current, outcome: unresolved))
          .recover();
      expect(
          result.disposition, DriverReadOnlyRecoveryDisposition.completedTrip);
      expect(result.attempt, same(unresolved.attempt));
      expect(result.retainedCompletion, isNull);
      expect(rpcCalls, 1, reason: 'Only original attempt dispatched');
      expect(receiptCalls, 0);
      expect(result.command!.expectedTripVersion, 4);
      expect(result.command!.idempotencyKey, 'original-key');
    });
  });

  group('real File Journal and canonical repository', () {
    late Directory directory;
    late IoSpy io;
    late FileDriverCompletionCommandStore store;
    setUp(() async {
      directory =
          await Directory.systemTemp.createTemp('ridex-readonly-recovery-');
      io = IoSpy();
      store = FileDriverCompletionCommandStore(directory: directory, io: io);
      await store.stage(
          backendNamespace: backend, driverId: driver, command: command());
      io.writes = 0;
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });
    test('stale lock blocks without deleting sentinel or evidence', () async {
      final lock = File.fromUri(io.journal!.parent.uri.resolve('writer.lock'));
      await lock.create(exclusive: true);
      final before = await io.journal!.readAsBytes();
      final reader = Reader(session());
      final coordinator = DriverCompletionRecoveryCoordinator(
          tripId: trip,
          owner: session(),
          journal: store,
          repository: reader,
          sessionReader: session);
      final result = await coordinator.recover();
      expect(result.journalIssue,
          CompletionJournalIssue.synchronizationUnavailable);
      expect(await lock.exists(), isTrue);
      expect(await io.journal!.readAsBytes(), before);
      expect(reader.commands, isEmpty);
      expect(io.writes, 0);
    });
    test(
        'new coordinator inspects unchanged durable bytes and never writes a command frame',
        () async {
      final before = await io.journal!.readAsBytes();
      final transport = RowTransport();
      final coordinator = DriverCompletionRecoveryCoordinator(
          tripId: trip,
          owner: session(),
          journal:
              FileDriverCompletionCommandStore(directory: directory, io: io),
          repository: ReadOnlyCanonicalTripReconciliationRepository(transport),
          sessionReader: session);
      final result = await coordinator.recover();
      expect(
          result.disposition, DriverReadOnlyRecoveryDisposition.completedTrip);
      expect(await io.journal!.readAsBytes(), before);
      expect(io.writes, 0);
      expect(transport.reads, 1);
      expect(
          (await store.inspect(
              backendNamespace: backend, driverId: driver, tripId: trip)),
          isA<CompletionValid>());
    });
    test('corruption blocks without truncation or repair', () async {
      await io.journal!.writeAsBytes([1, 2, 3], mode: FileMode.append);
      final before = await io.journal!.readAsBytes();
      final reader = Reader(session());
      final coordinator = DriverCompletionRecoveryCoordinator(
          tripId: trip,
          owner: session(),
          journal: store,
          repository: reader,
          sessionReader: session);
      expect((await coordinator.recover()).disposition,
          DriverReadOnlyRecoveryDisposition.journalBlocked);
      expect(await io.journal!.readAsBytes(), before);
      expect(reader.commands, isEmpty);
      expect(io.writes, 0);
    });
    test('invalid backend version from actual reader stays typed', () async {
      final transport = RowTransport()..version = 0;
      final coordinator = DriverCompletionRecoveryCoordinator(
          tripId: trip,
          owner: session(),
          journal: store,
          repository: ReadOnlyCanonicalTripReconciliationRepository(transport),
          sessionReader: session);
      final result = await coordinator.recover();
      expect(result.readFailure, CanonicalTripReadFailure.invalidVersion);
      expect(result.strongestTrip, isNull);
      expect(io.writes, 0);
    });
  });
}

class RowTransport implements CanonicalTripReadTransport {
  int reads = 0;
  int version = 9;
  @override
  CanonicalTripReadSession get currentSession => session();
  @override
  Future<Map<String, Object?>?> readTrip(String tripId) async {
    reads++;
    expect(tripId, trip);
    return {
      'id': trip,
      'driver_id': driver,
      'status': 'completed',
      'version': version
    };
  }
}
