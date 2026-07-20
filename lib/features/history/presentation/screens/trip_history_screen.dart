import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/app_empty_view.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class TripHistoryScreen extends ConsumerWidget {
  const TripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionControllerProvider).role ?? RideRole.rider;
    return AppScaffold(
      title: 'Trip history',
      bottomNavigationBar: MockBottomNavBar(
        currentIndex: 1,
        profilePath:
            role == RideRole.driver ? '/driver/profile' : '/rider/profile',
      ),
      body: FutureBuilder<List<MockTrip>>(
        future: ref.read(tripsRepositoryProvider).getTripHistory(),
        builder: (context, snapshot) {
          final trips = snapshot.data;
          if (trips == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (trips.isEmpty) {
            return const AppEmptyView(
              title: 'No trips yet',
              message: 'Your finished rides will appear here.',
            );
          }
          return ListView.separated(
            itemCount: trips.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final trip = trips[index];
              final isCompleted = trip.status == TripStatus.completed;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${trip.booking.pickup?.address} → ${trip.booking.destination?.address}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            formatMoney(trip.finalFare),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          StatusChip(
                            label: trip.status.label,
                            color: isCompleted
                                ? AppColors.accent
                                : AppColors.warning,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${trip.booking.distanceKm.toStringAsFixed(0)} km · ${trip.booking.etaMinutes} min',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
