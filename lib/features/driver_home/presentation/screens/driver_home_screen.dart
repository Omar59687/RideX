import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class DriverHomeScreen extends ConsumerWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(driverOnlineProvider);
    return AppScaffold(
      title: 'Driver mode',
      bottomNavigationBar: const MockBottomNavBar(
          currentIndex: 0, profilePath: '/driver/profile'),
      actions: [
        IconButton(
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_none_rounded))
      ],
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
                color: context.rideXTheme.brandedPanel,
                borderRadius: BorderRadius.circular(28)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text('You are ${online ? 'online' : 'offline'}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                    color: context
                                        .rideXTheme.brandedPanelForeground))),
                    StatusChip(
                        label: online ? 'Available' : 'Offline',
                        color: online ? AppColors.accent : AppColors.warning),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: const [
                    Expanded(
                        child: _SummaryTile(label: 'Today', value: '6 trips')),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                        child: _SummaryTile(
                            label: 'Earnings', value: '34.50 JOD')),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                        child: _SummaryTile(label: 'Rating', value: '4.9')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: SwitchListTile.adaptive(
              value: online,
              title: const Text('Accept incoming requests'),
              subtitle: const Text('Mock presence only for this phase.'),
              onChanged: (value) =>
                  ref.read(driverOnlineProvider.notifier).state = value,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const MapPlaceholder(height: 220),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Incoming request preview',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                      'Hashemite University → Abdali Boulevard\n5 km · 1.99 JOD · Taxi'),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                          child: AppButton(
                              label: 'Decline',
                              variant: AppButtonVariant.secondary,
                              onPressed: online ? () {} : null)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                          child: AppButton(
                              label: 'Accept',
                              onPressed: online
                                  ? () => context.push('/driver/request')
                                  : null)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
              label: 'View driver application',
              variant: AppButtonVariant.secondary,
              onPressed: () => context.push('/driver/application')),
          const SizedBox(height: AppSpacing.md),
          AppButton(
              key: const ValueKey('driver-demo-request-button'),
              label: 'Demo incoming trip',
              icon: Icons.campaign_outlined,
              onPressed: online ? () => context.push('/driver/request') : null),
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
                      onPressed: () => context.push('/driver/profile'))),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
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

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: context.rideXTheme.brandedPanelSubtle,
          borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.rideXTheme.brandedPanelMuted)),
          const SizedBox(height: 6),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: context.rideXTheme.brandedPanelForeground)),
        ],
      ),
    );
  }
}
