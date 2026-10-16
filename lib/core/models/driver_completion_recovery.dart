import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';

/// Sanitized transport-loss conditions for a completion attempt.
///
/// Both values mean the same thing for recovery: no backend response was
/// observed, so the outcome is unknown. They are distinguished only so logs
/// can tell a deadline expiry ([timeout]) apart from an ambiguous disconnect
/// ([disconnect]) without carrying raw transport errors.
enum TransportLossKind {
  timeout,
  disconnect,
}

/// A typed completion failure plus a log-safe diagnostic code.
///
/// [debugCode] is drawn from [closedDebugCodes] only: the five known SQLSTATE
/// values (`42501`, `P0002`, `40001`, `55000`, `22023`), `unknown-sqlstate`,
/// `idempotency-mismatch`, `timeout`, `transport-disconnect`, or
/// `malformed-payload`. Construction is restricted to the controlled mapper
/// factories in this file, so external callers cannot smuggle raw database
/// messages, provider payloads, or secrets into this field.
class ClassifiedCompletionFailure extends Equatable {
  const ClassifiedCompletionFailure._(this.failure, this.debugCode);

  /// Authoritative closed diagnostic vocabulary.
  static const Set<String> closedDebugCodes = {
    '42501',
    'P0002',
    '40001',
    '55000',
    '22023',
    'unknown-sqlstate',
    'idempotency-mismatch',
    'timeout',
    'transport-disconnect',
    'malformed-payload',
  };

  final DriverCompletionFailure failure;

  final String debugCode;

  @override
  List<Object?> get props => [failure, debugCode];
}

/// Pure backend-error classification for driver completion.
///
/// Consumes sanitized signals (a SQLSTATE string, a closed transport kind,
/// or a response map) and returns [ClassifiedCompletionFailure] values. It
/// performs no I/O, mints no idempotency keys, persists nothing, and never
/// declares payment success: Trip completion — Cash or Card — proves nothing
/// about payment settlement, which stays a trusted backend consequence.
class DriverCompletionErrorMapping {
  DriverCompletionErrorMapping._();

  /// Maps a backend SQLSTATE to a typed failure.
  ///
  /// Known completion-path codes (`008:494-506`, `014`, `017:223-254`):
  /// `42501` -> unauthorized, `P0002` -> tripNotFound, `40001` ->
  /// staleVersion, `55000` -> invalidTransition, `22023` ->
  /// invalidTransition (the approved contract has no finer category).
  ///
  /// Any other value — including an empty string, a code from another path
  /// such as `54000`, or a future unknown code — maps to `unknownResult`.
  /// That is deliberate conservatism: an unrecognized rejection must never
  /// be misread as a confirmed terminal trip outcome. Callers must reread
  /// canonical state instead of assuming success or a specific failure.
  static ClassifiedCompletionFailure fromSqlState(String sqlState) {
    final normalized = sqlState.trim().toUpperCase();
    return switch (normalized) {
      '42501' => const ClassifiedCompletionFailure._(
          DriverCompletionFailure.unauthorized, '42501'),
      'P0002' => const ClassifiedCompletionFailure._(
          DriverCompletionFailure.tripNotFound, 'P0002'),
      '40001' => const ClassifiedCompletionFailure._(
          DriverCompletionFailure.staleVersion, '40001'),
      '55000' => const ClassifiedCompletionFailure._(
          DriverCompletionFailure.invalidTransition, '55000'),
      '22023' => const ClassifiedCompletionFailure._(
          DriverCompletionFailure.invalidTransition, '22023'),
      _ => const ClassifiedCompletionFailure._(
          DriverCompletionFailure.unknownResult, 'unknown-sqlstate'),
    };
  }

  /// Classifies an exact idempotency-mismatch error shape.
  static ClassifiedCompletionFailure idempotencyMismatch() {
    return const ClassifiedCompletionFailure._(
      DriverCompletionFailure.idempotencyConflict,
      'idempotency-mismatch',
    );
  }

  /// Classifies a transport loss with no backend response observed.
  static ClassifiedCompletionFailure transportLoss(TransportLossKind kind) {
    return ClassifiedCompletionFailure._(
      DriverCompletionFailure.unknownResult,
      switch (kind) {
        TransportLossKind.timeout => 'timeout',
        TransportLossKind.disconnect => 'transport-disconnect',
      },
    );
  }

  /// Classifies a backend payload that cannot be parsed as a response.
  static ClassifiedCompletionFailure malformedPayload() {
    return const ClassifiedCompletionFailure._(
      DriverCompletionFailure.malformedResponse,
      'malformed-payload',
    );
  }
}

/// Recovery directive for one completion attempt.
///
/// Exactly one action follows from each directive:
///
/// - [ReceiptRereadRequired]: the canonical Trip reached backend-confirmed
///   `completed` — the only status that permits receipt-summary rereading.
///   Only the authorized reread can verify a receipt. The embedded result is
///   unverified and carries no version or receipt data.
/// - [RejectionConfirmed]: the backend confirmed a rejection. Do not mint a
///   new idempotency key and retry blindly. A [DriverCompletionFailure.staleVersion]
///   additionally requires rereading the Trip to form a new intent, because a
///   bumped version is not an exact replay.
/// - [CanonicalRereadRequired]: the outcome is unknown (timeout, disconnect,
///   unrecognized code, or garbled payload). Reread the canonical Trip first;
///   afterwards only an exact replay of the original command is permitted.
sealed class CompletionRecoveryDirective extends Equatable {
  const CompletionRecoveryDirective();
}

