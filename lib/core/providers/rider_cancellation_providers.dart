import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/repositories/rider_booking_cancellation_repository.dart';
import 'package:ridex/core/repositories/supabase_rider_booking_search_repository.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/services/rider_cancellation/rider_cancellation_coordinator.dart';

final riderCancellationRepositoryProvider =
    Provider<RiderBookingCancellationRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    if (client == null) return const UnavailableRiderBookingCancellationRepository();
    return SupabaseRiderBookingCancellationRepository(
      client,
      readSession: () => ref.read(sessionControllerProvider),
    );
  },
);

/// Process-local, Rider/Booking-scoped cancellation ownership shared by every
/// mounted instance of the canonical searching screen.
final riderCancellationCoordinatorProvider =
    ChangeNotifierProvider<RiderCancellationCoordinator>((ref) {
  return RiderCancellationCoordinator(
    repository: ref.watch(riderCancellationRepositoryProvider),
  );
});
