import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_empty_view.dart';
import 'package:ridex/core/widgets/app_error_view.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/route_timeline.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class TripDetailsScreen extends ConsumerStatefulWidget {
  const TripDetailsScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends ConsumerState<TripDetailsScreen> {
  late Future<MockTrip?> _trip;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _trip = ref.read(tripsRepositoryProvider).getTripById(widget.tripId);
  }

  void _retry() {
    setState(_load);
  }

  void _rebook(MockTrip trip) {
    final pickup = trip.booking.pickup;
    final destination = trip.booking.destination;
    if (pickup == null || destination == null) return;
    final booking = ref.read(bookingControllerProvider.notifier);
    booking.setPickup(pickup);
    booking.setDestination(destination);
    context.go('/rider/vehicle');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Trip receipt',
      body: FutureBuilder<MockTrip?>(
        future: _trip,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(key: Key('details-loading')),
            );
          }
          if (snapshot.hasError) {
            return AppErrorView(
              title: 'Trip details could not be loaded',
              message: 'Check your connection and try again.',
              onRetry: _retry,
            );
          }
          final trip = snapshot.data;
          if (trip == null) {
            return AppEmptyView(
              title: 'Trip not found',
              message: 'This trip is no longer available in your history.',
              icon: Icons.receipt_long_outlined,
              actionLabel: 'Back to ride history',
              onAction: () => context.go('/history'),
            );
          }
          return _TripReceipt(
            trip: trip,
            onRebook: () => _rebook(trip),
          );
        },
      ),
    );
  }
}

class _TripReceipt extends StatelessWidget {
  const _TripReceipt({required this.trip, required this.onRebook});

  final MockTrip trip;
  final VoidCallback onRebook;

  bool get _cancelled =>
      trip.status == TripStatus.cancelledByRider ||
      trip.status == TripStatus.cancelledByDriver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickup = trip.booking.pickup?.address ?? 'Pickup';
    final destination = trip.booking.destination?.address ?? 'Destination';
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MapPlaceholder(
            height: 220,
            showCars: false,
            semanticLabel: _cancelled
                ? 'Stylized map of the requested route from $pickup to $destination'
                : 'Stylized map of the completed route from $pickup to $destination',
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StatusChip(
                              label:
                                  _cancelled ? trip.status.label : 'Completed',
                              tone: _cancelled
                                  ? StatusChipTone.error
                                  : StatusChipTone.success,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              _formatReceiptDate(trip.occurredAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        formatMoney(trip.finalFare),
                        style: theme.textTheme.headlineSmall,
                      ),
                    ],
                  ),
                  const Divider(height: AppSpacing.xl),
                  RouteTimeline(
                    pickup: RouteTimelineStop(
                      title: pickup,
                      subtitle: 'Pickup',
                    ),
                    destination: RouteTimelineStop(
                      title: destination,
                      subtitle:
                          _cancelled ? 'Requested destination' : 'Drop-off',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!_cancelled) ...[
            const _SectionTitle('Driver & vehicle'),
            const SizedBox(height: AppSpacing.sm),
            _HistoricalDriverCard(trip: trip),
            const SizedBox(height: AppSpacing.lg),
            const _SectionTitle('Fare breakdown'),
            const SizedBox(height: AppSpacing.sm),
            _CompletedFareCard(trip: trip),
          ] else ...[
            const _SectionTitle('Cancellation summary'),
            const SizedBox(height: AppSpacing.sm),
            _CancelledFareCard(trip: trip),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const Key('rebook-route'),
            label: 'Book this route again',
            icon: Icons.refresh_rounded,
            onPressed:
                trip.booking.pickup != null && trip.booking.destination != null
                    ? onRebook
                    : null,
          ),
        ],
      ),
    );
  }
}

class _HistoricalDriverCard extends StatelessWidget {
  const _HistoricalDriverCard({required this.trip});

  final MockTrip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: const Icon(Icons.person_rounded),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trip.driver.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${trip.driver.vehicleName} | ${trip.driver.plate}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.star_rounded, size: 18),
            const SizedBox(width: AppSpacing.xxs),
            Text('${trip.driver.rating}', style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _CompletedFareCard extends StatelessWidget {
  const _CompletedFareCard({required this.trip});

  final MockTrip trip;

  @override
  Widget build(BuildContext context) {
    final baseFare = trip.finalFare.clamp(0, 1.2).toDouble();
    final distanceAndTime = trip.finalFare - baseFare;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            _ReceiptLine(label: 'Base fare', value: formatMoney(baseFare)),
            _ReceiptLine(
              label: 'Distance & time',
              value: formatMoney(distanceAndTime),
            ),
            _ReceiptLine(label: 'Promotion', value: formatMoney(0)),
            const Divider(height: AppSpacing.lg),
            _ReceiptLine(
              label: 'Demo payment record | Visa 2048',
              value: formatMoney(trip.finalFare),
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelledFareCard extends StatelessWidget {
  const _CancelledFareCard({required this.trip});

  final MockTrip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReceiptLine(
              label: 'Total charged',
              value: formatMoney(trip.finalFare),
              emphasized: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No driver, payment, or cancellation fee is recorded for this request.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: AppSpacing.sm),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleLarge);
  }
}

String _formatReceiptDate(DateTime? date) {
  if (date == null) return 'Date unavailable';
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
