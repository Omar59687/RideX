import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
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

    expect(find.text('Assigned Trip verified for Card checkout.'), findsOneWidget);
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

    expect(
      find.textContaining('outcome is unknown'),
      findsOneWidget,
    );
    expect(find.textContaining('paid'), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
  });
}
