import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/status_chip.dart';

@immutable
class FareSummaryItem {
  const FareSummaryItem({required this.label, required this.amount});

  final String label;
  final double amount;
}

class FareSummaryCard extends StatelessWidget {
  const FareSummaryCard({
    super.key,
    required this.total,
    this.items = const [],
    this.title = 'Fare summary',
    this.isEstimate = false,
    this.note,
  });

  final double total;
  final List<FareSummaryItem> items;
  final String title;
  final bool isEstimate;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$title, total ${formatMoney(total)}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(title, style: theme.textTheme.titleLarge)),
                  if (isEstimate)
                    const StatusChip(
                      label: 'Estimate',
                      tone: StatusChipTone.information,
                    ),
                ],
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                for (final item in items) ...[
                  _FareRow(label: item.label, amount: item.amount),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Divider(color: theme.colorScheme.outlineVariant),
                const SizedBox(height: AppSpacing.xs),
              ] else
                const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text('Total', style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    formatMoney(total),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: context.rideXTheme.brandEmphasis,
                    ),
                  ),
                ],
              ),
              if (note != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(formatMoney(amount), style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
