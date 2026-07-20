import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/core/models/booking_draft.dart';

class RideLocationCard extends StatelessWidget {
  const RideLocationCard(
      {super.key, required this.location, required this.icon, this.onTap});

  final RideLocation location;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('location-${location.label}'),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.cloud,
          child: Icon(icon, color: AppColors.ink),
        ),
        title: Text(
          location.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(location.address,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing:
            onTap == null ? null : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
