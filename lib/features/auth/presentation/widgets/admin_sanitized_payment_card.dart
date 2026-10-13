import 'package:flutter/material.dart';
import 'admin_sanitized_payment_mapper.dart';

export 'admin_sanitized_payment_mapper.dart' show AdminSanitizedPayment;

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
