import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';

class DriverProfileScreen extends ConsumerWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    return AppScaffold(
      title: 'Driver profile',
      bottomNavigationBar: const MockBottomNavBar(
          currentIndex: 2, profilePath: '/driver/profile'),
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
                color: AppColors.graphite,
                borderRadius: BorderRadius.circular(28)),
            child: Column(
              children: [
                const CircleAvatar(
                    radius: 38,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.drive_eta_rounded,
                        size: 34, color: Colors.white)),
                const SizedBox(height: AppSpacing.md),
                Text(user?.name ?? '-',
                    style: Theme.of(context)
                        .textTheme
                        .headlineLarge
                        ?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text('Approved driver · 4.9 rating',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _DriverProfileTile(
              title: 'Vehicle', subtitle: 'Toyota Camry · 652-UKW'),
          const SizedBox(height: AppSpacing.sm),
          const _DriverProfileTile(
              title: 'Rating', subtitle: '4.9 · 25 recommended'),
          const SizedBox(height: AppSpacing.sm),
          const _DriverProfileTile(
              title: 'Application status', subtitle: 'Approved'),
          const SizedBox(height: 92),
        ],
      ),
    );
  }
}

class _DriverProfileTile extends StatelessWidget {
  const _DriverProfileTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
