import 'dart:async';

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

/// Production driver completion adapter over the trusted backend path.
///
/// Invokes only `public.driver_transition_trip` with
/// `requested_status = 'completed'` (`017:204-210`, SECURITY DEFINER,
/// granted to `authenticated` at `016:66`). Cash settlement and receipt
/// issuance stay trusted backend consequences of that call
/// (`017:263-264`); this adapter never sets payment state client-side and
/// never declares payment success — a completed Card Trip proves nothing
/// about Card payment, and a completed Cash Trip is reported exactly as
/// the authorized rereads confirm (version from the canonical Trip row,
/// receipt data only from the Driver-safe receipt summary).
///
/// Behavior per [DriverTripCompletionRepository.completeTrip]:
/// - Sends the caller-supplied triple byte-identically (trip UUID,
///   expected version, idempotency key) with the fixed `completed`
///   transition. No key is minted, rotated, persisted, or repaired here.
/// - Maps backend rejections through the approved SQLSTATE vocabulary
///   (`42501` unauthorized, `P0002` tripNotFound, `40001` staleVersion,
///   `55000`/`22023` invalidTransition, anything else unknownResult) and
///   transport loss (timeout or any other transport error) to
///   `unknownResult`, which forces a canonical reread plus an exact replay
///   instead of a guessed outcome.
/// - Propagates the exact `idempotency_payload_mismatch` shape as
///   `idempotencyConflict` and any other garbled payload as
///   `malformedResponse`.
/// - After a `completed` response, rereads the canonical Trip row and
///   attaches its fresh `version` as [DriverCompleteTripResult.backendVersion].
///   The reread version is intentionally not compared to the command
///   version: the backend bumps `trips.version` on every transition
///   (`008:194`), so a bumped version is the expected outcome, not a
///   conflict. A missing row (RLS-filtered after a confirmed write)
///   means access was lost mid-flight and fails closed as `unauthorized`;
///   a non-`completed` status or an unparsable row fails closed as
///   `malformedResponse`.
/// - Rereads the Driver-safe receipt summary afterwards. An absent receipt
///   (Card Trips carry none by design) yields an unverified result with a
///   version but no receipt data. A present receipt number marks the result
///   verified. Reread transport or permission failures never return a
///   partial success; they throw instead.
/// - Reads no payment, attempt, or refund rows and calls no
///   `user_payment_*` function: Drivers are excluded from payment-row
///   access and this adapter must not depend on it.
///
/// This class performs no hosted write beyond the single trusted RPC call,
/// makes no settlement or execution claim (those wait on V5-01/V5-04
/// hosted evidence), and is not wired into any provider here — provider
/// wiring belongs to P6-09.
class SupabaseDriverTripCompletionRepository
    implements DriverTripCompletionRepository {
  SupabaseDriverTripCompletionRepository({
    required DriverCompletionRpc rpc,
    required DriverTripRowReader readTripRow,
    required DriverReceiptRowsReader readReceiptRows,
  })  : _rpc = rpc,
        _readTripRow = readTripRow,
        _readReceiptRows = readReceiptRows;

  final DriverCompletionRpc _rpc;
  final DriverTripRowReader _readTripRow;
  final DriverReceiptRowsReader _readReceiptRows;

  @override
  Future<DriverCompleteTripResult> completeTrip(
    DriverCompleteTripCommand command,
  ) async {
    final response = await _invokeCompletion(command);
    final parsed = DriverCompletionParsing.parseCompletionResponse(response);
    if (!parsed.isCompleted) {
      // Unreachable through the fixed `completed` transition, but a
      // non-completed answer to this command is not a known response and
      // must fail closed rather than surface as success.
      throw const DriverTripCompletionException(
        DriverCompletionFailure.malformedResponse,
      );
    }
    final backendVersion = await _rereadCanonicalVersion(command);
    final receiptNumber = await _rereadReceiptNumber(command);
    return DriverCompleteTripResult(
      tripId: command.tripId,
      status: DriverTripLifecycleStatus.completed,
      backendVersion: backendVersion,
      receiptVerified: receiptNumber != null,
      receiptNumber: receiptNumber,
    );
  }

  Future<Map<String, Object?>> _invokeCompletion(
    DriverCompleteTripCommand command,
  ) async {
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
      if (raw is Map) {
        return <String, Object?>{
          for (final entry in raw.entries) entry.key.toString(): entry.value,
        };
      }
      throw const DriverTripCompletionException(
        DriverCompletionFailure.malformedResponse,
      );
    } on DriverTripCompletionException {
      rethrow;
    } on PostgrestException catch (error) {
      throw DriverTripCompletionException(
        DriverCompletionErrorMapping.fromSqlState(error.code ?? '').failure,
      );
    } on TimeoutException {
      throw const DriverTripCompletionException(
        DriverCompletionFailure.unknownResult,
      );
    } on Object {
      // Any other transport error (disconnect, TLS, protocol) leaves the
      // outcome unconfirmed: fail closed to unknownResult so the caller
      // rereads canonical state and replays the exact command.
      throw const DriverTripCompletionException(
        DriverCompletionFailure.unknownResult,
      );
    }
  }

  Future<int> _rereadCanonicalVersion(
    DriverCompleteTripCommand command,
  ) async {
    final Map<String, Object?>? row;
    try {
      row = await _readTripRow(command.tripId);
    } on PostgrestException catch (error) {
      throw DriverTripCompletionException(
        DriverCompletionErrorMapping.fromSqlState(error.code ?? '').failure,
      );
    } on TimeoutException {
      throw const DriverTripCompletionException(
        DriverCompletionFailure.unknownResult,
      );
    } on Object {
      throw const DriverTripCompletionException(
        DriverCompletionFailure.unknownResult,
      );
    }
    if (row == null) {
      throw const DriverTripCompletionException(
        DriverCompletionFailure.unauthorized,
      );
    }
    final status = row['status'];
    final version = row['version'];
    if (status is! String || version is! int || version <= 0) {
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
    if (parsedStatus != DriverTripLifecycleStatus.completed) {
      throw const DriverTripCompletionException(
        DriverCompletionFailure.malformedResponse,
      );
    }
    return version;
  }

  Future<String?> _rereadReceiptNumber(
    DriverCompleteTripCommand command,
  ) async {
    final List<Map<String, Object?>> rows;
    try {
      rows = await _readReceiptRows(command.tripId);
    } on PostgrestException catch (error) {
      throw DriverTripCompletionException(
        DriverCompletionErrorMapping.fromSqlState(error.code ?? '').failure,
      );
    } on TimeoutException {
      throw const DriverTripCompletionException(
        DriverCompletionFailure.unknownResult,
      );
    } on Object {
      throw const DriverTripCompletionException(
        DriverCompletionFailure.unknownResult,
      );
    }
    for (final row in rows) {
      final rowTripId = row['trip_id'];
      if (rowTripId is String &&
          rowTripId.trim().toLowerCase() ==
              command.tripId.trim().toLowerCase()) {
        final receiptNumber = row['receipt_number'];
        if (receiptNumber is! String || receiptNumber.trim().isEmpty) {
          throw const DriverTripCompletionException(
            DriverCompletionFailure.malformedResponse,
          );
        }
        return receiptNumber.trim();
      }
    }
    return null;
  }
}
