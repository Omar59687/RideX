import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/ride_location_card.dart';

class FareEstimateScreen extends ConsumerWidget {
  const FareEstimateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingControllerProvider);
    final controller = ref.read(bookingControllerProvider.notifier);
    return AppScaffold(
      title: 'Trip summary',
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.md),
          if (draft.pickup != null)
            RideLocationCard(
                location: draft.pickup!, icon: Icons.my_location_rounded),
          const SizedBox(height: AppSpacing.sm),
          if (draft.destination != null)
            RideLocationCard(
                location: draft.destination!, icon: Icons.location_on_outlined),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(draft.vehicleType?.name ?? 'Vehicle',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text('${draft.distanceKm} km · ${draft.etaMinutes} min'),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                      formatMoney(draft.estimatedFare == 0
                          ? (draft.vehicleType?.baseFare ?? 0)
                          : draft.estimatedFare),
                      style: Theme.of(context).textTheme.displaySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Search for driver',
            onPressed: () async {
              await controller.estimateFare();
              if (context.mounted) context.push('/rider/searching');
            },
          ),
        ],
      ),
    );
  }
}
