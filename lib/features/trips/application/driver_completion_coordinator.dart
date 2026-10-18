import 'dart:async';

import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/driver_trip_completion_repository.dart';

/// Validated canonical context for one driver completion intent.
///
/// The context is supplied by an injected [CanonicalDriverCompletionSource],
/// never derived from mock identifiers. [driverId] is the captured account
/// identity (trimmed, nonempty); the staging gateway enforces its own
/// backend-namespace rules. [command] already enforces the canonical Trip
/// UUID, a positive expected version, and a 1..128 character idempotency
/// key, and is preserved byte-identically through staging and dispatch.
class CanonicalDriverCompletionContext {
  CanonicalDriverCompletionContext({
    required String driverId,
    required this.command,
  }) : driverId = driverId.trim() {
    if (this.driverId.isEmpty) {
      throw ArgumentError.value(
        driverId,
        'driverId',
        'Must be nonempty.',
      );
    }
  }

  /// Captured owning Driver identity for this intent.
  final String driverId;

  /// Original canonical command triple. Never mutated by the coordinator.
  final DriverCompleteTripCommand command;
}

/// Current session snapshot observed by the coordinator.
///
/// Read before and after every awaited boundary. Any change in owning
/// driver, approval, or epoch invalidates in-flight work: publication into
/// a changed session is forbidden and durable evidence is preserved.
class DriverCompletionSessionSnapshot {
  const DriverCompletionSessionSnapshot({
    required this.driverId,
    required this.epoch,
    required this.isApprovedDriver,
  });

  /// Authenticated Driver identity, or null when signed out.
  final String? driverId;

  /// Monotonic session/lifecycle epoch. Logout, account replacement,
  /// approval loss, and provider disposal all advance it.
  final int epoch;

  /// True only for an authenticated, approved, non-blocked Driver.
  final bool isApprovedDriver;

  bool sameOwner(DriverCompletionSessionSnapshot other) {
    return driverId == other.driverId &&
        epoch == other.epoch &&
        isApprovedDriver == other.isApprovedDriver;
  }
}

/// Closed staging-block reasons. Never carries paths, records, or errors.
enum StagingBlockReason {
  invalidIdentity,
  storageUnavailable,
  persistenceUncertain,
  corruptEvidence,
}

/// Store-agnostic staging decision for one canonical context.
///
/// This gateway is intentionally narrow: it stages or inspects durable
/// intent evidence only. It never dispatches, retries, rotates keys,
/// retires records, or clears unresolved evidence. Production binding
/// (which durable store backs this gateway) remains a Developer 1
/// decision; test fakes implement this interface directly.
sealed class CoordinatorStagingDecision {
  const CoordinatorStagingDecision();
}

/// A newly created intent whose durable write was positively acknowledged.
final class StagingNewlyCreated extends CoordinatorStagingDecision {
  const StagingNewlyCreated(this.storedCommand);

  final DriverCompleteTripCommand storedCommand;
}

/// An exact pre-existing record. It is evidence for reconciliation only and
/// never grants dispatch permission to a new coordinator.
final class StagingExistingEvidence extends CoordinatorStagingDecision {
  const StagingExistingEvidence(this.storedCommand);

  final DriverCompleteTripCommand storedCommand;
}

/// A different unresolved intent already owns the slot. No dispatch.
final class StagingConflict extends CoordinatorStagingDecision {
  const StagingConflict();
}

/// Staging cannot prove durable evidence. No dispatch.
final class StagingBlocked extends CoordinatorStagingDecision {
  const StagingBlocked(this.reason);

  final StagingBlockReason reason;
}

/// Supplies the validated canonical context, or null when no eligible
/// canonical Trip is available (wrong status, unapproved driver, hidden
/// row). Returning null blocks staging and dispatch without I/O side
/// effects. Never synthesizes a command from mock identifiers.
abstract interface class CanonicalDriverCompletionSource {
  Future<CanonicalDriverCompletionContext?> load();
}

/// Stages durable intent before any dispatch.
///
/// Implementations must create-or-load exactly one unresolved intent,
/// verify the write, and return [StagingNewlyCreated] only for a positively
/// acknowledged new intent, or [StagingExistingEvidence] for a prior record.
/// Any absent, corrupt, conflicting, or
/// uncertain persistence evidence must surface as [StagingConflict] or
/// [StagingBlocked], which both forbid dispatch.
abstract interface class DriverCompletionStagingGateway {
  Future<CoordinatorStagingDecision> stage(
    CanonicalDriverCompletionContext context,
  );
}

