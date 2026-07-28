import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';

enum AuthMethod { phone, email }

class AuthMethodTabs extends StatelessWidget {
  const AuthMethodTabs({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.phoneEnabled,
  });

  final AuthMethod selected;
  final ValueChanged<AuthMethod> onSelected;
  final bool phoneEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _MethodTab(
                label: 'Phone',
                icon: Icons.phone_android_rounded,
                selected: selected == AuthMethod.phone,
                enabled: phoneEnabled,
                onTap: () => onSelected(AuthMethod.phone),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _MethodTab(
                label: 'Email',
                icon: Icons.alternate_email_rounded,
                selected: selected == AuthMethod.email,
                onTap: () => onSelected(AuthMethod.email),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTab extends StatelessWidget {
  const _MethodTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '$label sign in',
      child: Material(
        color: selected ? colors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.control - 4),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadii.control - 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: enabled
                              ? selected
                                  ? colors.primary
                                  : colors.onSurfaceVariant
                              : colors.onSurfaceVariant.withValues(alpha: .55),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
