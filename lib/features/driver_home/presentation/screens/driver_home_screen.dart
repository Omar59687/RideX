import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/driver_tracking_providers.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';
import 'package:ridex/core/widgets/ride_current_location_map.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  bool _permissionRequestRunning = false;
  String? _permissionMessage;

  Future<void> _startSharing() async {
    if (_permissionRequestRunning) return;
    setState(() {
      _permissionRequestRunning = true;
      _permissionMessage = null;
    });
    final location =
        await ref.read(locationRepositoryProvider).requestPermissionAndLocate();
    if (!mounted) return;
    setState(() => _permissionRequestRunning = false);
    if (location.permission != LocationPermissionStatus.granted) {
      setState(() => _permissionMessage = _permissionFailureMessage(location));
      return;
    }
    await ref.read(driverTrackingControllerProvider.notifier).start();
  }

  String _permissionFailureMessage(CurrentLocationState location) {
    return switch (location.failure) {
      LocationFailure.permissionPermanentlyDenied =>
        'Location permission is blocked. Enable it in Settings to share your location.',
      LocationFailure.permissionDenied =>
        'Location permission was denied. Allow it to start sharing.',
      LocationFailure.serviceDisabled =>
        'Device location services are off. Turn them on and retry.',
      _ =>
        'Foreground location is unavailable. Check device settings and retry.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(driverOnlineProvider);
    return AppScaffold(
      title: 'Driver mode',
      bottomNavigationBar: const MockBottomNavBar(
          currentIndex: 0, profilePath: '/driver/profile'),
      actions: [
        IconButton(
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_none_rounded))
      ],
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
                color: context.rideXTheme.brandedPanel,
                borderRadius: BorderRadius.circular(28)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text('You are ${online ? 'online' : 'offline'}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                    color: context
                                        .rideXTheme.brandedPanelForeground))),
                    StatusChip(
                        label: online ? 'Available' : 'Offline',
                        color: online ? AppColors.accent : AppColors.warning),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: const [
                    Expanded(
                        child: _SummaryTile(label: 'Today', value: '6 trips')),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                        child: _SummaryTile(
                            label: 'Earnings', value: '34.50 JOD')),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                        child: _SummaryTile(label: 'Rating', value: '4.9')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: SwitchListTile.adaptive(
              value: online,
              title: const Text('Accept incoming requests'),
              subtitle: const Text('Mock presence only for this phase.'),
              onChanged: (value) =>
                  ref.read(driverOnlineProvider.notifier).state = value,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _DriverLocationSharingCardConsumer(
            permissionRequestRunning: _permissionRequestRunning,
            permissionMessage: _permissionMessage,
            onStart: _startSharing,
          ),
          const SizedBox(height: AppSpacing.lg),
          const RideCurrentLocationMap(
            height: 220,
            semanticLabel: 'Driver map showing current location',
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Incoming request preview',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                      'Hashemite University → Abdali Boulevard\n5 km · 1.99 JOD · Taxi'),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                          child: AppButton(
                              label: 'Decline',
                              variant: AppButtonVariant.secondary,
                              onPressed: online ? () {} : null)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                          child: AppButton(
                              label: 'Accept',
                              onPressed: online
                                  ? () => context.push('/driver/request')
                                  : null)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
              label: 'View driver application',
              variant: AppButtonVariant.secondary,
              onPressed: () => context.push('/driver/application')),
          const SizedBox(height: AppSpacing.md),
          AppButton(
              key: const ValueKey('driver-demo-request-button'),
              label: 'Demo incoming trip',
              icon: Icons.campaign_outlined,
              onPressed: online ? () => context.push('/driver/request') : null),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                  child: AppButton(
                      label: 'History',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => context.push('/history'))),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                  child: AppButton(
                      label: 'Profile',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => context.push('/driver/profile'))),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
              label: 'Settings',
              variant: AppButtonVariant.text,
              onPressed: () => context.push('/settings')),
          const SizedBox(height: 92),
        ],
      ),
    );
  }
}

