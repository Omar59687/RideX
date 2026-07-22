import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';

class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.child,
    this.compact = false,
    this.title,
    this.showHandle = false,
    this.useSafeArea = true,
    this.maxWidth = 640,
  });

  final Widget child;
  final bool compact;
  final String? title;
  final bool showHandle;
  final bool useSafeArea;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheet = Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        showHandle
            ? AppSpacing.xs
            : compact
                ? AppSpacing.md
                : AppSpacing.lg,
        AppSpacing.lg,
        compact ? AppSpacing.md : AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
        boxShadow: context.rideXTheme.sheetShadows,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHandle) ...[
            Semantics(
              label: 'Bottom sheet drag handle',
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(AppRadii.circle),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (title != null) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(title!, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          child,
        ],
      ),
    );

    final centered = Align(alignment: Alignment.bottomCenter, child: sheet);
    return useSafeArea
        ? SafeArea(top: false, minimum: EdgeInsets.zero, child: centered)
        : centered;
  }
}
