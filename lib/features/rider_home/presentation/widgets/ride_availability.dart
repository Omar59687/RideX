import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/vehicle_type.dart';
import 'package:ridex/core/widgets/vehicle_silhouette.dart';

class RideAvailability extends StatelessWidget {
  const RideAvailability({super.key, required this.vehicles});

  final List<VehicleType> vehicles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ride your way',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text('Demo availability',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: vehicles.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final vehicle = vehicles[index];
              return Container(
                width: 136,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VehicleSilhouette(
                      width: 58,
                      height: 32,
                      semanticLabel: '${vehicle.name} demo vehicle',
                    ),
                    const Spacer(),
                    Text(vehicle.name,
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '${vehicle.arrivalMinutes} min',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
