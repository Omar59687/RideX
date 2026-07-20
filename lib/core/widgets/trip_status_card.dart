import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class TripStatusCard extends StatelessWidget {
  const TripStatusCard(
      {super.key,
      required this.status,
      required this.title,
      required this.message});

  final TripStatus status;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusChip(label: status.label),
                const Spacer(),
                const Icon(Icons.timeline_rounded,
                    color: AppColors.muted, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(message),
          ],
        ),
      ),
    );
  }
}
