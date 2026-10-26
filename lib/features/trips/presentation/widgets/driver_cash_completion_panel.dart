import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/providers/driver_cash_completion_providers.dart';
import 'package:ridex/features/trips/application/driver_cash_completion_controller.dart';
import 'package:ridex/features/trips/application/driver_cash_recovery_controller.dart';

/// Canonical-screen panel. Intentionally not mounted on the MockTrip
/// route. Accepts no Trip ID/version/key or caller-supplied success evidence.
class DriverCashCompletionPanel extends ConsumerWidget {
  const DriverCashCompletionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(driverCashCompletionProvider);
    // Recovery is a separate notifier: its startup/resume/explicit read results
    // must rebuild the panel even when completion state has not changed.
    if (controller != null) {
      return ListenableBuilder(
        listenable: controller.recovery,
        builder: (context, _) => _content(controller),
      );
    }
    return _content(null);
  }

  Widget _content(DriverCashCompletionController? controller) {
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
    final recovery = controller?.recovery;
    final recoveryText = switch (recovery?.state) {
      null => 'Cash recovery is unavailable.',
      DriverCashRecoveryState.noPendingRecovery => 'No pending recovery.',
      DriverCashRecoveryState.checkingCanonicalTrip =>
        'Checking canonical Trip status.',
      DriverCashRecoveryState.completionVerifiedReceiptVerified =>
        'Trip completion verified. Receipt verified.',
      DriverCashRecoveryState.completionVerifiedReceiptUnverified =>
        'Trip completion verified. Receipt not verified; reconciliation required.',
      DriverCashRecoveryState.completionNotVisible =>
        'Completion is not visible. Outcome remains unresolved.',
      DriverCashRecoveryState.additionalPendingRecovery =>
        'Additional recovery records remain. Reconcile again to continue.',
      DriverCashRecoveryState.outcomeUnknown =>
        'Outcome unknown. Do not retry completion.',
      DriverCashRecoveryState.authorizationRevoked =>
        'Driver authorization changed. Recovery is unavailable.',
      DriverCashRecoveryState.journalCorruptedOrUnavailable =>
        'Recovery record is unavailable or invalid. Contact support.',
      DriverCashRecoveryState.networkReadFailure =>
        'Could not read canonical Trip or receipt evidence. Try reconciliation later.',
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
      const Divider(),
      Text(recoveryText, key: const ValueKey('canonical-cash-recovery-status')),
      if (recovery != null)
        TextButton(
            onPressed: recovery.reconcile,
            child: const Text('Reconcile Cash completion')),
    ]);
  }
}
