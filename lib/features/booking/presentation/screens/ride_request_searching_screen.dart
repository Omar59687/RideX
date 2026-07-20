import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_loading.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/trip_status_card.dart';

class RideRequestSearchingScreen extends ConsumerStatefulWidget {
  const RideRequestSearchingScreen({super.key});

  @override
  ConsumerState<RideRequestSearchingScreen> createState() =>
      _RideRequestSearchingScreenState();
}

class _RideRequestSearchingScreenState
    extends ConsumerState<RideRequestSearchingScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
        () => ref.read(activeTripControllerProvider.notifier).createTrip());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Searching',
      body: Column(
        children: [
          const Spacer(),
          const AppLoading(label: 'Matching you with a nearby driver'),
          const SizedBox(height: AppSpacing.xl),
          const TripStatusCard(
            status: TripStatus.searching,
            title: 'Search in progress',
            message:
                'Use the demo buttons below to walk through deterministic rider states.',
          ),
          const Spacer(),
          AppButton(
            label: 'Demo: Driver found',
            onPressed: () {
              ref
                  .read(activeTripControllerProvider.notifier)
                  .setStatus(TripStatus.accepted);
              context.go('/rider/trip');
            },
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Demo: No driver found',
            variant: AppButtonVariant.secondary,
            onPressed: () {
              ref
                  .read(activeTripControllerProvider.notifier)
                  .setStatus(TripStatus.noDriverFound);
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}
