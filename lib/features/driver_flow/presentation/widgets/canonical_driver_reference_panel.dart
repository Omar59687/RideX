import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/canonical_driver_repository.dart';
import '../providers/canonical_driver_presentation_controller.dart';

/// Unmounted reference-only panel. Session-owned provider survives panel removal;
/// this widget never constructs a repository, delivery source, intent or token.
class CanonicalDriverReferencePanel extends ConsumerStatefulWidget {
  const CanonicalDriverReferencePanel({super.key});
  @override
  ConsumerState<CanonicalDriverReferencePanel> createState() =>
      _CanonicalDriverReferencePanelState();
}

class _CanonicalDriverReferencePanelState
    extends ConsumerState<CanonicalDriverReferencePanel> {
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(driverCanonicalPresentationProvider)?.tick();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(driverCanonicalPresentationProvider);
    final view = controller?.view;
    final offer = view?.offer, trip = view?.trip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Canonical Driver references',
            style: Theme.of(context).textTheme.titleLarge),
        Text(_message(view?.phase),
            key: const ValueKey('canonical-driver-status')),
        if (offer != null) ...[
          Text('Offer ID: ${offer.id}'),
          Text('Offer version: ${offer.version}'),
          Text('Booking ID: ${offer.bookingId}'),
          Text('Quote ID: ${offer.quoteId}'),
          Text('Vehicle ID: ${offer.vehicleId}'),
        ],
        if (trip != null) ...[
          Text('Trip ID: ${trip.id}'),
          Text('Trip version: ${trip.version}'),
          Text('Trip status: ${trip.status.backendValue}'),
          Text('Booking ID: ${trip.bookingId}'),
          Text('Quote ID: ${trip.quoteId}'),
          Text('Vehicle ID: ${trip.vehicleId}'),
        ],
        const Text('Fare unavailable. Route unavailable.'),
        const Text('Rider details unavailable. Vehicle details unavailable.'),
        const Text(
            'Reference preview only. Live integration acceptance is pending.'),
        Wrap(spacing: 12, children: [
          FilledButton(
              onPressed: view?.canDecide == true
                  ? () => unawaited(
                      controller!.decide(view!, CanonicalOfferDecision.accept))
                  : null,
              child: const Text('Accept canonical offer')),
          OutlinedButton(
              onPressed: view?.canDecide == true
                  ? () => unawaited(
                      controller!.decide(view!, CanonicalOfferDecision.decline))
                  : null,
              child: const Text('Decline canonical offer')),
          OutlinedButton(
              onPressed: view?.canReconcile == true
                  ? () => unawaited(controller!.reconcile())
                  : null,
              child: const Text('Check original outcome')),
          const OutlinedButton(
              onPressed: null, child: Text('Completion unavailable')),
        ]),
        if (view != null) Text(view.completionGate.explanation),
      ],
    );
  }
}

String _message(CanonicalDriverPresentationPhase? phase) => switch (phase) {
      null ||
      CanonicalDriverPresentationPhase.disabled =>
        'Canonical presentation is disabled.',
      CanonicalDriverPresentationPhase.missingDelivery =>
        'Delivery source unavailable.',
      CanonicalDriverPresentationPhase.disconnected =>
        'Source disconnected. References hidden.',
      CanonicalDriverPresentationPhase.loading =>
        'Verifying canonical references.',
      CanonicalDriverPresentationPhase.empty => 'No verified offer or Trip.',
      CanonicalDriverPresentationPhase.offer =>
        'Canonical offer reference verified.',
      CanonicalDriverPresentationPhase.expired =>
        'Offer expired. Actions unavailable.',
      CanonicalDriverPresentationPhase.trip =>
        'Canonical Trip reference verified.',
      CanonicalDriverPresentationPhase.declined => 'Canonical offer declined.',
      CanonicalDriverPresentationPhase.pending => 'Checking original decision.',
      CanonicalDriverPresentationPhase.unknown =>
        'Outcome unknown. No automatic replay.',
      CanonicalDriverPresentationPhase.stale =>
        'References stale. Actions unavailable.',
      CanonicalDriverPresentationPhase.unavailable =>
        'Canonical references unavailable.',
      CanonicalDriverPresentationPhase.unauthorized =>
        'Driver authorization unavailable. References hidden.',
    };
