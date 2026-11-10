import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'canonical_driver_repository.dart';

/// Unmounted normal-user SDK adapter. Reuses application provenance, approved
/// backend identity and AuthService's single-client/epoch binding. Never creates
/// an SDK client, signs in, handles credentials or calls service-only matching.
final class SupabaseCanonicalDriverPort implements CanonicalDriverPort {
  SupabaseCanonicalDriverPort._(
      this._access, this._binding, this._clientIdentity);

  factory SupabaseCanonicalDriverPort.create({
    required VerifiedSupabaseDriverAccess access,
    required AuthService auth,
  }) {
    final client = access.client;
    if (client == null) throw StateError('Driver access is unavailable.');
    return SupabaseCanonicalDriverPort._(
        access, auth.driverBinding(access), client);
  }

  final VerifiedSupabaseDriverAccess _access;
  final SupabaseDriverAuthorityBinding _binding;
  final Object _clientIdentity;
  bool _disposed = false;

  @override
  DriverAuthorityOwner get currentOwner => _binding.currentOwner;

  @override
  Object? get sessionIdentity =>
      _disposed ? null : _access.client?.auth.currentSession;

  Future<void> dispose() async {
    _disposed = true;
    await _binding.dispose();
  }

  void _check(DriverAuthorityOwner owner, Object? session) {
    if (_disposed ||
        !owner.isUsable ||
        session == null ||
        !identical(_access.client, _clientIdentity) ||
        !currentOwner.isUsable ||
        !owner.sameOwner(currentOwner) ||
        !identical(sessionIdentity, session)) {
      throw StateError('Driver authority is unavailable.');
    }
  }

  @override
  Future<Map<String, Object?>?> readUser(String driverId) =>
      _binding.readUser(driverId);
  @override
  Future<Map<String, Object?>?> readDriverProfile(String driverId) =>
      _binding.readDriverProfile(driverId);

  @override
  Future<Map<String, Object?>?> readAvailability() => _read(
      'driver_availability',
      'driver_id,state,vehicle_id,reserved_booking_request_id,active_trip_id,version');

  static const _offerColumns =
      'id,driver_id,booking_request_id,fare_quote_id,vehicle_id,status,version,expires_at';
  static const _tripColumns =
      'id,driver_id,rider_id,booking_request_id,fare_quote_id,vehicle_id,status,version,payment_method';

  @override
  Future<Map<String, Object?>?> readOffer(String offerId) =>
      _read('driver_match_offers', _offerColumns, 'id', offerId);
  @override
  Future<Map<String, Object?>?> readBooking(String bookingId) => _read(
      'booking_requests',
      'id,fare_quote_id,status,payment_method',
      'id',
      bookingId);
  @override
  Future<Map<String, Object?>?> readTrip(String tripId) =>
      _read('trips', _tripColumns, 'id', tripId);
  @override
  Future<Map<String, Object?>?> readTripForBooking(String bookingId) =>
      _read('trips', _tripColumns, 'booking_request_id', bookingId);

  Future<Map<String, Object?>?> _read(String table, String columns,
      [String? column, String? id]) async {
    final owner = currentOwner;
    final session = sessionIdentity;
    _check(owner, session);
    final client = _access.client!;
    var query = client.from(table).select(columns);
    // Bookings have no driver_id column. Participant RLS authorizes the exact
    // locator; the repository verifies its relationship to the owned offer.
    if (table != 'booking_requests') {
      query = query.eq('driver_id', owner.driverId!);
    }
    if (column != null) query = query.eq(column, id!);
    try {
      final row = await query.maybeSingle();
      _check(owner, session);
      return row;
    } on Object {
      // No raw backend error, token or row is retained in public state.
      throw StateError('Canonical Driver read is unavailable.');
    }
  }

  @override
  Future<Object?> acceptOffer(String offerId, int version, String key) =>
      _command('driver_transition_trip', {
        'target_id': offerId,
        'requested_status': 'accepted',
        'expected_version': version,
        'idempotency_key': key,
      });

  @override
  Future<Object?> declineOffer(String offerId, int version, String key) =>
      _command('driver_decline_match_offer', {
        'target_offer_id': offerId,
        'expected_offer_version': version,
        'idempotency_key': key,
      });

  Future<Object?> _command(String name, Map<String, Object?> params) async {
    final owner = currentOwner;
    final session = sessionIdentity;
    _check(owner, session);
    try {
      final response = await _access.client!.rpc(name, params: params);
      _check(owner, session);
      return response;
    } on Object {
      // Any ambiguous write is reconciled by authenticated canonical reads.
      // No automatic SDK RPC retry or command-response assignment projection.
      throw StateError('Canonical Driver command outcome is unresolved.');
    }
  }
}
