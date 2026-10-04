import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/route_providers.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/fare_summary_card.dart';
import 'package:ridex/core/widgets/route_timeline.dart';
import 'package:ridex/core/widgets/route_status_panel.dart';
import 'package:ridex/core/widgets/vehicle_silhouette.dart';
import 'package:ridex/core/widgets/google_maps_attribution.dart';

/// Provisional backend vehicle-type codes (`public.vehicle_type_code`).
///
/// The local demo catalogue uses `economy`/`standard`/`premium`; the backend
/// contract uses `economy`/`comfort`/`xl`. Unknown ids pass through and the
/// backend rejects them honestly.
String _backendVehicleTypeCode(String id) {
  return switch (id) {
    'economy' => 'economy',
    'standard' => 'comfort',
    'premium' => 'xl',
    _ => id,
  };
}

/// The draft carries no payment selection yet; the screen displays `Cash`,
/// so draft persistence sends `cash` to match what is shown.
const _displayedPaymentMethod = 'cash';

String _fareFailureMessage(FareFailure failure) {
  return switch (failure) {
    FareFailure.versionConflict => 'The booking changed. Request a new fare.',
    FareFailure.notFound => 'The booking draft was not found.',
    FareFailure.pricingUnavailable => 'Fares are unavailable right now.',
    FareFailure.unauthorized ||
    FareFailure.forbidden =>
      'Sign in again to see fares.',
    FareFailure.timedOut => 'The fare request timed out.',
    FareFailure.networkFailure => 'Could not reach the fare service.',
    FareFailure.expired => 'This fare quote expired. Request a new fare.',
    FareFailure.unavailable ||
    FareFailure.invalidResponse =>
      'Fares are unavailable right now.',
  };
}

String _expiryLabel(DateTime expiresAt) {
  final local = expiresAt.toLocal();
  final hours = local.hour.toString().padLeft(2, '0');
  final minutes = local.minute.toString().padLeft(2, '0');
  return '$hours:$minutes';
}

class FareEstimateScreen extends ConsumerStatefulWidget {
  const FareEstimateScreen({super.key});

  @override
  ConsumerState<FareEstimateScreen> createState() => _FareEstimateScreenState();
}

class _FareEstimateScreenState extends ConsumerState<FareEstimateScreen> {
  FareBookingRef? _booking;
  FareQuote? _quote;
  FareFailure? _failure;
  bool _loading = false;
  String _requestKey = '';

  String _quoteKey(BookingDraft draft, RouteResult? result) {
    final stops = [
      for (final stop in draft.stops)
        '${stop.point.latitude},${stop.point.longitude},${stop.label}',
    ].join(';');
    return [
      draft.pickup?.point.latitude,
      draft.pickup?.point.longitude,
      draft.pickup?.label,
      draft.destination?.point.latitude,
      draft.destination?.point.longitude,
      draft.destination?.label,
      stops,
      draft.vehicleType?.id,
      _displayedPaymentMethod,
      result?.distanceMeters,
      result?.durationSeconds,
    ].join('|');
  }

  FareRouteLocation _fareLocation(RideLocation location) {
    return FareRouteLocation(
      latitude: location.point.latitude,
      longitude: location.point.longitude,
      label: location.label.trim().isEmpty ? null : location.label.trim(),
    );
  }

