import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import '../../application/driver_completion_handoff_controller.dart';
import '../../domain/driver_completion_handoff.dart';
import '../providers/driver_completion_handoff_provider.dart';

/// Independent financial evidence, never a completion or payment command UI.
class DriverCompletionHandoffPanel extends ConsumerWidget {
  const DriverCompletionHandoffPanel({super.key, this.controller});
  final DriverCompletionHandoffController? controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner =
        controller ?? ref.watch(driverCompletionHandoffProvider.notifier);
    if (owner == null) return const Text('Payment status is unavailable.');
    return AnimatedBuilder(
        animation: owner,
        builder: (context, _) {
          final event = owner.event;
          final tripText = event.tripCompleted
              ? 'Trip completion verified.'
              : event.tripState == DriverHandoffReadState.verified
                  ? 'Trip status: ${event.trip!.status.backendValue}. Completion not confirmed.'
                  : event.tripState == DriverHandoffReadState.unauthorized
                      ? 'Driver session unavailable.'
                      : 'Trip completion not verified.';
          return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tripText, key: const ValueKey('driver-handoff-trip')),
                Text(_paymentText(event),
                    key: const ValueKey('driver-handoff-payment')),
                Text(_receiptText(event),
                    key: const ValueKey('driver-handoff-receipt')),
                const Text(
                    'Trip completion alone does not confirm payment or a receipt.'),
                TextButton(
                    onPressed: owner.canRefresh ? owner.refresh : null,
                    child: const Text('Recheck completion evidence')),
              ]);
        });
  }
}

String _paymentText(DriverCompletionHandoffEvent event) {
  if (event.paymentState == DriverHandoffReadState.verified) {
    return switch (event.payment!) {
      DriverHandoffCashPayment(:final status) => switch (status) {
          CashPaymentStatus.cashSelected => 'Cash settlement pending.',
          CashPaymentStatus.paid => 'Cash settlement verified.',
          CashPaymentStatus.cancelled => 'Cash payment cancelled.',
        },
      DriverHandoffCardPayment(:final status) => switch (status) {
          CardPaymentStatus.cardPaymentPending =>
            'Card payment pending. Capture not verified.',
          CardPaymentStatus.cardPaymentAuthorized =>
            'Card authorized. Capture pending.',
          CardPaymentStatus.cardPaymentSucceeded => 'Card capture verified.',
          CardPaymentStatus.cardPaymentFailed =>
            'Card payment failed. Capture not confirmed.',
          CardPaymentStatus.paymentCancelled => 'Card payment cancelled.',
          CardPaymentStatus.refundPending => 'Refund pending.',
          CardPaymentStatus.refunded => 'Refund verified.',
        },
    };
  }
  return switch (event.paymentState) {
    DriverHandoffReadState.missing => 'Payment record unavailable.',
    DriverHandoffReadState.unknown => 'Payment outcome UNKNOWN. Recheck later.',
    DriverHandoffReadState.error => 'Payment verification failed.',
    DriverHandoffReadState.unauthorized =>
      'Payment read unavailable for this Driver.',
    _ => 'Payment not verified.',
  };
}

String _receiptText(DriverCompletionHandoffEvent event) =>
    switch (event.receiptState) {
      DriverHandoffReadState.verified =>
        'Receipt available: ${event.receipt!.number}',
      DriverHandoffReadState.missing => 'Receipt not available.',
      DriverHandoffReadState.unknown => 'Receipt availability UNKNOWN.',
      DriverHandoffReadState.error => 'Receipt verification failed.',
      _ => 'Receipt availability not verified.',
    };
