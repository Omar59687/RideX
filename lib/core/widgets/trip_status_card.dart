import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class TripStatusCard extends StatelessWidget {
  const TripStatusCard({
    super.key,
    required this.status,
    required this.title,
    required this.message,
    this.trailing,
  });

  final TripStatus status;
  final String title;
  final String message;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rideXTheme = context.rideXTheme;
    final tone = switch (status) {
      TripStatus.completed => StatusChipTone.success,
      TripStatus.cancelledByRider ||
      TripStatus.cancelledByDriver ||
      TripStatus.noDriverFound =>
        StatusChipTone.error,
      TripStatus.searching || TripStatus.requested => StatusChipTone.warning,
      _ => StatusChipTone.information,
    };

    return Semantics(
      container: true,
      liveRegion: true,
      label: '${status.label}. $title. $message',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 72,
                decoration: BoxDecoration(
                  gradient: rideXTheme.routeGradient,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                            child: StatusChip(label: status.label, tone: tone)),
                        const Spacer(),
                        trailing ??
                            Icon(
                              Icons.timeline_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
