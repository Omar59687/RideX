import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_motion.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.isExpanded = true,
    this.trailing,
    this.isLoading = false,
    this.destructive = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool isExpanded;
  final IconData? trailing;
  final bool isLoading;
  final bool destructive;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = onPressed != null && !isLoading;
    final foreground = destructive
        ? switch (variant) {
            AppButtonVariant.primary => colorScheme.onError,
            AppButtonVariant.secondary ||
            AppButtonVariant.text =>
              colorScheme.error,
          }
        : null;
    final background = destructive && variant == AppButtonVariant.primary
        ? colorScheme.error
        : null;
    final style = ButtonStyle(
      foregroundColor:
          foreground == null ? null : WidgetStatePropertyAll(foreground),
      backgroundColor:
          background == null ? null : WidgetStatePropertyAll(background),
      side: destructive && variant == AppButtonVariant.secondary
          ? WidgetStatePropertyAll(BorderSide(color: colorScheme.error))
          : null,
      minimumSize: const WidgetStatePropertyAll(Size(44, 52)),
    );
    final labelChild = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: AppSpacing.xs),
        ],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(trailing, size: 18),
        ],
      ],
    );
    final child = AnimatedSwitcher(
      duration: reduceMotion ? AppMotion.reduced : AppMotion.fast,
      child: isLoading
          ? Row(
              key: const ValueKey('loading'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: foreground ?? colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            )
          : KeyedSubtree(key: const ValueKey('label'), child: labelChild),
    );

    final button = switch (variant) {
      AppButtonVariant.primary => ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: style,
          child: child,
        ),
      AppButtonVariant.secondary => OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: style,
          child: child,
        ),
      AppButtonVariant.text => TextButton(
          onPressed: enabled ? onPressed : null,
          style: style,
          child: child,
        ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      value: isLoading ? 'Loading' : null,
      child: AnimatedOpacity(
        duration: reduceMotion ? AppMotion.reduced : AppMotion.fast,
        opacity: enabled || isLoading ? 1 : 0.72,
        child: isExpanded
            ? SizedBox(width: double.infinity, child: button)
            : DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  boxShadow: variant == AppButtonVariant.primary && enabled
                      ? context.rideXTheme.floatingShadows
                      : null,
                ),
                child: button,
              ),
      ),
    );
  }
}

enum AppButtonVariant { primary, secondary, text }
