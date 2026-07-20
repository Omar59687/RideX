import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_empty_view.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsControllerProvider);
    final role = ref.watch(sessionControllerProvider).role ?? RideRole.rider;
    return AppScaffold(
      title: 'Notifications',
      bottomNavigationBar: MockBottomNavBar(
        currentIndex: 0,
        profilePath:
            role == RideRole.driver ? '/driver/profile' : '/rider/profile',
      ),
      actions: [
        IconButton(
          onPressed: () =>
              ref.read(notificationsControllerProvider.notifier).markAllRead(),
          icon: const Icon(Icons.done_all_rounded),
        ),
      ],
      body: notifications.isEmpty
          ? const AppEmptyView(
              title: 'No notifications',
              message: 'Trip alerts and updates will appear here.',
            )
          : ListView.separated(
              itemCount: notifications.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return Card(
                  color: notification.isRead ? null : AppColors.cloud,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: notification.isRead
                          ? AppColors.cloud
                          : AppColors.accentSoft,
                      child: Icon(
                        notification.isRead
                            ? Icons.notifications_none_rounded
                            : Icons.notifications_active_rounded,
                        color: notification.isRead
                            ? AppColors.slate
                            : AppColors.accentDeep,
                      ),
                    ),
                    title: Text(notification.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(notification.body),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(notification.timeLabel,
                            style: Theme.of(context).textTheme.bodySmall),
                        if (!notification.isRead)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Icon(Icons.circle,
                                size: 8, color: AppColors.accent),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
