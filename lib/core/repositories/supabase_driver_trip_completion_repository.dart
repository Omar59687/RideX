import 'package:ridex/core/models/driver_completion_recovery.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/driver_trip_completion_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Backend invocation for driver completion (injectable for tests).
///
/// Production wiring (P6-09; not done here) supplies
/// `( {required name, required params} ) =>
/// client.rpc(name, params: params)`.
typedef DriverCompletionRpc = Future<Object?> Function({
  required String name,
  required Map<String, Object?> params,
});

/// Canonical Trip reread for driver completion (injectable for tests).
///
/// Production wiring (P6-09; not done here) supplies a closure over
/// `client.from('trips').select('id, status, version').eq('id', tripId)`
/// `.maybeSingle()`, normalized to `Map<String, Object?>`. The
/// `trips_participant_select` policy (`008:857-858`) admits the assigned
/// Driver through `private.can_read_trip` (`008:350-365`), so a `null`
/// result means the row is not visible to the caller — never a success.
/// Returns `null` when no row is visible.
typedef DriverTripRowReader = Future<Map<String, Object?>?> Function(
  String tripId,
);

/// Driver-safe receipt lookup by Trip (injectable for tests).
///
/// Production wiring (P6-09; not done here) supplies a closure over
/// `client.rpc('user_trip_receipt_summary',
/// params: {'target_trip_id': tripId})`, normalized to a row list. That
/// function admits the trip Driver through `private.require_receipt_reader`
/// (`020:16-28`) and returns only sanitized summary columns
/// (`019:192-201`); it never exposes payment rows, which Drivers cannot
/// read (`020:3-14`).
typedef DriverReceiptRowsReader = Future<List<Map<String, Object?>>> Function(
  String tripId,
);

/// Optional eligibility check before invoking the trusted RPC. A failure here
/// proves this adapter did not dispatch; it says nothing about earlier attempts.
/// Future composition owns session/SDK validation. No guard is wired here.
typedef DriverCompletionDispatchGuard = Future<void> Function(
  DriverCompleteTripCommand command,
);

