import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        destructive ? theme.colorScheme.error : theme.colorScheme.onSurface;
    final effectiveOnTap = enabled ? onTap : null;
    return Semantics(
      button: onTap != null,
      enabled: enabled,
      label: subtitle == null ? title : '$title, $subtitle',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: InkWell(
          onTap: effectiveOnTap,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: enabled ? color : theme.disabledColor,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: enabled ? color : theme.disabledColor,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: enabled
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.disabledColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  trailing ??
                      (onTap == null
                          ? const SizedBox.shrink()
                          : Icon(
                              Icons.chevron_right_rounded,
                              color: enabled
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.disabledColor,
                            )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
