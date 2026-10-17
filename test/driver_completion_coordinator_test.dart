import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/driver_trip_completion_repository.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';

const _driverA = 'a7000000-0000-0000-0000-000000000001';
const _driverB = 'b7000000-0000-0000-0000-000000000002';
const _trip = 'c7000000-0000-0000-0000-000000000001';
const _otherTrip = 'c7000000-0000-0000-0000-000000000002';
const _version = 4;
const _key = 'complete-key-1';

DriverCompleteTripCommand _command({
  String tripId = _trip,
  int version = _version,
  String key = _key,
}) =>
    DriverCompleteTripCommand(
      tripId: tripId,
      expectedTripVersion: version,
      idempotencyKey: key,
    );

CanonicalDriverCompletionContext _context({
  String driverId = _driverA,
  DriverCompleteTripCommand? command,
}) =>
    CanonicalDriverCompletionContext(
      driverId: driverId,
      command: command ?? _command(),
    );

DriverCompletionSessionSnapshot _session({
  String? driverId = _driverA,
  int epoch = 1,
  bool approved = true,
}) =>
    DriverCompletionSessionSnapshot(
      driverId: driverId,
      epoch: epoch,
      isApprovedDriver: approved,
    );

DriverCompleteTripResult _completedResult({
  String tripId = _trip,
  int? backendVersion = 5,
  bool receiptVerified = false,
  String? receiptNumber,
}) =>
    DriverCompleteTripResult(
      tripId: tripId,
      status: DriverTripLifecycleStatus.completed,
      backendVersion: backendVersion,
      receiptVerified: receiptVerified,
      receiptNumber: receiptNumber,
    );

class _FakeSource implements CanonicalDriverCompletionSource {
  _FakeSource({CanonicalDriverCompletionContext? context}) : _context = context;

  CanonicalDriverCompletionContext? _context;
  int loads = 0;
  Completer<void>? gate;
  Completer<void>? entered;
  Object? failure;

  set context(CanonicalDriverCompletionContext? value) => _context = value;

  @override
  Future<CanonicalDriverCompletionContext?> load() async {
    loads++;
    if (!(entered?.isCompleted ?? true)) entered!.complete();
    final pendingGate = gate;
    if (pendingGate != null) {
      gate = null;
      await pendingGate.future;
    }
    final failure = this.failure;
    if (failure != null) throw failure;
    return _context;
  }
}

class _FakeGateway implements DriverCompletionStagingGateway {
  _FakeGateway({CoordinatorStagingDecision? decision}) : _decision = decision;

  CoordinatorStagingDecision? _decision;
  CoordinatorStagingDecision Function(CanonicalDriverCompletionContext)?
      handler;
  final List<CanonicalDriverCompletionContext> stagedContexts = [];
  final List<String> callOrder = [];
  Completer<void>? gate;
  Completer<void>? entered;
  Object? failure;

  set decision(CoordinatorStagingDecision? value) => _decision = value;

  @override
  Future<CoordinatorStagingDecision> stage(
    CanonicalDriverCompletionContext context,
  ) async {
    stagedContexts.add(context);
    callOrder.add('stage');
    if (!(entered?.isCompleted ?? true)) entered!.complete();
    final pendingGate = gate;
    if (pendingGate != null) {
      gate = null;
      await pendingGate.future;
    }
    final failure = this.failure;
    if (failure != null) {
      this.failure = null;
      throw failure;
    }
    final handler = this.handler;
    if (handler != null) return handler(context);
    final decision = _decision;
    if (decision == null) {
      return StagingNewlyCreated(context.command);
    }
    return decision;
  }
}

class _FakeRepository implements DriverTripCompletionRepository {
  _FakeRepository({DriverCompleteTripResult? result}) : _result = result;

  DriverCompleteTripResult? _result;
  Object? failure;
  Completer<void>? gate;
  Completer<void>? entered;
  final List<DriverCompleteTripCommand> calls = [];
  final List<String> callOrder = [];

  set result(DriverCompleteTripResult? value) => _result = value;

  @override
  Future<DriverCompleteTripResult> completeTrip(
    DriverCompleteTripCommand command,
  ) async {
    calls.add(command);
    callOrder.add('dispatch');
    if (!(entered?.isCompleted ?? true)) entered!.complete();
    final pendingGate = gate;
    if (pendingGate != null) {
      gate = null;
      await pendingGate.future;
    }
    final failure = this.failure;
    if (failure != null) {
      this.failure = null;
      throw failure;
    }
    return _result ?? _completedResult(tripId: command.tripId);
  }
}

class _FakeSession {
  _FakeSession({DriverCompletionSessionSnapshot? snapshot})
      : _snapshot = snapshot ?? _session();

