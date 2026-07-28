import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/auth/presentation/widgets/auth_shell.dart';

class ProfileErrorScreen extends ConsumerWidget {
  const ProfileErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    return AuthShell(
      showBack: false,
      title: 'Account unavailable',
      subtitle: 'RideX could not verify the profile linked to this session.',
      child: Column(
        children: [
          const Icon(Icons.manage_accounts_outlined, size: 72),
          const SizedBox(height: AppSpacing.lg),
          Text(
            session.errorMessage ?? 'Your account profile could not be loaded.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Retry',
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).refreshSession(),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Sign out',
            variant: AppButtonVariant.secondary,
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}
