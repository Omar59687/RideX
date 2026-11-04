import 'package:ridex/core/models/rider_booking_search.dart';

enum RiderBookingSearchReadFailure { unavailable, invalidResponse }

class RiderBookingSearchReadException implements Exception {
  const RiderBookingSearchReadException(this.failure);

  final RiderBookingSearchReadFailure failure;
}

/// Reads the original BookingRequest using the adapter's authenticated Rider.
///
/// The ID is a locator, never authorization. Implementations must check the
/// current authenticated session and ownership before and after the read; null
/// means missing or inaccessible. This interface cannot create, confirm,
/// cancel, or restart a booking. No production reader is wired in Slice 1.
abstract interface class RiderBookingSearchRepository {
  Future<RiderBookingSearchSnapshot?> readBooking({
    required String bookingRequestId,
  });
}

/// Default for an unintegrated feature: never falls back to demo data.
class UnavailableRiderBookingSearchRepository
    implements RiderBookingSearchRepository {
  const UnavailableRiderBookingSearchRepository();

  @override
  Future<RiderBookingSearchSnapshot?> readBooking({
    required String bookingRequestId,
  }) async {
    throw const RiderBookingSearchReadException(
      RiderBookingSearchReadFailure.unavailable,
    );
  }
}
