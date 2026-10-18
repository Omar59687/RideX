import 'package:ridex/core/models/canonical_trip_reconciliation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/canonical_trip_reconciliation_repository.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';

/// Optional in-memory handoff, never persisted or reconstructed from Journal
/// bytes. Trusted composition supplies the original attempt's actual authority,
/// not the currently active account relabeled as that attempt's owner. Across
/// process restart only the original command survives in the existing Journal.
final class DriverCompletionRecoverySeed {
  DriverCompletionRecoverySeed.fromOutcome({
    required this.owner,
    required DriverCoordinatorOutcome outcome,
  }) {
    switch (outcome) {
      case CoordinatorCompleted(stagedCommand: final c, result: final r):
        command = c;
        attempt = null;
        completion = r;
      case CoordinatorUnresolved(stagedCommand: final c, attempt: final a):
        command = c;
        attempt = a;
        completion = a?.confirmedTrip;
      default:
        throw ArgumentError('A staged completion outcome is required.');
    }
    final retained = completion;
    if ((attempt != null && !attempt!.command.isExactReplayOf(command)) ||
        (retained != null &&
            (!retained.isCompleted ||
                retained.tripId.toLowerCase() !=
                    command.tripId.toLowerCase()))) {
      throw ArgumentError('Evidence must belong to the original command.');
    }
  }

  final CanonicalTripReadSession owner;
  late final DriverCompleteTripCommand command;
  late final DriverCompletionAttemptException? attempt;
  late final DriverCompleteTripResult? completion;
}

enum DriverReadOnlyRecoveryDisposition {
  completedTrip,
  terminalNonCompletedTrip,
  nonterminalTrip,
  notVisible,
  readFailed,
  noJournalEvidence,
  journalBlocked,
  conflictingEvidence,
  invalidated,
}

/// A canonical observation, never proof that the historical command executed.
/// No outcome grants dispatch, replacement intent or Journal retirement rights.
final class DriverReadOnlyRecoveryOutcome {
  const DriverReadOnlyRecoveryOutcome._(
    this.disposition, {
    this.command,
    this.observedTrip,
    this.strongestTrip,
    this.retainedCompletion,
    this.attempt,
    this.readFailure,
    this.journalIssue,
  });

  final DriverReadOnlyRecoveryDisposition disposition;
  final DriverCompleteTripCommand? command;

  /// This read's matching observation, if any; separate from historical truth.
  final CanonicalTripEvidence? observedTrip;

  /// Previously verified completion is retained after weaker/failed rereads.
  final CanonicalTripEvidence? strongestTrip;

  /// Exact prior result only, preserving any genuine receipt verification.
  /// Null or receiptVerified=false never means receipt absence. This slice
  /// performs no receipt read and cannot establish absence or issuance.
  final DriverCompleteTripResult? retainedCompletion;
  final DriverCompletionAttemptException? attempt;
  final CanonicalTripReadFailure? readFailure;
  final CompletionJournalIssue? journalIssue;
}

/// Explicit, unwired recovery for one known Trip/account/backend/lifecycle.
/// Uses only Journal.inspect and the merged canonical reader. It has no
/// completion repository, staging gateway, payment or SharedPreferences seam.
///
/// The approved synchronous authority must observe every lifecycle transition.
/// Composition must bind it to the canonical transport's authenticated client.
/// Latest invocation owns publication; an older success/error cannot overwrite
/// newer verified evidence. Invalidated/disposed instances cannot be reused.
final class DriverCompletionRecoveryCoordinator {
  DriverCompletionRecoveryCoordinator({
    required this.tripId,
    required CanonicalTripReadSession owner,
    required DriverCompletionCommandStore journal,
    required CanonicalTripReconciliationRepository repository,
    required CanonicalTripLifecycleReader sessionReader,
    DriverCompletionRecoverySeed? seed,
  })  : _owner = owner,
        _journal = journal,
        _repository = repository,
        _sessionReader = sessionReader,
        _seed = seed;

  final String tripId;
  final CanonicalTripReadSession _owner;
  final DriverCompletionCommandStore _journal;
  final CanonicalTripReconciliationRepository _repository;
  final CanonicalTripLifecycleReader _sessionReader;
  final DriverCompletionRecoverySeed? _seed;
  int _generation = 0;
  bool _invalidated = false;
  bool _seedAccepted = false;
  CanonicalTripEvidence? _strongest;
  DriverCompleteTripCommand? _command;
  DriverReadOnlyRecoveryOutcome? _current;

  DriverReadOnlyRecoveryOutcome? get current => _current;

  void invalidate() {
    _invalidated = true;
    _generation++;
    _current = null;
    _strongest = null;
    _command = null;
    _seedAccepted = false;
  }

  void dispose() => invalidate();

  bool _owns(int generation) {
    if (_invalidated || generation != _generation) return false;
    try {
      if (_owner.isApprovedDriver &&
          _owner.epoch >= 0 &&
          _owner.driverId != null &&
          isCompletionJournalIdentityValid(
            backendNamespace: _owner.backendNamespace,
            driverId: _owner.driverId!,
            tripId: tripId,
          ) &&
          _owner.sameAuthority(_sessionReader())) {
        return true;
      }
    } on Object {
      // An unavailable authority cannot publish account-owned evidence.
    }
    invalidate();
    return false;
  }

