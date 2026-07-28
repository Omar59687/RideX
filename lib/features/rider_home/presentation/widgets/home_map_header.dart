import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/ride_x_brand.dart';

class HomeMapHeader extends StatelessWidget {
  const HomeMapHeader({
    super.key,
    required this.firstName,
    required this.pickup,
    required this.unreadCount,
    required this.onNotifications,
    required this.onPlanRide,
  });

  final String firstName;
  final RideLocation pickup;
  final int unreadCount;
  final VoidCallback onNotifications;
  final VoidCallback onPlanRide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxWidth >= 600 ? 390.0 : 350.0;
        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                bottom: 38,
                child: MapPlaceholder(
                  borderRadius: 0,
                  semanticLabel: 'Stylized map of nearby rides in Amman',
                ),
              ),
              Positioned(
                left: AppSpacing.lg,
                top: AppSpacing.lg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RideXBrand(width: 82),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Good morning, $firstName',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Amman is moving.',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ],
                ),
              ),
              Positioned(
                right: AppSpacing.lg,
                top: AppSpacing.lg,
                child: _NotificationButton(
                  count: unreadCount,
                  onPressed: onNotifications,
                ),
              ),
              Positioned(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: 0,
                child: _DestinationSearch(
                  pickup: pickup,
                  onPressed: onPlanRide,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DestinationSearch extends StatelessWidget {
  const _DestinationSearch({required this.pickup, required this.onPressed});

  final RideLocation pickup;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: InkWell(
        key: const ValueKey('rider-destination-search-card'),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        context.rideXTheme.pickup.withValues(alpha: .15),
                    child: Text(
                      'A',
                      style: TextStyle(color: context.rideXTheme.pickup),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Where to?', style: theme.textTheme.titleMedium),
                        Text(
                          'Search Jordan destinations',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const Divider(height: AppSpacing.lg),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Pickup confirmed · ${pickup.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 9 ? '9+' : '$count'),
      child: IconButton.filledTonal(
        tooltip: 'Notifications',
        onPressed: onPressed,
        icon: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}
