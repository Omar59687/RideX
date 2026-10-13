import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/fare_quote.dart' show formatFareFils;
import 'package:ridex/core/models/payment_method.dart';

/// Immutable display data constructed only from canonical payment models.
///
/// The private constructor and final class prevent callers from supplying
/// arbitrary display strings or implementing a replacement display model.
@immutable
final class AdminSanitizedPayment {
  const AdminSanitizedPayment._({
    required this.methodLabel,
    required this.statusLabel,
    required this.amountDisplay,
    required this.currencyDisplay,
    this.cardBrandDisplay,
    this.maskedCardLastFourDisplay,
  });

  factory AdminSanitizedPayment.fromCash(CashPayment payment) =>
      AdminSanitizedPayment._(
        methodLabel: adminPaymentMethodLabel(PaymentMethod.cash),
        statusLabel: adminCashStatusLabel(payment.status),
        amountDisplay: formatFareFils(payment.amountFils),
        currencyDisplay: 'JOD',
      );

  factory AdminSanitizedPayment.fromCard(CardPayment payment) =>
      AdminSanitizedPayment._(
        methodLabel: adminPaymentMethodLabel(PaymentMethod.card),
        statusLabel: adminCardStatusLabel(payment.status),
        amountDisplay: formatFareFils(payment.amountFils),
        currencyDisplay: 'JOD',
        cardBrandDisplay: _cardBrandLabel(payment.cardBrand),
        maskedCardLastFourDisplay: payment.cardLastFour == null
            ? null
            : maskCardLastFour(payment.cardLastFour!),
      );

  final String methodLabel;
  final String statusLabel;
  final String amountDisplay;
  final String currencyDisplay;
  final String? cardBrandDisplay;
  final String? maskedCardLastFourDisplay;
}

// The domain validates brand length, not content. Never pass unknown text
// through to the display: it may contain identifiers or provider secrets.
String? _cardBrandLabel(String? brand) => switch (brand?.trim().toLowerCase()) {
      'visa' => 'Visa',
      'mastercard' => 'Mastercard',
      'amex' || 'american express' => 'American Express',
      'discover' => 'Discover',
      'diners' || 'diners club' => 'Diners Club',
      'jcb' => 'JCB',
      'unionpay' => 'UnionPay',
      _ => null,
    };

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
/// ASCII digits). Invalid input is rejected at runtime, including in release
/// builds, without including the supplied value in the exception.
String maskCardLastFour(String lastFour) {
  if (lastFour.length != 4 || !RegExp(r'^[0-9]{4}$').hasMatch(lastFour)) {
    throw ArgumentError('Expected exactly four ASCII digits.');
  }
  return '•••• $lastFour';
}

/// Maps a canonical Cash payment to its sanitized Admin display model.
AdminSanitizedPayment mapCashPaymentForAdmin(CashPayment payment) =>
    AdminSanitizedPayment.fromCash(payment);

/// Maps a canonical Card payment to its sanitized Admin display model.
///
/// Optional [CardPayment.cardBrand]/[CardPayment.cardLastFour] surface only
/// when present and allowlisted; the last four render masked.
AdminSanitizedPayment mapCardPaymentForAdmin(CardPayment payment) =>
    AdminSanitizedPayment.fromCard(payment);
