import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';

class DriverTripRequestScreen extends ConsumerWidget {
  const DriverTripRequestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingControllerProvider);
    return AppScaffold(
      title: 'Incoming request',
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.md),
          const MapPlaceholder(height: 220),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text('Ahmed is requesting a ride',
                              style: Theme.of(context).textTheme.titleLarge)),
                      const CircleAvatar(radius: 20, child: Icon(Icons.person)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _TripPoint(
                      label: 'Pickup',
                      value: 'Hashemite University',
                      icon: Icons.my_location_rounded),
                  const SizedBox(height: AppSpacing.sm),
                  const _TripPoint(
                      label: 'Destination',
                      value: 'Abdali Boulevard',
                      icon: Icons.location_on_outlined),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                          child: _TinyMetric(
                              label: 'Distance',
                              value:
                                  '${draft.distanceKm.toStringAsFixed(0)} km')),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                          child: _TinyMetric(
                              label: 'ETA', value: '${draft.etaMinutes} min')),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                          child: _TinyMetric(
                              label: 'Fare',
                              value: formatMoney(draft.estimatedFare == 0
                                  ? 1.99
                                  : draft.estimatedFare))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Decline',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  key: const ValueKey('driver-accept-request-button'),
                  label: 'Accept request',
                  onPressed: () {
                    ref.read(activeTripControllerProvider.notifier).setTrip(
                          MockData.sampleTrip(status: TripStatus.accepted),
                        );
                    context.go('/driver/arrival');
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripPoint extends StatelessWidget {
  const _TripPoint(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.cloud,
            child: Icon(icon, size: 16, color: AppColors.ink)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text('$label · $value')),
      ],
    );
  }
}

class _TinyMetric extends StatelessWidget {
  const _TinyMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.cloud, borderRadius: BorderRadius.circular(16)),
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
