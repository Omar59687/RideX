import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/fare_quote.dart' show formatFareFils;
import 'package:ridex/core/models/mock_trip.dart' show TripStatus;

/// Caller-supplied context for payment-success presentation.
///
/// This is presentation input, not a backend contract, credential, or proof
/// of trust. Supplying this object does NOT establish backend trust: the
/// public constructor means any caller can build one, including from MockTrip
/// data, locally constructed identifiers, or other client-owned state, and
/// construction is deliberately not restricted here. Copying a payment's own
/// identities into evidence also proves nothing.
///
/// Trust can only come from an approved canonical Trip-to-payment reader that
/// populates both the persisted payment record and this evidence from
/// authorized, participant-scoped backend data. That reader does not exist in
/// this slice.
///
/// PRODUCTION INTEGRATION BLOCKER: until an approved canonical reader exists,
/// [RiderPaymentPresentation.canDescribeAsPaid] must not be treated as trusted
/// payment confirmation, and this type must not be used to authorize any
/// financial outcome. Tests may supply explicit fixtures; missing evidence
/// fails closed.
final class RiderPaymentTripEvidence {
  /// Builds caller-supplied evidence. See the class documentation: this
  /// constructor does not authenticate or verify anything.
  const RiderPaymentTripEvidence({
    required this.paymentId,
    required this.tripId,
    required this.bookingRequestId,
    required this.tripStatus,
  });

  /// Unverified persisted payment identity, or null when unavailable.
  final String? paymentId;

  /// Unverified Trip identity, or null when unavailable.
  final String? tripId;

  /// Unverified booking-request identity, or null when unavailable.
  final String? bookingRequestId;

  /// Caller-asserted Trip status; not proof of backend completion.
  final TripStatus tripStatus;
}

/// Pure display data derived from a canonical Cash or Card payment record.
///
/// Status display, permission to describe payment success, and receipt
/// existence are separate. Mapping never changes a payment or Trip, and it
/// cannot establish that a real receipt has been issued. No repositories,
/// financial commands, client fare calculations, or Trip lookups belong here.
final class RiderPaymentPresentation {
  const RiderPaymentPresentation._({
    required this.methodLabel,
    required this.statusLabel,
    required this.statusDescription,
    required this.amountFils,
    required this.currency,
    required this.canDescribeAsPaid,
  });

  factory RiderPaymentPresentation.fromCash(
    CashPayment payment, {
    RiderPaymentTripEvidence? tripEvidence,
  }) {
    final canDescribeAsPaid = payment.status == CashPaymentStatus.paid &&
        _matchesCompletedTrip(
          paymentId: payment.paymentId,
          tripId: payment.tripId,
          bookingRequestId: payment.bookingRequestId,
          evidence: tripEvidence,
        );
    final (label, description) = switch (payment.status) {
      CashPaymentStatus.cashSelected => (
          'Cash selected (unpaid)',
          'Cash is selected; payment is still unpaid.',
        ),
      CashPaymentStatus.paid => canDescribeAsPaid
          ? (
              'Payment completed',
              'Cash payment is confirmed for this completed trip.',
            )
          : (
              'Paid status reported',
              'Payment identity and completed-trip evidence must match '
                  'before confirming payment.',
            ),
      CashPaymentStatus.cancelled => (
          'Payment cancelled',
          'Cash payment was cancelled; it is not a paid payment.',
        ),
    };
    return RiderPaymentPresentation._(
      methodLabel: 'Cash',
      statusLabel: label,
      statusDescription: description,
      amountFils: payment.amountFils,
      currency: payment.currency,
      canDescribeAsPaid: canDescribeAsPaid,
    );
  }

