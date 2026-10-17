import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/widgets/status_chip.dart';
import 'package:ridex/features/history/presentation/models/rider_payment_presentation.dart';
import 'package:ridex/features/history/presentation/widgets/rider_payment_status_card.dart';

/// Sanitized, allowlisted Card metadata for rider presentation.
///
/// Mirrors the Admin sanitization boundary: only a canonical [CardPayment]
/// can produce one, the brand must match a fixed allowlist, and the last
/// four is rendered masked. Unknown brands and malformed values render
/// nothing rather than echoing unvalidated text, and no raw card number
/// (PAN), token, or provider data is ever accepted or displayed.
@immutable
final class RiderCardPaymentMetadata {
  const RiderCardPaymentMetadata._({
    this.brandDisplay,
    this.maskedLastFourDisplay,
  });

  factory RiderCardPaymentMetadata.fromCard(CardPayment payment) {
    return RiderCardPaymentMetadata._(
      brandDisplay: _allowlistedCardBrand(payment.cardBrand),
      maskedLastFourDisplay: _maskedCardLastFour(payment.cardLastFour),
    );
  }

  final String? brandDisplay;
  final String? maskedLastFourDisplay;
}

String? _allowlistedCardBrand(String? brand) {
  return switch (brand?.trim().toLowerCase()) {
    'visa' => 'Visa',
    'mastercard' => 'Mastercard',
    'amex' || 'american express' => 'American Express',
    'discover' => 'Discover',
    'diners' || 'diners club' => 'Diners Club',
    'jcb' => 'JCB',
    'unionpay' => 'UnionPay',
    _ => null,
  };
}

String? _maskedCardLastFour(String? lastFour) {
  if (lastFour == null || !RegExp(r'^[0-9]{4}$').hasMatch(lastFour)) {
    return null;
  }
  return '\u2022\u2022\u2022\u2022 $lastFour';
}

/// Read-only, receipt-like record card for a canonical rider payment.
///
/// Built only from canonical [CashPayment]/[CardPayment] models through the
/// Slice 1 mapping layer. It never invents amounts, fees, taxes, fare
/// breakdowns, refund transactions, receipt identifiers, issuance dates,
/// names, or identifiers; it never displays payment, booking, or Trip
/// identities. Status wording fails closed exactly like
/// [RiderPaymentStatusCard]: caller-constructible evidence never produces a
/// confirmed paid/captured claim.
class RiderPaymentRecordCard extends StatelessWidget {
  const RiderPaymentRecordCard._({
    super.key,
    required this.presentation,
    this.cardMetadata,
  });

  factory RiderPaymentRecordCard.fromCash(
    CashPayment payment, {
    Key? key,
    RiderPaymentTripEvidence? tripEvidence,
  }) {
    return RiderPaymentRecordCard._(
      key: key,
      presentation: RiderPaymentPresentation.fromCash(
        payment,
        tripEvidence: tripEvidence,
      ),
    );
  }

  factory RiderPaymentRecordCard.fromCard(
    CardPayment payment, {
    Key? key,
    RiderPaymentTripEvidence? tripEvidence,
  }) {
    return RiderPaymentRecordCard._(
      key: key,
      presentation: RiderPaymentPresentation.fromCard(
        payment,
        tripEvidence: tripEvidence,
      ),
      cardMetadata: RiderCardPaymentMetadata.fromCard(payment),
    );
  }

  final RiderPaymentPresentation presentation;
  final RiderCardPaymentMetadata? cardMetadata;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = RiderPaymentStatusDisplay.failClosed(presentation);
    final brand = cardMetadata?.brandDisplay;
    final maskedLastFour = cardMetadata?.maskedLastFourDisplay;
    return Semantics(
      container: true,
      label: 'Payment record. Status ${display.title}.',
      child: Card(
        key: const ValueKey('rider-payment-record-card'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (display.markerLabel != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusChip(
                    label: display.markerLabel!,
                    tone: display.markerTone ?? StatusChipTone.neutral,
                    icon: display.markerIcon,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              _RecordRow(
                fieldKey: const ValueKey('rider-payment-record-method'),
                label: 'Method',
                value: presentation.methodLabel,
              ),
              _RecordRow(
                fieldKey: const ValueKey('rider-payment-record-status'),
                label: 'Status',
                value: display.title,
              ),
              _RecordRow(
                fieldKey: const ValueKey('rider-payment-record-amount'),
                label: 'Amount',
                value: display.amountDisplay,
              ),
              if (brand != null)
                _RecordRow(
                  fieldKey: const ValueKey('rider-payment-record-card-brand'),
                  label: 'Card brand',
                  value: brand,
                ),
              if (maskedLastFour != null)
                _RecordRow(
                  fieldKey: const ValueKey('rider-payment-record-card-ending'),
                  label: 'Card ending',
                  value: maskedLastFour,
                ),
              Divider(
                height: AppSpacing.lg,
                color: theme.colorScheme.outlineVariant,
              ),
              _RecordRow(
                fieldKey: const ValueKey('rider-payment-record-receipt'),
                label: 'Receipt',
                value: 'Unavailable',
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Payment success alone does not confirm that a receipt was '
                'issued, and no receipt details are available here.',
                key: const ValueKey('rider-payment-record-receipt-note'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.fieldKey,
    required this.label,
    required this.value,
  });

  final ValueKey<String> fieldKey;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: fieldKey,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