/// Reads the current session snapshot. Called before and after every
/// awaited staging/repository boundary.
typedef DriverCompletionSessionReader = Future<DriverCompletionSessionSnapshot>
    Function();

/// One-shot driver completion outcome. Exactly one value is produced per
/// coordinator lifetime; later [DriverCompletionCoordinator.complete] calls
/// return the settled value without new staging or dispatch, so recovery
/// always requires explicit reconciliation (a new coordinator with a
/// freshly authorized context).
sealed class DriverCoordinatorOutcome {
  const DriverCoordinatorOutcome();
}

/// Backend-confirmed `completed` Trip.
///
/// [result] is surfaced exactly as the repository returned it:
/// [DriverCompleteTripResult.backendVersion] comes only from an authorized
/// canonical reread, [DriverCompleteTripResult.receiptVerified] is true
/// only after an authorized driver-safe receipt reread, and completion
/// never implies payment success. Cash settlement and receipt issuance
/// stay trusted backend consequences.
final class CoordinatorCompleted extends DriverCoordinatorOutcome {
  const CoordinatorCompleted(this.result, {required this.stagedCommand});

  final DriverCompleteTripResult result;
  final DriverCompleteTripCommand stagedCommand;
}

/// Backend-confirmed rejection. No blind retry with a fresh key.
final class CoordinatorRejected extends DriverCoordinatorOutcome {
  const CoordinatorRejected(this.failure, {required this.stagedCommand});

  final DriverCompletionFailure failure;
  final DriverCompleteTripCommand stagedCommand;
}

/// The backend reported a stale expected version.
///
/// The original triple is preserved. A bumped version is a different
/// intent: the coordinator never mutates the staged version and never
/// creates the replacement intent. A new explicitly staged intent is
/// required if still eligible.
final class CoordinatorStaleVersion extends DriverCoordinatorOutcome {
  const CoordinatorStaleVersion({required this.stagedCommand});

  final DriverCompleteTripCommand stagedCommand;
}

/// The outcome is unknown. Retained for explicit reconciliation.
///
/// Covers transport loss, malformed responses, mismatched identities, and
/// unexpected errors. Never reported as confirmed rejection or success.
/// The original triple is preserved; only an exact replay after an
/// authorized canonical reread is permitted, and this coordinator never
/// performs that replay automatically.
final class CoordinatorUnresolved extends DriverCoordinatorOutcome {
  const CoordinatorUnresolved({
    required this.stagedCommand,
    this.failure,
    this.attempt,
  });

  final DriverCompleteTripCommand stagedCommand;
  final DriverCompletionFailure? failure;

  /// Validated stage-aware evidence for this exact staged command. Legacy
  /// consumers still see unresolved; no exception grants replay or retirement.
  final DriverCompletionAttemptException? attempt;
}

/// Staging could not prove durable evidence. No dispatch occurred.
final class CoordinatorBlocked extends DriverCoordinatorOutcome {
  const CoordinatorBlocked(this.reason);

  final StagingBlockReason reason;
}

/// Conflicting durable evidence owns the slot. No dispatch occurred.
final class CoordinatorConflict extends DriverCoordinatorOutcome {
  const CoordinatorConflict();
}

/// No eligible canonical context exists. No staging or dispatch occurred.
final class CoordinatorNoContext extends DriverCoordinatorOutcome {
  const CoordinatorNoContext();
}

/// The active session cannot own a dispatch. No staging or dispatch
/// occurred. Covers signed-out, unapproved, mismatched, or changed
/// sessions observed before staging.
final class CoordinatorSessionInvalid extends DriverCoordinatorOutcome {
  const CoordinatorSessionInvalid();
}

/// In-flight work was retired before it could publish.
///
/// Covers disposal, explicit invalidation (state replacement / provider
/// recreation), and session/account changes observed after staging or
/// dispatch started. The in-flight backend result, if any, is discarded:
/// it never changes [DriverCompletionCoordinator.current]. Durable staged
/// evidence, when already captured, is preserved in [stagedCommand] for
/// authorized reconciliation; nothing is cleared or retired here.
final class CoordinatorInvalidated extends DriverCoordinatorOutcome {
  const CoordinatorInvalidated({this.stagedCommand});

  final DriverCompleteTripCommand? stagedCommand;
}

