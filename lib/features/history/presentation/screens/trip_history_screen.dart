import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/app_empty_view.dart';
import 'package:ridex/core/widgets/app_error_view.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';
import 'package:ridex/core/widgets/ride_x_bottom_navigation.dart';
import 'package:ridex/core/widgets/route_timeline.dart';
import 'package:ridex/core/widgets/status_chip.dart';

enum _HistoryFilter { all, completed, cancelled }

class TripHistoryScreen extends ConsumerStatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  ConsumerState<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends ConsumerState<TripHistoryScreen> {
  late Future<List<MockTrip>> _history;
  var _filter = _HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    _history = ref.read(tripsRepositoryProvider).getTripHistory();
  }

  void _reload() {
    setState(() {
      _history = ref.read(tripsRepositoryProvider).getTripHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(sessionControllerProvider).role ?? RideRole.rider;
    final isDriver = role == RideRole.driver;
    return AppScaffold(
      title: isDriver ? 'Trip history' : 'Your rides',
      showBack: isDriver,
      bottomNavigationBar: isDriver
          ? const MockBottomNavBar(
              currentIndex: 1,
              profilePath: '/driver/profile',
            )
          : const RideXBottomNavigation(currentIndex: 1),
      body: FutureBuilder<List<MockTrip>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(key: Key('history-loading')),
            );
          }
          if (snapshot.hasError) {
            return AppErrorView(
              title: 'Trips could not be loaded',
              message: 'Check your connection and try again.',
              onRetry: _reload,
            );
          }
          final trips = snapshot.data ?? const <MockTrip>[];
          if (isDriver) return _DriverHistoryList(trips: trips);
          return _RiderHistory(
            trips: trips,
            filter: _filter,
            onFilterChanged: (filter) => setState(() => _filter = filter),
          );
        },
      ),
    );
  }
}

class _RiderHistory extends StatelessWidget {
  const _RiderHistory({
    required this.trips,
    required this.filter,
    required this.onFilterChanged,
  });

  final List<MockTrip> trips;
  final _HistoryFilter filter;
  final ValueChanged<_HistoryFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final filtered = trips.where((trip) {
      return switch (filter) {
        _HistoryFilter.all => true,
        _HistoryFilter.completed => trip.status == TripStatus.completed,
        _HistoryFilter.cancelled => _isCancelled(trip.status),
      };
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final option in _HistoryFilter.values) ...[
                ChoiceChip(
                  key: Key('history-filter-${option.name}'),
                  label: Text(_filterLabel(option)),
                  selected: filter == option,
                  onSelected: (_) => onFilterChanged(option),
                ),
                if (option != _HistoryFilter.values.last)
                  const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (trips.isEmpty)
          const Expanded(
            child: AppEmptyView(
              title: 'No rides yet',
              message: 'Completed and cancelled rides will appear here.',
              icon: Icons.route_outlined,
            ),
          )
        else if (filtered.isEmpty)
          Expanded(
            child: AppEmptyView(
              title: 'No ${_filterLabel(filter).toLowerCase()} rides',
              message: 'Choose another filter to see your ride history.',
              icon: Icons.filter_alt_off_outlined,
              actionLabel: 'Show all rides',
              onAction: () => onFilterChanged(_HistoryFilter.all),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              itemCount: filtered.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) =>
                  _RiderHistoryCard(trip: filtered[index]),
            ),
          ),
      ],
    );
  }
}

class _RiderHistoryCard extends StatelessWidget {
  const _RiderHistoryCard({required this.trip});

  final MockTrip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cancelled = _isCancelled(trip.status);
    return Semantics(
      button: true,
      label: 'Open ${trip.status.label} trip from '
          '${trip.booking.pickup?.address ?? 'pickup'} to '
          '${trip.booking.destination?.address ?? 'destination'}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          key: Key('history-trip-${trip.id}'),
          onTap: () => context.push('/history/${trip.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: cancelled
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatHistoryDate(trip.occurredAt),
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      StatusChip(
                        label: cancelled ? 'Cancelled' : 'Completed',
                        tone: cancelled
                            ? StatusChipTone.error
                            : StatusChipTone.success,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    RouteTimeline(
                      compact: true,
                      pickup: RouteTimelineStop(
                        title: trip.booking.pickup?.address ?? 'Pickup',
                      ),
                      destination: RouteTimelineStop(
                        title:
                            trip.booking.destination?.address ?? 'Destination',
                      ),
                    ),
                    const Divider(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cancelled
                                ? '${trip.booking.vehicleType?.name ?? 'Ride'} | No charge'
                                : '${trip.booking.vehicleType?.name ?? 'Ride'} | ${trip.booking.etaMinutes} min',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          formatMoney(trip.finalFare),
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverHistoryList extends StatelessWidget {
  const _DriverHistoryList({required this.trips});

  final List<MockTrip> trips;

  @override
  Widget build(BuildContext context) {
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
                        '${trip.booking.pickup?.address} -> ${trip.booking.destination?.address}',
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
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(
                      label: trip.status.label,
                      color: isCompleted ? AppColors.accent : AppColors.warning,
                    ),
                    Text(
                      '${trip.booking.distanceKm.toStringAsFixed(0)} km | ${trip.booking.etaMinutes} min',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

bool _isCancelled(TripStatus status) =>
    status == TripStatus.cancelledByRider ||
    status == TripStatus.cancelledByDriver;

String _filterLabel(_HistoryFilter filter) => switch (filter) {
      _HistoryFilter.all => 'All',
      _HistoryFilter.completed => 'Completed',
      _HistoryFilter.cancelled => 'Cancelled',
    };

String _formatHistoryDate(DateTime? date) {
  if (date == null) return 'Recent ride';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${date.day} ${months[date.month - 1]} | $hour:$minute $period';
}
