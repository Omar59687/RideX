import 'package:ridex/core/models/driver_trip_completion.dart';

/// Closed diagnostic vocabulary. Never includes paths, raw records or errors.
enum CompletionJournalIssue {
  invalidIdentity,
  storageUnavailable,
  synchronizationUnavailable,
  persistenceUncertain,
  invalidFrame,
  invalidRecord,
  unsupportedSchema,
  ownershipMismatch,
  conflictingEvidence,
  sizeLimit,
}

sealed class CompletionSlot {
  const CompletionSlot();
}

sealed class CompletionDriverSnapshot {
  const CompletionDriverSnapshot();
}

final class CompletionDriverCommands extends CompletionDriverSnapshot {
  const CompletionDriverCommands(this.commands);
  final List<DriverCompleteTripCommand> commands;
}

final class CompletionDriverUnavailable extends CompletionDriverSnapshot {
  const CompletionDriverUnavailable(this.issue);
  final CompletionJournalIssue issue;
}

final class CompletionAbsent extends CompletionSlot {
  const CompletionAbsent();
}

final class CompletionValid extends CompletionSlot {
  const CompletionValid(this.command);
  final DriverCompleteTripCommand command;
}

final class CompletionCorrupt extends CompletionSlot {
  const CompletionCorrupt(this.issue);
  final CompletionJournalIssue issue;
}

final class CompletionUnavailable extends CompletionSlot {
  const CompletionUnavailable(this.issue);
  final CompletionJournalIssue issue;
}

sealed class CompletionStageResult {
  const CompletionStageResult();
}

final class CompletionCreated extends CompletionStageResult {
  const CompletionCreated(this.command);
  final DriverCompleteTripCommand command;
}

final class CompletionExisting extends CompletionStageResult {
  const CompletionExisting(this.command);
  final DriverCompleteTripCommand command;
}

enum CompletionConflictKind { tripOccupied, keyReused }

/// Deliberately does not expose another Trip's stored command.
final class CompletionConflict extends CompletionStageResult {
  const CompletionConflict(this.kind);
  final CompletionConflictKind kind;
}

final class CompletionBlocked extends CompletionStageResult {
  const CompletionBlocked(this.issue);
  final CompletionJournalIssue issue;
}

/// Local recovery evidence only. No outcome, authentication, dispatch, replay,
/// retirement, replacement, expiry, or key-generation capability.
///
/// Backend namespaces are explicit 1..64 ASCII characters, starting with an
/// alphanumeric and otherwise allowing alphanumerics, '.', '_', ':' and '-'.
/// They identify a backend/environment, not a URL or secret. Driver/Trip
/// identities must be UUID-shaped without surrounding whitespace. UUID case
/// is ignored for slot ownership, but the supplied normalized command triple
/// is preserved exactly and compared using isExactReplayOf.
///
/// Callers supply captured account identity; implementations never follow an
/// ambient active account. Account separation is not local encryption or
/// authentication. Canonical eligibility and session checks belong upstream.
abstract interface class DriverCompletionCommandStore {
  /// Read-only startup discovery for one captured Driver/backend partition.
  /// Implementations must not append, flush, repair or retire command evidence.
  Future<CompletionDriverSnapshot> inspectDriver({
    required String backendNamespace,
    required String driverId,
  });

  Future<CompletionSlot> inspect({
    required String backendNamespace,
    required String driverId,
    required String tripId,
  });

  /// Creates an immutable Trip record, returns an existing exact record, or
  /// blocks/conflicts without overwriting evidence. Success reports persistence
  /// acknowledgement only, never permission to execute backend operations.
  Future<CompletionStageResult> stage({
    required String backendNamespace,
    required String driverId,
    required DriverCompleteTripCommand command,
  });
}

bool isCompletionJournalIdentityValid({
  required String backendNamespace,
  required String driverId,
  required String tripId,
}) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:\-]{0,63}$').hasMatch(backendNamespace) &&
    isCanonicalTripId(driverId) &&
    isCanonicalTripId(tripId);
