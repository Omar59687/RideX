import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/driver_info_card.dart';
import 'package:ridex/core/widgets/fare_summary_card.dart';
import 'package:ridex/core/widgets/route_timeline.dart';

class TripCompletionScreen extends ConsumerWidget {
  const TripCompletionScreen({super.key, required this.isDriverView});

  final bool isDriverView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(activeTripControllerProvider);
    if (!isDriverView && trip == null) {
      return AppScaffold(
        title: 'Trip completed',
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Trip details are unavailable.'),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Return home',
              onPressed: () => context.go('/rider/home'),
            ),
          ],
        ),
      );
    }

    return AppScaffold(
      title: 'Trip completed',
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            const CircleAvatar(
                radius: 42, child: Icon(Icons.check_rounded, size: 40)),
            const SizedBox(height: AppSpacing.lg),
            Text(
                isDriverView
                    ? 'Ride finished successfully'
                    : 'Thanks for riding with RideX',
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(formatMoney(isDriverView ? 1.99 : trip!.finalFare),
                style: Theme.of(context).textTheme.displaySmall),
            if (!isDriverView) ...[
              const SizedBox(height: AppSpacing.lg),
              FareSummaryCard(
                total: trip!.finalFare,
                title: 'Final fare',
                note: 'Payment: Cash',
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: RouteTimeline(
                    pickup: RouteTimelineStop(
                      title: trip.booking.pickup?.address ?? 'Pickup',
                    ),
                    destination: RouteTimelineStop(
                      title: trip.booking.destination?.address ?? 'Destination',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DriverInfoCard(driver: trip.driver),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: isDriverView ? 'Open trip history' : 'Rate driver',
              onPressed: () =>
                  context.go(isDriverView ? '/history' : '/rider/rating'),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