/// The Trip reached backend-confirmed `completed`; reread the receipt summary.
class ReceiptRereadRequired extends CompletionRecoveryDirective {
  const ReceiptRereadRequired(this.result);

  final DriverCompleteTripResult result;

  @override
  List<Object?> get props => [result];
}

/// The backend confirmed a rejection; no blind retry with a fresh key.
class RejectionConfirmed extends CompletionRecoveryDirective {
  const RejectionConfirmed(this.error);

  final ClassifiedCompletionFailure error;

  @override
  List<Object?> get props => [error];
}

/// The outcome is unknown; reread the canonical Trip before anything else.
class CanonicalRereadRequired extends CompletionRecoveryDirective {
  const CanonicalRereadRequired(this.error);

  final ClassifiedCompletionFailure error;

  @override
  List<Object?> get props => [error];
}

/// Pure recovery classification built on the merged completion contract.
class CompletionRecovery {
  CompletionRecovery._();

  /// Classifies a SQLSTATE rejection into a recovery directive.
  ///
  /// Recognized rejections become [RejectionConfirmed]; unrecognized or
  /// absent codes become [CanonicalRereadRequired] with `unknownResult`,
  /// forcing a canonical reread instead of a guessed outcome.
  static CompletionRecoveryDirective fromSqlState(String sqlState) {
    final error = DriverCompletionErrorMapping.fromSqlState(sqlState);
    return switch (error.failure) {
      DriverCompletionFailure.unknownResult => CanonicalRereadRequired(error),
      _ => RejectionConfirmed(error),
    };
  }

  /// Classifies one raw backend JSON response map.
  ///
  /// Only a well-formed response with `status == completed` becomes
  /// [ReceiptRereadRequired]: the completion command fixes
  /// `requested_status` to `completed`, so receipt-summary rereading is
  /// permitted only after confirmed completion. Any other canonical status
  /// is not a known response to this command and fails closed to
  /// [CanonicalRereadRequired] with `malformedResponse`, as does any
  /// garbled payload — the category is preserved while recovery rereads
  /// canonical state first. The exact mismatch shape becomes
  /// [RejectionConfirmed] with `idempotencyConflict`.
  static CompletionRecoveryDirective fromJsonResponse(
    Map<String, Object?> json,
  ) {
    try {
      final result = DriverCompletionParsing.parseCompletionResponse(json);
      if (result.status != DriverTripLifecycleStatus.completed) {
        return CanonicalRereadRequired(
          DriverCompletionErrorMapping.malformedPayload(),
        );
      }
      return ReceiptRereadRequired(result);
    } on DriverTripCompletionException catch (error) {
      final classified = switch (error.failure) {
        DriverCompletionFailure.idempotencyConflict =>
          DriverCompletionErrorMapping.idempotencyMismatch(),
        _ => DriverCompletionErrorMapping.malformedPayload(),
      };
      return switch (classified.failure) {
        DriverCompletionFailure.idempotencyConflict =>
          RejectionConfirmed(classified),
        _ => CanonicalRereadRequired(classified),
      };
    }
  }

  /// Classifies a transport loss into a canonical-reread directive.
  static CompletionRecoveryDirective fromTransportLoss(
    TransportLossKind kind,
  ) {
    return CanonicalRereadRequired(
      DriverCompletionErrorMapping.transportLoss(kind),
    );
  }
}

/// Granular replay validity for a candidate retry command.
///
/// Priority is deterministic when several fields differ: a changed trip is
/// reported before a changed version, which is reported before a changed
/// key. Only [exactReplay] authorizes resending; every other value forbids
/// treating the candidate as the same intent.
enum ReplayValidity {
  exactReplay,
  tripChanged,
  versionChanged,
  keyChanged,
}

/// Validates whether [candidate] is an exact replay of [original].
///
/// An exact replay resends the identical triple (trip UUID, expected
/// version, idempotency key), matching the backend fingerprint over
/// `target_id|requested_status|expected_version`. A bumped version or a
/// rotated key is a different intent and must be classified as such — never
/// silently accepted as a replay.
///
/// Property: returns [ReplayValidity.exactReplay] if and only if
/// `original.isExactReplayOf(candidate)` holds.
ReplayValidity validateCompletionReplay(
  DriverCompleteTripCommand original,
  DriverCompleteTripCommand candidate,
) {
  if (original.tripId != candidate.tripId) {
    return ReplayValidity.tripChanged;
  }
  if (original.expectedTripVersion != candidate.expectedTripVersion) {
    return ReplayValidity.versionChanged;
  }
  if (original.idempotencyKey != candidate.idempotencyKey) {
    return ReplayValidity.keyChanged;
  }
  return ReplayValidity.exactReplay;
}
