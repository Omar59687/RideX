import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/app_bottom_sheet.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/driver_info_card.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class RiderActiveTripScreen extends ConsumerWidget {
  const RiderActiveTripScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(activeTripControllerProvider);
    if (trip == null) {
      return const AppScaffold(
        title: 'Trip',
        body: Center(child: Text('No active trip yet.')),
      );
    }

    final config = switch (trip.status) {
      TripStatus.accepted => _StatusConfig(
          'Driver found',
          'Omar accepted your request.',
          'Pickup in 2 min',
          'Demo: Driver arriving',
          TripStatus.driverArriving,
          true),
      TripStatus.driverArriving => _StatusConfig(
          'Driver arriving',
          'Live updates stay deterministic for demos.',
          'ETA 2 min',
          'Demo: Driver arrived',
          TripStatus.driverArrived,
          true),
      TripStatus.driverArrived => _StatusConfig(
          'Driver has arrived',
          'Meet your driver at the pickup pin.',
          'Outside now',
          'Demo: Start trip',
          TripStatus.inProgress,
          true),
      TripStatus.inProgress => _StatusConfig(
          'Trip in progress',
          'You are heading toward the destination.',
          '5 km remaining',
          'Demo: Complete trip',
          TripStatus.completed,
          false),
      _ => _StatusConfig('Trip update', 'Continue the trip demo flow.', '-',
          'Continue', TripStatus.completed, false),
    };

    return AppScaffold(
      title: null,
      extendBodyBehindAppBar: true,
      maxContentWidth: 700,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final mapHeight = constraints.maxWidth > 600
              ? 520.0
              : constraints.maxHeight.clamp(560, 760).toDouble() - 24;
          return Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: MapPlaceholder(height: mapHeight),
                ),
              ),
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: _TopTripHeader(config: config),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: AppBottomSheet(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DriverInfoCard(driver: trip.driver),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                  child: _MetricTile(
                                      label: 'Distance',
                                      value:
                                          '${trip.booking.distanceKm.toStringAsFixed(0)} km')),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                  child: _MetricTile(
                                      label: 'ETA',
                                      value: '${trip.driver.etaMinutes} min')),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                  child: _MetricTile(
                                      label: 'Price',
                                      value: formatMoney(
                                          trip.booking.estimatedFare))),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text('Route',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: AppSpacing.sm),
                          _RouteRow(
                              icon: Icons.my_location_rounded,
                              title: 'Pickup',
                              value: trip.booking.pickup?.address ?? '-'),
                          const SizedBox(height: AppSpacing.sm),
                          _RouteRow(
                              icon: Icons.location_on_outlined,
                              title: 'Destination',
                              value: trip.booking.destination?.address ?? '-'),
                          const SizedBox(height: AppSpacing.lg),
                          AppButton(
                            label: config.nextLabel,
                            trailing: Icons.arrow_forward_rounded,
                            onPressed: () {
                              ref
                                  .read(activeTripControllerProvider.notifier)
                                  .setStatus(config.nextStatus);
                              if (config.nextStatus == TripStatus.completed) {
                                context.go('/rider/completed');
                              }
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  label: 'Contact driver',
                                  icon: Icons.chat_bubble_outline_rounded,
                                  isExpanded: true,
                                  variant: AppButtonVariant.secondary,
                                  onPressed: () {},
                                ),
                              ),
                              if (config.allowCancel) ...[
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: AppButton(
                                    label: 'Cancel request',
                                    isExpanded: true,
                                    variant: AppButtonVariant.secondary,
                                    onPressed: () {},
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusConfig {
  const _StatusConfig(this.title, this.message, this.badge, this.nextLabel,
      this.nextStatus, this.allowCancel);

  final String title;
  final String message;
  final String badge;
  final String nextLabel;
  final TripStatus nextStatus;
  final bool allowCancel;
}

class _TopTripHeader extends StatelessWidget {
  const _TopTripHeader({required this.config});

  final _StatusConfig config;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 8))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(config.title,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(config.message,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusChip(
              label: config.badge,
              color: AppColors.info,
              icon: Icons.route_rounded),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.cloud, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow(
      {required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.cloud,
            child: Icon(icon, size: 16, color: AppColors.ink)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
