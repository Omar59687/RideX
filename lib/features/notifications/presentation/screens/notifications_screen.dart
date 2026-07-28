import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/models/app_notification.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_empty_view.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';
import 'package:ridex/core/widgets/ride_x_bottom_navigation.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsControllerProvider);
    final role = ref.watch(sessionControllerProvider).role ?? RideRole.rider;
    if (role == RideRole.driver) {
      return _DriverNotificationsScreen(notifications: notifications);
    }

    final unreadCount = notifications.where((item) => !item.isRead).length;
    return AppScaffold(
      title: 'Notifications',
      maxContentWidth: 600,
      bottomNavigationBar: const RideXBottomNavigation(currentIndex: 0),
      actions: [
        TextButton(
          key: const Key('notifications-mark-all-read'),
          onPressed: unreadCount == 0
              ? null
              : () => ref
                  .read(notificationsControllerProvider.notifier)
                  .markAllRead(),
          child: const Text('Mark all read'),
        ),
      ],
      body: notifications.isEmpty
          ? const AppEmptyView(
              title: 'No notifications',
              message: 'Trip alerts and updates will appear here.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                const SizedBox(height: AppSpacing.sm),
                _NotificationsSummary(unreadCount: unreadCount),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'RIDE UPDATES',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 1.1,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (var index = 0; index < notifications.length; index++) ...[
                  _NotificationCard(
                    notification: notifications[index],
                    onTap: notifications[index].isRead
                        ? null
                        : () => ref
                            .read(notificationsControllerProvider.notifier)
                            .markRead(notifications[index].id),
                  ),
                  if (index != notifications.length - 1)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

class _NotificationsSummary extends StatelessWidget {
  const _NotificationsSummary({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: context.rideXTheme.brandGradient,
        borderRadius: BorderRadius.circular(AppRadii.sheet),
        boxShadow: context.rideXTheme.floatingShadows,
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined,
              color: Colors.white, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unreadCount == 0
                      ? 'You are all caught up'
                      : '$unreadCount new ${unreadCount == 1 ? 'update' : 'updates'}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Driver arrivals and trip activity appear here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, this.onTap});

  final AppNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRead = notification.isRead;
    return Card(
      key: Key('notification-${notification.id}'),
      margin: EdgeInsets.zero,
      color: isRead ? null : theme.colorScheme.primaryContainer,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isRead
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Icon(
                  notification.title == 'Trip completed'
                      ? Icons.check_circle_outline_rounded
                      : Icons.directions_car_filled_outlined,
                  color: isRead
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(notification.title,
                              style: theme.textTheme.titleMedium),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(notification.timeLabel,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(notification.body, style: theme.textTheme.bodyMedium),
                    if (!isRead) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Tap to mark as read',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverNotificationsScreen extends ConsumerWidget {
  const _DriverNotificationsScreen({required this.notifications});

  final List<AppNotification> notifications;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      title: 'Notifications',
      bottomNavigationBar: const MockBottomNavBar(
        currentIndex: 0,
        profilePath: '/driver/profile',
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
                final theme = Theme.of(context);
                return Card(
                  color: notification.isRead
                      ? null
                      : theme.colorScheme.primaryContainer,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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
                    title: Text(
                      notification.title,
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(notification.body),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          notification.timeLabel,
                          style: theme.textTheme.bodySmall,
                        ),
                        if (!notification.isRead)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Icon(
                              Icons.circle,
                              size: 8,
                              color: AppColors.accent,
                            ),
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
