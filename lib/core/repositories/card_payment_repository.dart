import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/repositories/payment_repository.dart';

/// Read-only, provider-neutral view of a persisted Card payment.
///
/// Flutter-facing read contract only — not a payment-provider execution
/// adapter. Choosing Card belongs to the booking draft: callers pass `card`
/// as the payment method to `FareRepository.createBookingDraft` or
/// `FareRepository.updateBookingDraft`. Neither choosing Card nor confirming
/// a booking creates a Payment row.
///
/// Only trusted backend operations create a Payment from a Trip, using its
/// locked FareQuote and Card method, and only trusted operations perform
/// authorization, capture, void, refund, or webhook processing.
/// [CardPayment.version] refers only to a persisted Payment; it must not be
/// confused with the booking draft version.
///
/// Trip states drive server-side Card reconciliation (authorization retry,
/// capture, cancellation); Flutter must only display canonical state, never
/// perform any payment transition. Reading a payment grants no financial
/// authority. A production reader must use authorized, participant-scoped
/// backend data; it must not synthesize missing CardPayment fields from a
/// summary response.
///
/// No Stripe SDK, provider credential, or provider-specific type may enter
/// this contract. The executable payment-provider adapter is deferred to the
/// authorized P6-04/P8 scope and must remain behind a trusted server-side
/// boundary, never in UI-facing models.
abstract class CardPaymentRepository {
  /// Reads the current persisted Card Payment by its backend-issued ID.
  ///
  /// Throws [PaymentException] with [PaymentFailure.invalidRequest] for a
  /// blank ID, or [PaymentFailure.notFound] if no payment exists. The caller
  /// must have appropriate backend authorization for a production read.
  Future<CardPayment> readCardPayment({required String paymentId});
}

/// In-memory fixture reader for mock-backed payment presentation.
///
/// [seedCardPayment] is a test/demo-only fixture setup method, not part of
/// [CardPaymentRepository]. Seed any canonical [CardPaymentStatus] only as
/// states returned by trusted backend operations. No fake authorization,
/// capture, refund, cancellation, or settlement operation is exposed:
/// changing fixture state requires constructing a new fake for each scenario.
/// Never wire this concrete fake as a production payment authority.
class FakeCardPaymentRepository implements CardPaymentRepository {
  final Map<String, CardPayment> _payments = {};

  /// Loads a complete, backend-shaped Card Payment fixture.
  ///
  /// Rejects missing canonical identifiers or duplicate payment, booking,
  /// and Trip identities (the backend keeps `booking_request_id` and
  /// `trip_id` unique on `payments`). Invalid seeds leave the fake unchanged.
  void seedCardPayment(CardPayment payment) {
    final id = payment.paymentId;
    final bookingId = payment.bookingRequestId;
    final tripId = payment.tripId;
    if (id == null ||
        id.trim().isEmpty ||
        bookingId == null ||
        bookingId.trim().isEmpty ||
        tripId == null ||
        tripId.trim().isEmpty ||
        _payments.containsKey(id) ||
        _payments.values.any((existing) =>
            existing.bookingRequestId == bookingId ||
            existing.tripId == tripId)) {
      throw const PaymentException(PaymentFailure.invalidRequest);
    }
    _payments[id] = payment;
  }

  @override
  Future<CardPayment> readCardPayment({required String paymentId}) async {
    if (paymentId.trim().isEmpty) {
      throw const PaymentException(PaymentFailure.invalidRequest);
    }
    final payment = _payments[paymentId];
    if (payment == null) {
      throw const PaymentException(PaymentFailure.notFound);
    }
    return payment;
  }
}
