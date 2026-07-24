import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/auth/presentation/widgets/auth_shell.dart';

class AdminPlaceholderScreen extends ConsumerWidget {
  const AdminPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AuthShell(
      showBack: false,
      title: 'Admin access',
      subtitle: 'This account is authorized for RideX administration.',
      child: Column(
        children: [
          const Icon(Icons.admin_panel_settings_outlined, size: 72),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Admin tools are not available in this build.',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Driver promotion and approval are managed through the approved server-side process.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
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
