import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/rider_payments/data/a04_rider_financial_read_adapter.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Authenticated application-client transport for the read-only A04 RPC.
/// No service-role client or financial command is exposed by this class.
final class SupabaseA04FinancialReadTransport
    implements A04FinancialReadTransport {
  const SupabaseA04FinancialReadTransport(this.client);

  final SupabaseClient client;

  @override
  Future<Object?> readFinancialRow({required String tripId}) => client.rpc(
        'user_trip_financial_read_v1',
        params: {'target_trip_id': tripId},
      );
}

/// Reads the exact Trip context through participant RLS before the financial
/// RPC. A04 omits booking, Rider and Driver IDs, so they must come from this
/// separately authorized canonical table read.
final class SupabaseA04AuthorizedTripContextReader
    implements A04AuthorizedTripContextReader {
  SupabaseA04AuthorizedTripContextReader({
    required this.client,
    required this.riderId,
    required this.readSession,
    required this.isCurrent,
  }) : _sdkSession = client.auth.currentSession;

  final SupabaseClient client;
  final String riderId;
  final SessionState Function() readSession;
  final bool Function() isCurrent;
  final Session? _sdkSession;

  bool get _authorized => _sdkSession != null &&
      !_sdkSession.isExpired &&
      _sdkSession.user.id == riderId &&
      identical(client.auth.currentSession, _sdkSession) &&
      isCurrent() &&
      _riderSession(readSession(), riderId);

  @override
  Future<RiderCheckoutTrip?> readAuthorizedTrip({
    required String tripId,
    required String riderId,
  }) async {
    if (!_authorized || riderId != this.riderId || !isCanonicalTripId(tripId)) {
      throw const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.unauthorized,
      );
    }
    try {
      final profile = await client
          .from('users')
          .select('id,role,is_blocked')
          .eq('id', riderId)
          .maybeSingle();
      if (!_authorized) throw const _StaleA04Read();
      if (profile == null ||
          profile['id'] != riderId ||
          profile['role'] != 'rider' ||
          profile['is_blocked'] != false) {
        throw const RiderCheckoutTripReadException(
          RiderCheckoutTripReadFailure.unauthorized,
        );
      }

      final row = await client
          .from('trips')
          .select(
            'id,booking_request_id,rider_id,driver_id,version,'
            'current_fare_fils,currency,status,payment_method',
          )
          .eq('id', tripId)
          .eq('rider_id', riderId)
          .maybeSingle();
      if (!_authorized) throw const _StaleA04Read();
      if (row == null) return null;
      if (row['id'] != tripId || row['rider_id'] != riderId) {
        throw const FormatException('A04 Trip identity mismatch.');
      }
      final version = row['version'];
      final amount = row['current_fare_fils'];
      if (version is! int || amount is! int ||
          !isCanonicalTripId(row['booking_request_id'] as String? ?? '') ||
          !isCanonicalTripId(row['driver_id'] as String? ?? '') ||
          row['currency'] != 'JOD') {
        throw const FormatException('Invalid A04 Trip context.');
      }
      final status = DriverTripLifecycleStatus.fromBackendValue(
        row['status'] as String,
      );
      final method = PaymentMethod.fromBackendValue(
        row['payment_method'] as String,
      );
      return RiderCheckoutTrip(
        tripId: tripId,
        bookingRequestId: row['booking_request_id'] as String,
        riderId: riderId,
        driverId: row['driver_id'] as String,
        version: version,
        currentFareFils: amount,
        currency: 'JOD',
        status: status,
        paymentMethod: method,
      );
    } on RiderCheckoutTripReadException {
      rethrow;
    } on _StaleA04Read {
      throw const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.unauthorized,
      );
    } on Object {
      throw const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.unavailable,
      );
    }
  }
}

bool _riderSession(SessionState state, String riderId) =>
    state.status == SessionStatus.authenticated &&
    state.role == RideRole.rider &&
    state.user?.id == riderId &&
    state.user?.isBlocked == false;

final class _StaleA04Read implements Exception {
  const _StaleA04Read();
}
