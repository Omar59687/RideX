import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/vehicle_type.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';

class RiderHomeScreen extends ConsumerWidget {
  const RiderHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final booking = ref.watch(bookingControllerProvider);
    final notifications = ref.watch(notificationsControllerProvider);
    final fullName = session.user?.name.trim();
    final firstName = fullName == null || fullName.isEmpty
        ? 'Rider'
        : fullName.split(RegExp(r'\s+')).first;
    final pickup = booking.pickup ?? MockData.locations.first;
    final unreadCount = notifications.where((item) => !item.isRead).length;

    void startBooking() => context.push('/rider/pickup');

    return AppScaffold(
      showBack: false,
      bottomNavigationBar: const MockBottomNavBar(
        currentIndex: 0,
        profilePath: '/rider/profile',
        emphasizeSelection: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            key: const ValueKey('rider-home-scroll'),
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.md,
            ),
            children: [
              _RideXHero(
                firstName: firstName,
                pickup: pickup,
                unreadCount: unreadCount,
                onNotifications: () => context.push('/notifications'),
                onStartBooking: startBooking,
              ).animate().fadeIn(duration: 220.ms).slideY(begin: .02),
              const SizedBox(height: AppSpacing.lg),
              _RouteMapCard(
                booking: booking,
                vehicles: MockData.vehicleTypes,
              ).animate().fadeIn(duration: 260.ms),
              const SizedBox(height: AppSpacing.lg),
              const _HomeSectionHeader(
                title: 'Go again',
                trailing: 'Saved places',
              ),
              const SizedBox(height: AppSpacing.sm),
              _SavedPlacesStrip(
                locations: MockData.locations,
                onLocationTap: startBooking,
              ),
              const SizedBox(height: AppSpacing.lg),
              const _HomeSectionHeader(
                title: 'Ride your way',
                trailing: 'Estimated availability',
              ),
              const SizedBox(height: AppSpacing.sm),
              const _VehicleAvailabilityStrip(
                vehicles: MockData.vehicleTypes,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }
}

class _RideXHero extends StatelessWidget {
  const _RideXHero({
    required this.firstName,
    required this.pickup,
    required this.unreadCount,
    required this.onNotifications,
    required this.onStartBooking,
  });

  final String firstName;
  final RideLocation pickup;
  final int unreadCount;
  final VoidCallback onNotifications;
  final VoidCallback onStartBooking;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 350;
        return SizedBox(
          height: compact ? 286 : 278,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                bottom: 58,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.graphite,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -12,
                          bottom: -36,
                          child: Text(
                            'RX',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .045),
                              fontSize: 132,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -8,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.card,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Text(
                                      'RX',
                                      style: TextStyle(
                                        color: AppColors.graphite,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    'RideX',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(color: AppColors.card),
                                  ),
                                  const Spacer(),
                                  _NotificationButton(
                                    unreadCount: unreadCount,
                                    onPressed: onNotifications,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'Good morning, $firstName',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Your city is ready\nwhen you are.',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge
                                    ?.copyWith(
                                      color: AppColors.card,
                                      fontSize: compact ? 24 : 27,
                                      height: 1.08,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: 0,
                child: _DestinationPlanner(
                  pickup: pickup,
                  onPressed: onStartBooking,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({
    required this.unreadCount,
    required this.onPressed,
  });

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            tooltip: 'Notifications',
            onPressed: onPressed,
            style: IconButton.styleFrom(
              foregroundColor: AppColors.card,
              backgroundColor: Colors.white.withValues(alpha: .08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: .12),
                ),
              ),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            right: -3,
            top: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.graphite, width: 2),
              ),
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DestinationPlanner extends StatelessWidget {
  const _DestinationPlanner({
    required this.pickup,
    required this.onPressed,
  });

  final RideLocation pickup;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      elevation: 10,
      shadowColor: AppColors.shadow,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        key: const ValueKey('rider-destination-search-card'),
        borderRadius: BorderRadius.circular(22),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.mist,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.trip_origin_rounded,
                      color: AppColors.ink,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Where are you going?',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Search Jordan destinations',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.filled(
                    key: const ValueKey('rider-start-booking-button'),
                    tooltip: 'Start booking',
                    onPressed: onPressed,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: AppColors.accentDeep,
                      foregroundColor: AppColors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 17,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Pickup confirmed: ',
                        children: [
                          TextSpan(
                            text: pickup.address,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteMapCard extends StatelessWidget {
  const _RouteMapCard({
    required this.booking,
    required this.vehicles,
  });

  final BookingDraft booking;
  final List<VehicleType> vehicles;

  @override
  Widget build(BuildContext context) {
    final pickupLabel = booking.pickup?.address ?? 'Current pickup';
    final destinationLabel =
        booking.destination?.address ?? 'Choose destination';
    final availableVehicles = vehicles.take(2).toList();

    return SizedBox(
      height: 268,
      child: Stack(
        children: [
          const Positioned.fill(child: MapPlaceholder(height: 268)),
          Positioned(
            left: AppSpacing.sm,
            right: 64,
            top: AppSpacing.sm,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.card.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Text(
                  '$pickupLabel to $destinationLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(15),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
          Positioned(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: Row(
              children: [
                for (var index = 0;
                    index < availableVehicles.length;
                    index++) ...[
                  if (index > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _MapAvailabilityCard(
                      vehicle: availableVehicles[index],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapAvailabilityCard extends StatelessWidget {
  const _MapAvailabilityCard({required this.vehicle});

  final VehicleType vehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: .95),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.local_taxi_rounded, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  '${vehicle.arrivalMinutes} min away',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            trailing,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _SavedPlacesStrip extends StatelessWidget {
  const _SavedPlacesStrip({
    required this.locations,
    required this.onLocationTap,
  });

  final List<RideLocation> locations;
  final VoidCallback onLocationTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: locations.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final location = locations[index];
          return SizedBox(
            width: 122,
            child: Material(
              color: index == 0 ? AppColors.ink : AppColors.card,
              borderRadius: BorderRadius.circular(17),
              child: InkWell(
                key: ValueKey('rider-saved-place-${location.label}'),
                borderRadius: BorderRadius.circular(17),
                onTap: onLocationTap,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _locationIcon(location),
                        size: 19,
                        color: index == 0 ? AppColors.card : AppColors.ink,
                      ),
                      const Spacer(),
                      Text(
                        location.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  index == 0 ? AppColors.card : AppColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        location.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  index == 0 ? Colors.white60 : AppColors.muted,
                              fontSize: 10,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _locationIcon(RideLocation location) {
    final value = '${location.label} ${location.address}'.toLowerCase();
    if (value.contains('airport')) return Icons.flight_takeoff_rounded;
    if (value.contains('mall') || value.contains('abdali')) {
      return Icons.shopping_bag_outlined;
    }
    if (value.contains('university')) return Icons.school_outlined;
    return Icons.location_on_outlined;
  }
}

class _VehicleAvailabilityStrip extends StatelessWidget {
  const _VehicleAvailabilityStrip({required this.vehicles});

  final List<VehicleType> vehicles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: vehicles.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final vehicle = vehicles[index];
          return Semantics(
            label:
                '${vehicle.name}, ${vehicle.arrivalMinutes} minutes, ${formatMoney(vehicle.baseFare)}',
            child: Container(
              width: 146,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.mist,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      vehicle.id == 'taxi'
                          ? Icons.local_taxi_rounded
                          : Icons.directions_car_filled_rounded,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicle.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${vehicle.arrivalMinutes} min | ${formatMoney(vehicle.baseFare)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
