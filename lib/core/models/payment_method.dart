/// Provider-independent payment method (`public.payment_method`).
///
/// The payment *method* (how the rider intends to pay) is a different
/// concept from the payment *status* (where the payment stands). See
/// [CashPaymentStatus] for the Cash lifecycle.
///
/// Canonical backend strings (verbatim from
/// `supabase/migrations/005_phase3_core_security_foundation.sql`):
/// `'cash'` and `'card'`.
enum PaymentMethod {
  cash,
  card;

  /// Exact backend string for this method.
  String get backendValue => name;

  /// Parses an exact backend string. Rejects anything else.
  static PaymentMethod fromBackendValue(String value) {
    return switch (value) {
      'cash' => PaymentMethod.cash,
      'card' => PaymentMethod.card,
      _ => throw ArgumentError.value(value, 'value', 'Unknown payment method.'),
    };
  }
}
