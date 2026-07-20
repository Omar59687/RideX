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

class DriverActiveTripScreen extends ConsumerWidget {
  const DriverActiveTripScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(activeTripControllerProvider);
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
                child: Text('Destination route active',
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
                    status: trip?.status ?? TripStatus.inProgress,
                    title: 'Drive to destination',
                    message:
                        'This mock state mirrors the active driver flow without backend dependencies.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Complete trip',
                    onPressed: () {
                      ref
                          .read(activeTripControllerProvider.notifier)
                          .setStatus(TripStatus.completed);
                      context.go('/driver/completed');
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
