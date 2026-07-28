import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';

enum StatusChipTone { brand, success, warning, error, information, neutral }

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.tone = StatusChipTone.brand,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final StatusChipTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rideXTheme = context.rideXTheme;
    final effectiveColor = color ??
        switch (tone) {
          StatusChipTone.brand => rideXTheme.brandEmphasis,
          StatusChipTone.success => rideXTheme.success,
          StatusChipTone.warning => rideXTheme.warning,
          StatusChipTone.error => theme.colorScheme.error,
          StatusChipTone.information => rideXTheme.information,
          StatusChipTone.neutral => theme.colorScheme.onSurfaceVariant,
        };

    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.circle),
          border: Border.all(color: effectiveColor.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: effectiveColor),
                const SizedBox(width: AppSpacing.xxs),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: effectiveColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
