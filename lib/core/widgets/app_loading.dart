import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';

class AppLoading extends StatelessWidget {
  const AppLoading({
    super.key,
    this.label = 'Loading...',
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: compact ? 22 : 28,
              child: const CircularProgressIndicator(strokeWidth: 2.6),
            ),
            if (!compact) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
