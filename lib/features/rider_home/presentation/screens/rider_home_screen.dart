import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/ride_x_bottom_navigation.dart';
import 'package:ridex/features/rider_home/presentation/widgets/home_map_header.dart';
import 'package:ridex/features/rider_home/presentation/widgets/ride_availability.dart';
import 'package:ridex/features/rider_home/presentation/widgets/saved_recent_places.dart';

class RiderHomeScreen extends ConsumerWidget {
  const RiderHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final booking = ref.watch(bookingControllerProvider);
    final notifications = ref.watch(notificationsControllerProvider);
    final name = session.user?.name.trim();
    final firstName = name == null || name.isEmpty
        ? 'Rider'
        : name.split(RegExp(r'\s+')).first;
    final unreadCount = notifications.where((item) => !item.isRead).length;

    return AppScaffold(
      showBack: false,
      padding: EdgeInsets.zero,
      maxContentWidth: 720,
      bottomNavigationBar: const RideXBottomNavigation(currentIndex: 0),
      body: ListView(
        key: const ValueKey('rider-home-scroll'),
        children: [
          HomeMapHeader(
            firstName: firstName,
            pickup: booking.pickup ?? MockData.locations.first,
            unreadCount: unreadCount,
            onNotifications: () => context.push('/notifications'),
            onPlanRide: () => context.go('/rider/destination'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SavedRecentPlaces(
                  locations: MockData.locations.skip(1).toList(),
                  onPlaceTap: () => context.go('/rider/destination'),
                  onViewAll: () => context.go('/rider/destination'),
                ),
                const SizedBox(height: AppSpacing.xl),
                const RideAvailability(vehicles: MockData.vehicleTypes),
                const SizedBox(height: AppSpacing.xl),
                const _RewardsCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardsCard extends StatelessWidget {
  const _RewardsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: context.rideXTheme.rewardGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('REWARDS PREVIEW', style: theme.textTheme.labelSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'RideX rewards are coming soon',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'This preview is not connected to a rewards balance yet.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
