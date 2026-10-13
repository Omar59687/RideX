import 'package:flutter/material.dart';

/// Presentation-only view-model for sanitized payment information.
///
/// Display strings only. This type carries no backend identifiers, status
/// enums, raw payloads, secrets, idempotency keys, provider references, or
/// raw card numbers. Instances must be built through the allowlist payment
/// mapper, never from free-form maps or payload passthrough. Card brand/last-four surface only when the
/// validated [CardPayment] model carries them; anything else stays absent.
@immutable
class AdminSanitizedPayment {
  const AdminSanitizedPayment({
    this.methodLabel,
    this.statusLabel,
    this.amountDisplay,
    this.currencyDisplay,
    this.cardBrandDisplay,
    this.maskedCardLastFourDisplay,
  });

  final String? methodLabel;
  final String? statusLabel;
  final String? amountDisplay;
  final String? currencyDisplay;

  /// Validated card brand, if the canonical Card model carries one.
  final String? cardBrandDisplay;

  /// Masked last four (`•••• 1234`), if the canonical Card model carries one.
  final String? maskedCardLastFourDisplay;
}

/// Read-only card rendering an [AdminSanitizedPayment].
///
/// Stateless and side-effect free: no navigation, logging, network calls,
/// or mutation controls. Missing values render as "Unavailable".
class AdminSanitizedPaymentCard extends StatelessWidget {
  const AdminSanitizedPaymentCard({super.key, required this.payment});

  final AdminSanitizedPayment payment;

  static const unavailableLabel = 'Unavailable';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sanitized payment information',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FieldRow(
                fieldKey: const ValueKey('admin-payment-method'),
                label: 'Method',
                value: payment.methodLabel,
              ),
              _FieldRow(
                fieldKey: const ValueKey('admin-payment-status'),
                label: 'Status',
                value: payment.statusLabel,
              ),
              _FieldRow(
                fieldKey: const ValueKey('admin-payment-amount'),
                label: 'Amount',
                value: payment.amountDisplay,
              ),
              _FieldRow(
                fieldKey: const ValueKey('admin-payment-currency'),
                label: 'Currency',
                value: payment.currencyDisplay,
              ),
              if (payment.cardBrandDisplay != null)
                _FieldRow(
                  fieldKey: const ValueKey('admin-payment-card-brand'),
                  label: 'Card',
                  value: payment.cardBrandDisplay,
                ),
              if (payment.maskedCardLastFourDisplay != null)
                _FieldRow(
                  fieldKey: const ValueKey('admin-payment-card-last4'),
                  label: 'Card ending',
                  value: payment.maskedCardLastFourDisplay,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.fieldKey,
    required this.label,
    required this.value,
  });

  final ValueKey<String> fieldKey;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = value?.trim().isNotEmpty == true
        ? value!.trim()
        : AdminSanitizedPaymentCard.unavailableLabel;
    return Padding(
      key: fieldKey,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              display,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
