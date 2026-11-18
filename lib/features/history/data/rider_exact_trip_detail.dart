import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';

/// Payment/receipt evidence is deliberately separate from Trip lifecycle.
/// The eventual production adapter must use Yousuf's independently authorized
/// typed payment and receipt reads; this port has no finance writes.
enum RiderDetailPaymentState {
  unavailable,
  cashSelectedUnpaid,
  cashReportedPaidUnverified,
  cardPending,
  cardUnknown,
  cardReportedCapturedUnverified,
  cancelled,
}

enum RiderDetailReceiptState { unavailable, unverified, reportedIssuedUnverified }

final class RiderDetailFinancialRead {
  const RiderDetailFinancialRead({
    required this.tripId,
    required this.bookingRequestId,
    required this.riderId,
    required this.paymentId,
    required this.payment,
    required this.receipt,
  });

  final String tripId;
  final String bookingRequestId;
  final String riderId;
  final String paymentId;
  final RiderDetailPaymentState payment;
  final RiderDetailReceiptState receipt;
}

/// Accepts only an explicitly backend-linked payment ID. Implementations must
/// independently validate SDK session, Rider profile, payment/Trip linkage,
/// and receipt evidence. The view never turns reported paid/issued into proof.
abstract interface class RiderTripFinancialReadPort {
  Future<RiderDetailFinancialRead?> readForTrip({
    required String riderId,
    required String tripId,
    required String bookingRequestId,
    required String paymentId,
  });
}

final class RiderExactTripDetail {
  const RiderExactTripDetail({required this.trip, this.financial});
  final RiderHistoryTrip trip;
  final RiderDetailFinancialRead? financial;
}

/// Feature-local coordinator. This does not replace Supabase RLS or SDK
/// identity pinning inside production adapters. It checks the caller's Rider
/// authorization both before and after every await, including A->B->A changes
/// where a production session-epoch callback must invalidate the request.
final class RiderExactTripDetailReader {
  const RiderExactTripDetailReader({
    required this.history,
    required this.activeRiderId,
    required this.isAuthorized,
    required this.sessionEpoch,
    this.financial,
  });

  final RiderTripHistoryRepository history;
  final RiderTripFinancialReadPort? financial;
  final String? Function() activeRiderId;
  final bool Function() isAuthorized;
  final Object? Function() sessionEpoch;

  bool _valid(String riderId, Object? epoch) =>
      isCanonicalTripId(riderId) &&
      activeRiderId() == riderId &&
      isAuthorized() &&
      identical(sessionEpoch(), epoch);

  Future<RiderExactTripDetail?> readExact({
    required String riderId,
    required String tripId,
  }) async {
    final epoch = sessionEpoch();
    if (!_valid(riderId, epoch)) {
      throw const RiderHistoryException(RiderHistoryFailure.unauthorized);
    }
    if (!isCanonicalTripId(tripId)) {
      throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
    }

    final trip = await history.readExactTrip(riderId: riderId, tripId: tripId);
    if (!_valid(riderId, epoch)) {
      throw const RiderHistoryException(RiderHistoryFailure.staleSession);
    }
    if (trip == null) return null;
    if (trip.tripId != tripId || trip.riderId != riderId ||
        !isCanonicalTripId(trip.bookingRequestId)) {
      throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
    }

    // No financial inference from completed/cancelled Trip status or fare.
    RiderDetailFinancialRead? evidence;
    final paymentId = trip.paymentId;
    if (paymentId != null && financial != null) {
      evidence = await financial!.readForTrip(
        riderId: riderId,
        tripId: tripId,
        bookingRequestId: trip.bookingRequestId,
        paymentId: paymentId,
      );
      if (!_valid(riderId, epoch)) {
        throw const RiderHistoryException(RiderHistoryFailure.staleSession);
      }
      if (evidence != null &&
          (evidence.tripId != tripId ||
              evidence.riderId != riderId ||
              evidence.bookingRequestId != trip.bookingRequestId ||
              evidence.paymentId != paymentId)) {
        throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
      }
    }
    return RiderExactTripDetail(trip: trip, financial: evidence);
  }
}