class _DriverLocationSharingCardConsumer extends ConsumerWidget {
  const _DriverLocationSharingCardConsumer({
    required this.permissionRequestRunning,
    required this.permissionMessage,
    required this.onStart,
  });

  final bool permissionRequestRunning;
  final String? permissionMessage;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = ref.watch(driverTrackingControllerProvider);
    return _DriverLocationSharingCard(
      state: tracking,
      permissionRequestRunning: permissionRequestRunning,
      permissionMessage: permissionMessage,
      onStart: onStart,
      onStop: () => ref.read(driverTrackingControllerProvider.notifier).stop(),
    );
  }
}

class _DriverLocationSharingCard extends StatelessWidget {
  const _DriverLocationSharingCard({
    required this.state,
    required this.permissionRequestRunning,
    required this.permissionMessage,
    required this.onStart,
    required this.onStop,
  });

  final DriverTrackingState state;
  final bool permissionRequestRunning;
  final String? permissionMessage;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final isActive = state.status == DriverTrackingStatus.sharing ||
        state.status == DriverTrackingStatus.starting;
    final canStop = isActive || state.status == DriverTrackingStatus.paused;
    final status = switch (state.status) {
      DriverTrackingStatus.stopped => 'Stopped',
      DriverTrackingStatus.paused => 'Paused',
      DriverTrackingStatus.starting => 'Starting',
      DriverTrackingStatus.sharing => 'Sharing',
      DriverTrackingStatus.unavailable => 'Unavailable',
    };
    return Card(
      key: const ValueKey('driver-location-sharing-card'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on_outlined),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Driver location sharing',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                StatusChip(
                  label: status,
                  color: isActive ? AppColors.accent : AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(_description),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _lastConfirmedLabel,
              key: const ValueKey('driver-location-last-confirmed'),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: ValueKey(
                canStop ? 'driver-location-stop' : 'driver-location-start',
              ),
              label: canStop ? 'Stop sharing' : 'Start sharing',
              icon: canStop ? Icons.stop_circle_outlined : Icons.play_arrow,
              onPressed: permissionRequestRunning
                  ? null
                  : canStop
                      ? onStop
                      : onStart,
            ),
          ],
        ),
      ),
    );
  }

  String get _description {
    if (permissionRequestRunning) {
      return 'Checking foreground location access...';
    }
    if (permissionMessage case final message?) return message;
    if (state.status == DriverTrackingStatus.starting) {
      return 'Preparing foreground GPS sharing.';
    }
    if (state.status == DriverTrackingStatus.paused) {
      return 'Sharing is paused while RideX is in the background. It will resume in the foreground.';
    }
    if (state.status == DriverTrackingStatus.sharing) {
      return 'Your current position is being shared securely.';
    }
    if (state.status == DriverTrackingStatus.unavailable) {
      return switch (state.failure) {
        DriverLocationFailure.ineligible =>
          'Location sharing needs an approved vehicle and active availability.',
        DriverLocationFailure.unauthorized =>
          'Your session cannot share location. Sign in again and retry.',
        DriverLocationFailure.staleSequence =>
          'Location sharing needs to resync. Try starting again.',
        _ =>
          'Location sharing is unavailable. Check GPS and network, then retry.',
      };
    }
    return 'Share foreground GPS only when Driver operations require it.';
  }

  String get _lastConfirmedLabel {
    final confirmedAt = state.latestConfirmedAt;
    if (confirmedAt == null) return 'No server-confirmed location yet.';
    final age = DateTime.now().toUtc().difference(confirmedAt.toUtc());
    final safeAge = age.isNegative ? Duration.zero : age;
    if (safeAge.inSeconds < 60) {
      return 'Last server-confirmed location: ${safeAge.inSeconds}s ago';
    }
    return 'Last server-confirmed location: ${safeAge.inMinutes}m ago';
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: context.rideXTheme.brandedPanelSubtle,
          borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.rideXTheme.brandedPanelMuted)),
          const SizedBox(height: 6),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: context.rideXTheme.brandedPanelForeground)),
        ],
      ),
    );
  }
}
