import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(selectedRoleProvider);
    final showDemo = !EnvConfig.hasBackendConfig;

    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Choose your role',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            showDemo
                ? 'Use one polished app with rider and driver demo flows.'
                : 'Choose whether you are creating or entering a rider or driver account.',
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final item in RideRole.values) ...[
            Card(
              child: RadioListTile<RideRole>(
                value: item,
                groupValue: role,
                title: Text(item.label),
                subtitle: Text(
                  item == RideRole.rider
                      ? 'Book, track, and rate a trip.'
                      : 'Accept rides and manage trip progress.',
                ),
                onChanged: (value) {
                  ref.read(selectedRoleProvider.notifier).state = value!;
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const Spacer(),
          AppButton(
            label: 'Continue to sign in',
            onPressed: () => context.go('/sign-in'),
          ),
          if (showDemo) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Continue as Demo ${role.label}',
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                await ref
                    .read(sessionControllerProvider.notifier)
                    .continueAsDemo(role);
                if (context.mounted) {
                  context.go(
                      role == RideRole.rider ? '/rider/home' : '/driver/home');
                }
              },
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}
