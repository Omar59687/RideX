import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/providers/driver_cash_completion_providers.dart';
import 'package:ridex/features/trips/application/driver_cash_completion_controller.dart';

/// Optional canonical-screen seam. Intentionally not mounted on the MockTrip
/// route. Accepts no Trip ID/version/key or caller-supplied success evidence.
class DriverCashCompletionPanel extends ConsumerWidget {
  const DriverCashCompletionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(driverCashCompletionProvider);
    final state = controller?.state ?? DriverCashCompletionState.unavailable;
    final text = switch (state) {
      DriverCashCompletionState.unavailable =>
        'Canonical Cash completion is unavailable.',
      DriverCashCompletionState.ready => 'Ready to complete',
      DriverCashCompletionState.processing => 'Processing',
      DriverCashCompletionState.completedReceiptVerified =>
        'Trip completed. Receipt verified.',
      DriverCashCompletionState.completedReceiptUnverified =>
        'Trip completed. Receipt unverified; reconciliation required.',
      DriverCashCompletionState.unresolved =>
        'Unresolved - reconciliation required. Do not retry completion.',
      DriverCashCompletionState.authorizationLost =>
        'Authorization lost. Completion is unavailable.',
      DriverCashCompletionState.storageFailure =>
        'Durable storage unavailable. Reconciliation required before another attempt.',
      DriverCashCompletionState.networkFailure =>
        'Network verification unavailable. Reconciliation required before another attempt.',
    };
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(text, key: const ValueKey('canonical-cash-status')),
      if (controller != null && state == DriverCashCompletionState.unavailable)
        TextButton(
            onPressed: controller.prepare,
            child: const Text('Check completion availability')),
      if (controller != null && state == DriverCashCompletionState.ready)
        FilledButton(
            onPressed: controller.complete,
            child: const Text('Complete Cash trip')),
    ]);
  }
}
