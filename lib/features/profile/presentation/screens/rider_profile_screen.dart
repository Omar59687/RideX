import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';

class RiderProfileScreen extends ConsumerWidget {
  const RiderProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    return AppScaffold(
      title: 'Profile',
      bottomNavigationBar: const MockBottomNavBar(
          currentIndex: 2, profilePath: '/rider/profile'),
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
                    child: Icon(Icons.person, size: 34, color: Colors.white)),
                const SizedBox(height: AppSpacing.md),
                Text(user?.name ?? '-',
                    style: Theme.of(context)
                        .textTheme
                        .headlineLarge
                        ?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(user?.email ?? '-',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _ProfileTile(title: 'Email', subtitle: 'ahmed@ridex.demo'),
          const SizedBox(height: AppSpacing.sm),
          const _ProfileTile(title: 'Phone', subtitle: '+962 7X XXX XXXX'),
          const SizedBox(height: AppSpacing.sm),
          const _ProfileTile(title: 'Preferred payment', subtitle: 'Cash'),
          const SizedBox(height: 92),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.title, required this.subtitle});

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