/// Isolated driver completion coordinator (Developer 3 slice).
///
/// Independent of production providers and the existing mock
/// [ActiveTripController] flow. It consumes only injected seams:
/// a validated canonical source, a store-agnostic staging gateway, the
/// approved completion repository interface, and a session reader.
///
/// Guarantees:
/// - Stage-before-dispatch: the repository is invoked only after
///   [StagingNewlyCreated] with a verified exact replay of the original triple.
/// - Exact identity: trip UUID, original version, and original idempotency
///   key are preserved byte-identically; rotated keys or bumped versions
///   are never treated as replays.
/// - Single-flight: concurrent [complete] calls share one staging +
///   dispatch operation.
/// - Session/lifecycle safety: the session snapshot is checked before and
///   after every await; logout, account switch (including A->B->A),
///   approval loss, [invalidate], or [dispose] retires publication rights
///   without erasing durable evidence or cancelling an airborne RPC.
/// - Repository exceptions stay unresolved for compatibility. Stage-aware
///   exceptions retain their validated evidence for explicit read-only recovery.
/// - Confirmed completion is distinct from receipt verification
///   ([DriverCompleteTripResult.receiptVerified]) and never declares
///   payment success.
/// - No automatic retry, key rotation, retirement, or clearing of
///   unresolved evidence. No Supabase, provider, router, migration, or
///   payment-model dependency.
class DriverCompletionCoordinator {
  DriverCompletionCoordinator({
    required CanonicalDriverCompletionSource canonicalSource,
    required DriverCompletionStagingGateway stagingGateway,
    required DriverTripCompletionRepository repository,
    required DriverCompletionSessionReader sessionReader,
  })  : _canonicalSource = canonicalSource,
        _stagingGateway = stagingGateway,
        _repository = repository,
        _sessionReader = sessionReader;

  final CanonicalDriverCompletionSource _canonicalSource;
  final DriverCompletionStagingGateway _stagingGateway;
  final DriverTripCompletionRepository _repository;
  final DriverCompletionSessionReader _sessionReader;

  int _generation = 0;
  bool _disposed = false;
  bool _retired = false;
  DriverCompletionSessionSnapshot? _owner;
  Future<DriverCoordinatorOutcome>? _inFlight;
  DriverCoordinatorOutcome? _settled;
  DriverCoordinatorOutcome? _current;

  /// Currently published outcome, or null before the first settlement.
  ///
  /// Only updated by the owning generation. Stale async results arriving
  /// after [invalidate], [dispose], or a session change never modify it.
  DriverCoordinatorOutcome? get current => _current;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Retires publication rights for in-flight and future work.
  ///
  /// Simulates UI state replacement or provider recreation. Durable staged
  /// evidence is preserved; an airborne RPC is never claimed cancelled.
  /// The in-flight [complete] future still settles, but as
  /// [CoordinatorInvalidated] without publishing.
  void invalidate() {
    _retire();
  }

