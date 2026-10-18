import 'package:equatable/equatable.dart';

/// Canonical Trip lifecycle statuses (`public.trip_status`).
///
/// Verbatim backend values from
/// `supabase/migrations/005_phase3_core_security_foundation.sql:9-12`:
/// `'accepted'`, `'driverArriving'`, `'driverArrived'`, `'inProgress'`,
/// `'completed'`, `'cancelledByRider'`, `'cancelledByDriver'`,
/// `'cancelledByAdmin'`, `'failed'`. CamelCase is intentional.
///
/// This enum is intentionally narrower than the mock-only [TripStatus] in
/// `mock_trip.dart`, which carries presentation states (`requested`,
/// `searching`, `noDriverFound`) that never appear in backend Trip rows.
enum DriverTripLifecycleStatus {
  accepted,
  driverArriving,
  driverArrived,
  inProgress,
  completed,
  cancelledByRider,
  cancelledByDriver,
  cancelledByAdmin,
  failed;

  /// Exact backend string for this status.
  String get backendValue => name;

  /// Parses an exact backend string. Rejects anything else.
  static DriverTripLifecycleStatus fromBackendValue(String value) {
    return switch (value) {
      'accepted' => DriverTripLifecycleStatus.accepted,
      'driverArriving' => DriverTripLifecycleStatus.driverArriving,
      'driverArrived' => DriverTripLifecycleStatus.driverArrived,
      'inProgress' => DriverTripLifecycleStatus.inProgress,
      'completed' => DriverTripLifecycleStatus.completed,
      'cancelledByRider' => DriverTripLifecycleStatus.cancelledByRider,
      'cancelledByDriver' => DriverTripLifecycleStatus.cancelledByDriver,
      'cancelledByAdmin' => DriverTripLifecycleStatus.cancelledByAdmin,
      'failed' => DriverTripLifecycleStatus.failed,
      _ => throw ArgumentError.value(value, 'value', 'Unknown trip status.'),
    };
  }
}

/// Canonical UUID check for backend Trip identity (`public.trips.id`).
///
/// Accepts only the hyphenated 8-4-4-4-12 hexadecimal form. Mock identifiers
/// such as `trip-1` are rejected.
bool isCanonicalTripId(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

/// Production driver completion command.
///
/// Maps to `public.driver_transition_trip(target_id uuid, requested_status
/// public.trip_status, expected_version integer, idempotency_key text)` with
/// `requested_status` fixed to `'completed'` (`017:204-210`). Flutter never
/// sends any other status through this contract.
///
/// - [tripId] is the canonical backend Trip UUID, never a mock identifier.
/// - [expectedTripVersion] is the canonical `public.trips.version` (> 0),
///   never a booking, payment, or offer version.
/// - [idempotencyKey] is stored trimmed; the backend trims and requires 1..128
///   characters (`005:121`). The key must be persisted before the first call
///   and replayed byte-identically (same triple) after unknown outcomes.
class DriverCompleteTripCommand extends Equatable {
  DriverCompleteTripCommand({
    required String tripId,
    required this.expectedTripVersion,
    required String idempotencyKey,
  })  : tripId = tripId.trim(),
        idempotencyKey = idempotencyKey.trim() {
    if (!isCanonicalTripId(this.tripId)) {
      throw ArgumentError.value(
        tripId,
        'tripId',
        'Must be a canonical Trip UUID.',
      );
    }
    if (expectedTripVersion <= 0) {
      throw ArgumentError.value(
        expectedTripVersion,
        'expectedTripVersion',
        'Must be positive.',
      );
    }
    if (this.idempotencyKey.isEmpty || this.idempotencyKey.length > 128) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'Must be 1..128 characters after trimming.',
      );
    }
  }

  /// Canonical backend Trip UUID.
  final String tripId;

  /// Canonical backend Trip version the driver observed.
  final int expectedTripVersion;

  /// Stable idempotency key for this completion intent (trimmed).
  final String idempotencyKey;

  /// Whether [other] is an exact replay of this command.
  ///
  /// Exact replay means the identical triple: same trip UUID, same expected
  /// version, same key. Bumping the version is a different intent, not a
  /// replay, because the backend fingerprint covers all three fields.
  bool isExactReplayOf(DriverCompleteTripCommand other) {
    return tripId == other.tripId &&
        expectedTripVersion == other.expectedTripVersion &&
        idempotencyKey == other.idempotencyKey;
  }

  @override
  List<Object?> get props => [tripId, expectedTripVersion, idempotencyKey];
}