  DriverCompletionSessionSnapshot _snapshot;
  Future<DriverCompletionSessionSnapshot> Function()? handler;
  int reads = 0;
  Completer<DriverCompletionSessionSnapshot>? nextReadGate;
  Completer<void>? nextReadEntered;

  set snapshot(DriverCompletionSessionSnapshot value) => _snapshot = value;

  Future<DriverCompletionSessionSnapshot> read() async {
    reads++;
    final gate = nextReadGate;
    if (gate != null) {
      nextReadGate = null;
      final entered = nextReadEntered;
      nextReadEntered = null;
      if (entered != null && !entered.isCompleted) entered.complete();
      return gate.future;
    }
    final handler = this.handler;
    if (handler != null) return handler();
    return _snapshot;
  }
}

DriverCompletionCoordinator _coordinator({
  _FakeSource? source,
  _FakeGateway? gateway,
  _FakeRepository? repository,
  _FakeSession? session,
}) {
  final resolvedSource = source ?? _FakeSource(context: _context());
  final resolvedGateway = gateway ?? _FakeGateway();
  final resolvedRepository = repository ?? _FakeRepository();
  final resolvedSession = session ?? _FakeSession();
  return DriverCompletionCoordinator(
    canonicalSource: resolvedSource,
    stagingGateway: resolvedGateway,
    repository: resolvedRepository,
    sessionReader: resolvedSession.read,
  );
}

