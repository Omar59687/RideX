import 'package:ridex/core/models/rider_booking_search.dart';

/// Client-selected cancellation reasons.
///
/// The backend stores free text bounded to 1..100 characters; these are values
/// chosen by the Rider, not a server-side enum.
const List<String> riderCancellationReasonOptions = [
  'Changed my mind',
  'Booked by mistake',
  'Driver took too long',
  'Other reason',
];

/// Cancellation state kept separate from ordinary booking-read outcomes.
enum RiderCancellationPhase {
  idle,
  cancelling,
  rejected,
  uncertain,
}

/// Typed backend rejection for one cancellation attempt.
enum RiderCancellationRejection {
  staleVersion,
  notCancellable,
  notFound,
  reasonInvalid,
  blockedOrDenied,
  backend,
}

/// The only booking statuses from which the Rider may cancel.
bool isCancellableBookingStatus(RiderBookingSearchStatus status) =>
    status == RiderBookingSearchStatus.confirmed ||
    status == RiderBookingSearchStatus.searching;

/// Trims and validates a client-selected reason before any dispatch.
bool isValidCancellationReason(String value) {
  final trimmed = value.trim();
  return trimmed.isNotEmpty && trimmed.length <= 100;
}

/// Result of exactly one cancellation attempt.
sealed class RiderBookingCancellationResult {
  const RiderBookingCancellationResult();
}

/// The backend confirmed cancellation; [booking] must already be validated as
/// the same owned, Cash, cancelled BookingRequest snapshot.
final class RiderBookingCancellationAccepted
    extends RiderBookingCancellationResult {
  const RiderBookingCancellationAccepted(this.booking);

  final RiderBookingSearchSnapshot booking;
}

/// The backend definitively rejected the attempt without a committed update.
final class RiderBookingCancellationRejected
    extends RiderBookingCancellationResult {
  const RiderBookingCancellationRejected(this.rejection);

  final RiderCancellationRejection rejection;
}

/// The outcome cannot be established. The booking must not be reported as
/// cancelled, and another cancellation must not be replayed automatically.
final class RiderBookingCancellationUnknown
    extends RiderBookingCancellationResult {
  const RiderBookingCancellationUnknown();
}
