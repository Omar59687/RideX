import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';

/// Independent receipt presentation contract. Only a trusted, actor-scoped
/// canonical backend read may construct verified receipt evidence in production.
/// This is not derived from Trip completion or a Card Payment status.
final class RiderVerifiedReceipt {
  RiderVerifiedReceipt({
    required this.receiptId,
    required this.receiptNumber,
    required this.tripId,
    required this.paymentId,
    required this.amountPaidFils,
    required this.currency,
    required this.paymentMethod,
    required this.issuedAt,
  }) {
    for (final value in [receiptId, tripId, paymentId]) {
      if (!isCanonicalTripId(value)) {
        throw ArgumentError.value(value, 'receipt identity', 'Must be a UUID.');
      }
    }
    if (receiptNumber.trim().isEmpty ||
        receiptNumber.trim().length > 128 ||
        amountPaidFils < 0 ||
        currency != 'JOD' ||
        paymentMethod != PaymentMethod.card ||
        !issuedAt.isUtc) {
      throw ArgumentError('Invalid canonical Card receipt evidence.');
    }
  }

  final String receiptId;
  final String receiptNumber;
  final String tripId;
  final String paymentId;
  final int amountPaidFils;
  final String currency;
  final PaymentMethod paymentMethod;
  final DateTime issuedAt;

  bool matches({required String tripId, required String paymentId}) =>
      this.tripId.toLowerCase() == tripId.toLowerCase() &&
      this.paymentId.toLowerCase() == paymentId.toLowerCase();
}

/// Receipt states remain independent from financial state. UNKNOWN means that
/// receipt issuance or read outcome could not be established; it is not absence.
sealed class RiderReceiptState {
  const RiderReceiptState();
}

final class RiderReceiptUnavailable extends RiderReceiptState {
  const RiderReceiptUnavailable();
}

final class RiderReceiptLoading extends RiderReceiptState {
  const RiderReceiptLoading();
}

final class RiderReceiptUnknown extends RiderReceiptState {
  const RiderReceiptUnknown();
}

final class RiderReceiptNotIssued extends RiderReceiptState {
  const RiderReceiptNotIssued();
}

final class RiderReceiptReadError extends RiderReceiptState {
  const RiderReceiptReadError();
}

final class RiderReceiptVerified extends RiderReceiptState {
  const RiderReceiptVerified(this.receipt);
  final RiderVerifiedReceipt receipt;
}

/// Fail closed if the independently read receipt does not match the canonical
/// Trip and Payment identity already verified in the same authenticated session.
RiderReceiptState verifiedReceiptForPayment({
  required RiderVerifiedReceipt receipt,
  required String tripId,
  required String paymentId,
}) {
  if (!isCanonicalTripId(tripId) || !isCanonicalTripId(paymentId)) {
    return const RiderReceiptUnknown();
  }
  if (!receipt.matches(tripId: tripId, paymentId: paymentId)) {
    return const RiderReceiptUnknown();
  }
  return RiderReceiptVerified(receipt);
}

/// Separate, read-only seam for B05's eventually approved canonical receipt
/// reader. No endpoint name, forged success, or direct finance table access.
abstract interface class RiderReceiptReader {
  /// Returns a typed outcome from an independent authenticated read. A
  /// production adapter may return [RiderCanonicalReceiptNotIssued] only
  /// when its reviewed contract authoritatively establishes absence. A null
  /// row, hidden record, malformed payload, or uncertain result must not be
  /// mapped to that outcome.
  Future<RiderCanonicalReceiptReadResult> readReceipt({
    required String tripId,
    required String paymentId,
  });
}

/// Typed outcomes of an independent canonical receipt read. These are
/// client-side read results, not server payment/receipt status values.
sealed class RiderCanonicalReceiptReadResult {
  const RiderCanonicalReceiptReadResult();
}

final class RiderCanonicalReceiptFound extends RiderCanonicalReceiptReadResult {
  const RiderCanonicalReceiptFound(this.receipt);

  final RiderVerifiedReceipt receipt;
}

/// A reader may produce this only for an authoritative canonical absence.
final class RiderCanonicalReceiptNotIssued
    extends RiderCanonicalReceiptReadResult {
  const RiderCanonicalReceiptNotIssued();
}

final class UnavailableRiderReceiptReader implements RiderReceiptReader {
  const UnavailableRiderReceiptReader();

  @override
  Future<RiderCanonicalReceiptReadResult> readReceipt({
    required String tripId,
    required String paymentId,
  }) async {
    throw const RiderReceiptUnavailableException();
  }
}

final class RiderReceiptUnavailableException implements Exception {
  const RiderReceiptUnavailableException();
}

/// The receipt reader could not establish whether a receipt exists. This is
/// distinct from an authoritative empty result and must remain UNKNOWN.
final class RiderReceiptOutcomeUnknownException implements Exception {
  const RiderReceiptOutcomeUnknownException();
}
