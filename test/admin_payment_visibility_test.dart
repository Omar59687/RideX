import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/repositories/card_payment_repository.dart';
import 'package:ridex/core/repositories/payment_repository.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_card.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_mapper.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    AdminSanitizedPayment payment,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: _TestHarness(payment: payment)),
    );
    await tester.pump();
  }

  testWidgets('displays sanitized cash-payment information', (tester) async {
    await pumpCard(
      tester,
      const AdminSanitizedPayment(
        methodLabel: 'Cash',
        statusLabel: 'Selected',
        amountDisplay: '4.200',
        currencyDisplay: 'JOD',
      ),
    );

    expect(find.byType(AdminSanitizedPaymentCard), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-payment-method')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-payment-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-payment-amount')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-payment-currency')),
      findsOneWidget,
    );
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('4.200'), findsOneWidget);
    expect(find.text('JOD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders unavailable values safely', (tester) async {
    await pumpCard(tester, const AdminSanitizedPayment());

    expect(
      find.text(AdminSanitizedPaymentCard.unavailableLabel),
      findsNWidgets(4),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('treats blank strings as unavailable', (tester) async {
    await pumpCard(
      tester,
      const AdminSanitizedPayment(
        methodLabel: '  ',
        statusLabel: '',
        amountDisplay: '4.200',
        currencyDisplay: 'JOD',
      ),
    );

    expect(
      find.text(AdminSanitizedPaymentCard.unavailableLabel),
      findsNWidgets(2),
    );
    expect(find.text('4.200'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes no mutation controls or navigation', (tester) async {
    await pumpCard(
      tester,
      const AdminSanitizedPayment(
        methodLabel: 'Cash',
        statusLabel: 'Paid',
        amountDisplay: '4.200',
        currencyDisplay: 'JOD',
      ),
    );

    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders no sensitive payment strings', (tester) async {
    await pumpCard(
      tester,
      const AdminSanitizedPayment(
        methodLabel: 'Cash',
        statusLabel: 'Paid',
        amountDisplay: '4.200',
        currencyDisplay: 'JOD',
      ),
    );

    for (final canary in [
      '4242424242424242',
      'sk_test',
      'card number',
      'raw payload',
      'service_role',
    ]) {
      expect(find.textContaining(canary, findRichText: true), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('mapped cashSelected is not shown as paid', (tester) async {
    final payment = CashPayment(
      amountFils: 4200,
      status: CashPaymentStatus.cashSelected,
      version: 1,
    );
    await pumpCard(tester, mapCashPaymentForAdmin(payment));

    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Selected (unpaid)'), findsOneWidget);
    expect(find.text('JOD 4.20'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
    expect(
      find.byKey(const ValueKey('admin-payment-card-brand')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('admin-payment-card-last4')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mapped card shows brand and masked last four', (tester) async {
    final payment = CardPayment(
      amountFils: 1990,
      status: CardPaymentStatus.cardPaymentSucceeded,
      version: 1,
      cardBrand: 'Visa',
      cardLastFour: '4242',
    );
    await pumpCard(tester, mapCardPaymentForAdmin(payment));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin-payment-method')),
        matching: find.text('Card'),
      ),
      findsOneWidget,
    );
    expect(find.text('Succeeded'), findsOneWidget);
    expect(find.text('JOD 1.99'), findsOneWidget);
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('•••• 4242'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-payment-card-brand')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('admin-payment-card-last4')),
      findsOneWidget,
    );
    expect(find.textContaining('4242424242424242'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mapped card without metadata omits card rows', (tester) async {
    final payment = CardPayment(
      amountFils: 1990,
      status: CardPaymentStatus.cardPaymentPending,
      version: 1,
    );
    await pumpCard(tester, mapCardPaymentForAdmin(payment));

    expect(find.text('Pending'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-payment-card-brand')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('admin-payment-card-last4')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('repository-backed payments render without identifiers',
      (tester) async {
    final cashRepository = FakePaymentRepository()
      ..seedCashPayment(
        CashPayment(
          paymentId: 'pay-cash-9',
          bookingRequestId: 'booking-9',
          tripId: 'trip-9',
          amountFils: 2500,
          status: CashPaymentStatus.paid,
          version: 4,
          idempotencyKey: 'idem-cash-9',
        ),
      );
    final cardRepository = FakeCardPaymentRepository()
      ..seedCardPayment(
        CardPayment(
          paymentId: 'pay-card-9',
          bookingRequestId: 'booking-8',
          tripId: 'trip-8',
          amountFils: 3100,
          status: CardPaymentStatus.refunded,
          version: 5,
          idempotencyKey: 'idem-card-9',
          cardBrand: 'Mastercard',
          cardLastFour: '5555',
        ),
      );

    final cash = mapCashPaymentForAdmin(
      await cashRepository.readCashPayment(paymentId: 'pay-cash-9'),
    );
    await pumpCard(tester, cash);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('JOD 2.50'), findsOneWidget);

    final card = mapCardPaymentForAdmin(
      await cardRepository.readCardPayment(paymentId: 'pay-card-9'),
    );
    await pumpCard(tester, card);
    expect(find.text('Refunded'), findsOneWidget);
    expect(find.text('Mastercard'), findsOneWidget);
    expect(find.text('•••• 5555'), findsOneWidget);

    for (final secret in [
      'pay-cash-9',
      'pay-card-9',
      'booking-9',
      'booking-8',
      'trip-9',
      'trip-8',
      'idem-cash-9',
      'idem-card-9',
    ]) {
      expect(find.textContaining(secret), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}

class _TestHarness extends StatelessWidget {
  const _TestHarness({required this.payment});

  final AdminSanitizedPayment payment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: AdminSanitizedPaymentCard(payment: payment));
  }
}
