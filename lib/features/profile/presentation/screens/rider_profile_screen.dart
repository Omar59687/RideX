import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_error_view.dart';
import 'package:ridex/core/widgets/app_loading.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/ride_x_bottom_navigation.dart';
import 'package:ridex/core/widgets/section_header.dart';
import 'package:ridex/core/widgets/settings_row.dart';

class RiderProfileScreen extends ConsumerStatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  ConsumerState<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends ConsumerState<RiderProfileScreen> {
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
    final profile = ref.watch(currentProfileProvider);
    return AppScaffold(
      padding: EdgeInsets.zero,
      useSafeArea: false,
      maxContentWidth: 600,
      bottomNavigationBar: const RideXBottomNavigation(currentIndex: 2),
      body: profile.when(
        loading: () => const SafeArea(
          child: AppLoading(
            key: Key('profile-loading'),
            label: 'Loading your profile...',
          ),
        ),
        error: (_, __) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AppErrorView(
              title: 'Profile could not be loaded',
              message: 'Check your connection and try again.',
              onRetry: () => ref.invalidate(currentProfileProvider),
            ),
          ),
        ),
        data: (user) => _ProfileContent(
          user: user,
          isSigningOut: _isSigningOut,
          onSignOut: _signOut,
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.user,
    required this.isSigningOut,
    required this.onSignOut,
  });

  final AppUser user;
  final bool isSigningOut;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('profile-content'),
      padding: EdgeInsets.zero,
      children: [
        _ProfileHero(user: user),
        Transform.translate(
          offset: const Offset(0, -AppSpacing.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: const _AvailabilityCards(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            96,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(
                title: 'Your RideX',
                subtitle: 'More ways to personalize your rides are on the way.',
                compact: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              const _ProfileGroup(
                children: [
                  SettingsRow(
                    icon: Icons.place_outlined,
                    title: 'Saved places',
                    subtitle: 'Coming soon',
                    enabled: false,
                    trailing: _ComingSoonLabel(),
                  ),
                  Divider(height: 1),
                  SettingsRow(
                    icon: Icons.credit_card_outlined,
                    title: 'Payment methods',
                    subtitle: 'Coming soon',
                    enabled: false,
                    trailing: _ComingSoonLabel(),
                  ),
                  Divider(height: 1),
                  SettingsRow(
                    icon: Icons.auto_awesome_outlined,
                    title: 'RideX Rewards',
                    subtitle: 'Coming soon',
                    enabled: false,
                    trailing: _ComingSoonLabel(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Contact', compact: true),
              const SizedBox(height: AppSpacing.sm),
              _ProfileGroup(
                children: [
                  SettingsRow(
                    icon: Icons.alternate_email_rounded,
                    title: 'Email',
                    subtitle: user.email,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Account', compact: true),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const Key('profile-sign-out'),
                label: 'Sign out',
                icon: Icons.logout_rounded,
                variant: AppButtonVariant.secondary,
                destructive: true,
                isLoading: isSigningOut,
                onPressed: isSigningOut ? null : onSignOut,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        MediaQuery.paddingOf(context).top + AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      decoration: const BoxDecoration(
        color: AppColors.midnight900,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppRadii.sheet),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Profile',
                style: textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const Spacer(),
              Tooltip(
                message: 'Edit profile - Coming soon',
                child: IconButton.outlined(
                  key: const Key('profile-edit'),
                  onPressed: null,
                  icon: const Icon(Icons.edit_outlined),
                  color: Colors.white,
                  disabledColor: AppColors.midnight300,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _ProfileAvatar(user: user),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.midnight100,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.aqua500.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        border: Border.all(
                          color: AppColors.aqua300.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Text(
                        'RideX rider',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.aqua100,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        _initials(user.name),
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.midnight900,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
    final avatarUrl = user.avatarUrl?.trim();
    return Semantics(
      image: true,
      label: '${user.name} profile picture',
      child: Container(
        width: 76,
        height: 76,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: context.rideXTheme.rewardGradient,
          borderRadius: BorderRadius.circular(AppRadii.sheet),
        ),
        child: avatarUrl == null || avatarUrl.isEmpty
            ? fallback
            : Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

class _AvailabilityCards extends StatelessWidget {
  const _AvailabilityCards();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _AvailabilityCard(label: 'Rides')),
        SizedBox(width: AppSpacing.sm),
        Expanded(child: _AvailabilityCard(label: 'Rating')),
        SizedBox(width: AppSpacing.sm),
        Expanded(child: _AvailabilityCard(label: 'Points')),
      ],
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label, Coming soon',
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: context.rideXTheme.cardShadows,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '--',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.disabledColor,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileGroup extends StatelessWidget {
  const _ProfileGroup({required this.children});

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

class _ComingSoonLabel extends StatelessWidget {
  const _ComingSoonLabel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        style: theme.textTheme.labelSmall?.copyWith(
          color: context.rideXTheme.disabledContent,
        ),
      ),
    );
  }
}

String _initials(String name) {
  final words =
      name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
  return words.take(2).map((word) => word[0].toUpperCase()).join();
}
