import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';
import 'package:ridex/features/rider_payments/presentation/widgets/rider_checkout_panel.dart';

void main() {
  testWidgets('action-required state makes no live Card action available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RiderCheckoutPanel(
            state: RiderCheckoutState(
              trip: RiderCheckoutTripEligible(
                RiderCheckoutTrip(
                  tripId: 'a1b2c3d4-e5f6-4a1b-8c2d-a1b2c3d4e5f6',
                  bookingRequestId: '22222222-2222-4222-8222-222222222222',
                  riderId: '33333333-3333-4333-8333-333333333333',
                  driverId: '44444444-4444-4444-8444-444444444444',
                  version: 4,
                  status: DriverTripLifecycleStatus.accepted,
                  paymentMethod: PaymentMethod.card,
                ),
              ),
              payment: const RiderCheckoutActionRequired(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Assigned Trip verified for Card checkout.'),
      findsOneWidget,
    );
    expect(
      find.text('Card checkout is required but not available in this build.'),
      findsOneWidget,
    );
    expect(find.byType(ElevatedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown Payment is not presented as paid or failed', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RiderCheckoutPanel(
            state: RiderCheckoutState(
              trip: RiderCheckoutTripUnavailable(),
              payment: RiderCheckoutPaymentUnknown(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('outcome is unknown'), findsOneWidget);
    expect(find.textContaining('paid'), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
  });

  testWidgets('payment lifecycle states have distinct verified copy', (
    tester,
  ) async {
    final payment = CardPayment(
      paymentId: '55555555-5555-4555-8555-555555555555',
      bookingRequestId: '22222222-2222-4222-8222-222222222222',
      tripId: 'a1b2c3d4-e5f6-4a1b-8c2d-a1b2c3d4e5f6',
      amountFils: 7450,
      status: CardPaymentStatus.cardPaymentPending,
      version: 2,
    );
    final cases = <(RiderCheckoutPaymentState, String)>[
      (
        RiderCheckoutPaymentPending(payment),
        'Payment is pending; it is not confirmed.',
      ),
      (
        RiderCheckoutAuthorized(payment),
        'Card authorization is verified; capture is separate.',
      ),
      (
        RiderCheckoutCaptured(payment),
        'Captured status was read from the payment record.',
      ),
      (RiderCheckoutPaymentFailed(payment), 'Card payment failed.'),
      (RiderCheckoutPaymentCancelled(payment), 'Card payment was cancelled.'),
      (RiderCheckoutRefundPending(payment), 'Refund is pending.'),
      (RiderCheckoutRefunded(payment), 'Refund status is verified.'),
      (
        const RiderCheckoutPaymentReadError(
          RiderCheckoutPaymentReadFailure.unavailable,
        ),
        'Payment status could not be read.',
      ),
    ];

    for (final (state, expectedText) in cases) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: RiderCheckoutPanel(
              state: RiderCheckoutState(
                trip: const RiderCheckoutTripUnavailable(),
                payment: state,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(expectedText), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('canonical read failure exposes accessible retry action', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RiderCheckoutPanel(
            state: const RiderCheckoutState(
              trip: RiderCheckoutTripUnavailable(),
              payment: RiderCheckoutPaymentReadError(
                RiderCheckoutPaymentReadFailure.unavailable,
              ),
            ),
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('rider-checkout-retry')));

    expect(retries, 1);
    expect(find.text('Recheck status'), findsOneWidget);
  });
  testWidgets('receipt section is opt-in and never inferred from payment', (
    tester,
  ) async {
    final payment = CardPayment(
      paymentId: '55555555-5555-4555-8555-555555555555',
      bookingRequestId: '22222222-2222-4222-8222-222222222222',
      tripId: 'a1b2c3d4-e5f6-4a1b-8c2d-a1b2c3d4e5f6',
      amountFils: 7450,
      status: CardPaymentStatus.cardPaymentSucceeded,
      version: 2,
    );
    final state = RiderCheckoutState(
      trip: const RiderCheckoutTripUnavailable(),
      payment: RiderCheckoutCaptured(payment),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RiderCheckoutPanel(state: state))),
    );
    expect(find.text('Receipt'), findsNothing);
    expect(find.text('Verified receipt is available.'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RiderCheckoutPanel(
            state: state,
            receiptState: const RiderReceiptUnknown(),
          ),
        ),
      ),
    );
    expect(find.text('Receipt'), findsOneWidget);
    expect(find.textContaining('Receipt outcome is unknown'), findsOneWidget);
    expect(find.text('Verified receipt is available.'), findsNothing);
    expect(find.byKey(const ValueKey('rider-verified-receipt-number')), findsNothing);
  });

}
