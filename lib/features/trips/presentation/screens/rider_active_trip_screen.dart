import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_motion.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_bottom_sheet.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_dialog.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/coming_soon_dialog.dart';
import 'package:ridex/core/widgets/driver_info_card.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/trip_status_card.dart';
import 'package:ridex/features/trips/presentation/widgets/rider_trip_widgets.dart';

class RiderActiveTripScreen extends ConsumerWidget {
  const RiderActiveTripScreen({super.key});

  static const _activeStatuses = {
    TripStatus.accepted,
    TripStatus.driverArriving,
    TripStatus.driverArrived,
    TripStatus.inProgress,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(activeTripControllerProvider);
    if (trip == null) {
      return _TerminalTripView(
        title: 'No active trip',
        message: 'Start a new ride request when you are ready.',
        onHome: () => context.go('/rider/home'),
      );
    }
    if (!_activeStatuses.contains(trip.status)) {
      return _TerminalTripView(
        title: trip.status.label,
        message: 'This ride is no longer active.',
        status: trip.status,
        onHome: () => context.go('/rider/home'),
      );
    }

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final controller = ref.read(activeTripControllerProvider.notifier);
    return AppScaffold(
      title: null,
      extendBodyBehindAppBar: true,
      maxContentWidth: 700,
      padding: EdgeInsets.zero,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapPlaceholder(
              borderRadius: 0,
              routeProgress: trip.status == TripStatus.inProgress ? .72 : .28,
              semanticLabel:
                  'Route from ${trip.booking.pickup?.address ?? 'pickup'} to ${trip.booking.destination?.address ?? 'destination'}',
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: AnimatedSwitcher(
                duration: reduceMotion ? AppMotion.reduced : AppMotion.standard,
                child: RiderTripStatusContent(trip: trip),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AppBottomSheet(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trip.status == TripStatus.accepted) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Driver found',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    DriverInfoCard(
                      driver: trip.driver,
                      onCall: () => showComingSoonDialog(
                        context,
                        feature: 'Calling your driver',
                      ),
                      onMessage: () => showComingSoonDialog(
                        context,
                        feature: 'Driver messaging',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Deterministic demo driver',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    RiderTripRouteCard(trip: trip),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: _nextLabel(trip.status),
                      trailing: Icons.arrow_forward_rounded,
                      onPressed: () {
                        final next = _nextStatus(trip.status);
                        controller.setStatus(next);
                        if (next == TripStatus.completed && context.mounted) {
                          context.go('/rider/completed');
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (trip.status == TripStatus.inProgress)
                      AppButton(
                        label: 'Safety tools',
                        icon: Icons.health_and_safety_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => showComingSoonDialog(
                          context,
                          feature: 'Safety tools',
                        ),
                      )
                    else
                      AppButton(
                        key: const ValueKey('cancel-active-trip-button'),
                        label: 'Cancel ride',
                        variant: AppButtonVariant.text,
                        destructive: true,
                        onPressed: () => _cancelTrip(context, ref),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static TripStatus _nextStatus(TripStatus status) => switch (status) {
        TripStatus.accepted => TripStatus.driverArriving,
        TripStatus.driverArriving => TripStatus.driverArrived,
        TripStatus.driverArrived => TripStatus.inProgress,
        TripStatus.inProgress => TripStatus.completed,
        _ => status,
      };

  static String _nextLabel(TripStatus status) => switch (status) {
        TripStatus.accepted => 'Demo: Driver departing',
        TripStatus.driverArriving => 'Demo: Driver arrived',
        TripStatus.driverArrived => 'Demo: Start trip',
        TripStatus.inProgress => 'Demo: Complete trip',
        _ => 'Continue',
      };

  static Future<void> _cancelTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Cancel this ride?',
      message: 'Your driver will be notified that you cancelled.',
      icon: Icons.warning_amber_rounded,
      confirmLabel: 'Cancel ride',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    ref
        .read(activeTripControllerProvider.notifier)
        .setStatus(TripStatus.cancelledByRider);
    if (ref.read(activeTripControllerProvider)?.status ==
            TripStatus.cancelledByRider &&
        context.mounted) {
      context.go('/rider/home');
    }
  }
}

class _TerminalTripView extends StatelessWidget {
  const _TerminalTripView({
    required this.title,
    required this.message,
    required this.onHome,
    this.status = TripStatus.cancelledByRider,
  });

  final String title;
  final String message;
  final VoidCallback onHome;
  final TripStatus status;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Trip',
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TripStatusCard(status: status, title: title, message: message),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Return home', onPressed: onHome),
        ],
      ),
    );
  }
}
