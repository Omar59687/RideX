import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/ride_x_brand.dart';

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(selectedRoleProvider);
    final showDemo = !EnvConfig.hasBackendConfig;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 560,
                  minHeight: constraints.maxHeight - AppSpacing.xxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: RideXBrand(width: 92, height: 32),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      'Choose your role',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      showDemo
                          ? 'Explore RideX from either side of the journey.'
                          : 'Choose whether you are creating or entering a rider or driver account.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    for (final item in RideRole.values) ...[
                      _RoleCard(
                        role: item,
                        selected: role == item,
                        onSelected: () => ref
                            .read(selectedRoleProvider.notifier)
                            .state = item,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    const SizedBox(height: AppSpacing.xl),
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
                            context.go(role == RideRole.rider
                                ? '/rider/home'
                                : '/driver/home');
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.selected,
    required this.onSelected,
  });

  final RideRole role;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isRider = role == RideRole.rider;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(
            color: selected ? colors.primary : colors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  child: Icon(
                    isRider
                        ? Icons.person_pin_circle_rounded
                        : Icons.drive_eta_rounded,
                    color:
                        selected ? colors.onPrimary : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(role.label,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        isRider
                            ? 'Book, track, and rate a trip.'
                            : 'Accept rides and manage trip progress.',
                      ),
                    ],
                  ),
                ),
                Radio<RideRole>(
                  value: role,
                  groupValue: selected ? role : null,
                  onChanged: (_) => onSelected(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
