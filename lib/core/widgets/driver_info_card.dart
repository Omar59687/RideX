import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class DriverInfoCard extends StatelessWidget {
  const DriverInfoCard({
    super.key,
    required this.driver,
    this.onCall,
    this.onMessage,
    this.avatar,
  });

  final DriverSummary driver;
  final VoidCallback? onCall;
  final VoidCallback? onMessage;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rideXTheme = context.rideXTheme;
    return Semantics(
      container: true,
      label: '${driver.name}, rated ${driver.rating}, '
          '${driver.vehicleName}, plate ${driver.plate}, '
          '${driver.etaMinutes} minutes away',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: avatar ?? const Icon(Icons.person_rounded, size: 26),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            driver.name,
                            style: theme.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.star_rounded,
                          color: rideXTheme.warning,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text('${driver.rating}',
                            style: theme.textTheme.labelLarge),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${driver.vehicleName} | ${driver.plate}',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip(
                          label: '${driver.etaMinutes} min away',
                          tone: StatusChipTone.information,
                          icon: Icons.access_time_rounded,
                        ),
                        if (onCall != null)
                          _DriverAction(
                            tooltip: 'Call driver',
                            icon: Icons.call_rounded,
                            onPressed: onCall!,
                          ),
                        if (onMessage != null)
                          _DriverAction(
                            tooltip: 'Message driver',
                            icon: Icons.chat_bubble_outline_rounded,
                            onPressed: onMessage!,
                          ),
                      ],
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

class _DriverAction extends StatelessWidget {
  const _DriverAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
    );
  }
}
