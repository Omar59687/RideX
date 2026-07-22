import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/route_timeline.dart';
import 'package:ridex/core/widgets/trip_status_card.dart';

@immutable
class RiderTripStatusContent extends StatelessWidget {
  const RiderTripStatusContent({super.key, required this.trip});

  final MockTrip trip;

  @override
  Widget build(BuildContext context) {
    final (title, message) = switch (trip.status) {
      TripStatus.accepted => (
          'Driver assigned',
          '${trip.driver.name} accepted your request.'
        ),
      TripStatus.driverArriving => (
          'Driver arriving',
          '${trip.driver.name} is heading to your pickup.'
        ),
      TripStatus.driverArrived => (
          'Driver has arrived',
          'Meet ${trip.driver.name} at the pickup point.'
        ),
      TripStatus.inProgress => (
          'Trip in progress',
          'On the way to ${trip.booking.destination?.address ?? 'your destination'}.'
        ),
      _ => ('Trip update', trip.status.label),
    };
    return TripStatusCard(
      key: ValueKey(trip.status),
      status: trip.status,
      title: title,
      message: message,
      trailing: Text(
        trip.status == TripStatus.inProgress
            ? formatMoney(trip.finalFare)
            : '${trip.driver.etaMinutes} min',
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class RiderTripRouteCard extends StatelessWidget {
  const RiderTripRouteCard({super.key, required this.trip});

  final MockTrip trip;

  @override
  Widget build(BuildContext context) {
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
                    trip.booking.vehicleType?.name ?? 'Ride',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  formatMoney(trip.booking.estimatedFare),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            RouteTimeline(
              compact: true,
              pickup: RouteTimelineStop(
                title: trip.booking.pickup?.address ?? 'Pickup',
              ),
              destination: RouteTimelineStop(
                title: trip.booking.destination?.address ?? 'Destination',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