/// Unwired adapter for the existing trusted completion RPC.
///
/// Handoff to Developer 3: the method signature is unchanged. Failures are
/// [DriverCompletionAttemptException] (a legacy-compatible exception subtype).
/// Its stage, original command, and write evidence distinguish no dispatch,
/// known RPC rejection, ambiguous dispatch, acknowledged completion with failed
/// Trip reread, and verified completion with failed receipt reread. Legacy
/// consumers see unknownResult for post-write read failures and stay unresolved.
/// Use CompletionRecovery.fromAttempt for stage-aware reconciliation; it grants
/// no replay/retirement authority. Only the selected file journal may stage a
/// future production intent; this adapter touches neither local store.
///
/// Both RPC and canonical row identities must match the command UUID (UUID case
/// is insignificant). Canonical versions are read, never calculated. Receipt
/// P0002 from the documented user_trip_receipt_summary contract means no receipt,
/// not no Trip. It returns verified Trip truth without receipt/payment claims.
/// Other receipt failures retain that truth on the typed exception. Card Trips
/// may have no receipt until trusted payment execution issues one.
///
/// No automatic retry, key generation, provider wiring, finance-table reads,
/// Cash settlement, Card capture, or receipt issuance occurs in Flutter.
class SupabaseDriverTripCompletionRepository
    implements DriverTripCompletionRepository {
  SupabaseDriverTripCompletionRepository({
    required DriverCompletionRpc rpc,
    required DriverTripRowReader readTripRow,
    required DriverReceiptRowsReader readReceiptRows,
    DriverCompletionDispatchGuard? beforeDispatch,
  })  : _rpc = rpc,
        _readTripRow = readTripRow,
        _readReceiptRows = readReceiptRows,
        _beforeDispatch = beforeDispatch;

  final DriverCompletionRpc _rpc;
  final DriverTripRowReader _readTripRow;
  final DriverReceiptRowsReader _readReceiptRows;
  final DriverCompletionDispatchGuard? _beforeDispatch;

  @override
  Future<DriverCompleteTripResult> completeTrip(
    DriverCompleteTripCommand command,
  ) async {
    try {
      await _beforeDispatch?.call(command);
    } on Object catch (error) {
      throw DriverCompletionAttemptException.beforeDispatch(
        command,
        _failure(error),
      );
    }

    final DriverCompleteTripResult acknowledged;
    var conflictEnvelope = false;
    try {
      final raw = await _rpc(
        name: 'driver_transition_trip',
        params: <String, Object?>{
          'target_id': command.tripId,
          'requested_status': DriverTripLifecycleStatus.completed.backendValue,
          'expected_version': command.expectedTripVersion,
          'idempotency_key': command.idempotencyKey,
        },
      );
      if (raw is! Map<String, dynamic>) {
        throw const DriverTripCompletionException(
          DriverCompletionFailure.malformedResponse,
        );
      }
      conflictEnvelope =
          raw.length == 1 && raw['error'] == 'idempotency_payload_mismatch';
      acknowledged = DriverCompletionParsing.parseCompletionResponse(raw);
      if (!acknowledged.isCompleted ||
          !_sameTrip(acknowledged.tripId, command.tripId)) {
        throw const DriverTripCompletionException(
          DriverCompletionFailure.malformedResponse,
        );
      }
    } on Object catch (error) {
      final failure = _failure(error);
      // Only inspected SQL rejections or the exact backend conflict envelope
      // prove rejection. An arbitrary injected exception is not that evidence.
      final rejected = (error is PostgrestException &&
              failure != DriverCompletionFailure.unknownResult) ||
          conflictEnvelope;
      throw DriverCompletionAttemptException.rpc(
        command,
        failure,
        rejectionConfirmed: rejected,
      );
    }

    final DriverCompleteTripResult confirmed;
    try {
      final row = await _readTripRow(command.tripId);
      if (row == null) {
        throw const DriverTripCompletionException(
          DriverCompletionFailure.unauthorized,
        );
      }
      final id = row['id'];
      final version = row['version'];
      if (id is! String ||
          !isCanonicalTripId(id) ||
          !_sameTrip(id, command.tripId) ||
          row['status'] != DriverTripLifecycleStatus.completed.backendValue ||
          version is! int ||
          version <= 0) {
        throw const DriverTripCompletionException(
          DriverCompletionFailure.malformedResponse,
        );
      }
      confirmed = DriverCompleteTripResult(
        tripId: id,
        status: DriverTripLifecycleStatus.completed,
        backendVersion: version,
      );
    } on Object catch (error) {
      throw DriverCompletionAttemptException.tripReread(
          command, _failure(error));
    }

    final String? receiptNumber;
    try {
      final rows = await _readReceiptRows(command.tripId);
      if (rows.isEmpty) {
        receiptNumber = null;
      } else {
        // One receipt per Trip. Foreign, duplicate or malformed rows are not
        // equivalent to legitimate absence and must never be silently ignored.
        if (rows.length != 1) {
          throw const DriverTripCompletionException(
            DriverCompletionFailure.malformedResponse,
          );
        }
        final row = rows.single;
        final receiptId = row['id'];
        final id = row['trip_id'];
        final number = row['receipt_number'];
        if (receiptId is! String ||
            !isCanonicalTripId(receiptId) ||
            id is! String ||
            !isCanonicalTripId(id) ||
            !_sameTrip(id, command.tripId) ||
            number is! String ||
            number.trim().isEmpty) {
          throw const DriverTripCompletionException(
            DriverCompletionFailure.malformedResponse,
          );
        }
        receiptNumber = number.trim();
      }
    } on PostgrestException catch (error) {
      if (error.code?.trim().toUpperCase() != 'P0002') {
        throw DriverCompletionAttemptException.receiptReread(
          command,
          _failure(error),
          confirmed,
        );
      }
      // This boundary invokes only user_trip_receipt_summary: its P0002 is
      // receipt absence. The matching completed Trip was already verified.
      return confirmed;
    } on Object catch (error) {
      throw DriverCompletionAttemptException.receiptReread(
        command,
        _failure(error),
        confirmed,
      );
    }
    return DriverCompleteTripResult(
      tripId: confirmed.tripId,
      status: confirmed.status,
      backendVersion: confirmed.backendVersion,
      receiptVerified: receiptNumber != null,
      receiptNumber: receiptNumber,
    );
  }

  static bool _sameTrip(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  static DriverCompletionFailure _failure(Object error) {
    if (error is DriverTripCompletionException) return error.failure;
    if (error is TypeError || error is FormatException) {
      return DriverCompletionFailure.malformedResponse;
    }
    if (error is PostgrestException) {
      return DriverCompletionErrorMapping.fromSqlState(error.code ?? '')
          .failure;
    }
    return DriverCompletionFailure.unknownResult;
  }
}
