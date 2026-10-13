import 'package:equatable/equatable.dart';

/// Cash payment status (`public.cash_payment_status`).
///
/// Canonical backend values (verbatim from
/// `supabase/migrations/005_phase3_core_security_foundation.sql`):
/// `'cashSelected'`, `'paid'`, `'cancelled'`. CamelCase is intentional and
/// must be preserved exactly; snake_case variants do not exist in the
/// database contract.
///
/// - [cashSelected] means the rider selected Cash but has NOT paid yet.
///   It is an unpaid state. Only a trusted backend operation (after trip
///   completion) may move a payment to [paid].
/// - [paid] and [cancelled] are terminal: no further transition exists.
enum CashPaymentStatus {
  cashSelected,
  paid,
  cancelled;

  /// Exact backend string for this status.
  String get backendValue => name;

  /// Parses an exact backend string. Rejects anything else, including
  /// snake_case lookalikes such as `cash_selected`.
  static CashPaymentStatus fromBackendValue(String value) {
    return switch (value) {
      'cashSelected' => CashPaymentStatus.cashSelected,
      'paid' => CashPaymentStatus.paid,
      'cancelled' => CashPaymentStatus.cancelled,
      _ => throw ArgumentError.value(value, 'value', 'Unknown cash status.'),
    };
  }
}

/// Immutable Cash payment domain object.
///
/// Conventions mirror [FareQuote]: all money is integer fils in JOD, and
/// Flutter only carries backend-computed values — it never calculates fares
/// and never declares payment success.
///
/// Security notes:
/// - Payment method and payment status are separate concepts; a selected
///   method ([cashSelected]) is not a completed payment.
/// - Only trusted backend operations may confirm Cash payment success
///   (backend requires the trip to be completed before `paid`);
///   Flutter-side state is advisory and must be reconciled with the server.
/// - No secrets, provider references, or card data belong in this model.
class CashPayment extends Equatable {
  CashPayment({
    this.paymentId,
    this.bookingRequestId,
    this.tripId,
    required this.amountFils,
    this.currency = 'JOD',
    required this.status,
    required this.version,
    this.idempotencyKey,
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
  }

  final String? paymentId;
  final String? bookingRequestId;
  final String? tripId;
  final int amountFils;
  final String currency;
  final CashPaymentStatus status;
  final int version;
  final String? idempotencyKey;

  /// Whether any money has changed hands. Only [CashPaymentStatus.paid]
  /// counts; [CashPaymentStatus.cashSelected] is explicitly unpaid.
  bool get isPaid => status == CashPaymentStatus.paid;

  /// Whether this payment can still move to another status.
  bool get isTerminal => status != CashPaymentStatus.cashSelected;

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
      ];
}

/// Pure check of possible canonical Cash lifecycle transitions across trusted
/// backend operations.
///
/// `cashSelected` -> `paid` occurs only through atomic trusted Trip completion.
/// The public `backend_transition_payment` RPC cannot settle Cash to `paid`,
/// and this function does not authorize Flutter or any client to perform
/// payment settlement.
///
/// Allowed: `cashSelected` -> `paid`, `cashSelected` -> `cancelled`.
/// [CashPaymentStatus.paid] and [CashPaymentStatus.cancelled] are terminal.
bool canTransitionCash(CashPaymentStatus from, CashPaymentStatus to) {
  return from == CashPaymentStatus.cashSelected &&
      (to == CashPaymentStatus.paid || to == CashPaymentStatus.cancelled);
}
