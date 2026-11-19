import 'package:flutter/material.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';

/// Accessible, presentation-only B01 checkout status surface.
///
/// There is deliberately no payment action callback: this checkpoint cannot
/// launch a provider or dispatch a financial command. B02 owns the approved
/// provider-neutral handoff seam.
class RiderCheckoutPanel extends StatelessWidget {
  const RiderCheckoutPanel({
    super.key,
    required this.state,
    this.onRetry,
  });

  final RiderCheckoutState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tripMessage = switch (state.trip) {
      RiderCheckoutTripUnavailable() => 'Trip is unavailable.',
      RiderCheckoutTripLoading() => 'Verifying assigned Trip.',
      RiderCheckoutTripEligible() => 'Assigned Trip verified for Card checkout.',
      RiderCheckoutTripIneligible() => 'This Trip is not eligible for Card checkout.',
      RiderCheckoutTripStale() => 'Trip changed; verify its current status.',
      RiderCheckoutTripTerminal() => 'Trip has ended. Checkout is unavailable.',
      RiderCheckoutTripReadError() => 'Trip status could not be verified.',
    };
    final paymentMessage = switch (state.payment) {
      RiderCheckoutPaymentUnavailable() => 'Payment status unavailable.',
      RiderCheckoutPaymentLoading() => 'Loading canonical payment status.',
      RiderCheckoutActionRequired() =>
        'Card checkout is required but not available in this build.',
      RiderCheckoutPaymentPending() => 'Payment is pending; it is not confirmed.',
      RiderCheckoutPaymentUnknown() =>
        'Payment outcome is unknown. Recheck canonical status before any action.',
      RiderCheckoutAuthorized() => 'Card authorization is verified; capture is separate.',
      RiderCheckoutCaptured() => 'Captured status was read from the payment record.',
      RiderCheckoutPaymentFailed() => 'Card payment failed.',
      RiderCheckoutPaymentCancelled() => 'Card payment was cancelled.',
      RiderCheckoutRefundPending() => 'Refund is pending.',
      RiderCheckoutRefunded() => 'Refund status is verified.',
      RiderCheckoutPaymentReadError() => 'Payment status could not be read.',
    };
    final canRetry = onRetry != null &&
        (state.trip is RiderCheckoutTripReadError ||
            state.trip is RiderCheckoutTripStale ||
            state.payment is RiderCheckoutPaymentReadError ||
            state.payment is RiderCheckoutPaymentUnknown);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          label: 'Trip status. $tripMessage',
          child: Text(
            tripMessage,
            key: const ValueKey('rider-checkout-trip-status'),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          label: 'Payment status. $paymentMessage',
          child: Text(
            paymentMessage,
            key: const ValueKey('rider-checkout-payment-status'),
          ),
        ),
        if (canRetry) ...[
          const SizedBox(height: 12),
          AppButton(
            key: const ValueKey('rider-checkout-retry'),
            label: 'Recheck status',
            onPressed: onRetry,
          ),
        ],
      ],
    );
  }
}
