import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import '../providers/driver_availability_controller.dart';

class DriverAvailabilityScreen extends ConsumerWidget {
  const DriverAvailabilityScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(driverAvailabilityControllerProvider);
    final controller = ref.read(driverAvailabilityControllerProvider.notifier);
    final scope = ref.watch(driverAvailabilityScopeProvider);
    final configured = scope != null && scope.vehicleId.trim().isNotEmpty;
    final online =
        view.availability?.state == DriverAvailabilityState.available;
    final label = switch (view.availability?.state) {
      DriverAvailabilityState.offline => 'Offline',
      DriverAvailabilityState.available => 'Online',
      DriverAvailabilityState.reserved => 'Reserved',
      DriverAvailabilityState.onTrip => 'On trip',
      null => 'No availability observed',
    };
    final message = switch (view.phase) {
      DriverFlowPhase.loading => 'Loading availability?',
      DriverFlowPhase.pending =>
        'Changing availability? Last observed status is shown.',
      DriverFlowPhase.unauthorized =>
        'Access ended. Availability controls are disabled.',
      DriverFlowPhase.unavailable =>
        'Availability is unavailable. Check again when the local preview is configured.',
      DriverFlowPhase.stale =>
        'Availability changed. Read the latest state before trying again.',
      DriverFlowPhase.unknown =>
        'Change outcome is unknown. Check status; do not repeat the change.',
      DriverFlowPhase.completionBlocked => 'Availability changes are blocked.',
      DriverFlowPhase.ready => view.availability?.state ==
                  DriverAvailabilityState.reserved ||
              view.availability?.state == DriverAvailabilityState.onTrip
          ? 'Matching or trip services control this state. Changes are disabled.'
          : 'Choose whether to receive requests in this local preview.',
    };
    return Scaffold(
        appBar: AppBar(title: const Text('Availability preview')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Local demonstration only',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'This preview does not confirm backend Online status or change GPS sharing.'),
          const SizedBox(height: 24),
          Semantics(
              liveRegion: true,
              child: Text(label,
                  key: const ValueKey('availability-observed'),
                  style: Theme.of(context).textTheme.headlineMedium)),
          const SizedBox(height: 12),
          Text(message),
          if (view.reading ||
              view.changing ||
              (view.phase == DriverFlowPhase.loading ||
                  view.phase == DriverFlowPhase.pending))
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator()),
          SwitchListTile(
              key: const ValueKey('availability-switch'),
              title: const Text('Receive requests in local preview'),
              subtitle: const Text('Online / Offline'),
              value: online,
              onChanged:
                  configured && view.canChange ? controller.setOnline : null),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              key: const ValueKey('availability-refresh'),
              onPressed:
                  configured && view.canRefresh ? controller.refresh : null,
              icon: const Icon(Icons.refresh),
              label: const Text('Check status')),
        ])));
  }
}
