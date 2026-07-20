import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_bottom_sheet.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/trip_status_card.dart';

class DriverArrivalScreen extends ConsumerWidget {
  const DriverArrivalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(activeTripControllerProvider);
    final status = trip?.status ?? TripStatus.accepted;
    final isArrived = status == TripStatus.driverArrived;
    return AppScaffold(
      title: null,
      extendBodyBehindAppBar: true,
      maxContentWidth: 700,
      body: Stack(
        children: [
          const Positioned.fill(
              child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: MapPlaceholder(height: 620))),
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                    isArrived
                        ? 'You have arrived at pickup'
                        : 'Drive toward the pickup point',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AppBottomSheet(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TripStatusCard(
                    status: status,
                    title: isArrived ? 'Rider is ready' : 'Pickup in progress',
                    message: isArrived
                        ? 'Start the trip once the rider is in the vehicle.'
                        : 'Use the mock button to move from navigation to arrival.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: isArrived ? 'Start trip' : 'Mark arrived',
                    onPressed: () {
                      if (!isArrived) {
                        ref
                            .read(activeTripControllerProvider.notifier)
                            .setStatus(TripStatus.driverArriving);
                        ref
                            .read(activeTripControllerProvider.notifier)
                            .setStatus(TripStatus.driverArrived);
                      } else {
                        ref
                            .read(activeTripControllerProvider.notifier)
                            .setStatus(TripStatus.inProgress);
                        context.go('/driver/trip');
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
