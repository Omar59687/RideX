import 'package:equatable/equatable.dart';

/// Card payment status (`public.card_payment_status`).
///
/// Canonical backend values (verbatim from
/// `supabase/migrations/005_phase3_core_security_foundation.sql`):
/// `'cardPaymentPending'`, `'cardPaymentAuthorized'`,
/// `'cardPaymentSucceeded'`, `'cardPaymentFailed'`, `'paymentCancelled'`,
/// `'refundPending'`, `'refunded'`. CamelCase is intentional and must be
/// preserved exactly; snake_case variants do not exist in the database
/// contract.
///
/// These are statuses only. Authorization occurs after matching and capture
/// only after trusted completion, both exclusively through trusted backend
/// operations with verified provider attempts. Refunds and webhook
/// verification remain backend-controlled. Flutter never declares Card
/// payment success; client-side state is advisory and must be reconciled
/// with the server.
enum CardPaymentStatus {
  cardPaymentPending,
  cardPaymentAuthorized,
  cardPaymentSucceeded,
  cardPaymentFailed,
  paymentCancelled,
  refundPending,
  refunded;

  /// Exact backend string for this status.
  String get backendValue => name;

  /// Parses an exact backend string. Rejects anything else, including
  /// snake_case lookalikes such as `card_payment_pending`.
  static CardPaymentStatus fromBackendValue(String value) {
    return switch (value) {
      'cardPaymentPending' => CardPaymentStatus.cardPaymentPending,
      'cardPaymentAuthorized' => CardPaymentStatus.cardPaymentAuthorized,
      'cardPaymentSucceeded' => CardPaymentStatus.cardPaymentSucceeded,
      'cardPaymentFailed' => CardPaymentStatus.cardPaymentFailed,
      'paymentCancelled' => CardPaymentStatus.paymentCancelled,
      'refundPending' => CardPaymentStatus.refundPending,
      'refunded' => CardPaymentStatus.refunded,
      _ => throw ArgumentError.value(value, 'value', 'Unknown card status.'),
    };
  }
}

/// Immutable Card payment domain object.
///
/// Conventions mirror [CashPayment] and [FareQuote]: all money is integer
/// fils in JOD, and Flutter only carries backend-computed values — it never
/// calculates fares and never declares payment success.
///
/// Security notes:
/// - Payment method and payment status are separate concepts; selecting Card
///   as a method is not an authorization, capture, or completed payment.
/// - Only trusted backend operations may authorize, capture, cancel, or
///   refund a Card payment (authorization post-match with a verified
///   current-cycle attempt; capture post-completion with a verified capture;
///   cancellation only for a terminal cancelled Trip with a verified void
///   when required).
/// - Only sanitized card metadata belongs here: [cardBrand] (1–32
///   characters) and [cardLastFour] (exactly four ASCII digits), mirroring
///   the backend `payments` constraints. Never store raw card numbers (PAN),
///   CVV/CVC, tokens, secrets, or provider SDK types in this model.
class CardPayment extends Equatable {
  CardPayment({
    this.paymentId,
    this.bookingRequestId,
    this.tripId,
    required this.amountFils,
    this.currency = 'JOD',
    required this.status,
    required this.version,
    this.idempotencyKey,
    this.cardBrand,
    this.cardLastFour,
  }) {
    if (amountFils < 0) {
      throw ArgumentError.value(
        amountFils,
        'amountFils',
        'Must be nonnegative.',
      );
    }
    if (currency != 'JOD') {
      throw ArgumentError.value(currency, 'currency', 'Only JOD is supported.');
    }
    if (version <= 0) {
      throw ArgumentError.value(version, 'version', 'Must be positive.');
    }
    for (final entry in {
      'paymentId': paymentId,
      'bookingRequestId': bookingRequestId,
      'tripId': tripId,
      'idempotencyKey': idempotencyKey,
    }.entries) {
      if (entry.value != null && entry.value!.trim().isEmpty) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'Must be non-empty when provided.',
        );
      }
    }
    if (cardBrand != null &&
        (cardBrand!.trim().isEmpty || cardBrand!.trim().length > 32)) {
      throw ArgumentError.value(
        cardBrand,
        'cardBrand',
        'Must be 1-32 characters when provided.',
      );
    }
    if (cardLastFour != null &&
        !RegExp(r'^[0-9]{4}$').hasMatch(cardLastFour!)) {
      throw ArgumentError.value(
        cardLastFour,
        'cardLastFour',
        'Must be exactly four ASCII digits when provided.',
      );
    }
  }

  final String? paymentId;
  final String? bookingRequestId;
  final String? tripId;
  final int amountFils;
  final String currency;
  final CardPaymentStatus status;
  final int version;
  final String? idempotencyKey;
  final String? cardBrand;
  final String? cardLastFour;

  /// Whether this payment can still move to another status. Only
  /// [CardPaymentStatus.paymentCancelled] and [CardPaymentStatus.refunded]
  /// are terminal.
  bool get isTerminal =>
      status == CardPaymentStatus.paymentCancelled ||
      status == CardPaymentStatus.refunded;

  @override
  List<Object?> get props => [
        paymentId,
        bookingRequestId,
        tripId,
        amountFils,
        currency,
        status,
        version,
        idempotencyKey,
        cardBrand,
        cardLastFour,
      ];
}