  /// Permanently retires this coordinator. See [invalidate] for semantics.
  /// Later [complete] calls return [CoordinatorInvalidated] without I/O.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retire();
  }

  /// Permanently revokes this coordinator's cached and in-flight authority.
  /// Persisted commands are deliberately left untouched.
  void _retire() {
    if (!_retired) {
      _retired = true;
      _generation++;
    }
    _settled = null;
    _current = null;
    _owner = null;
  }

  /// Stages (once) then dispatches (once) the canonical completion intent.
  ///
  /// Concurrent callers share the same future. After settlement, later
  /// calls return the settled outcome without new staging or dispatch.
  Future<DriverCoordinatorOutcome> complete() {
    if (_retired || _disposed) {
      return Future.value(const CoordinatorInvalidated());
    }
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final settled = _settled;
    if (settled != null) {
      return _validateCached(settled);
    }
    final future = _runOnce();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }

  Future<DriverCoordinatorOutcome> _validateCached(
    DriverCoordinatorOutcome cached,
  ) async {
    final generation = _generation;
    final owner = _owner;
    if (_retired || _disposed || owner == null) {
      if (!_retired && !_disposed) _retire();
      return const CoordinatorInvalidated();
    }
    try {
      final current = await _sessionReader();
      if (!_isCurrent(generation)) {
        return const CoordinatorInvalidated();
      }
      if (!_isUsableSession(current) || !current.sameOwner(owner)) {
        _retire();
        return const CoordinatorInvalidated();
      }
      return cached;
    } on Object {
      if (!_isCurrent(generation)) {
        return const CoordinatorInvalidated();
      }
      _retire();
      return const CoordinatorInvalidated();
    }
  }

  Future<DriverCoordinatorOutcome> _runOnce() async {
    final generation = _generation;
    if (_retired || _disposed || !_isCurrent(generation)) {
      return _settle(
        generation,
        const CoordinatorInvalidated(),
        publish: false,
      );
    }

    final DriverCompletionSessionSnapshot sessionBefore;
    try {
      sessionBefore = await _sessionReader();
    } on Object {
      if (!_isCurrent(generation)) {
        return _settle(generation, const CoordinatorInvalidated(),
            publish: false);
      }
      return _settle(
        generation,
        const CoordinatorSessionInvalid(),
      );
    }
    if (!_isCurrent(generation) || _disposed) {
      return _settle(
        generation,
        const CoordinatorInvalidated(),
        publish: false,
      );
    }
    if (!_isUsableSession(sessionBefore)) {
      return _settle(
        generation,
        const CoordinatorSessionInvalid(),
      );
    }
    _owner = sessionBefore;

    final CanonicalDriverCompletionContext? context;
    try {
      context = await _canonicalSource.load();
    } on Object {
      return _exceptionAfterBoundary(generation, sessionBefore, null);
    }
    if (!_isCurrent(generation) || _disposed) {
      return _settle(
        generation,
        const CoordinatorInvalidated(),
        publish: false,
      );
    }
    final DriverCompletionSessionSnapshot sessionAfterLoad;
    try {
      sessionAfterLoad = await _sessionReader();
    } on Object {
      return _settle(
        generation,
        const CoordinatorInvalidated(),
        publish: false,
      );
    }
    if (!_isCurrent(generation) ||
        _disposed ||
        !sessionAfterLoad.sameOwner(sessionBefore)) {
      return _settle(
        generation,
        const CoordinatorInvalidated(),
        publish: false,
      );
    }
    if (context == null) {
      return _settle(
        generation,
        const CoordinatorNoContext(),
      );
    }
    if (context.driverId != sessionBefore.driverId) {
      return _settle(
        generation,
        const CoordinatorSessionInvalid(),
      );
    }

    final CoordinatorStagingDecision decision;
    try {
      decision = await _stagingGateway.stage(context);
    } on Object {
      return _exceptionAfterBoundary(
        generation,
        sessionBefore,
        const CoordinatorBlocked(StagingBlockReason.storageUnavailable),
      );
    }
    if (!_isCurrent(generation) || _disposed) {
      return _settle(
        generation,
        const CoordinatorInvalidated(),
        publish: false,
      );
    }
    final DriverCompletionSessionSnapshot sessionAfterStage;
    try {
      sessionAfterStage = await _sessionReader();
    } on Object {
      return _settle(
        generation,
        const CoordinatorInvalidated(),
        publish: false,
      );
    }
    if (!_isCurrent(generation) ||
        _disposed ||
        !sessionAfterStage.sameOwner(sessionBefore)) {
      final stagedForInvalidation = switch (decision) {
        StagingNewlyCreated(storedCommand: final stored) => stored,
        StagingExistingEvidence(storedCommand: final stored) => stored,
        _ => null,
      };
      return _settle(
        generation,
        CoordinatorInvalidated(stagedCommand: stagedForInvalidation),
        publish: false,
      );
    }

    final DriverCompleteTripCommand stagedCommand;
    switch (decision) {
      case StagingNewlyCreated(storedCommand: final stored):
        if (!stored.isExactReplayOf(context.command)) {
          return _settle(
            generation,
            const CoordinatorConflict(),
          );
        }
        stagedCommand = stored;
      case StagingExistingEvidence(storedCommand: final stored):
        if (!stored.isExactReplayOf(context.command)) {
          return _settle(generation, const CoordinatorConflict());
        }
        return _settle(
          generation,
          CoordinatorUnresolved(stagedCommand: stored),
        );
      case StagingConflict():
        return _settle(
          generation,
          const CoordinatorConflict(),
        );
      case StagingBlocked(reason: final reason):
        return _settle(
          generation,
          CoordinatorBlocked(reason),
        );
    }

    final DriverCompleteTripResult result;
    try {
      result = await _repository.completeTrip(stagedCommand);
    } on DriverCompletionAttemptException catch (error) {
      final matches = error.command.isExactReplayOf(stagedCommand);
      return _settleAfterDispatch(
        generation,
        sessionBefore,
        stagedCommand,
        CoordinatorUnresolved(
          stagedCommand: stagedCommand,
          failure: matches
              ? error.failure
              : DriverCompletionFailure.malformedResponse,
          attempt: matches ? error : null,
        ),
      );
    } on DriverTripCompletionException catch (error) {
      return _settleAfterDispatch(
        generation,
        sessionBefore,
        stagedCommand,
        CoordinatorUnresolved(
            stagedCommand: stagedCommand, failure: error.failure),
      );
    } on Object {
      return _settleAfterDispatch(
        generation,
        sessionBefore,
        stagedCommand,
        CoordinatorUnresolved(
          stagedCommand: stagedCommand,
          failure: DriverCompletionFailure.unknownResult,
        ),
      );
    }

    if (!_isCurrent(generation)) {
      return _settle(
        generation,
        CoordinatorInvalidated(stagedCommand: stagedCommand),
        publish: false,
      );
    }
    final DriverCompletionSessionSnapshot sessionAfterDispatch;
    try {
      sessionAfterDispatch = await _sessionReader();
    } on Object {
      return _settle(
        generation,
        CoordinatorInvalidated(stagedCommand: stagedCommand),
        publish: false,
      );
    }
    if (!_isCurrent(generation) ||
        _disposed ||
        !sessionAfterDispatch.sameOwner(sessionBefore)) {
      return _settle(
        generation,
        CoordinatorInvalidated(stagedCommand: stagedCommand),
        publish: false,
      );
    }

    if (result.tripId.toLowerCase() != stagedCommand.tripId.toLowerCase() ||
        !result.isCompleted) {
      return _settle(
        generation,
        CoordinatorUnresolved(
          stagedCommand: stagedCommand,
          failure: DriverCompletionFailure.malformedResponse,
        ),
      );
    }
    return _settle(
      generation,
      CoordinatorCompleted(result, stagedCommand: stagedCommand),
    );
  }

  bool _isCurrent(int generation) =>
      !_retired && !_disposed && generation == _generation;

  Future<DriverCoordinatorOutcome> _exceptionAfterBoundary(
    int generation,
    DriverCompletionSessionSnapshot owner,
    DriverCoordinatorOutcome? fallback,
  ) async {
    if (!_isCurrent(generation)) {
      return _settle(generation, const CoordinatorInvalidated(),
          publish: false);
    }
    try {
      final current = await _sessionReader();
      if (!_isCurrent(generation) || !current.sameOwner(owner)) {
        if (_generation == generation && !_disposed) _current = null;
        return _settle(generation, const CoordinatorInvalidated(),
            publish: false);
      }
      return _settle(generation, fallback ?? const CoordinatorSessionInvalid());
    } on Object {
      return _settle(generation, const CoordinatorInvalidated(),
          publish: false);
    }
  }

  bool _isUsableSession(DriverCompletionSessionSnapshot snapshot) {
    final driverId = snapshot.driverId;
    return driverId != null &&
        driverId.trim().isNotEmpty &&
        snapshot.isApprovedDriver;
  }

  /// Settles a post-dispatch outcome only when the owning generation and
  /// session still own publication rights. Otherwise discards the backend
  /// result as [CoordinatorInvalidated] while preserving [stagedCommand].
  Future<DriverCoordinatorOutcome> _settleAfterDispatch(
    int generation,
    DriverCompletionSessionSnapshot sessionBefore,
    DriverCompleteTripCommand stagedCommand,
    DriverCoordinatorOutcome outcome,
  ) async {
    if (!_isCurrent(generation)) {
      return _settle(
        generation,
        CoordinatorInvalidated(stagedCommand: stagedCommand),
        publish: false,
      );
    }
    final DriverCompletionSessionSnapshot sessionAfter;
    try {
      sessionAfter = await _sessionReader();
    } on Object {
      return _settle(
        generation,
        CoordinatorInvalidated(stagedCommand: stagedCommand),
        publish: false,
      );
    }
    if (!_isCurrent(generation) || !sessionAfter.sameOwner(sessionBefore)) {
      return _settle(
        generation,
        CoordinatorInvalidated(stagedCommand: stagedCommand),
        publish: false,
      );
    }
    return _settle(generation, outcome);
  }

  DriverCoordinatorOutcome _settle(
    int generation,
    DriverCoordinatorOutcome outcome, {
    bool publish = true,
  }) {
    if (!_isCurrent(generation)) {
      final invalidated = outcome is CoordinatorInvalidated
          ? outcome
          : CoordinatorInvalidated(
              stagedCommand: switch (outcome) {
                CoordinatorCompleted(stagedCommand: final c) => c,
                CoordinatorRejected(stagedCommand: final c) => c,
                CoordinatorStaleVersion(stagedCommand: final c) => c,
                CoordinatorUnresolved(stagedCommand: final c) => c,
                _ => null,
              },
            );
      return invalidated;
    }
    if (publish) {
      _current = outcome;
    }
    _settled ??= outcome;
    return outcome;
  }
}