  Future<void> _refresh() async {
    if (_loading || !mounted) return;
    final draft = ref.read(bookingControllerProvider);
    final route = ref.read(routeControllerProvider);
    final result = route.resultFor(draft);
    final vehicle = draft.vehicleType;
    if (result == null || vehicle == null) return;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final repository = ref.read(fareRepositoryProvider);
      final pickup = _fareLocation(draft.pickup!);
      final destination = _fareLocation(draft.destination!);
      final stops = [
        for (final stop in draft.stops)
          FareStopInput(location: _fareLocation(stop), label: stop.label),
      ];
      final vehicleTypeCode = _backendVehicleTypeCode(vehicle.id);
      final FareBookingRef booking;
      final current = _booking;
      if (current == null) {
        booking = await repository.createBookingDraft(
          pickup: pickup,
          destination: destination,
          vehicleTypeCode: vehicleTypeCode,
          paymentMethod: _displayedPaymentMethod,
          stops: stops,
        );
      } else {
        // Updating the draft supersedes its `calculated` quotes
        // server-side, so every draft/route change re-quotes below.
        booking = await repository.updateBookingDraft(
          bookingRequestId: current.bookingRequestId,
          expectedBookingVersion: current.version,
          pickup: pickup,
          destination: destination,
          vehicleTypeCode: vehicleTypeCode,
          paymentMethod: _displayedPaymentMethod,
          stops: stops,
        );
      }
      final quote = await repository.fetchQuote(
        bookingRequestId: booking.bookingRequestId,
        expectedBookingVersion: booking.version,
        routeDistanceMeters: result.distanceMeters,
        routeDurationSeconds: result.durationSeconds,
      );
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _quote = quote;
        _failure = null;
        _loading = false;
      });
    } on FareException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error.failure;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingControllerProvider);
    final route = ref.watch(routeControllerProvider);
    final vehicle = draft.vehicleType;
    final rider = ref.watch(sessionControllerProvider).user;
    final repository = ref.watch(fareRepositoryProvider);
    // Demo mode keeps the current deterministic demo fare path; the
    // authoritative backend-quote path below only runs when a real fare
    // repository is configured.
    final isDemo = repository is UnavailableFareRepository;

    final result = route.resultFor(draft);
    final routeReady =
        draft.isRoutingReady && route.isReadyFor(draft) && result != null;

    if (!isDemo && routeReady && vehicle != null) {
      final key = _quoteKey(draft, result);
      if (key != _requestKey && !_loading) {
        _requestKey = key;
        // A changed draft/route invalidates the displayed quote: never show
        // a stale total while the re-quote is in flight.
        _quote = null;
        _failure = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      }
    }

    final demoFare =
        draft.estimatedFare > 0 ? draft.estimatedFare : vehicle?.baseFare ?? 0;
    final now = DateTime.now();
    // Only the quote fetched for the currently displayed draft/route may
    // back the total; anything else is stale and never shown.
    final quote =
        (!isDemo && _requestKey == _quoteKey(draft, result)) ? _quote : null;
    final usableQuote = quote != null && quote.isUsableAt(now) ? quote : null;
    final staleQuote =
        quote != null && usableQuote == null && _failure == null && !_loading;
    final ready = isDemo
        ? draft.isRoutingReady &&
            route.isReadyFor(draft) &&
            vehicle != null &&
            demoFare > 0
        : routeReady && vehicle != null && usableQuote != null;

    return AppScaffold(
      title: 'Review booking',
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.inverseSurface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR ROUTE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Theme(
                  data: Theme.of(context).copyWith(
                    textTheme: Theme.of(context).textTheme.apply(
                          bodyColor:
                              Theme.of(context).colorScheme.onInverseSurface,
                          displayColor:
                              Theme.of(context).colorScheme.onInverseSurface,
                        ),
                  ),
                  child: RouteTimeline(
                    pickup: RouteTimelineStop(
                      title: draft.pickup?.address ?? 'Pickup not selected',
                      subtitle: draft.pickup?.label,
                    ),
                    destination: RouteTimelineStop(
                      title: draft.destination?.address ??
                          'Destination not selected',
                      subtitle: draft.destination?.label,
                    ),
                    stops: [
                      for (final stop in draft.stops)
                        RouteTimelineStop(
                          title: stop.address,
                          subtitle: stop.label,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (draft.pickup?.providerName == 'google' ||
              draft.destination?.providerName == 'google')
            const Align(
              alignment: Alignment.centerRight,
              child: GoogleMapsAttribution(),
            ),
          const SizedBox(height: AppSpacing.xl),
          RouteStatusPanel(
            state: route,
            onRetry: () => ref.read(routeControllerProvider.notifier).retry(),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Ride details', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Row(
                    children: [
                      const VehicleSilhouette(width: 72, height: 42),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle?.name ?? 'No ride selected',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              vehicle == null
                                  ? 'Return to choose a ride'
                                  : 'Arrives in ${vehicle.arrivalMinutes} min · ${vehicle.capacity} passengers',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: AppSpacing.xl),
                  _SummaryRow(
                    label: 'Passenger',
                    value: rider?.name ?? 'Demo rider',
                  ),
                  const _SummaryRow(label: 'Payment', value: 'Cash'),
                  const _SummaryRow(
                    label: 'Location status',
                    value: 'Pickup and destination selected',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isDemo)
            FareSummaryCard(
              title: 'Demo fare',
              total: demoFare,
              note:
                  'Demo fare — a deterministic placeholder, not a backend quote. It stays fixed for the route shown.',
            )
          else if (!routeReady || vehicle == null)
            Text(
              'Select a route and ride to request the authoritative fare.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else if (usableQuote != null)
            _AuthoritativeFareCard(quote: usableQuote)
          else if (staleQuote)
            _ExpiredFareCard(
              onRequote: () {
                _requestKey = _quoteKey(draft, result);
                _quote = null;
                _failure = null;
                unawaited(_refresh());
              },
            )
          else if (_failure != null)
            _FareErrorCard(
              failure: _failure!,
              onRetry: () {
                _requestKey = _quoteKey(draft, result);
                _quote = null;
                _failure = null;
                unawaited(_refresh());
              },
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text('Requesting the authoritative fare…'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Unsupported route changes must be confirmed before requesting a driver.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Confirm & find a driver',
            onPressed: ready
                ? () async {
                    if (isDemo) {
                      await ref
                          .read(bookingControllerProvider.notifier)
                          .estimateFare();
                      if (context.mounted) context.push('/rider/searching');
                      return;
                    }

                    final booking = _booking;
                    final currentQuote = usableQuote;
                    if (booking == null || currentQuote == null) return;
                    setState(() {
                      _loading = true;
                      _failure = null;
                    });
                    try {
                      final locked = await repository.lockQuote(
                        bookingRequestId: booking.bookingRequestId,
                        fareQuoteId: currentQuote.id,
                        expectedBookingVersion: booking.version,
                        expectedQuoteVersion: currentQuote.quoteVersion,
                      );
                      if (!mounted) return;
                      setState(() {
                        _quote = locked;
                        _loading = false;
                      });
                      if (context.mounted) context.push('/rider/searching');
                    } on FareException catch (error) {
                      if (!mounted) return;
                      setState(() {
                        _failure = error.failure;
                        _loading = false;
                      });
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _AuthoritativeFareCard extends StatelessWidget {
  const _AuthoritativeFareCard({required this.quote});

  final FareQuote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breakdown = quote.breakdown;
    return Semantics(
      container: true,
      label: 'Upfront fare, total ${formatFareFils(quote.fixedFareFils)}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Upfront fare', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              _FareFilsRow(
                  label: 'Base fare',
                  value: formatFareFils(breakdown.baseFareFils)),
              const SizedBox(height: AppSpacing.xs),
              _FareFilsRow(
                  label: 'Distance',
                  value: formatFareFils(breakdown.distanceFils)),
              const SizedBox(height: AppSpacing.xs),
              _FareFilsRow(
                  label: 'Duration',
                  value: formatFareFils(breakdown.durationFils)),
              const SizedBox(height: AppSpacing.xs),
              _FareFilsRow(
                  label: 'Stops', value: formatFareFils(breakdown.stopsFils)),
              const SizedBox(height: AppSpacing.xs),
              _FareFilsRow(
                  label: 'Subtotal',
                  value: formatFareFils(breakdown.subtotalFils)),
              Divider(color: theme.colorScheme.outlineVariant),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text('Total', style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    formatFareFils(quote.fixedFareFils),
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Fixed fare · Quote v${quote.quoteVersion} · '
                'Pricing v${quote.pricingVersion} · '
                'Expires ${_expiryLabel(quote.expiresAt)}'
                '${breakdown.minimumApplied ? ' · Minimum fare applied' : ''} · '
                'Rounded to the nearest ${breakdown.roundingIncrementFils} fils.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpiredFareCard extends StatelessWidget {
  const _ExpiredFareCard({required this.onRequote});

  final VoidCallback onRequote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fare quote expired', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'This quote is no longer valid, so no total is shown. '
              'Request a new fare to continue.',
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Request a new fare', onPressed: onRequote),
          ],
        ),
      ),
    );
  }
}

class _FareErrorCard extends StatelessWidget {
  const _FareErrorCard({required this.failure, required this.onRetry});

  final FareFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fare unavailable', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(_fareFailureMessage(failure)),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Retry fare request', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _FareFilsRow extends StatelessWidget {
  const _FareFilsRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
