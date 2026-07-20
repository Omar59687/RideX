import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';
import 'package:ridex/core/widgets/ride_location_card.dart';
import 'package:ridex/core/widgets/section_header.dart';
import 'package:ridex/core/models/booking_draft.dart';

class RiderHomeScreen extends StatelessWidget {
  const RiderHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'RideX',
      bottomNavigationBar: const MockBottomNavBar(
          currentIndex: 0, profilePath: '/rider/profile'),
      actions: [
        IconButton(
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_none_rounded))
      ],
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.graphite,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Good morning, Ahmed',
                    style: Theme.of(context)
                        .textTheme
                        .headlineLarge
                        ?.copyWith(color: Colors.white)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                    'Your next city ride should feel simple, calm, and on time.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white70)),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(18)),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                          child: Text('Current location · Hashemite University',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.white))),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 240.ms).slideY(begin: .03),
          const SizedBox(height: AppSpacing.lg),
          GestureDetector(
            key: const ValueKey('rider-destination-search-card'),
            onTap: () => context.push('/rider/pickup'),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    const CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.accentSoft,
                        child: Icon(Icons.search_rounded,
                            color: AppColors.accentDeep)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Where are you going?',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(
                              'Search destination, choose ride, and see fare first.'),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(
              title: 'Your route preview',
              subtitle:
                  'Map placeholder isolated so Google Maps can replace it later.'),
          const SizedBox(height: AppSpacing.md),
          const MapPlaceholder(height: 260).animate().fadeIn(duration: 260.ms),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(
              title: 'Saved places',
              subtitle: 'Quick picks inspired by the original prototypes.'),
          const SizedBox(height: AppSpacing.md),
          const RideLocationCard(
              location: RideLocation(
                  label: 'Hashemite University', address: 'Quick pickup point'),
              icon: Icons.school_rounded),
          const SizedBox(height: AppSpacing.sm),
          const RideLocationCard(
              location: RideLocation(
                  label: 'Abdali Boulevard', address: 'Popular destination'),
              icon: Icons.local_mall_rounded),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
              key: const ValueKey('rider-start-booking-button'),
              label: 'Start booking',
              icon: Icons.my_location_rounded,
              trailing: Icons.arrow_forward_rounded,
              onPressed: () => context.push('/rider/pickup')),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                  child: AppButton(
                      label: 'History',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => context.push('/history'))),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                  child: AppButton(
                      label: 'Profile',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => context.push('/rider/profile'))),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
              label: 'Settings',
              variant: AppButtonVariant.text,
              onPressed: () => context.push('/settings')),
          const SizedBox(height: 92),
        ],
      ),
    );
  }
}
