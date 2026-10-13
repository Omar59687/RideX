import 'package:ridex/core/models/cash_payment.dart';

/// Sanitized failures for reading a canonical Cash payment.
enum PaymentFailure { notFound, invalidRequest }

class PaymentException implements Exception {
  const PaymentException(this.failure);

  final PaymentFailure failure;
}

/// Read-only, provider-neutral view of a persisted Cash payment.
///
/// Choosing Cash belongs to the booking draft: callers pass `cash` as the
/// payment method to `FareRepository.createBookingDraft` or
/// `FareRepository.updateBookingDraft` (the latter takes a booking version).
/// Fare locking and confirmation retain that booking lineage. Neither
/// choosing Cash nor confirming a booking creates a Payment row.
///
/// Only trusted backend operations create a Payment from a Trip, using its
/// locked FareQuote and Cash method. Until then there is no payment ID or
/// payment version to read or mutate. [CashPayment.version] refers only to a
/// persisted Payment; it must not be confused with the booking draft version.
///
/// Trip cancellation reconciles a Cash Payment to `cancelled` server-side;
/// atomic trusted Trip completion settles it to `paid`. Flutter must only
/// display canonical state, never perform either payment transition. A
/// production reader must use authorized, participant-scoped backend data;
/// it must not synthesize missing CashPayment fields from a summary response.
abstract class PaymentRepository {
  /// Reads the current persisted Cash Payment by its backend-issued ID.
  ///
  /// Throws [PaymentException] with [PaymentFailure.invalidRequest] for a
  /// blank ID, or [PaymentFailure.notFound] if no payment exists. The caller
  /// must have appropriate backend authorization for a production read.
  Future<CashPayment> readCashPayment({required String paymentId});
}

/// In-memory fixture reader for mock-backed payment presentation.
///
/// [seedCashPayment] is a test/demo-only fixture setup method, not part of
/// [PaymentRepository]. Seed `cashSelected`, `cancelled`, or `paid` only as
/// canonical states returned by trusted backend operations. No fake
/// selection, cancellation, or settlement operation is exposed: changing
/// fixture state requires constructing a new fake for each scenario.
/// Never wire this concrete fake as a production payment authority.
class FakePaymentRepository implements PaymentRepository {
  final Map<String, CashPayment> _payments = {};

  /// Loads a complete, backend-shaped Cash Payment fixture.
  ///
  /// Rejects missing canonical identifiers or duplicate payment, booking,
  /// and Trip identities. Invalid seeds leave the fake unchanged.
  void seedCashPayment(CashPayment payment) {
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
  Future<CashPayment> readCashPayment({required String paymentId}) async {
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
