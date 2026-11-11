import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';

enum RiderMatchingState { awaitingDriver, noCandidates, assigned }

enum RiderMatchingFailure {
  unauthorized,
  invalidReference,
  conflict,
  unavailable,
  invalidResponse,
}

final class RiderMatchingException implements Exception {
  const RiderMatchingException(this.failure);

  final RiderMatchingFailure failure;

  @override
  String toString() => 'RiderMatchingException($failure)';
}

/// A bounded result from the existing server-side A05 Cash matching adapter.
/// `tripId`, when present, is a locator only; canonical assignment reads still
/// decide whether the Rider may enter tracking.
final class RiderMatchingRequestResult {
  const RiderMatchingRequestResult({
    required this.bookingRequestId,
    required this.fareQuoteId,
    required this.state,
    this.tripId,
  });

  final String bookingRequestId;
  final String fareQuoteId;
  final RiderMatchingState state;
  final String? tripId;
}

abstract interface class RiderMatchingRequestRepository {
  Future<RiderMatchingRequestResult> requestMatching(
    ConfirmedBookingReference reference, {
    required int expectedBookingVersion,
  });
}

/// Default for builds where live Cash matching has not been approved.
final class UnavailableRiderMatchingRequestRepository
    implements RiderMatchingRequestRepository {
  const UnavailableRiderMatchingRequestRepository();

  @override
  Future<RiderMatchingRequestResult> requestMatching(
    ConfirmedBookingReference reference, {
    required int expectedBookingVersion,
  }) async {
    throw const RiderMatchingException(RiderMatchingFailure.unavailable);
  }
}

RiderMatchingRequestResult riderMatchingResultFromJson(
  Map<dynamic, dynamic> value, {
  required String expectedBookingId,
  required String expectedQuoteId,
}) {
  final bookingId = value['booking_id'];
  final quoteId = value['fare_quote_id'];
  final rawState = value['state'];
  final tripId = value['trip_id'];
  if (bookingId is! String ||
      quoteId is! String ||
      bookingId.toLowerCase() != expectedBookingId.toLowerCase() ||
      quoteId.toLowerCase() != expectedQuoteId.toLowerCase()) {
    throw const RiderMatchingException(RiderMatchingFailure.invalidResponse);
  }
  final state = switch (rawState) {
    'awaitingDriver' => RiderMatchingState.awaitingDriver,
    'noCandidates' => RiderMatchingState.noCandidates,
    'assigned' => RiderMatchingState.assigned,
    _ => throw const RiderMatchingException(
        RiderMatchingFailure.invalidResponse,
      ),
  };
  if (state == RiderMatchingState.assigned) {
    if (tripId is! String || !isCanonicalTripId(tripId)) {
      throw const RiderMatchingException(RiderMatchingFailure.invalidResponse);
    }
  } else if (tripId != null) {
    throw const RiderMatchingException(RiderMatchingFailure.invalidResponse);
  }
  return RiderMatchingRequestResult(
    bookingRequestId: bookingId,
    fareQuoteId: quoteId,
    state: state,
    tripId: tripId as String?,
  );
}