/// Canonical driver completion result.
///
/// Constructed only from trusted backend data plus authorized rereads:
///
/// - Trip `completed` never implies payment success. Cash settlement
///   (`cashSelected` -> `paid`) and receipt issuance are separate trusted
///   backend steps; a Card Trip completing never proves Card payment success.
/// - [backendVersion] is populated only from an authorized canonical Trip
///   reread, never from the completion RPC JSON (which returns `{trip_id,
///   status}` only). It stays `null` until that reread.
/// - [receiptVerified] is true only after an authorized driver-safe receipt
///   summary reread (`user_receipt_summary` / `user_trip_receipt_summary`).
///   [receiptNumber] is present if and only if [receiptVerified] is true;
///   the result never fabricates receipt data.
class DriverCompleteTripResult extends Equatable {
  DriverCompleteTripResult({
    required String tripId,
    required this.status,
    this.backendVersion,
    this.receiptVerified = false,
    this.receiptNumber,
  }) : tripId = tripId.trim() {
    if (!isCanonicalTripId(this.tripId)) {
      throw ArgumentError.value(
        tripId,
        'tripId',
        'Must be a canonical Trip UUID.',
      );
    }
    if (backendVersion != null && backendVersion! <= 0) {
      throw ArgumentError.value(
        backendVersion,
        'backendVersion',
        'Must be positive when provided.',
      );
    }
    final receipt = receiptNumber?.trim();
    if (receiptVerified && (receipt == null || receipt.isEmpty)) {
      throw ArgumentError.value(
        receiptNumber,
        'receiptNumber',
        'Verified results require a receipt number.',
      );
    }
    if (!receiptVerified && receiptNumber != null) {
      throw ArgumentError.value(
        receiptNumber,
        'receiptNumber',
        'Unverified results must not carry receipt data.',
      );
    }
  }

  /// Canonical backend Trip UUID echoed by the backend.
  final String tripId;

  /// Canonical lifecycle status echoed by the backend.
  final DriverTripLifecycleStatus status;

  /// Canonical backend Trip version from an authorized reread, if done.
  final int? backendVersion;

  /// True only after an authorized driver-safe receipt reread succeeded.
  final bool receiptVerified;

  /// Receipt number from the authorized reread; null unless verified.
  final String? receiptNumber;

  /// Whether the canonical Trip reached `completed`.
  bool get isCompleted => status == DriverTripLifecycleStatus.completed;

  @override
  List<Object?> get props => [
        tripId,
        status,
        backendVersion,
        receiptVerified,
        receiptNumber,
      ];
}

/// Typed completion outcomes.
///
/// Mapping to the existing backend contract:
/// unauthorized -> `42501`; tripNotFound -> `P0002`; staleVersion -> `40001`;
/// invalidTransition -> `55000`/`22023` wrong-status; idempotencyConflict ->
/// `{'error': 'idempotency_payload_mismatch'}` JSON; unknownResult -> transport
/// timeout or dropped response (outcome unconfirmed); malformedResponse ->
/// missing or unparsable `trip_id`/`status` or wrong JSON types.
///
/// `unknownResult` is explicitly not a failure confirmation: the caller must
/// reread canonical state and replay the exact command instead of assuming
/// success or failure.
enum DriverCompletionFailure {
  unauthorized,
  tripNotFound,
  staleVersion,
  invalidTransition,
  idempotencyConflict,
  unknownResult,
  malformedResponse,
}

/// Sanitized completion error.
///
/// Carries only the typed [failure]. Raw backend messages, SQL errcodes, and
/// provider details must never be placed in user-facing strings; map them to
/// [failure] at the adapter boundary instead.
class DriverTripCompletionException implements Exception {
  const DriverTripCompletionException(this.failure);

  final DriverCompletionFailure failure;

  @override
  String toString() => 'DriverTripCompletionException($failure)';
}

/// Boundary at which an adapter attempt stopped. No stage authorizes replay.
enum DriverCompletionAttemptStage {
  beforeDispatch,
  rpc,
  tripReread,
  receiptReread
}

/// Evidence about this attempt, never about Cash settlement or Card capture.
enum DriverCompletionWriteEvidence {
  notDispatched,
  rejected,
  unknown,
  acknowledged,
  verified,
}

