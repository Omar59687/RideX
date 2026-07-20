import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class DriverInfoCard extends StatelessWidget {
  const DriverInfoCard({super.key, required this.driver});

  final DriverSummary driver;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(radius: 28, child: Icon(Icons.person, size: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(driver.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('${driver.vehicleName} · ${driver.plate}'),
                  const SizedBox(height: 8),
                  StatusChip(
                    label: '${driver.etaMinutes} min away',
                    color: AppColors.info,
                    icon: Icons.access_time_rounded,
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                Text('${driver.rating}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
