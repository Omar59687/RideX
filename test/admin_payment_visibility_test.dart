import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_card.dart';

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
}

class _TestHarness extends StatelessWidget {
  const _TestHarness({required this.payment});

  final AdminSanitizedPayment payment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: AdminSanitizedPaymentCard(payment: payment));
  }
}