  factory RiderPaymentPresentation.fromCard(
    CardPayment payment, {
    RiderPaymentTripEvidence? tripEvidence,
  }) {
    final canDescribeAsPaid =
        payment.status == CardPaymentStatus.cardPaymentSucceeded &&
            _matchesCompletedTrip(
              paymentId: payment.paymentId,
              tripId: payment.tripId,
              bookingRequestId: payment.bookingRequestId,
              evidence: tripEvidence,
            );
    final (label, description) = switch (payment.status) {
      CardPaymentStatus.cardPaymentPending => (
          'Payment pending',
          'Card payment is pending; capture is not confirmed.',
        ),
      CardPaymentStatus.cardPaymentAuthorized => (
          'Authorized (not captured)',
          'Card payment is authorized; authorization is not capture.',
        ),
      CardPaymentStatus.cardPaymentSucceeded => canDescribeAsPaid
          ? (
              'Payment captured',
              'Card payment was successfully captured for this completed trip.',
            )
          : (
              'Success status reported',
              'Payment identity and completed-trip evidence must match '
                  'before confirming capture.',
            ),
      CardPaymentStatus.cardPaymentFailed => (
          'Payment failed',
          'Card payment failed. Trip completion is a separate state.',
        ),
      CardPaymentStatus.paymentCancelled => (
          'Payment cancelled',
          'Card payment was cancelled; it is not a paid payment.',
        ),
      CardPaymentStatus.refundPending => (
          'Refund pending',
          'A refund is pending for this card payment.',
        ),
      CardPaymentStatus.refunded => (
          'Refunded',
          'Card payment is refunded; it is not a current completed payment.',
        ),
    };
    return RiderPaymentPresentation._(
      methodLabel: 'Card',
      statusLabel: label,
      statusDescription: description,
      amountFils: payment.amountFils,
      currency: payment.currency,
      canDescribeAsPaid: canDescribeAsPaid,
    );
  }

  final String methodLabel;
  final String statusLabel;
  final String statusDescription;

  /// Exact backend-supplied amount and currency, independent of Trip fares.
  final int amountFils;
  final String currency;

  /// Presentation eligibility only; never authorizes a financial operation and
  /// never establishes backend trust.
  ///
  /// True only when a successful canonical payment status is combined with
  /// exact, nonblank payment/Trip/booking identities matching the supplied
  /// evidence for a completed Trip. Because [RiderPaymentTripEvidence] is
  /// caller-constructible, a true value reflects the caller's assertion rather
  /// than verified backend evidence. A production claim requires evidence from
  /// an approved canonical Trip-to-payment reader, which is a deferred
  /// production integration requirement (see the evidence class docs).
  /// Refund states are never ordinary paid presentation.
  final bool canDescribeAsPaid;

  /// Uses the existing fils formatter's two-decimal display rounding only.
  /// [amountFils] retains the exact amount; no fare components are inferred.
  String get formattedAmount => formatFareFils(amountFils);

  /// Unknown until an approved receipt contract supplies actual receipt data.
  ///
  /// Always null here: null means unavailable, not proof of absence. Payment
  /// success, refund state and completed-Trip evidence never establish that a
  /// receipt was issued, and this model fabricates no receipt ID, issuance
  /// timestamp, tax line, fare breakdown, or refund record. Receipt
  /// presentation is deferred to a later slice with a trusted receipt contract.
  bool? get issuedReceiptExists => null;
}

bool _matchesCompletedTrip({
  required String? paymentId,
  required String? tripId,
  required String? bookingRequestId,
  required RiderPaymentTripEvidence? evidence,
}) {
  return evidence != null &&
      evidence.tripStatus == TripStatus.completed &&
      _matchesNonblankId(paymentId, evidence.paymentId) &&
      _matchesNonblankId(tripId, evidence.tripId) &&
      _matchesNonblankId(bookingRequestId, evidence.bookingRequestId);
}

bool _matchesNonblankId(String? recordId, String? evidenceId) {
  // Do not normalize identifiers to make mismatched records appear linked.
  return recordId != null &&
      recordId.trim().isNotEmpty &&
      recordId == evidenceId;
}
