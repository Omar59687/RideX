import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/canonical_trip_reconciliation.dart';
import 'package:ridex/core/repositories/canonical_trip_reconciliation_repository.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
import 'package:ridex/core/repositories/driver_trip_completion_repository.dart';
import 'package:ridex/core/repositories/supabase_driver_trip_completion_repository.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DriverReceiptReadStatus { verified, missing, unavailable, unauthorized }

final class DriverReceiptReadResult {
  const DriverReceiptReadResult(this.status, {this.receiptNumber});
  final DriverReceiptReadStatus status;
  final String? receiptNumber;
}

/// Explicit composition over the verified B1-A singleton. The B1-B lifecycle
/// owner and existing coordinator/journal must be supplied by integration.
/// This class creates no session, epoch, key, intent, provider or UI activation.
/// Only the existing trusted Cash Trip-completion RPC may mutate server state.
final class SupabaseDriverCashCompletionComposition
    implements
        DriverTripCompletionRepository,
        CanonicalTripReconciliationRepository {
  SupabaseDriverCashCompletionComposition({
    required VerifiedSupabaseDriverAccess access,
    required SupabaseDriverAuthorityBinding authority,
  })  : _access = access,
        _authority = authority;
  final VerifiedSupabaseDriverAccess _access;
  final SupabaseDriverAuthorityBinding _authority;

  /// Driver-safe read-only receipt reconciliation using the existing RPC.
  Future<DriverReceiptReadResult> readReceipt({
    required String tripId,
    required String capturedDriverId,
    required String capturedBackendNamespace,
  }) async {
    final owner = _authority.currentOwner;
    final client = _access.client;
    final session = client?.auth.currentSession;
    bool current() =>
        owner.isUsable &&
        owner.driverId?.toLowerCase() == capturedDriverId.toLowerCase() &&
        owner.backend.namespace == capturedBackendNamespace &&
        client != null &&
        session != null &&
        !session.isExpired &&
        session.user.id.toLowerCase() == capturedDriverId.toLowerCase() &&
        identical(_access.backend, owner.backend) &&
        identical(_access.client, client) &&
        identical(client.auth.currentSession, session) &&
        owner.sameOwner(_authority.currentOwner);
    if (!isCanonicalTripId(tripId) || !current()) {
      return const DriverReceiptReadResult(
          DriverReceiptReadStatus.unauthorized);
    }
    final eligible = await DriverEligibilityRepository(_authority).validate();
    if (!current()) {
      return const DriverReceiptReadResult(
          DriverReceiptReadStatus.unauthorized);
    }
    if (eligible is! DriverEligible || !owner.sameOwner(eligible.owner)) {
      return const DriverReceiptReadResult(
          DriverReceiptReadStatus.unauthorized);
    }
    try {
      final rows = await client!
          .rpc('user_trip_receipt_summary', params: {'target_trip_id': tripId});
      if (!current()) {
        return const DriverReceiptReadResult(
            DriverReceiptReadStatus.unauthorized);
      }
      if (rows is! List || rows.length > 1 || rows.any((row) => row is! Map)) {
        return const DriverReceiptReadResult(
            DriverReceiptReadStatus.unavailable);
      }
      if (rows.isEmpty) {
        return const DriverReceiptReadResult(DriverReceiptReadStatus.missing);
      }
      final row = Map<String, Object?>.from(rows.single as Map);
      final id = row['id'];
      final linkedTrip = row['trip_id'];
      final number = row['receipt_number'];
      if (id is! String ||
          !isCanonicalTripId(id) ||
          linkedTrip is! String ||
          !isCanonicalTripId(linkedTrip) ||
          linkedTrip.toLowerCase() != tripId.toLowerCase() ||
          number is! String ||
          number.trim().isEmpty) {
        return const DriverReceiptReadResult(
            DriverReceiptReadStatus.unavailable);
      }
      return DriverReceiptReadResult(DriverReceiptReadStatus.verified,
          receiptNumber: number.trim());
    } on PostgrestException catch (error) {
      if (!current()) {
        return const DriverReceiptReadResult(
            DriverReceiptReadStatus.unauthorized);
      }
      return DriverReceiptReadResult(error.code?.toUpperCase() == 'P0002'
          ? DriverReceiptReadStatus.missing
          : DriverReceiptReadStatus.unavailable);
    } on Object {
      if (!current()) {
        return const DriverReceiptReadResult(
            DriverReceiptReadStatus.unauthorized);
      }
      return const DriverReceiptReadResult(DriverReceiptReadStatus.unavailable);
    }
  }

  /// Recovery performs authenticated SELECT only. Existing reconciliation owns
  /// status/identity/version classification; no outcome authorizes a replay.
  @override
  Future<CanonicalTripReadOutcome> readCanonicalTrip({
    required DriverCompleteTripCommand command,
    required String capturedDriverId,
    required String capturedBackendNamespace,
  }) async {
    final owner = _authority.currentOwner;
    final client = _access.client;
    final session = client?.auth.currentSession;
    bool current() =>
        owner.isUsable &&
        client != null &&
        session != null &&
        !session.isExpired &&
        identical(_access.client, client) &&
        identical(client.auth.currentSession, session) &&
        identical(owner.backend, _access.backend) &&
        owner.sameOwner(_authority.currentOwner);
    if (!current()) {
      return const CanonicalTripReadFailed(
          CanonicalTripReadFailure.sessionInvalidated);
    }
    final eligible = await DriverEligibilityRepository(_authority).validate();
    if (!current()) {
      return const CanonicalTripReadFailed(
          CanonicalTripReadFailure.sessionInvalidated);
    }
    if (eligible is! DriverEligible || !owner.sameOwner(eligible.owner)) {
      return const CanonicalTripReadFailed(
          CanonicalTripReadFailure.authorizationDenied);
    }
    final transport = SupabaseCanonicalTripReadTransport(
      client: client!,
      backendNamespace: owner.backend.namespace,
      lifecycleReader: () => CanonicalTripReadSession(
          driverId: _authority.currentOwner.driverId,
          backendNamespace: owner.backend.namespace,
          epoch: _authority.currentOwner.epoch,
          isApprovedDriver: current()),
    );
    return ReadOnlyCanonicalTripReconciliationRepository(transport)
        .readCanonicalTrip(
            command: command,
            capturedDriverId: capturedDriverId,
            capturedBackendNamespace: capturedBackendNamespace);
  }

  @override
  Future<DriverCompleteTripResult> completeTrip(
      DriverCompleteTripCommand command) {
    final owner = _authority.currentOwner;
    final client = _access.client;
    final session = client?.auth.currentSession;
    void requireOwner() {
      final current = _authority.currentOwner;
      if (client == null ||
          session == null ||
          session.isExpired ||
          !owner.isUsable ||
          !current.isUsable ||
          !owner.sameOwner(current) ||
          !identical(owner.backend, _access.backend) ||
          !identical(_access.client, client) ||
          !identical(client.auth.currentSession, session) ||
          session.user.id.toLowerCase() != owner.driverId?.toLowerCase()) {
        throw const DriverTripCompletionException(
            DriverCompletionFailure.unauthorized);
      }
    }

    Future<Map<String, Object?>?> readTrip(String tripId) async {
      requireOwner();
      final row = await client!
          .from('trips')
          .select('id,driver_id,status,version,payment_method')
          .eq('id', tripId)
          .maybeSingle();
      requireOwner();
      if (row != null &&
          (row['driver_id'] is! String ||
              (row['driver_id'] as String).toLowerCase() !=
                  owner.driverId?.toLowerCase())) {
        throw const DriverTripCompletionException(
            DriverCompletionFailure.unauthorized);
      }
      return row;
    }

    final adapter = SupabaseDriverTripCompletionRepository(
      beforeDispatch: (original) async {
        requireOwner();
        final eligible =
            await DriverEligibilityRepository(_authority).validate();
        requireOwner();
        if (eligible is! DriverEligible || !owner.sameOwner(eligible.owner)) {
          throw const DriverTripCompletionException(
              DriverCompletionFailure.unauthorized);
        }
        final trip = await readTrip(original.tripId);
        requireOwner();
        if (trip == null ||
            trip['id'] is! String ||
            (trip['id'] as String).toLowerCase() !=
                original.tripId.toLowerCase()) {
          throw const DriverTripCompletionException(
              DriverCompletionFailure.tripNotFound);
        }
        if (trip['version'] != original.expectedTripVersion) {
          throw const DriverTripCompletionException(
              DriverCompletionFailure.staleVersion);
        }
        if (trip['status'] != 'inProgress' ||
            trip['payment_method'] != 'cash') {
          throw const DriverTripCompletionException(
              DriverCompletionFailure.invalidTransition);
        }
      },
      rpc: ({required name, required params}) async {
        requireOwner();
        final result = await client!.rpc(name, params: params);
        requireOwner();
        return result;
      },
      readTripRow: readTrip,
      readReceiptRows: (tripId) async {
        requireOwner();
        // The Driver-safe receipt RPC, never payments or finance-table SELECT.
        final result = await client!.rpc('user_trip_receipt_summary',
            params: {'target_trip_id': tripId});
        requireOwner();
        if (result is! List || result.any((row) => row is! Map)) {
          throw const DriverTripCompletionException(
              DriverCompletionFailure.malformedResponse);
        }
        return [
          for (final row in result) Map<String, Object?>.from(row as Map)
        ];
      },
    );
    return adapter.completeTrip(command).then((result) {
      try {
        requireOwner();
      } on DriverTripCompletionException {
        throw DriverCompletionAttemptException.receiptReread(
            command,
            DriverCompletionFailure.unauthorized,
            DriverCompleteTripResult(
                tripId: result.tripId,
                status: result.status,
                backendVersion: result.backendVersion));
      }
      return result;
    });
  }
}