  static const _stale = DriverReadOnlyRecoveryOutcome._(
    DriverReadOnlyRecoveryDisposition.invalidated,
  );

  Future<DriverReadOnlyRecoveryOutcome> recover() async {
    final generation = ++_generation;
    if (!_owns(generation)) return _stale;

    final CompletionSlot slot;
    try {
      slot = await _journal.inspect(
        backendNamespace: _owner.backendNamespace,
        driverId: _owner.driverId!,
        tripId: tripId,
      );
    } on Object {
      return _publish(
          generation, DriverReadOnlyRecoveryDisposition.journalBlocked,
          journalIssue: CompletionJournalIssue.storageUnavailable);
    }
    if (!_owns(generation)) return _stale;
    switch (slot) {
      case CompletionAbsent():
        return _publish(
            generation, DriverReadOnlyRecoveryDisposition.noJournalEvidence);
      case CompletionCorrupt(issue: final issue):
      case CompletionUnavailable(issue: final issue):
        return _publish(
            generation, DriverReadOnlyRecoveryDisposition.journalBlocked,
            journalIssue: issue);
      case CompletionValid(command: final command):
        if (command.tripId.toLowerCase() != tripId.toLowerCase() ||
            (_command != null && !_command!.isExactReplayOf(command)) ||
            (_seed != null &&
                (!_seed.owner.sameAuthority(_owner) ||
                    !_seed.command.isExactReplayOf(command)))) {
          return _publish(generation,
              DriverReadOnlyRecoveryDisposition.conflictingEvidence);
        }
        _command = command;
        _seedAccepted = _seed != null;
    }

    final retained = _seed?.completion;
    if (_strongest == null && retained?.backendVersion != null) {
      _strongest = CanonicalTripEvidence(
        tripId: retained!.tripId,
        driverId: _owner.driverId!,
        status: retained.status,
        backendVersion: retained.backendVersion!,
      );
    }
    final CanonicalTripReadOutcome read;
    try {
      read = await _repository.readCanonicalTrip(
        command: _command!,
        capturedDriverId: _owner.driverId!,
        capturedBackendNamespace: _owner.backendNamespace,
      );
    } on Object {
      return _publish(generation, DriverReadOnlyRecoveryDisposition.readFailed,
          readFailure: CanonicalTripReadFailure.transportUncertain);
    }
    if (!_owns(generation)) return _stale;
    switch (read) {
      case CanonicalTripNotVisible():
        return _publish(
            generation, DriverReadOnlyRecoveryDisposition.notVisible);
      case CanonicalTripReadFailed(failure: final failure):
        if (failure == CanonicalTripReadFailure.sessionInvalidated) {
          invalidate();
          return _stale;
        }
        return _publish(
            generation, DriverReadOnlyRecoveryDisposition.readFailed,
            readFailure: failure);
      case CanonicalTripVisible(trip: final trip, session: final session):
        if (!session.sameAuthority(_owner)) {
          invalidate();
          return _stale;
        }
        if (trip.tripId.toLowerCase() != tripId.toLowerCase() ||
            trip.driverId.toLowerCase() != _owner.driverId!.toLowerCase()) {
          return _publish(
              generation, DriverReadOnlyRecoveryDisposition.readFailed,
              readFailure: CanonicalTripReadFailure.foreignEvidence);
        }
        final previous = _strongest;
        if (previous != null &&
            (trip.backendVersion < previous.backendVersion ||
                (previous.status == DriverTripLifecycleStatus.completed &&
                    trip.status != DriverTripLifecycleStatus.completed) ||
                (trip.backendVersion == previous.backendVersion &&
                    trip.status != previous.status))) {
          return _publish(
              generation, DriverReadOnlyRecoveryDisposition.conflictingEvidence,
              observedTrip: trip);
        }
        _strongest = trip;
        final disposition = switch (trip.status) {
          DriverTripLifecycleStatus.completed =>
            DriverReadOnlyRecoveryDisposition.completedTrip,
          DriverTripLifecycleStatus.cancelledByRider ||
          DriverTripLifecycleStatus.cancelledByDriver ||
          DriverTripLifecycleStatus.cancelledByAdmin ||
          DriverTripLifecycleStatus.failed =>
            DriverReadOnlyRecoveryDisposition.terminalNonCompletedTrip,
          _ => DriverReadOnlyRecoveryDisposition.nonterminalTrip,
        };
        return _publish(generation, disposition, observedTrip: trip);
    }
  }

  DriverReadOnlyRecoveryOutcome _publish(
    int generation,
    DriverReadOnlyRecoveryDisposition disposition, {
    CanonicalTripEvidence? observedTrip,
    CanonicalTripReadFailure? readFailure,
    CompletionJournalIssue? journalIssue,
  }) {
    if (!_owns(generation)) return _stale;
    return _current = DriverReadOnlyRecoveryOutcome._(
      disposition,
      command: _command,
      observedTrip: observedTrip,
      strongestTrip: _strongest,
      retainedCompletion: _seedAccepted ? _seed?.completion : null,
      attempt: _seedAccepted ? _seed?.attempt : null,
      readFailure: readFailure,
      journalIssue: journalIssue,
    );
  }
}
