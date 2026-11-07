import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/repositories/rider_booking_cancellation_repository.dart';
import 'package:ridex/core/services/rider_cancellation/rider_cancellation_coordinator.dart';

final riderCancellationRepositoryProvider =
    Provider<RiderBookingCancellationRepository>(
  (ref) => const UnavailableRiderBookingCancellationRepository(),
);

/// Process-local, Rider/Booking-scoped cancellation ownership shared by every
/// mounted instance of the canonical searching screen.
final riderCancellationCoordinatorProvider =
    ChangeNotifierProvider<RiderCancellationCoordinator>((ref) {
  return RiderCancellationCoordinator(
    repository: ref.watch(riderCancellationRepositoryProvider),
  );
});
