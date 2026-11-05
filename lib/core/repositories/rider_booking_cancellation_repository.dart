import 'package:ridex/core/models/rider_booking_cancellation.dart';

/// Provider-neutral command boundary for cancelling one original
/// BookingRequest.
///
/// The ID is a locator, never authorization. Implementations must resolve the
/// current authenticated Rider and verify ownership before dispatching. An
/// accepted result must be re-validated (same BookingRequest, same Rider, Cash,
/// status cancelled) or reported as unknown. This interface cannot create a
/// booking, dispatch matching, or mutate a Trip.
abstract interface class RiderBookingCancellationRepository {
  /// Dispatches exactly one cancellation attempt for [bookingRequestId].
  ///
  /// Expected backend mapping:
  /// - `55000` non-cancellable state -> [RiderCancellationRejection.notCancellable]
  /// - `40001` stale aggregate version -> [RiderCancellationRejection.staleVersion]
  /// - `P0002` missing or foreign booking -> [RiderCancellationRejection.notFound]
  /// - `22023` invalid reason -> [RiderCancellationRejection.reasonInvalid]
  /// - `42501` blocked or unauthorized Rider -> [RiderCancellationRejection.blockedOrDenied]
  /// - transport failure, timeout, or unverifiable response -> unknown
  Future<RiderBookingCancellationResult> cancelBooking({
    required String bookingRequestId,
    required int expectedVersion,
    required String reasonCode,
  });
}

/// Fail-closed default for the unintegrated surface.
///
/// It never claims success and never fabricates a rejection; the outcome stays
/// unknown so cancellation remains blocked.
class UnavailableRiderBookingCancellationRepository
    implements RiderBookingCancellationRepository {
  const UnavailableRiderBookingCancellationRepository();

  @override
  Future<RiderBookingCancellationResult> cancelBooking({
    required String bookingRequestId,
    required int expectedVersion,
    required String reasonCode,
  }) async {
    return const RiderBookingCancellationUnknown();
  }
}