/// Pure check of possible canonical Card lifecycle transitions across
/// trusted backend operations.
///
/// Allowed: `cardPaymentPending` -> `cardPaymentAuthorized`,
/// `cardPaymentFailed`, `paymentCancelled`; `cardPaymentAuthorized` ->
/// `cardPaymentPending`, `cardPaymentSucceeded`, `cardPaymentFailed`,
/// `paymentCancelled`; `cardPaymentFailed` -> `cardPaymentPending`,
/// `cardPaymentSucceeded`, `paymentCancelled`; `cardPaymentSucceeded` ->
/// `refundPending` (trusted refund request only); `refundPending` ->
/// `refunded` (trusted refund completion only).
/// [CardPaymentStatus.paymentCancelled] and [CardPaymentStatus.refunded]
/// are terminal.
///
/// This predicate represents lifecycle possibilities only. It does NOT
/// authorize Flutter or any client to initiate authorization, capture,
/// settlement, cancellation, or refunds: every real transition additionally
/// requires trusted backend preconditions (verified current-cycle attempts,
/// Trip states, version checks) that only the server can satisfy.
bool canTransitionCard(CardPaymentStatus from, CardPaymentStatus to) {
  return switch (from) {
    CardPaymentStatus.cardPaymentPending =>
      to == CardPaymentStatus.cardPaymentAuthorized ||
          to == CardPaymentStatus.cardPaymentFailed ||
          to == CardPaymentStatus.paymentCancelled,
    CardPaymentStatus.cardPaymentAuthorized =>
      to == CardPaymentStatus.cardPaymentPending ||
          to == CardPaymentStatus.cardPaymentSucceeded ||
          to == CardPaymentStatus.cardPaymentFailed ||
          to == CardPaymentStatus.paymentCancelled,
    CardPaymentStatus.cardPaymentFailed =>
      to == CardPaymentStatus.cardPaymentPending ||
          to == CardPaymentStatus.cardPaymentSucceeded ||
          to == CardPaymentStatus.paymentCancelled,
    CardPaymentStatus.cardPaymentSucceeded =>
      to == CardPaymentStatus.refundPending,
    CardPaymentStatus.refundPending => to == CardPaymentStatus.refunded,
    CardPaymentStatus.paymentCancelled => false,
    CardPaymentStatus.refunded => false,
  };
}

/// Server-enforced Card attempt boundaries, represented here as contract
/// metadata only.
///
/// The backend permits at most two authorization attempts
/// (`initialAuthorization` then optionally one `replacementAuthorization`),
/// at most three capture attempts (one `capture` plus `captureRetry` while
/// the latest current-cycle capture has failed), and at most three attempts
/// per refund. An authorization attempt must complete within two minutes of
/// its creation. This timeout does not represent the lifetime or expiry of an
/// already completed authorization. These limits are enforced exclusively by
/// trusted backend operations; Flutter must never enforce, bypass, or
/// reinterpret them.
abstract final class CardAttemptLimits {
  static const int maxAuthorizationAttempts = 2;
  static const int maxCaptureAttempts = 3;
  static const int maxRefundAttempts = 3;
  static const Duration authorizationAttemptTimeout = Duration(minutes: 2);
}
