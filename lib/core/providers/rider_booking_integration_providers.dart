import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/trip_realtime_providers.dart';
import 'package:ridex/core/repositories/rider_booking_search_repository.dart';
import 'package:ridex/core/repositories/rider_matching_request_repository.dart';
import 'package:ridex/core/repositories/supabase_rider_booking_search_repository.dart';
import 'package:ridex/core/repositories/supabase_rider_matching_request_repository.dart';
import 'package:ridex/core/repositories/supabase_rider_trip_tracking_repository.dart';
import 'package:ridex/core/models/rider_trip_cancellation.dart';
import 'package:ridex/core/repositories/supabase_rider_trip_cancellation_repository.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/features/booking/application/rider_booking_integration_gate.dart';

final riderBookingSearchRepositoryProvider =
    Provider<RiderBookingSearchRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const UnavailableRiderBookingSearchRepository();
  return SupabaseRiderBookingSearchRepository(
    client,
    readSession: () => ref.read(sessionControllerProvider),
  );
});

final riderMatchingRequestRepositoryProvider =
    Provider<RiderMatchingRequestRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (!riderCashMatchingIntegrationEnabled || client == null) {
    return const UnavailableRiderMatchingRequestRepository();
  }
  return SupabaseRiderMatchingRequestRepository(
    client,
    readSession: () => ref.read(sessionControllerProvider),
  );
});

/// Wires the existing D02/D04 adapters into the canonical Rider lifecycle
/// read/watch seam. It does not mount a screen or start a second GPS publisher.
final riderSupabaseTripTrackingRepositoryProvider =
    Provider<SupabaseRiderTripTrackingRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final realtime = ref.watch(tripRealtimeAdapterProvider);
  if (client == null || realtime == null) return null;
  return SupabaseRiderTripTrackingRepository(
    client,
    realtime: realtime,
    readSession: () => ref.read(sessionControllerProvider),
  );
});

final riderTripCancellationRepositoryProvider =
    Provider<RiderTripCancellationRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final trips = ref.watch(riderSupabaseTripTrackingRepositoryProvider);
  if (client == null || trips == null) return null;
  return SupabaseRiderTripCancellationRepository(
    client,
    readSession: () => ref.read(sessionControllerProvider),
    tripRepository: trips,
  );
});
