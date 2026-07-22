import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/models/booking_draft.dart';

enum RideLocationTone { neutral, pickup, destination }

class RideLocationCard extends StatelessWidget {
  const RideLocationCard({
    super.key,
    required this.location,
    required this.icon,
    this.onTap,
    this.tone = RideLocationTone.neutral,
    this.trailing,
  });

  final RideLocation location;
  final IconData icon;
  final VoidCallback? onTap;
  final RideLocationTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rideXTheme = context.rideXTheme;
    final accent = switch (tone) {
      RideLocationTone.neutral => rideXTheme.information,
      RideLocationTone.pickup => rideXTheme.pickup,
      RideLocationTone.destination => rideXTheme.destination,
    };

    return Semantics(
      button: onTap != null,
      label: '${location.label}, ${location.address}',
      child: Card(
        key: ValueKey('location-${location.label}'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: accent.withValues(alpha: 0.12),
                    child: Icon(icon, color: accent),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(location.label,
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          location.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null)
                    trailing!
                  else if (onTap != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
