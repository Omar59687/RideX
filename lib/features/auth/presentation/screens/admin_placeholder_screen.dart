import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/auth/presentation/widgets/auth_shell.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_payment_visibility_panel.dart';
import 'package:ridex/features/auth/presentation/providers/admin_payment_providers.dart';

class AdminPlaceholderScreen extends ConsumerWidget {
  const AdminPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorized = canReadAdminPayments(
      ref.watch(sessionControllerProvider),
    );
    return AuthShell(
      showBack: false,
      title: 'Admin payments',
      subtitle: authorized
          ? 'Read-only payment summaries for RideX administration.'
          : 'An authorized administrator account is required.',
      child: Column(
        children: [
          const Icon(Icons.admin_panel_settings_outlined, size: 72),
          const SizedBox(height: AppSpacing.lg),
          const AdminPaymentVisibilityPanel(),
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
