import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';
import 'package:ridex/core/widgets/ride_x_bottom_navigation.dart';
import 'package:ridex/core/widgets/settings_row.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  var _isSigningOut = false;

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signOut();
      if (mounted) context.go('/sign-in');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSigningOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign out could not be completed. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(sessionControllerProvider).role ?? RideRole.rider;
    if (role == RideRole.driver) {
      return _DriverSettingsScreen(onSignOut: _signOut);
    }

    final preferences = ref.watch(notificationPreferencesProvider);
    return AppScaffold(
      title: 'Settings',
      maxContentWidth: 600,
      bottomNavigationBar: const RideXBottomNavigation(currentIndex: 3),
      body: ListView(
        key: const Key('rider-settings-content'),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const SizedBox(height: AppSpacing.sm),
          const _SectionLabel('NOTIFICATIONS'),
          const SizedBox(height: AppSpacing.sm),
          _SettingsGroup(
            children: [
              _PreferenceRow(
                icon: Icons.notifications_active_outlined,
                title: 'Push notifications',
                subtitle: 'Driver arrival and trip updates',
                value: preferences.push,
                onChanged: (value) => ref
                    .read(notificationPreferencesProvider.notifier)
                    .state = preferences.copyWith(push: value),
                controlKey: const Key('settings-push'),
              ),
              const Divider(height: 1),
              _PreferenceRow(
                icon: Icons.sms_outlined,
                title: 'SMS notifications',
                subtitle: 'Important booking updates',
                value: preferences.sms,
                onChanged: (value) => ref
                    .read(notificationPreferencesProvider.notifier)
                    .state = preferences.copyWith(sms: value),
                controlKey: const Key('settings-sms'),
              ),
              const Divider(height: 1),
              _PreferenceRow(
                icon: Icons.alternate_email_rounded,
                title: 'Email notifications',
                subtitle: 'Receipts and RideX news',
                value: preferences.email,
                onChanged: (value) => ref
                    .read(notificationPreferencesProvider.notifier)
                    .state = preferences.copyWith(email: value),
                controlKey: const Key('settings-email'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Preferences are saved for this session. Notification delivery is not connected yet.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionLabel('ACCOUNT & EXPERIENCE'),
          const SizedBox(height: AppSpacing.sm),
          const _SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.shield_outlined,
                title: 'Security',
                subtitle: 'Password and trusted devices',
                enabled: false,
                trailing: _ComingSoonLabel(),
              ),
              Divider(height: 1),
              SettingsRow(
                icon: Icons.language_rounded,
                title: 'Language',
                subtitle: 'English; Arabic is coming soon',
                enabled: false,
                trailing: _ComingSoonLabel(),
              ),
              Divider(height: 1),
              SettingsRow(
                icon: Icons.support_agent_rounded,
                title: 'Contact & support',
                subtitle: 'Help with your rides',
                enabled: false,
                trailing: _ComingSoonLabel(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: context.rideXTheme.surfaceLive,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.accessibility_new_rounded),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Motion & accessibility\nRideX follows your device text size and reduced-motion preference.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const Key('settings-sign-out'),
            label: 'Sign out',
            icon: Icons.logout_rounded,
            variant: AppButtonVariant.secondary,
            destructive: true,
            isLoading: _isSigningOut,
            onPressed: _isSigningOut ? null : _signOut,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'RideX V2 · Urban Aurora',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 1.1,
          ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Column(children: children),
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.controlKey,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key controlKey;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(
        key: controlKey,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _ComingSoonLabel extends StatelessWidget {
  const _ComingSoonLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: context.rideXTheme.disabledBackground,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(
        'Coming soon',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.rideXTheme.disabledContent,
            ),
      ),
    );
  }
}

class _DriverSettingsScreen extends StatelessWidget {
  const _DriverSettingsScreen({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Settings',
      bottomNavigationBar: const MockBottomNavBar(
        currentIndex: 3,
        profilePath: '/driver/profile',
      ),
      body: ListView(
        key: const Key('driver-settings-content'),
        children: [
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.graphite,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ahmed Yaser',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cash payment · Demo account',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _DriverSettingsTile(
            title: 'Notifications',
            subtitle: 'Mock notification preferences',
            icon: Icons.notifications_none_rounded,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _DriverSettingsTile(
            title: 'Security',
            subtitle: 'Backend is not connected in this phase',
            icon: Icons.shield_outlined,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _DriverSettingsTile(
            title: 'Language',
            subtitle: 'English',
            icon: Icons.language_rounded,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _DriverSettingsTile(
            title: 'Contact us',
            subtitle: 'Support is mocked in this phase',
            icon: Icons.support_agent_rounded,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Sign out',
            variant: AppButtonVariant.secondary,
            onPressed: onSignOut,
          ),
          const SizedBox(height: 92),
        ],
      ),
    );
  }
}

class _DriverSettingsTile extends StatelessWidget {
  const _DriverSettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: AppColors.cloud,
          child: Icon(icon, color: AppColors.ink),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
