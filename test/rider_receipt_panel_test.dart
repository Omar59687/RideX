import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';
import 'package:ridex/features/rider_payments/presentation/widgets/rider_receipt_panel.dart';

const tripId = '11111111-1111-4111-8111-111111111111';
const paymentId = '22222222-2222-4222-8222-222222222222';

RiderVerifiedReceipt receipt({
  String trip = tripId,
  String payment = paymentId,
}) => RiderVerifiedReceipt(
  receiptId: '33333333-3333-4333-8333-333333333333',
  receiptNumber: 'RDX-EXAMPLE-001',
  tripId: trip,
  paymentId: payment,
  amountPaidFils: 3250,
  currency: 'JOD',
  paymentMethod: PaymentMethod.card,
  issuedAt: DateTime.utc(2026, 11, 19),
);

void main() {
  test('canonical receipt identity must match both Trip and Payment', () {
    expect(
      verifiedReceiptForPayment(
        receipt: receipt(),
        tripId: tripId,
        paymentId: paymentId,
      ),
      isA<RiderReceiptVerified>(),
    );
    expect(
      verifiedReceiptForPayment(
        receipt: receipt(payment: '44444444-4444-4444-8444-444444444444'),
        tripId: tripId,
        paymentId: paymentId,
      ),
      isA<RiderReceiptUnknown>(),
    );
    expect(
      verifiedReceiptForPayment(
        receipt: receipt(trip: '44444444-4444-4444-8444-444444444444'),
        tripId: tripId,
        paymentId: paymentId,
      ),
      isA<RiderReceiptUnknown>(),
    );
    expect(
      verifiedReceiptForPayment(
        receipt: null,
        tripId: tripId,
        paymentId: paymentId,
      ),
      isA<RiderReceiptNotIssued>(),
    );
    expect(
      verifiedReceiptForPayment(
        receipt: receipt(),
        tripId: 'not-a-uuid',
        paymentId: paymentId,
      ),
      isA<RiderReceiptUnknown>(),
    );
  });

  test('unavailable reader cannot return fabricated receipt', () async {
    await expectLater(
      const UnavailableRiderReceiptReader().readReceipt(
        tripId: tripId,
        paymentId: paymentId,
      ),
      throwsA(isA<RiderReceiptUnavailableException>()),
    );
  });

  testWidgets('unknown and absent receipts never show receipt number', (tester) async {
    for (final state in <RiderReceiptState>[
      const RiderReceiptUnavailable(),
      const RiderReceiptUnknown(),
      const RiderReceiptNotIssued(),
      const RiderReceiptReadError(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RiderReceiptPanel(state: state))),
      );
      expect(find.byKey(const ValueKey('rider-verified-receipt-number')), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('verified receipt is distinct from payment status', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RiderReceiptPanel(state: RiderReceiptVerified(receipt())),
        ),
      ),
    );
    expect(find.text('Verified receipt is available.'), findsOneWidget);
    expect(find.text('Receipt: RDX-EXAMPLE-001'), findsOneWidget);
    expect(find.textContaining('paid'), findsNothing);
  });

  testWidgets('retry is read-only, explicit, and not shown for unavailable', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RiderReceiptPanel(
            state: const RiderReceiptUnknown(),
            onRecheck: () => calls++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('rider-receipt-recheck')));
    expect(calls, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RiderReceiptPanel(
            state: const RiderReceiptUnavailable(),
            onRecheck: () => calls++,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('rider-receipt-recheck')), findsNothing);
  });
}
