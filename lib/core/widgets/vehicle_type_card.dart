import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/models/vehicle_type.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/status_chip.dart';
import 'package:ridex/core/widgets/vehicle_silhouette.dart';

class VehicleTypeCard extends StatelessWidget {
  const VehicleTypeCard({
    super.key,
    required this.vehicle,
    required this.selected,
    this.onTap,
  });

  final VehicleType vehicle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rideXTheme = context.rideXTheme;
    final type = switch (vehicle.id) {
      'taxi' => VehicleSilhouetteType.taxi,
      'suv' => VehicleSilhouetteType.suv,
      _ => VehicleSilhouetteType.car,
    };

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '${vehicle.name}, ${vehicle.capacity} seats, '
          '${vehicle.arrivalMinutes} minutes away, '
          '${formatMoney(vehicle.baseFare)}',
      child: Card(
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color:
                selected ? rideXTheme.focus : theme.colorScheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 92),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: VehicleSilhouette(
                        type: type,
                        width: 58,
                        height: 36,
                        semanticLabel: vehicle.name,
                      ),
                    ),
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
                                vehicle.name,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            if (vehicle.isPopular)
                              const StatusChip(label: 'Popular'),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          '${vehicle.capacity} seats | '
                          '${vehicle.arrivalMinutes} min',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          vehicle.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    formatMoney(vehicle.baseFare),
                    style: theme.textTheme.titleMedium,
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
