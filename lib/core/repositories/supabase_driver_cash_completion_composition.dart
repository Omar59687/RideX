import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/canonical_trip_reconciliation.dart';
import 'package:ridex/core/repositories/canonical_trip_reconciliation_repository.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
import 'package:ridex/core/repositories/driver_trip_completion_repository.dart';
import 'package:ridex/core/repositories/supabase_driver_trip_completion_repository.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';

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
