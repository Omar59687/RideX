import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/fare_quote.dart' show formatFareFils;
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_card.dart';

/// Allowlist mapper from canonical payment domain objects to the sanitized
/// Admin display model (P6-08 Slice B).
///
/// Sanitization boundary: the only accepted inputs are the typed
/// [CashPayment]/[CardPayment] contracts. Arbitrary strings, maps, or raw
/// payloads cannot enter — every display string below is either a fixed
/// allowlist label, a validated model field formatted by a canonical
/// formatter, or a masked derivative of a validated field.
///
/// Never emitted: payment/booking/Trip identifiers, versions, idempotency
/// keys, provider names/references/secrets, PANs, CVVs, or anything absent
/// from the P6-01/P6-03 contracts.
String adminPaymentMethodLabel(PaymentMethod method) => switch (method) {
      PaymentMethod.cash => 'Cash',
      PaymentMethod.card => 'Card',
    };

/// Fixed display label for a canonical Cash status.
///
/// [CashPaymentStatus.cashSelected] is explicitly unpaid; only
/// [CashPaymentStatus.paid] (set by trusted backend Trip completion) reads
/// as paid.
String adminCashStatusLabel(CashPaymentStatus status) => switch (status) {
      CashPaymentStatus.cashSelected => 'Selected (unpaid)',
      CashPaymentStatus.paid => 'Paid',
      CashPaymentStatus.cancelled => 'Cancelled',
    };

/// Fixed display label for a canonical Card status.
///
/// These describe persisted backend state only. Authorization, capture, and
/// success are trusted-backend outcomes; this mapper never infers them from
/// frontend actions.
String adminCardStatusLabel(CardPaymentStatus status) => switch (status) {
      CardPaymentStatus.cardPaymentPending => 'Pending',
      CardPaymentStatus.cardPaymentAuthorized => 'Authorized',
      CardPaymentStatus.cardPaymentSucceeded => 'Succeeded',
      CardPaymentStatus.cardPaymentFailed => 'Failed',
      CardPaymentStatus.paymentCancelled => 'Cancelled',
      CardPaymentStatus.refundPending => 'Refund pending',
      CardPaymentStatus.refunded => 'Refunded',
    };

/// Masks a validated last-four into display form.
///
/// [lastFour] must already satisfy the [CardPayment] contract (exactly four
/// ASCII digits); this function only prefixes the mask, never accepts raw
/// card numbers.
String maskCardLastFour(String lastFour) {
  assert(
    RegExp(r'^[0-9]{4}$').hasMatch(lastFour),
    'maskCardLastFour accepts only validated four-digit input.',
  );
  return '•••• $lastFour';
}

/// Maps a canonical Cash payment to its sanitized Admin display model.
AdminSanitizedPayment mapCashPaymentForAdmin(CashPayment payment) {
  return AdminSanitizedPayment(
    methodLabel: adminPaymentMethodLabel(PaymentMethod.cash),
    statusLabel: adminCashStatusLabel(payment.status),
    amountDisplay: formatFareFils(payment.amountFils),
    currencyDisplay: payment.currency,
  );
}

/// Maps a canonical Card payment to its sanitized Admin display model.
///
/// Optional [CardPayment.cardBrand]/[CardPayment.cardLastFour] surface only
/// when the validated model carries them; the last four render masked.
AdminSanitizedPayment mapCardPaymentForAdmin(CardPayment payment) {
  final brand = payment.cardBrand?.trim();
  final lastFour = payment.cardLastFour;
  return AdminSanitizedPayment(
    methodLabel: adminPaymentMethodLabel(PaymentMethod.card),
    statusLabel: adminCardStatusLabel(payment.status),
    amountDisplay: formatFareFils(payment.amountFils),
    currencyDisplay: payment.currency,
    cardBrandDisplay: brand == null || brand.isEmpty ? null : brand,
    maskedCardLastFourDisplay:
        lastFour == null ? null : maskCardLastFour(lastFour),
  );
}
