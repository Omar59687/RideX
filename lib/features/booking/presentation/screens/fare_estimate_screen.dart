import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/fare_summary_card.dart';
import 'package:ridex/core/widgets/route_timeline.dart';
import 'package:ridex/core/widgets/vehicle_silhouette.dart';

class FareEstimateScreen extends ConsumerWidget {
  const FareEstimateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingControllerProvider);
    final vehicle = draft.vehicleType;
    final rider = ref.watch(sessionControllerProvider).user;
    final fare =
        draft.estimatedFare > 0 ? draft.estimatedFare : vehicle?.baseFare ?? 0;
    final ready = draft.pickup != null &&
        draft.destination != null &&
        vehicle != null &&
        fare > 0;

    return AppScaffold(
      title: 'Review booking',
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.inverseSurface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR ROUTE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Theme(
                  data: Theme.of(context).copyWith(
                    textTheme: Theme.of(context).textTheme.apply(
                          bodyColor:
                              Theme.of(context).colorScheme.onInverseSurface,
                          displayColor:
                              Theme.of(context).colorScheme.onInverseSurface,
                        ),
                  ),
                  child: RouteTimeline(
                    pickup: RouteTimelineStop(
                      title: draft.pickup?.address ?? 'Pickup not selected',
                      subtitle: draft.pickup?.label,
                    ),
                    destination: RouteTimelineStop(
                      title: draft.destination?.address ??
                          'Destination not selected',
                      subtitle: draft.destination?.label,
                    ),
                    stops: [
                      for (final stop in draft.stops)
                        RouteTimelineStop(
                          title: stop.address,
                          subtitle: stop.label,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Ride details', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Row(
                    children: [
                      const VehicleSilhouette(width: 72, height: 42),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle?.name ?? 'No ride selected',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              vehicle == null
                                  ? 'Return to choose a ride'
                                  : 'Arrives in ${vehicle.arrivalMinutes} min · ${vehicle.capacity} passengers',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: AppSpacing.xl),
                  _SummaryRow(
                    label: 'Passenger',
                    value: rider?.name ?? 'Demo rider',
                  ),
                  const _SummaryRow(label: 'Payment', value: 'Cash'),
                  _SummaryRow(
                    label: 'Estimated duration',
                    value: '${draft.etaMinutes} min',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FareSummaryCard(
            title: 'Upfront fare',
            total: fare,
            note:
                'This deterministic demo fare stays fixed for the route shown.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Unsupported route changes must be confirmed before requesting a driver.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Confirm & find a driver',
            onPressed: ready
                ? () async {
                    await ref
                        .read(bookingControllerProvider.notifier)
                        .estimateFare();
                    if (context.mounted) context.push('/rider/searching');
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
