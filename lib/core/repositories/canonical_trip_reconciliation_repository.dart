import 'package:ridex/core/models/canonical_trip_reconciliation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Trusted injection boundary. Session identity MUST come from the same
/// authenticated client that performs the read. No service-role client, cached
/// caller identity, financial access, RPC, persistence or mutation capability.
abstract interface class CanonicalTripReadTransport {
  CanonicalTripReadSession get currentSession;

  /// Exactly one requested Trip, through authenticated SELECT with RLS intact.
  Future<Map<String, Object?>?> readTrip(String tripId);
}

/// Synchronous lifecycle authority supplied by future integration. Approval
/// must belong to [CanonicalTripReadSession.driverId]; epoch must observe every
/// auth/lifecycle transition, not merely compare the current user ID.
typedef CanonicalTripLifecycleReader = CanonicalTripReadSession Function();

/// Unwired Supabase transport. The lifecycle namespace must match the immutable
/// configured namespace of this client. SDK identity independently validates
/// lifecycle approval ownership. No caller-provided Driver can authorize a read.
final class SupabaseCanonicalTripReadTransport
    implements CanonicalTripReadTransport {
  SupabaseCanonicalTripReadTransport({
    required SupabaseClient client,
    required String backendNamespace,
    required CanonicalTripLifecycleReader lifecycleReader,
  })  : _client = client,
        _backendNamespace = backendNamespace,
        _lifecycleReader = lifecycleReader;

  final SupabaseClient _client;
  final String _backendNamespace;
  final CanonicalTripLifecycleReader _lifecycleReader;

  @override
  CanonicalTripReadSession get currentSession {
    final lifecycle = _lifecycleReader();
    final authSession = _client.auth.currentSession;
    final driverId = authSession?.user.id;
    return CanonicalTripReadSession(
      driverId: driverId,
      backendNamespace: _backendNamespace,
      epoch: lifecycle.epoch,
      isApprovedDriver: authSession != null &&
          !authSession.isExpired &&
          driverId?.toLowerCase() == lifecycle.driverId?.toLowerCase() &&
          lifecycle.backendNamespace == _backendNamespace &&
          lifecycle.isApprovedDriver,
    );
  }

  @override
  Future<Map<String, Object?>?> readTrip(String tripId) async => _client
      .from('trips')
      .select('id, driver_id, status, version, payment_method')
      .eq('id', tripId)
      .maybeSingle();
}

abstract interface class CanonicalTripReconciliationRepository {
  /// Rereads an existing durable intent's Trip, without accepting dispatch
  /// authority. The captured Journal owner/namespace must match authenticated
  /// transport authority. Neither command version nor key is changed or sent.
  Future<CanonicalTripReadOutcome> readCanonicalTrip({
    required DriverCompleteTripCommand command,
    required String capturedDriverId,
    required String capturedBackendNamespace,
  });
}

/// New, unwired, read-only recovery foundation. Schema/RLS authority:
/// 008_phase3_trip_cash_change_foundation.sql (trips; can_read_trip;
/// trips_participant_select). Status authority: existing public.trip_status enum.
///
/// One read per call; no caching, retry, replay or Journal access. Session loss
/// takes precedence over every response/error, suppressing stale evidence.
/// Future consumers must also check ownership before publishing after their
/// own awaits. Production lifecycle/namespace binding is a prerequisite to
/// wiring; this class does not invent a session epoch or approval source.
final class ReadOnlyCanonicalTripReconciliationRepository
    implements CanonicalTripReconciliationRepository {
  ReadOnlyCanonicalTripReconciliationRepository(this._transport);
  final CanonicalTripReadTransport _transport;

  @override
  Future<CanonicalTripReadOutcome> readCanonicalTrip({
    required DriverCompleteTripCommand command,
    required String capturedDriverId,
    required String capturedBackendNamespace,
  }) async {
    if (!isCompletionJournalIdentityValid(
      backendNamespace: capturedBackendNamespace,
      driverId: capturedDriverId,
      tripId: command.tripId,
    )) {
      return _failed(CanonicalTripReadFailure.invalidRequest);
    }
    final owner = _session();
    if (owner == null ||
        !owner.isApprovedDriver ||
        owner.epoch < 0 ||
        owner.driverId?.toLowerCase() != capturedDriverId.toLowerCase() ||
        owner.backendNamespace != capturedBackendNamespace) {
      return _failed(CanonicalTripReadFailure.sessionInvalidated);
    }

    final Map<String, Object?>? row;
    try {
      row = await _transport.readTrip(command.tripId);
    } on Object catch (error) {
      if (!_stillOwned(owner)) {
        return _failed(CanonicalTripReadFailure.sessionInvalidated);
      }
      return _failed(_classify(error));
    }
    if (!_stillOwned(owner)) {
      return _failed(CanonicalTripReadFailure.sessionInvalidated);
    }
    if (row == null) return const CanonicalTripNotVisible();
    final id = row['id'];
    final driver = row['driver_id'];
    if (id is! String ||
        driver is! String ||
        !isCanonicalTripId(id) ||
        !isCanonicalTripId(driver)) {
      return _failed(CanonicalTripReadFailure.malformedEvidence);
    }
    if (id.toLowerCase() != command.tripId.toLowerCase() ||
        driver.toLowerCase() != capturedDriverId.toLowerCase()) {
      return _failed(CanonicalTripReadFailure.foreignEvidence);
    }
    final version = row['version'];
    if (version is! int || version <= 0) {
      return _failed(CanonicalTripReadFailure.invalidVersion);
    }
    if (row['payment_method'] != 'cash') {
      return _failed(CanonicalTripReadFailure.unsupportedPaymentMethod);
    }
    final rawStatus = row['status'];
    if (rawStatus is! String) {
      return _failed(CanonicalTripReadFailure.malformedEvidence);
    }
    final DriverTripLifecycleStatus status;
    try {
      status = DriverTripLifecycleStatus.fromBackendValue(rawStatus);
    } on ArgumentError {
      return _failed(CanonicalTripReadFailure.unsupportedStatus);
    }
    return CanonicalTripVisible(
      CanonicalTripEvidence(
        tripId: id,
        driverId: driver,
        status: status,
        backendVersion: version,
        paymentMethod: 'cash',
      ),
      owner,
    );
  }

  CanonicalTripReadSession? _session() {
    try {
      return _transport.currentSession;
    } on Object {
      return null;
    }
  }

  bool _stillOwned(CanonicalTripReadSession owner) {
    final current = _session();
    return current != null && owner.sameAuthority(current);
  }

  static CanonicalTripReadFailed _failed(CanonicalTripReadFailure failure) =>
      CanonicalTripReadFailed(failure);

  static CanonicalTripReadFailure _classify(Object error) {
    if (error is AuthException) {
      return CanonicalTripReadFailure.sessionInvalidated;
    }
    if (error is PostgrestException) {
      return switch (error.code) {
        '42501' => CanonicalTripReadFailure.authorizationDenied,
        'PGRST301' ||
        'PGRST302' ||
        'PGRST303' ||
        '28000' ||
        '28P01' =>
          CanonicalTripReadFailure.sessionInvalidated,
        _ => CanonicalTripReadFailure.transportUncertain,
      };
    }
    if (error is FormatException || error is TypeError) {
      return CanonicalTripReadFailure.malformedEvidence;
    }
    return CanonicalTripReadFailure.transportUncertain;
  }
}