void main() {
  group('stage-before-dispatch ordering', () {
    test('stages before dispatch with the exact original triple', () async {
      final source = _FakeSource(context: _context());
      final gateway = _FakeGateway();
      final repository = _FakeRepository(
        result: _completedResult(backendVersion: 7),
      );
      final session = _FakeSession();
      final coordinator = _coordinator(
        source: source,
        gateway: gateway,
        repository: repository,
        session: session,
      );
      final order = <String>[];
      gateway.handler = (context) {
        order.add('stage');
        return StagingNewlyCreated(context.command);
      };

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorCompleted>());
      final completed = outcome as CoordinatorCompleted;
      expect(source.loads, 1);
      expect(gateway.stagedContexts, hasLength(1));
      expect(repository.calls, hasLength(1));
      expect(order, ['stage']);
      // Original triple preserved byte-identically.
      expect(repository.calls.single.isExactReplayOf(_command()), isTrue);
      expect(repository.calls.single.tripId, _trip);
      expect(repository.calls.single.expectedTripVersion, _version);
      expect(repository.calls.single.idempotencyKey, _key);
      expect(completed.stagedCommand.isExactReplayOf(_command()), isTrue);
      expect(coordinator.current, same(outcome));
    });

    test('never dispatches when no eligible canonical context exists',
        () async {
      final source = _FakeSource(context: null);
      final gateway = _FakeGateway();
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        source: source,
        gateway: gateway,
        repository: repository,
      );

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorNoContext>());
      expect(gateway.stagedContexts, isEmpty);
      expect(repository.calls, isEmpty);
      expect(coordinator.current, same(outcome));
    });

    test('rejects mock identifiers before any staging or dispatch', () {
      expect(
        () => DriverCompleteTripCommand(
          tripId: 'trip-1',
          expectedTripVersion: 1,
          idempotencyKey: _key,
        ),
        throwsArgumentError,
      );
    });
  });

  group('exact command identity', () {
    test('conflicts when the gateway returns a rotated key', () async {
      final gateway = _FakeGateway();
      gateway.handler = (context) {
        return StagingNewlyCreated(_command(key: 'rotated-key'));
      };
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        gateway: gateway,
        repository: repository,
      );

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorConflict>());
      expect(repository.calls, isEmpty);
    });

    test('conflicts when the gateway returns a bumped version', () async {
      final gateway = _FakeGateway();
      gateway.handler = (context) {
        return StagingNewlyCreated(_command(version: _version + 1));
      };
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        gateway: gateway,
        repository: repository,
      );

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorConflict>());
      expect(repository.calls, isEmpty);
    });

    test('conflicts when the gateway returns another trip', () async {
      final gateway = _FakeGateway();
      gateway.handler = (context) {
        return StagingNewlyCreated(_command(tripId: _otherTrip));
      };
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        gateway: gateway,
        repository: repository,
      );

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorConflict>());
      expect(repository.calls, isEmpty);
    });
  });

  group('single-flight', () {
    test('concurrent taps share one staging and one dispatch', () async {
      final stageGate = Completer<void>();
      final gateway = _FakeGateway()..gate = stageGate;
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        gateway: gateway,
        repository: repository,
      );

      final first = coordinator.complete();
      final second = coordinator.complete();
      expect(identical(first, second), isTrue);

      stageGate.complete();
      final results = await Future.wait([first, second]);

      expect(identical(results[0], results[1]), isTrue);
      expect(results[0], isA<CoordinatorCompleted>());
      expect(gateway.stagedContexts, hasLength(1));
      expect(repository.calls, hasLength(1));
    });

    test('rapid double dispatch shares one repository call', () async {
      final dispatchGate = Completer<void>();
      final repository = _FakeRepository()
        ..gate = dispatchGate
        ..entered = Completer<void>();
      final coordinator = _coordinator(repository: repository);

      final first = coordinator.complete();
      await repository.entered!.future;
      final second = coordinator.complete();
      expect(identical(first, second), isTrue);

      dispatchGate.complete();
      await Future.wait([first, second]);

      expect(repository.calls, hasLength(1));
    });
  });

  group('conflicting and blocked storage', () {
    test('gateway conflict blocks dispatch', () async {
      final gateway = _FakeGateway(
        decision: const StagingConflict(),
      );
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        gateway: gateway,
        repository: repository,
      );

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorConflict>());
      expect(repository.calls, isEmpty);
    });

    for (final reason in StagingBlockReason.values) {
      test('gateway blocked ($reason) prevents dispatch', () async {
        final gateway = _FakeGateway(
          decision: StagingBlocked(reason),
        );
        final repository = _FakeRepository();
        final coordinator = _coordinator(
          gateway: gateway,
          repository: repository,
        );

        final outcome = await coordinator.complete();

        expect(outcome, isA<CoordinatorBlocked>());
        expect((outcome as CoordinatorBlocked).reason, reason);
        expect(repository.calls, isEmpty);
        // Explicit retry without reconciliation performs no new I/O.
        final retry = await coordinator.complete();
        expect(identical(retry, outcome), isTrue);
        expect(gateway.stagedContexts, hasLength(1));
        expect(repository.calls, isEmpty);
      });
    }

    test('staging throw fails closed as blocked without dispatch', () async {
      final gateway = _FakeGateway()..failure = StateError('disk lost');
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        gateway: gateway,
        repository: repository,
      );

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorBlocked>());
      expect(
        (outcome as CoordinatorBlocked).reason,
        StagingBlockReason.storageUnavailable,
      );
      expect(repository.calls, isEmpty);
    });
  });

  group('completion outcomes', () {
    test('unknownResult stays unresolved and preserves the triple', () async {
      final repository = _FakeRepository()
        ..failure = const DriverTripCompletionException(
          DriverCompletionFailure.unknownResult,
        );
      final coordinator = _coordinator(repository: repository);

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorUnresolved>());
      final unresolved = outcome as CoordinatorUnresolved;
      expect(unresolved.failure, DriverCompletionFailure.unknownResult);
      expect(unresolved.stagedCommand.isExactReplayOf(_command()), isTrue);
      expect(repository.calls, hasLength(1));
      expect(repository.calls.single.idempotencyKey, _key);
    });

    test('malformedResponse stays unresolved, never rejected', () async {
      final repository = _FakeRepository()
        ..failure = const DriverTripCompletionException(
          DriverCompletionFailure.malformedResponse,
        );
      final coordinator = _coordinator(repository: repository);

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorUnresolved>());
      expect(
        (outcome as CoordinatorUnresolved).failure,
        DriverCompletionFailure.malformedResponse,
      );
    });

    test('unexpected repository error stays unresolved as unknownResult',
        () async {
      final repository = _FakeRepository()..failure = StateError('boom');
      final coordinator = _coordinator(repository: repository);

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorUnresolved>());
      final unresolved = outcome as CoordinatorUnresolved;
      expect(unresolved.failure, DriverCompletionFailure.unknownResult);
      expect(
        unresolved.stagedCommand.isExactReplayOf(
          _command(),
        ),
        isTrue,
      );
    });

    test('mismatched result identity stays unresolved', () async {
      final repository = _FakeRepository(
        result: _completedResult(tripId: _otherTrip),
      );
      final coordinator = _coordinator(repository: repository);

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorUnresolved>());
      expect(
        (outcome as CoordinatorUnresolved).failure,
        DriverCompletionFailure.malformedResponse,
      );
    });

    test('staleVersion preserves evidence and never mutates the triple',
        () async {
      final repository = _FakeRepository()
        ..failure = const DriverTripCompletionException(
          DriverCompletionFailure.staleVersion,
        );
      final gateway = _FakeGateway();
      final coordinator = _coordinator(
        gateway: gateway,
        repository: repository,
      );

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorUnresolved>());
      final stale = outcome as CoordinatorUnresolved;
      expect(stale.stagedCommand.isExactReplayOf(_command()), isTrue);
      expect(stale.stagedCommand.expectedTripVersion, _version);
      expect(stale.stagedCommand.idempotencyKey, _key);
      // No automatic new intent with a bumped version.
      expect(repository.calls, hasLength(1));
      final retry = await coordinator.complete();
      expect(identical(retry, outcome), isTrue);
      expect(repository.calls, hasLength(1));
      expect(gateway.stagedContexts, hasLength(1));
    });

    for (final failure in [
      DriverCompletionFailure.unauthorized,
      DriverCompletionFailure.tripNotFound,
      DriverCompletionFailure.invalidTransition,
      DriverCompletionFailure.idempotencyConflict,
    ]) {
      test('ambiguous $failure stays unresolved without blind retry', () async {
        final repository = _FakeRepository()
          ..failure = DriverTripCompletionException(failure);
        final coordinator = _coordinator(repository: repository);

        final outcome = await coordinator.complete();

        expect(outcome, isA<CoordinatorUnresolved>());
        final rejected = outcome as CoordinatorUnresolved;
        expect(rejected.failure, failure);
        expect(
          rejected.stagedCommand.isExactReplayOf(
            _command(),
          ),
          isTrue,
        );
        final retry = await coordinator.complete();
        expect(identical(retry, outcome), isTrue);
        expect(repository.calls, hasLength(1));
      });
    }
  });

  group('receipt verification and payment neutrality', () {
    test('unverified completion carries version but no receipt', () async {
      final repository = _FakeRepository(
        result: _completedResult(backendVersion: 9, receiptVerified: false),
      );
      final coordinator = _coordinator(repository: repository);

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorCompleted>());
      final completed = outcome as CoordinatorCompleted;
      expect(completed.result.isCompleted, isTrue);
      expect(completed.result.backendVersion, 9);
      expect(completed.result.receiptVerified, isFalse);
      expect(completed.result.receiptNumber, isNull);
      // The backend bumped version is preserved, never synthesized as +1.
      expect(completed.result.backendVersion, isNot(_version));
    });

    test('verified completion surfaces the authorized receipt number',
        () async {
      final repository = _FakeRepository(
        result: _completedResult(
          backendVersion: 6,
          receiptVerified: true,
          receiptNumber: 'RX-2026-0001',
        ),
      );
      final coordinator = _coordinator(repository: repository);

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorCompleted>());
      final completed = outcome as CoordinatorCompleted;
      expect(completed.result.receiptVerified, isTrue);
      expect(completed.result.receiptNumber, 'RX-2026-0001');
      expect(completed.result.backendVersion, 6);
      // No client-side payment-success mutation: the surfaced result is the
      // repository result, with receipt state only from authorized rereads.
      expect(repository.calls.single.isExactReplayOf(_command()), isTrue);
    });
  });

  group('session and lifecycle invalidation', () {
    test('context owned by another driver never stages', () async {
      final source = _FakeSource(context: _context(driverId: _driverB));
      final gateway = _FakeGateway();
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        source: source,
        gateway: gateway,
        repository: repository,
      );

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorSessionInvalid>());
      expect(gateway.stagedContexts, isEmpty);
      expect(repository.calls, isEmpty);
    });

    test('unapproved driver session never stages', () async {
      final session = _FakeSession(snapshot: _session(approved: false));
      final gateway = _FakeGateway();
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        gateway: gateway,
        repository: repository,
        session: session,
      );

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorSessionInvalid>());
      expect(gateway.stagedContexts, isEmpty);
      expect(repository.calls, isEmpty);
    });

    test('signed-out session never stages', () async {
      final session = _FakeSession(snapshot: _session(driverId: null));
      final coordinator = _coordinator(session: session);

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorSessionInvalid>());
    });

    test('account switch mid-dispatch discards the result', () async {
      final dispatchGate = Completer<void>();
      final repository = _FakeRepository()
        ..gate = dispatchGate
        ..entered = Completer<void>();
      final session = _FakeSession();
      var call = 0;
      session.handler = () async {
        call++;
        if (call <= 3) return _session(epoch: 1);
        return _session(driverId: _driverB, epoch: 2);
      };
      final coordinator = _coordinator(
        repository: repository,
        session: session,
      );

      final pending = coordinator.complete();
      await repository.entered!.future;
      expect(repository.calls, hasLength(1));
      dispatchGate.complete();
      final outcome = await pending;

      expect(outcome, isA<CoordinatorInvalidated>());
      expect(
        (outcome as CoordinatorInvalidated).stagedCommand?.isExactReplayOf(
              _command(),
            ),
        isTrue,
      );
      expect(repository.calls, hasLength(1));
      // The airborne RPC is not claimed cancelled, but it never publishes.
      expect(coordinator.current, isNull);
    });

    test('epoch change without driver change still invalidates', () async {
      final dispatchGate = Completer<void>();
      final repository = _FakeRepository()
        ..gate = dispatchGate
        ..entered = Completer<void>();
      final session = _FakeSession();
      var call = 0;
      session.handler = () async {
        call++;
        if (call <= 3) return _session(epoch: 7);
        return _session(epoch: 8);
      };
      final coordinator = _coordinator(
        repository: repository,
        session: session,
      );

      final pending = coordinator.complete();
      await repository.entered!.future;
      expect(repository.calls, hasLength(1));
      dispatchGate.complete();
      final outcome = await pending;

      expect(outcome, isA<CoordinatorInvalidated>());
      expect(coordinator.current, isNull);
    });

    test('in-flight result after state replacement never publishes', () async {
      final dispatchGate = Completer<void>();
      final repository = _FakeRepository()
        ..gate = dispatchGate
        ..entered = Completer<void>();
      final coordinator = _coordinator(repository: repository);

      final pending = coordinator.complete();
      await repository.entered!.future;
      expect(repository.calls, hasLength(1));
      coordinator.invalidate();
      dispatchGate.complete();
      final outcome = await pending;

      expect(outcome, isA<CoordinatorInvalidated>());
      expect(
        (outcome as CoordinatorInvalidated).stagedCommand?.isExactReplayOf(
              _command(),
            ),
        isTrue,
      );
      expect(repository.calls, hasLength(1));
      expect(coordinator.current, isNull);
    });

    test('disposal before completion performs no I/O', () async {
      final gateway = _FakeGateway();
      final repository = _FakeRepository();
      final source = _FakeSource(context: _context());
      final coordinator = _coordinator(
        source: source,
        gateway: gateway,
        repository: repository,
      );
      coordinator.dispose();
      expect(coordinator.isDisposed, isTrue);

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorInvalidated>());
      expect(source.loads, 0);
      expect(gateway.stagedContexts, isEmpty);
      expect(repository.calls, isEmpty);
      expect(coordinator.current, isNull);
    });

    test('disposal mid-flight discards a successful completion', () async {
      final dispatchGate = Completer<void>();
      final repository = _FakeRepository()
        ..gate = dispatchGate
        ..entered = Completer<void>();
      final coordinator = _coordinator(repository: repository);

      final pending = coordinator.complete();
      await repository.entered!.future;
      expect(repository.calls, hasLength(1));
      coordinator.dispose();
      dispatchGate.complete();
      final outcome = await pending;

      expect(outcome, isA<CoordinatorInvalidated>());
      expect(repository.calls, hasLength(1));
      expect(coordinator.current, isNull);
    });
  });

  group('explicit reconciliation', () {
    test('unresolved outcome never auto-retries on a second call', () async {
      final gateway = _FakeGateway();
      final repository = _FakeRepository()
        ..failure = const DriverTripCompletionException(
          DriverCompletionFailure.unknownResult,
        );
      final coordinator = _coordinator(
        gateway: gateway,
        repository: repository,
      );

      final first = await coordinator.complete();
      expect(first, isA<CoordinatorUnresolved>());
      final second = await coordinator.complete();

      expect(identical(second, first), isTrue);
      expect(gateway.stagedContexts, hasLength(1));
      expect(repository.calls, hasLength(1));
      expect(
        (coordinator.current as CoordinatorUnresolved)
            .stagedCommand
            .idempotencyKey,
        _key,
      );
    });

    test('completed outcome never dispatches a second mutation', () async {
      final coordinator = _coordinator();
      final first = await coordinator.complete();
      expect(first, isA<CoordinatorCompleted>());

      final second = await coordinator.complete();

      expect(identical(second, first), isTrue);
    });
  });

  group('existing evidence and lifecycle regression coverage', () {
    test('dispatch waits for positive staging acknowledgement', () async {
      final stageGate = Completer<void>();
      final gateway = _FakeGateway()
        ..gate = stageGate
        ..entered = Completer<void>();
      final repository = _FakeRepository();
      final coordinator =
          _coordinator(gateway: gateway, repository: repository);
      final pending = coordinator.complete();
      await gateway.entered!.future;
      expect(repository.calls, isEmpty);
      expect(gateway.callOrder, ['stage']);
      stageGate.complete();
      expect(await pending, isA<CoordinatorCompleted>());
      expect(repository.callOrder, ['dispatch']);
    });

    test('injected trip reread unauthorized classification remains unresolved',
        () async {
      final repository = _FakeRepository()
        ..failure = const DriverTripCompletionException(
            DriverCompletionFailure.unauthorized);
      final outcome = await _coordinator(repository: repository).complete();
      expect(outcome, isA<CoordinatorUnresolved>());
      expect(
          (outcome as CoordinatorUnresolved)
              .stagedCommand
              .isExactReplayOf(_command()),
          isTrue);
    });

    test('injected P0002 receipt reread classification remains unresolved',
        () async {
      final repository = _FakeRepository()
        ..failure = const DriverTripCompletionException(
            DriverCompletionFailure.tripNotFound);
      final outcome = await _coordinator(repository: repository).complete();
      expect(outcome, isA<CoordinatorUnresolved>());
      expect(
          (outcome as CoordinatorUnresolved)
              .stagedCommand
              .isExactReplayOf(_command()),
          isTrue);
    });

    test('existing evidence never authorizes dispatch across coordinators',
        () async {
      final firstRepo = _FakeRepository();
      final secondRepo = _FakeRepository();
      final first = _coordinator(
        gateway: _FakeGateway(decision: StagingExistingEvidence(_command())),
        repository: firstRepo,
      );
      final second = _coordinator(
        gateway: _FakeGateway(decision: StagingExistingEvidence(_command())),
        repository: secondRepo,
      );
      final firstOutcome = await first.complete();
      final secondOutcome = await second.complete();
      expect(firstOutcome, isA<CoordinatorUnresolved>());
      expect(secondOutcome, isA<CoordinatorUnresolved>());
      expect(firstRepo.calls, isEmpty);
      expect(secondRepo.calls, isEmpty);
      expect(
          (firstOutcome as CoordinatorUnresolved)
              .stagedCommand
              .isExactReplayOf(_command()),
          isTrue);
      expect(
          (secondOutcome as CoordinatorUnresolved)
              .stagedCommand
              .isExactReplayOf(_command()),
          isTrue);
    });

    test('retirement prevents cached success from being returned', () async {
      for (final retire in <void Function(DriverCompletionCoordinator)>[
        (coordinator) => coordinator.dispose(),
        (coordinator) => coordinator.invalidate(),
      ]) {
        final coordinator = _coordinator();
        final first = await coordinator.complete();
        expect(first, isA<CoordinatorCompleted>());
        retire(coordinator);
        expect(await coordinator.complete(), isA<CoordinatorInvalidated>());
        expect(coordinator.current, isNull);
      }
    });

    test(
        'cached result is invalidated after account replacement or epoch change',
        () async {
      final session = _FakeSession();
      final coordinator = _coordinator(session: session);
      expect(await coordinator.complete(), isA<CoordinatorCompleted>());
      session.snapshot = _session(driverId: _driverB, epoch: 2);
      expect(await coordinator.complete(), isA<CoordinatorInvalidated>());
      expect(coordinator.current, isNull);

      final abaSession = _FakeSession();
      final aba = _coordinator(session: abaSession);
      expect(await aba.complete(), isA<CoordinatorCompleted>());
      abaSession.snapshot = _session(driverId: _driverB, epoch: 2);
      expect(await aba.complete(), isA<CoordinatorInvalidated>());
      // Even when the ID returns to A, the changed epoch cannot resurrect it.
      abaSession.snapshot = _session(driverId: _driverA, epoch: 3);
      expect(await aba.complete(), isA<CoordinatorInvalidated>());
    });

    test('invalidation before first call prevents all I/O', () async {
      final source = _FakeSource(context: _context());
      final gateway = _FakeGateway();
      final repository = _FakeRepository();
      final coordinator = _coordinator(
          source: source, gateway: gateway, repository: repository);
      coordinator.invalidate();
      expect(await coordinator.complete(), isA<CoordinatorInvalidated>());
      expect(source.loads, 0);
      expect(gateway.stagedContexts, isEmpty);
      expect(repository.calls, isEmpty);
    });

    test('staging success after disposal or replacement does not dispatch',
        () async {
      for (final retire in <void Function(DriverCompletionCoordinator)>[
        (coordinator) => coordinator.dispose(),
        (coordinator) => coordinator.invalidate(),
      ]) {
        final gate = Completer<void>();
        final gateway = _FakeGateway()
          ..gate = gate
          ..entered = Completer<void>();
        final repository = _FakeRepository();
        final coordinator =
            _coordinator(gateway: gateway, repository: repository);
        final pending = coordinator.complete();
        await gateway.entered!.future;
        retire(coordinator);
        gate.complete();
        expect(await pending, isA<CoordinatorInvalidated>());
        expect(repository.calls, isEmpty);
        expect(coordinator.current, isNull);
      }
    });

    test('session replacement during staging success blocks dispatch',
        () async {
      final gate = Completer<void>();
      final gateway = _FakeGateway()
        ..gate = gate
        ..entered = Completer<void>();
      final repository = _FakeRepository();
      final session = _FakeSession();
      final coordinator = _coordinator(
          gateway: gateway, repository: repository, session: session);
      final pending = coordinator.complete();
      await gateway.entered!.future;
      session.snapshot = _session(driverId: _driverB, epoch: 2);
      gate.complete();
      expect(await pending, isA<CoordinatorInvalidated>());
      expect(repository.calls, isEmpty);
      expect(coordinator.current, isNull);
    });

    test(
        'context replacement while calls overlap shares and invalidates operation',
        () async {
      final gate = Completer<void>();
      final repository = _FakeRepository()
        ..gate = gate
        ..entered = Completer<void>();
      final session = _FakeSession();
      final coordinator =
          _coordinator(repository: repository, session: session);
      final first = coordinator.complete();
      await repository.entered!.future;
      final second = coordinator.complete();
      expect(identical(first, second), isTrue);
      session.snapshot = _session(driverId: _driverB, epoch: 2);
      gate.complete();
      expect(await first, isA<CoordinatorInvalidated>());
      expect(await second, isA<CoordinatorInvalidated>());
      expect(repository.calls, hasLength(1));
      expect(coordinator.current, isNull);
    });

    test('session replacement during staging exception wins over storage error',
        () async {
      final gate = Completer<void>();
      final gateway = _FakeGateway()
        ..gate = gate
        ..entered = Completer<void>()
        ..failure = StateError('disk');
      final session = _FakeSession();
      final coordinator = _coordinator(gateway: gateway, session: session);
      final pending = coordinator.complete();
      await gateway.entered!.future;
      session.snapshot = _session(driverId: _driverB, epoch: 2);
      gate.complete();
      expect(await pending, isA<CoordinatorInvalidated>());
      expect(coordinator.current, isNull);
    });

    test('canonical source exception after session replacement is invalidated',
        () async {
      final gate = Completer<void>();
      final source = _FakeSource(context: _context())
        ..gate = gate
        ..entered = Completer<void>()
        ..failure = StateError('canonical read');
      final session = _FakeSession();
      final coordinator = _coordinator(source: source, session: session);
      final pending = coordinator.complete();
      await source.entered!.future;
      session.snapshot = _session(driverId: _driverB, epoch: 2);
      gate.complete();
      expect(await pending, isA<CoordinatorInvalidated>());
      expect(coordinator.current, isNull);
    });

    test('repository non-completed response stays unresolved', () async {
      final repository = _FakeRepository(
          result: DriverCompleteTripResult(
        tripId: _trip,
        status: DriverTripLifecycleStatus.inProgress,
      ));
      final coordinator = _coordinator(repository: repository);
      expect(await coordinator.complete(), isA<CoordinatorUnresolved>());
    });

    test(
        'existing coordinator evidence after unknown completion is not replayed',
        () async {
      final firstRepository = _FakeRepository()
        ..failure = const DriverTripCompletionException(
            DriverCompletionFailure.unknownResult);
      final first = _coordinator(repository: firstRepository);
      expect(await first.complete(), isA<CoordinatorUnresolved>());
      final recreatedRepository = _FakeRepository();
      final recreated = _coordinator(
        gateway: _FakeGateway(decision: StagingExistingEvidence(_command())),
        repository: recreatedRepository,
      );
      expect(await recreated.complete(), isA<CoordinatorUnresolved>());
      expect(recreatedRepository.calls, isEmpty);
    });
  });

  group('original-key preservation', () {
    test('repository receives the original key, never a rotated one', () async {
      const originalKey = 'original-stable-key-007';
      final source = _FakeSource(
        context: _context(command: _command(key: originalKey)),
      );
      final gateway = _FakeGateway();
      gateway.handler = (context) => StagingNewlyCreated(context.command);
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        source: source,
        gateway: gateway,
        repository: repository,
      );

      final outcome = await coordinator.complete();

      expect(outcome, isA<CoordinatorCompleted>());
      expect(repository.calls.single.idempotencyKey, originalKey);
      expect(
        (outcome as CoordinatorCompleted).stagedCommand.idempotencyKey,
        originalKey,
      );
    });
  });

  group('cached ownership validation retirement', () {
    test(
        'concurrent cached validations cannot return success after ownership loss',
        () async {
      final source = _FakeSource(context: _context());
      final gateway = _FakeGateway();
      final repository = _FakeRepository();
      final session = _FakeSession();
      final coordinator = _coordinator(
        source: source,
        gateway: gateway,
        repository: repository,
        session: session,
      );
      final cached = await coordinator.complete();
      expect(cached, isA<CoordinatorCompleted>());
      final sourceLoads = source.loads;
      final stagingCalls = gateway.stagedContexts.length;
      final dispatchCalls = repository.calls.length;

      final gateX = Completer<DriverCompletionSessionSnapshot>();
      final enteredX = Completer<void>();
      session.nextReadGate = gateX;
      session.nextReadEntered = enteredX;
      final validationX = coordinator.complete();
      await enteredX.future;

      final gateY = Completer<DriverCompletionSessionSnapshot>();
      final enteredY = Completer<void>();
      session.nextReadGate = gateY;
      session.nextReadEntered = enteredY;
      final validationY = coordinator.complete();
      await enteredY.future;

      gateY.complete(_session(driverId: _driverB, epoch: 2));
      expect(await validationY, isA<CoordinatorInvalidated>());
      expect(coordinator.current, isNull);

      gateX.complete(_session(driverId: _driverA, epoch: 1));
      expect(await validationX, isA<CoordinatorInvalidated>());
      expect(coordinator.current, isNull);
      expect(await coordinator.complete(), isA<CoordinatorInvalidated>());
      expect(source.loads, sourceLoads);
      expect(gateway.stagedContexts, hasLength(stagingCalls));
      expect(repository.calls, hasLength(dispatchCalls));
    });

    test(
        'cached session reader exception permanently retires overlapping reads',
        () async {
      final session = _FakeSession();
      final source = _FakeSource(context: _context());
      final gateway = _FakeGateway();
      final repository = _FakeRepository();
      final coordinator = _coordinator(
        source: source,
        gateway: gateway,
        repository: repository,
        session: session,
      );
      expect(await coordinator.complete(), isA<CoordinatorCompleted>());
      final sourceLoads = source.loads;
      final stagingCalls = gateway.stagedContexts.length;
      final dispatchCalls = repository.calls.length;

      final gateX = Completer<DriverCompletionSessionSnapshot>();
      final enteredX = Completer<void>();
      session.nextReadGate = gateX;
      session.nextReadEntered = enteredX;
      final validationX = coordinator.complete();
      await enteredX.future;

      final gateY = Completer<DriverCompletionSessionSnapshot>();
      final enteredY = Completer<void>();
      session.nextReadGate = gateY;
      session.nextReadEntered = enteredY;
      final validationY = coordinator.complete();
      await enteredY.future;

      gateY.completeError(StateError('session unavailable'));
      expect(await validationY, isA<CoordinatorInvalidated>());
      expect(coordinator.current, isNull);
      gateX.complete(_session(driverId: _driverA, epoch: 1));
      expect(await validationX, isA<CoordinatorInvalidated>());
      expect(await coordinator.complete(), isA<CoordinatorInvalidated>());
      expect(source.loads, sourceLoads);
      expect(gateway.stagedContexts, hasLength(stagingCalls));
      expect(repository.calls, hasLength(dispatchCalls));
    });

    test('dispose and invalidate retire pending cached ownership reads',
        () async {
      for (final retire in <void Function(DriverCompletionCoordinator)>[
        (coordinator) => coordinator.dispose(),
        (coordinator) => coordinator.invalidate(),
      ]) {
        final session = _FakeSession();
        final coordinator = _coordinator(session: session);
        expect(await coordinator.complete(), isA<CoordinatorCompleted>());

        final gate = Completer<DriverCompletionSessionSnapshot>();
        final entered = Completer<void>();
        session.nextReadGate = gate;
        session.nextReadEntered = entered;
        final pending = coordinator.complete();
        await entered.future;
        retire(coordinator);
        gate.complete(_session());
        expect(await pending, isA<CoordinatorInvalidated>());
        expect(coordinator.current, isNull);
        expect(await coordinator.complete(), isA<CoordinatorInvalidated>());
      }
    });

    test('cached success remains reusable while ownership is unchanged',
        () async {
      final coordinator = _coordinator();
      final first = await coordinator.complete();
      expect(first, isA<CoordinatorCompleted>());
      final second = await coordinator.complete();
      expect(identical(second, first), isTrue);
      expect(coordinator.current, same(first));
    });

    test('cached ownership loss retires signed-out and unapproved sessions',
        () async {
      for (final replacement in [
        _session(driverId: null),
        _session(approved: false),
      ]) {
        final session = _FakeSession();
        final coordinator = _coordinator(session: session);
        expect(await coordinator.complete(), isA<CoordinatorCompleted>());
        session.snapshot = replacement;
        expect(await coordinator.complete(), isA<CoordinatorInvalidated>());
        expect(coordinator.current, isNull);
        session.snapshot = _session();
        expect(await coordinator.complete(), isA<CoordinatorInvalidated>());
      }
    });
  });
}
