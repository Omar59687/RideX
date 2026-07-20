import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';

class MockBottomNavBar extends StatelessWidget {
  const MockBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.profilePath,
  });

  final int currentIndex;
  final String profilePath;

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(
          'Home',
          Icons.home_rounded,
          currentIndex == 0,
          () => context.go(profilePath.contains('/driver')
              ? '/driver/home'
              : '/rider/home')),
      _NavItem('History', Icons.receipt_long_rounded, currentIndex == 1,
          () => context.push('/history')),
      _NavItem('Profile', Icons.person_rounded, currentIndex == 2,
          () => context.push(profilePath)),
      _NavItem('Settings', Icons.tune_rounded, currentIndex == 3,
          () => context.push('/settings')),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 20,
                  offset: Offset(0, 8)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Row(
              children: [
                for (final item in items)
                  Expanded(child: _NavButton(item: item)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.selected, this.onTap);

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item});

  final _NavItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon,
                size: 22,
                color: item.selected ? AppColors.ink : AppColors.muted),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: item.selected ? AppColors.ink : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
