import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import '../providers/driver_incoming_offer_controller.dart';

class DriverIncomingOfferScreen extends ConsumerStatefulWidget {
  const DriverIncomingOfferScreen({super.key});
  @override
  ConsumerState<DriverIncomingOfferScreen> createState() =>
      _DriverIncomingOfferScreenState();
}

class _DriverIncomingOfferScreenState
    extends ConsumerState<DriverIncomingOfferScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The first frame uses a pure time projection below. Persist its expiry latch
    // only after the frame, when Riverpod mutations are safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(driverIncomingOfferProvider.notifier).updateTime();
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(driverIncomingOfferProvider.notifier).updateTime();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(driverIncomingOfferProvider.notifier).updateTime();
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final observed = ref.watch(driverIncomingOfferProvider);
    final view = ref
        .read(driverIncomingOfferProvider.notifier)
        .viewAtCurrentTime(observed);
    final offer = view.offer;
    final journey = offer?.journey;
    final message = switch (view.status) {
      IncomingOfferStatus.loading => 'Loading incoming requests',
      IncomingOfferStatus.empty => 'No available offer',
      IncomingOfferStatus.offer => 'Incoming offer',
      IncomingOfferStatus.replaced =>
        'A different offer replaced the previous request',
      IncomingOfferStatus.stale =>
        'Offer changed or is stale. Review status again.',
      IncomingOfferStatus.expired => 'Offer expired',
      IncomingOfferStatus.pending =>
        'Acceptance observation pending. No assignment confirmed.',
      IncomingOfferStatus.unknown =>
        'Acceptance outcome unknown. No assignment confirmed.',
      IncomingOfferStatus.unauthorized =>
        'Access ended. Offer details are hidden.',
      IncomingOfferStatus.unavailable =>
        'Requests unavailable. Local preview is not configured or could not be read.',
    };
    return AppScaffold(
        title: 'Incoming requests preview',
        body: ListView(children: [
          const Text('Local demonstration only',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Text(
              'Simulated offers do not confirm a real assignment or payment.'),
          const SizedBox(height: 20),
          Semantics(
              liveRegion: true,
              child:
                  Text(message, style: Theme.of(context).textTheme.titleLarge)),
          if (view.status == IncomingOfferStatus.loading)
            const LinearProgressIndicator(),
          if (offer != null && journey != null) ...[
            const SizedBox(height: 16),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pickup: ${journey.pickup.label}'),
                          if (journey.pickup.address.isNotEmpty)
                            Text(journey.pickup.address),
                          for (var i = 0; i < journey.stops.length; i++)
                            Text('Stop ${i + 1}: ${journey.stops[i].label}'),
                          Text('Destination: ${journey.destination.label}'),
                          if (journey.destination.address.isNotEmpty)
                            Text(journey.destination.address),
                          const Divider(),
                          Text(
                              'Route: ${(journey.distanceMeters / 1000).toStringAsFixed(2)} km / ${journey.durationSeconds} seconds'),
                          Text(
                              'Locked Cash fare: JOD ${journey.lockedFareFils ~/ 1000}.${(journey.lockedFareFils % 1000).toString().padLeft(3, '0')}',
                              style: Theme.of(context).textTheme.headlineSmall),
                          Text(
                              'Vehicle: ${journey.vehicleLabel} (${journey.vehicleId})'),
                          Text(
                              'Expires: ${offer.expiresAt.toIso8601String()} (UTC)'),
                          Text('Remaining: ${view.remainingSeconds} seconds'),
                        ]))),
          ],
          const SizedBox(height: 16),
          const Wrap(spacing: 12, children: [
            OutlinedButton(onPressed: null, child: Text('Decline unavailable')),
            FilledButton(onPressed: null, child: Text('Accept unavailable')),
          ]),
          const Text('Offer actions are disabled in this local preview.'),
          TextButton(
              onPressed: view.status == IncomingOfferStatus.unauthorized
                  ? null
                  : ref.read(driverIncomingOfferProvider.notifier).refresh,
              child: const Text('Check status')),
        ]));
  }
}
