import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/core/models/vehicle_type.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class VehicleTypeCard extends StatelessWidget {
  const VehicleTypeCard(
      {super.key, required this.vehicle, required this.selected, this.onTap});

  final VehicleType vehicle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: selected ? AppColors.ink : Colors.transparent, width: 1.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.mist,
          child: Icon(vehicle.id == 'taxi'
              ? Icons.local_taxi_rounded
              : Icons.directions_car_filled_rounded),
        ),
        title: Row(
          children: [
            Expanded(child: Text(vehicle.name)),
            if (vehicle.isPopular) const StatusChip(label: 'Popular'),
          ],
        ),
        subtitle: Text(
            '${vehicle.capacity} seats · ${vehicle.arrivalMinutes} min · ${vehicle.description}'),
        trailing: Text(formatMoney(vehicle.baseFare),
            style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
