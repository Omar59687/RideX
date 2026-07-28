import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/ride_role.dart';

class RideXBottomNavigation extends StatelessWidget {
  const RideXBottomNavigation({
    super.key,
    required this.currentIndex,
    this.role = RideRole.rider,
  });

  final int currentIndex;
  final RideRole role;

  @override
  Widget build(BuildContext context) {
    final homePath = switch (role) {
      RideRole.rider => '/rider/home',
      RideRole.driver => '/driver/home',
      RideRole.admin => '/admin',
    };
    final profilePath = switch (role) {
      RideRole.rider => '/rider/profile',
      RideRole.driver => '/driver/profile',
      RideRole.admin => '/admin',
    };
    final paths = [homePath, '/history', profilePath, '/settings'];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: NavigationBar(
          selectedIndex: currentIndex.clamp(0, paths.length - 1),
          onDestinationSelected: (index) => context.go(paths[index]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