/// Additive adapter handoff for Developer 3: existing callers can keep catching
/// [DriverTripCompletionException]. Post-write read failures expose
/// `unknownResult` through that legacy API, so they cannot look like a rejected
/// completion. [cause] describes only the failed boundary, not the write.
///
/// Preserve [command] and staged journal evidence. Reconcile canonical state;
/// never rotate its key, replay automatically, or retire evidence from this
/// exception. The unchanged coordinator conservatively publishes unresolved
/// and retains its staged command; it does not yet consume [confirmedTrip].
/// The file journal is the selected future staging authority. The separate
/// SharedPreferences store remains inactive; this contract performs no writes.
class DriverCompletionAttemptException extends DriverTripCompletionException {
  DriverCompletionAttemptException.beforeDispatch(this.command, this.cause)
      : stage = DriverCompletionAttemptStage.beforeDispatch,
        writeEvidence = DriverCompletionWriteEvidence.notDispatched,
        confirmedTrip = null,
        super(cause);

  DriverCompletionAttemptException.rpc(
    this.command,
    this.cause, {
    bool rejectionConfirmed = false,
  })  : stage = DriverCompletionAttemptStage.rpc,
        writeEvidence = rejectionConfirmed
            ? DriverCompletionWriteEvidence.rejected
            : DriverCompletionWriteEvidence.unknown,
        confirmedTrip = null,
        super(cause);

  DriverCompletionAttemptException.tripReread(this.command, this.cause)
      : stage = DriverCompletionAttemptStage.tripReread,
        writeEvidence = DriverCompletionWriteEvidence.acknowledged,
        confirmedTrip = null,
        super(DriverCompletionFailure.unknownResult);

  DriverCompletionAttemptException.receiptReread(
    this.command,
    this.cause,
    DriverCompleteTripResult trip,
  )   : stage = DriverCompletionAttemptStage.receiptReread,
        writeEvidence = DriverCompletionWriteEvidence.verified,
        confirmedTrip = trip,
        super(DriverCompletionFailure.unknownResult) {
    if (trip.tripId.toLowerCase() != command.tripId.toLowerCase() ||
        !trip.isCompleted ||
        trip.backendVersion == null ||
        trip.receiptVerified) {
      throw ArgumentError(
          'Matching unreceipted canonical completion required.');
    }
  }

  final DriverCompleteTripCommand command;
  final DriverCompletionAttemptStage stage;
  final DriverCompletionWriteEvidence writeEvidence;
  final DriverCompletionFailure cause;

  /// Verified completed Trip/version retained after a failed receipt read.
  /// Never contains an inferred receipt or payment outcome.
  final DriverCompleteTripResult? confirmedTrip;

  @override
  String toString() => 'DriverCompletionAttemptException('
      '$stage, $writeEvidence, $failure, $cause)';
}

/// Pure parsers for the existing `driver_transition_trip` JSON response.
///
/// The backend returns `{'trip_id': <uuid>, 'status': <trip_status>}` on
/// success or `{'error': 'idempotency_payload_mismatch'}` on a key conflict.
/// It never returns a Trip version or receipt data in this response; parsers
/// below never manufacture either field.
class DriverCompletionParsing {
  DriverCompletionParsing._();

  /// Parses one backend completion response map.
  ///
  /// Returns an unverified [DriverCompleteTripResult] (`backendVersion`
  /// null, `receiptVerified` false) on valid input. Throws
  /// [DriverTripCompletionException] with `idempotencyConflict` for the
  /// mismatch error shape, or `malformedResponse` for anything else that is
  /// not a well-formed completion response.
  static DriverCompleteTripResult parseCompletionResponse(
    Map<String, Object?> json,
  ) {
    if (json.containsKey('error')) {
      // The backend mismatch shape is exactly `{'error':
      // 'idempotency_payload_mismatch'}`. Any other error value, or an error
      // combined with data keys, is not a known backend response.
      if (json.length == 1 && json['error'] == 'idempotency_payload_mismatch') {
        throw const DriverTripCompletionException(
          DriverCompletionFailure.idempotencyConflict,
        );
      }
      throw const DriverTripCompletionException(
        DriverCompletionFailure.malformedResponse,
      );
    }
    final tripId = json['trip_id'];
    final status = json['status'];
    if (tripId is! String ||
        status is! String ||
        !isCanonicalTripId(tripId.trim())) {
      throw const DriverTripCompletionException(
        DriverCompletionFailure.malformedResponse,
      );
    }
    late final DriverTripLifecycleStatus parsedStatus;
    try {
      parsedStatus = DriverTripLifecycleStatus.fromBackendValue(status);
    } on ArgumentError {
      throw const DriverTripCompletionException(
        DriverCompletionFailure.malformedResponse,
      );
    }
    return DriverCompleteTripResult(
      tripId: tripId.trim(),
      status: parsedStatus,
    );
  }
}
