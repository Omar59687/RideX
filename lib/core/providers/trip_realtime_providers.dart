import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/core/services/trips/rider_trip_location_adapter.dart';
import 'package:ridex/core/services/trips/rider_trip_location_source.dart';
import 'package:ridex/core/services/trips/supabase_rider_trip_location_source.dart';
import 'package:ridex/core/services/trips/supabase_trip_realtime_source.dart';
import 'package:ridex/core/services/trips/trip_realtime_adapter.dart';
import 'package:ridex/core/services/trips/trip_realtime_source.dart';

/// Session-scoped adapters for explicitly composed Trip tracking consumers.
/// These providers do not mount routes or enable the still-gated Rider flow.
final tripRealtimeSourceProvider = Provider<TripRealtimeSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseTripRealtimeSource(client);
});

final tripRealtimeAdapterProvider = Provider<TripRealtimeAdapter?>((ref) {
  final source = ref.watch(tripRealtimeSourceProvider);
  return source == null ? null : TripRealtimeAdapter(source);
});

final riderTripLocationSourceProvider =
    Provider<RiderTripLocationSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseRiderTripLocationSource(client);
});

final riderTripLocationAdapterProvider =
    Provider<RiderTripLocationAdapter?>((ref) {
  final trips = ref.watch(tripRealtimeAdapterProvider);
  final locations = ref.watch(riderTripLocationSourceProvider);
  if (trips == null || locations == null) return null;
  return RiderTripLocationAdapter(trips: trips, locations: locations);
});
