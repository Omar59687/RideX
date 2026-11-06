import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/route_timeline.dart';
import '../../domain/driver_flow_contract.dart';
import '../providers/driver_trip_presentation_controller.dart';

class DriverTripPreviewScreen extends ConsumerStatefulWidget {
  const DriverTripPreviewScreen({super.key});
  @override
  ConsumerState<DriverTripPreviewScreen> createState() =>
      _DriverTripPreviewScreenState();
}

class _DriverTripPreviewScreenState
    extends ConsumerState<DriverTripPreviewScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(driverTripPresentationProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(driverTripPresentationProvider);
    final controller = ref.read(driverTripPresentationProvider.notifier);
    final enabled = ref.watch(driverTripSimulationEnabledProvider);
    final trip = view.trip;
    final session = view.session;
    final next = view.nextStatus;
    final message = switch (view.phase) {
      DriverFlowPhase.loading => 'Loading Trip preview',
      DriverFlowPhase.ready =>
        trip == null ? 'No Trip available' : 'Simulated Trip observation',
      DriverFlowPhase.pending =>
        'Trip observation pending. Actions are unavailable.',
      DriverFlowPhase.unavailable =>
        'Trip preview unavailable. No live integration is configured.',
      DriverFlowPhase.unauthorized => 'Access ended. Trip details are hidden.',
      DriverFlowPhase.stale =>
        'Trip changed or is stale. Actions are unavailable.',
      DriverFlowPhase.unknown =>
        'Trip observation is uncertain. Do not repeat an action.',
      DriverFlowPhase.completionBlocked =>
        'Trip completion is blocked. No financial operation is available.',
    };
    final actionMessage = switch (view.progressStatus) {
      DriverTripProgressStatus.idle ||
      DriverTripProgressStatus.unauthorized =>
        null,
      DriverTripProgressStatus.pending =>
        'Simulated progression pending. No real Trip changed.',
      DriverTripProgressStatus.simulated =>
        'Simulated status observed. No assignment or payment authority.',
      DriverTripProgressStatus.rejected =>
        'Simulated progression rejected. Check status.',
      DriverTripProgressStatus.stale =>
        'Progression target changed. Check status.',
      DriverTripProgressStatus.unknown =>
        'Outcome unknown. Do not repeat the action.',
    };
    return AppScaffold(
        title: 'Local Trip preview',
        // Keep this finite preview's status/access explanations mounted as the
        // stop-gate section increases scroll extent. It owns no local Trip state.
        body: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              const Text('Local demonstration only',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Text(
                  'Simulated Trips never prove backend assignment, payment or receipt issuance.'),
              const SizedBox(height: 20),
              Semantics(
                  liveRegion: true,
                  child: Text(message,
                      style: Theme.of(context).textTheme.titleLarge)),
              if (view.reading || view.phase == DriverFlowPhase.loading)
                const LinearProgressIndicator(),
              if (trip != null) ...[
                const SizedBox(height: 16),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Trip ${trip.id} · version ${trip.version}'),
                              Text('Status: ${_statusLabel(trip.status)}',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              _JourneySummary(journey: trip.journey),
                              const Divider(),
                              Text(
                                  'Locked Cash fare: JOD ${trip.journey.lockedFareFils ~/ 1000}.${(trip.journey.lockedFareFils % 1000).toString().padLeft(3, '0')}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              Text(
                                  'Vehicle: ${trip.journey.vehicleLabel} (${trip.journey.vehicleId})'),
                              Text(
                                  'Recorded route: ${trip.journey.distanceMeters} meters / ${trip.journey.durationSeconds} seconds. Not a live arrival estimate.'),
                            ]))),
                OutlinedButton(
                    onPressed: session != null &&
                            controller.canPreview(trip, session, view.lifetime)
                        ? () {
                            if (!controller.canPreview(
                                trip, session, view.lifetime)) {
                              return;
                            }
                            showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => _RoutePreview(
                                    trip: trip,
                                    session: session,
                                    lifetime: view.lifetime));
                          }
                        : null,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48)),
                    child: const Text('View route preview')),
              ],
              const SizedBox(height: 16),
              if (actionMessage != null)
                Semantics(liveRegion: true, child: Text(actionMessage)),
              if (view.offerBlocked)
                Semantics(
                    liveRegion: true,
                    child: Text(
                        'An offer decision is unresolved. Trip progression is unavailable.')),
              FilledButton(
                  onPressed: enabled &&
                          view.canProgress &&
                          trip != null &&
                          next != null
                      ? () => controller.progress(trip, next,
                          lifetime: view.lifetime)
                      : null,
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(enabled && next != null
                      ? 'Simulate ${_statusLabel(next).toLowerCase()}'
                      : 'Progression unavailable')),
              if (!enabled)
                const Text('Simulated progression is disabled by default.'),
              const Text(
                  'Completion, settlement and receipts are unavailable in this preview.'),
              const SizedBox(height: 16),
              _CompletionStop(gate: view.completionGate),
              if (view.progressStatus == DriverTripProgressStatus.pending ||
                  view.progressStatus == DriverTripProgressStatus.unknown)
                const Text(
                    'Leaving this screen does not cancel or resolve the attempt.'),
              TextButton(
                  onPressed:
                      view.phase == DriverFlowPhase.unauthorized || view.reading
                          ? null
                          : controller.refresh,
                  child: const Text('Check status')),
              const SizedBox(height: 20),
            ])));
  }
}

