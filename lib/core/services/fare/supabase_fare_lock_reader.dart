import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// RLS-protected read adapter. No RPC, Edge Function, service-role credential,
/// draft mutation, or client-side latest-quote selection is involved.
class SupabaseFareLockReader {
  const SupabaseFareLockReader(this._client);

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> read({
    required String bookingRequestId,
    required String riderId,
  }) async {
    if (_client.auth.currentUser?.id != riderId) {
      throw const FareException(FareFailure.unauthorized);
    }
    try {
      // One embedded SELECT gives one database snapshot. The composite FK
      // disambiguates it from booking_requests_current_fare_quote_fk. Read all
      // candidates; never select an arbitrary first or latest quote.
      final rows = await _client
          .from('booking_requests')
          .select(
            'id,rider_id,version,status,fare_quote_id,'
            'fare_quotes!fare_quotes_booking_rider_fk('
            'id,booking_request_id,rider_id,quote_version,pricing_version,'
            'fixed_fare_fils,breakdown,status,expires_at,currency,created_at,'
            'route_distance_meters,route_duration_seconds,locked_at)',
          )
          .eq('id', bookingRequestId)
          .eq('rider_id', riderId);
      if (_client.auth.currentUser?.id != riderId) {
        throw const FareException(FareFailure.unauthorized);
      }
      return rows;
    } on PostgrestException catch (error) {
      throw FareTransportFailure(code: error.code);
    }
  }
}