class _CompletionStop extends StatelessWidget {
  const _CompletionStop({required this.gate});
  final DriverTripCompletionGate gate;

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Cash completion stop gate',
                style: Theme.of(context).textTheme.titleMedium),
            const Text('Simulated progression: local preview only.'),
            const Text('Canonical Trip completion: not verified.'),
            const Text('Cash settlement: not verified.'),
            const Text('Payment confirmation: not verified.'),
            const Text('Receipt issuance: not verified.'),
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(gate.explanation)),
            Text(
                'Required acceptance: ${gate.requiredPhase6Gates.join(', ')}.'),
            const OutlinedButton(
                key: ValueKey('driver-cash-completion-stop'),
                onPressed: null,
                child: Text('Complete Cash Trip unavailable')),
          ])));
}

String _statusLabel(DriverTripLifecycleStatus status) => switch (status) {
      DriverTripLifecycleStatus.accepted => 'Accepted',
      DriverTripLifecycleStatus.driverArriving => 'Driver arriving',
      DriverTripLifecycleStatus.driverArrived => 'Driver arrived',
      DriverTripLifecycleStatus.inProgress => 'In progress',
      DriverTripLifecycleStatus.completed =>
        'Completed (reported; no payment proof)',
      DriverTripLifecycleStatus.cancelledByRider => 'Cancelled by Rider',
      DriverTripLifecycleStatus.cancelledByDriver => 'Cancelled by Driver',
      DriverTripLifecycleStatus.cancelledByAdmin => 'Cancelled by Admin',
      DriverTripLifecycleStatus.failed => 'Failed',
    };

class _JourneySummary extends StatelessWidget {
  const _JourneySummary({required this.journey});
  final DriverFlowJourney journey;
  @override
  Widget build(BuildContext context) => RouteTimeline(
          pickup: RouteTimelineStop(
              title: 'Pickup: ${journey.pickup.label}',
              subtitle: journey.pickup.address),
          destination: RouteTimelineStop(
              title: 'Destination: ${journey.destination.label}',
              subtitle: journey.destination.address),
          stops: [
            for (var i = 0; i < journey.stops.length; i++)
              RouteTimelineStop(
                  title: 'Stop ${i + 1}: ${journey.stops[i].label}',
                  subtitle: journey.stops[i].address)
          ]);
}

/// Captured identity and route context only, never a second Trip-state owner.
class _RoutePreview extends ConsumerWidget {
  const _RoutePreview(
      {required this.trip, required this.session, required this.lifetime});
  final DriverFlowTrip trip;
  final DriverFlowSession session;
  final int lifetime;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(driverTripPresentationProvider);
    final valid = ref
        .read(driverTripPresentationProvider.notifier)
        .canPreview(trip, session, lifetime);
    final route = RouteRequest(
        origin: trip.journey.pickup.point,
        destination: trip.journey.destination.point,
        intermediatePoints: [
          for (final stop in trip.journey.stops) stop.point
        ]);
    final points = [
      route.origin,
      ...route.intermediatePoints,
      route.destination
    ];
    final longitudes = points.map((p) => p.longitude);
    final latitudes = points.map((p) => p.latitude);
    final minX = longitudes.reduce((a, b) => a < b ? a : b);
    final maxX = longitudes.reduce((a, b) => a > b ? a : b);
    final minY = latitudes.reduce((a, b) => a < b ? a : b);
    final maxY = latitudes.reduce((a, b) => a > b ? a : b);
    final normalized = [
      for (final point in points)
        Offset(
            maxX == minX
                ? 0.5
                : 0.15 + 0.7 * (point.longitude - minX) / (maxX - minX),
            maxY == minY
                ? 0.5
                : 0.85 - 0.7 * (point.latitude - minY) / (maxY - minY))
    ];
    return SafeArea(
        child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.8,
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!valid)
                        Semantics(
                            liveRegion: true,
                            child: Text('Route preview is no longer current.'))
                      else ...[
                        Text('Illustrative route preview',
                            style: Theme.of(context).textTheme.titleLarge),
                        Text('Trip ${trip.id} · version ${trip.version}'),
                        const Text(
                            'Schematic connections only. No road routing, GPS or live navigation.'),
                        const SizedBox(height: 12),
                        MapPlaceholder(
                            height: 220,
                            showCars: false,
                            liveState: MapLiveState.idle,
                            routePoints: normalized,
                            markers: [
                              MapMarker(
                                  position: normalized.first,
                                  type: MapMarkerType.pickup),
                              MapMarker(
                                  position: normalized.last,
                                  type: MapMarkerType.destination)
                            ],
                            semanticLabel:
                                'Illustrative pickup, ordered stops and destination; no live tracking'),
                        _JourneySummary(journey: trip.journey),
                      ],
                      TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close route preview')),
                    ]))));
  }
}
