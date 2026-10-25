import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/mock_trip.dart' show TripStatus;
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_loading.dart';
import 'package:ridex/features/history/presentation/models/rider_payment_presentation.dart';
import 'package:ridex/features/history/presentation/widgets/rider_payment_record_card.dart';
import 'package:ridex/features/history/presentation/widgets/rider_payment_status_card.dart';

CashPayment _cash({
  CashPaymentStatus status = CashPaymentStatus.cashSelected,
  String? paymentId = 'payment-1',
  String? tripId = 'trip-1',
  String? bookingRequestId = 'booking-1',
  int amountFils = 7350,
}) => CashPayment(
  paymentId: paymentId,
  tripId: tripId,
  bookingRequestId: bookingRequestId,
  amountFils: amountFils,
  status: status,
  version: 3,
);

CardPayment _card({
  CardPaymentStatus status = CardPaymentStatus.cardPaymentSucceeded,
  String? paymentId = 'payment-1',
  String? tripId = 'trip-1',
  String? bookingRequestId = 'booking-1',
  int amountFils = 7350,
  String? cardBrand,
  String? cardLastFour,
}) => CardPayment(
  paymentId: paymentId,
  tripId: tripId,
  bookingRequestId: bookingRequestId,
  amountFils: amountFils,
  status: status,
  version: 3,
  cardBrand: cardBrand,
  cardLastFour: cardLastFour,
);

RiderPaymentTripEvidence _evidence({
  String? paymentId = 'payment-1',
  String? tripId = 'trip-1',
  String? bookingRequestId = 'booking-1',
  TripStatus tripStatus = TripStatus.completed,
}) => RiderPaymentTripEvidence(
  paymentId: paymentId,
  tripId: tripId,
  bookingRequestId: bookingRequestId,
  tripStatus: tripStatus,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _semanticsTextOf(SemanticsNode node) {
  final buffer = StringBuffer(node.label);
  node.visitChildren((child) {
    buffer
      ..write('\n')
      ..write(_semanticsTextOf(child));
    return true;
  });
  return buffer.toString();
}

void main() {
  group('Read states', () {
    testWidgets('loading shows a loading indicator without failure wording', (
      tester,
    ) async {
      await _pump(
        tester,
        const RiderPaymentStatusCard(readState: RiderPaymentLoading()),
      );
      expect(
        find.byKey(const ValueKey('rider-payment-status-loading')),
        findsOneWidget,
      );
      expect(find.byType(AppLoading), findsOneWidget);
      expect(find.text('Payment status could not be loaded'), findsNothing);
      expect(find.text('Payment failed'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unavailable is a distinct state, not a payment failure', (
      tester,
    ) async {
      await _pump(
        tester,
        const RiderPaymentStatusCard(readState: RiderPaymentUnavailable()),
      );
      expect(
        find.byKey(const ValueKey('rider-payment-status-unavailable')),
        findsOneWidget,
      );
      expect(find.text('Payment record unavailable'), findsOneWidget);
      expect(
        find.textContaining('This is not a payment failure'),
        findsOneWidget,
      );
      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('authorization failure is distinct from payment failure', (
      tester,
    ) async {
      await _pump(
        tester,
        const RiderPaymentStatusCard(
          readState: RiderPaymentAuthorizationFailure(),
        ),
      );
      expect(
        find.byKey(
          const ValueKey('rider-payment-status-authorization-failure'),
        ),
        findsOneWidget,
      );
      expect(find.text('Payment access could not be verified'), findsOneWidget);
      expect(find.text('Payment failed'), findsNothing);
    });

    testWidgets('read failure is distinct and can be retried', (tester) async {
      var retries = 0;
      await _pump(
        tester,
        RiderPaymentStatusCard(
          readState: const RiderPaymentReadFailure(),
          onRetry: () => retries += 1,
        ),
      );
      expect(
        find.byKey(const ValueKey('rider-payment-status-read-failure')),
        findsOneWidget,
      );
      expect(find.text('Payment status could not be loaded'), findsOneWidget);
      expect(
        find.textContaining('This is not a payment failure'),
        findsOneWidget,
      );
      expect(find.text('Payment failed'), findsNothing);
      expect(find.text('Refunded'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('rider-payment-status-retry')),
      );
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('read failure without a callback offers no retry control', (
      tester,
    ) async {
      await _pump(
        tester,
        const RiderPaymentStatusCard(readState: RiderPaymentReadFailure()),
      );
      expect(
        find.byKey(const ValueKey('rider-payment-status-retry')),
        findsNothing,
      );
      expect(find.byType(AppButton), findsNothing);
    });
  });

  group('Cash canonical states', () {
    testWidgets('selected cash renders unpaid, never paid', (tester) async {
      final presentation = RiderPaymentPresentation.fromCash(_cash());
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Cash selected (unpaid)'), findsOneWidget);
      expect(
        find.text('Cash is selected; payment is still unpaid.'),
        findsOneWidget,
      );
      expect(find.text('JOD 7.35'), findsOneWidget);
      expect(find.text('Paid'), findsNothing);
      expect(find.text('Payment completed'), findsNothing);
      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('null canonical Trip link is shown without inferring success', (
      tester,
    ) async {
      final presentation = RiderPaymentPresentation.fromCash(
        _cash(tripId: null),
      );
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(
        find.byKey(const ValueKey('rider-payment-trip-unlinked')),
        findsOneWidget,
      );
      expect(find.text('Trip not yet linked'), findsOneWidget);
      expect(find.text('Payment completed'), findsNothing);
      expect(presentation.issuedReceiptExists, isNull);
    });

    testWidgets('cancelled cash is not a paid payment', (tester) async {
      final presentation = RiderPaymentPresentation.fromCash(
        _cash(status: CashPaymentStatus.cancelled),
      );
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(find.text('Payment cancelled'), findsOneWidget);
      expect(
        find.text('Cash payment was cancelled; it is not a paid payment.'),
        findsOneWidget,
      );
      expect(find.text('Payment completed'), findsNothing);
    });

    testWidgets('paid cash without evidence reports an unconfirmed status', (
      tester,
    ) async {
      final presentation = RiderPaymentPresentation.fromCash(
        _cash(status: CashPaymentStatus.paid),
      );
      expect(presentation.canDescribeAsPaid, isFalse);
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(find.text('Paid status reported'), findsOneWidget);
      expect(find.text('Payment completed'), findsNothing);
      expect(find.text('Unverified'), findsNothing);
    });

    testWidgets('paid cash with caller-constructed evidence stays unverified', (
      tester,
    ) async {
      final presentation = RiderPaymentPresentation.fromCash(
        _cash(status: CashPaymentStatus.paid),
        tripEvidence: _evidence(),
      );
      expect(presentation.canDescribeAsPaid, isTrue);
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(find.text('Payment status unverified'), findsOneWidget);
      expect(find.text('Unverified'), findsOneWidget);
      expect(find.text('Payment completed'), findsNothing);
    });
  });

  group('Card canonical states', () {
    testWidgets('pending card is not capture', (tester) async {
      final presentation = RiderPaymentPresentation.fromCard(
        _card(status: CardPaymentStatus.cardPaymentPending),
      );
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(find.text('Payment pending'), findsOneWidget);
      expect(
        find.text('Card payment is pending; capture is not confirmed.'),
        findsOneWidget,
      );
      expect(find.text('Payment captured'), findsNothing);
    });

    testWidgets('authorized card is not capture', (tester) async {
      final presentation = RiderPaymentPresentation.fromCard(
        _card(status: CardPaymentStatus.cardPaymentAuthorized),
      );
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(find.text('Authorized (not captured)'), findsOneWidget);
      expect(
        find.text('Card payment is authorized; authorization is not capture.'),
        findsOneWidget,
      );
      expect(find.text('Payment captured'), findsNothing);
    });

    testWidgets('success status without evidence is not confirmed capture', (
      tester,
    ) async {
      final presentation = RiderPaymentPresentation.fromCard(_card());
      expect(presentation.canDescribeAsPaid, isFalse);
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(find.text('Success status reported'), findsOneWidget);
      expect(find.text('Payment captured'), findsNothing);
      expect(find.text('Unverified'), findsNothing);
      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('failed card keeps trip completion a separate state', (
      tester,
    ) async {
      final presentation = RiderPaymentPresentation.fromCard(
        _card(status: CardPaymentStatus.cardPaymentFailed),
        tripEvidence: _evidence(),
      );
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(find.text('Payment failed'), findsOneWidget);
      expect(
        find.text('Card payment failed. Trip completion is a separate state.'),
        findsOneWidget,
      );
      expect(find.text('Trip failed'), findsNothing);
      expect(find.text('Trip cancelled'), findsNothing);
    });

    testWidgets('cancelled card is not a paid payment', (tester) async {
      final presentation = RiderPaymentPresentation.fromCard(
        _card(status: CardPaymentStatus.paymentCancelled),
      );
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(find.text('Payment cancelled'), findsOneWidget);
      expect(
        find.text('Card payment was cancelled; it is not a paid payment.'),
        findsOneWidget,
      );
      expect(find.text('Payment captured'), findsNothing);
    });

    testWidgets('refund pending and refunded stay distinct', (tester) async {
      final pending = RiderPaymentPresentation.fromCard(
        _card(status: CardPaymentStatus.refundPending),
      );
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(pending)),
      );
      expect(find.text('Refund pending'), findsOneWidget);

      final refunded = RiderPaymentPresentation.fromCard(
        _card(status: CardPaymentStatus.refunded),
      );
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(refunded)),
      );
      expect(find.text('Refunded'), findsOneWidget);
      expect(find.text('Refund pending'), findsNothing);
      expect(find.text('Payment captured'), findsNothing);
      expect(find.text('Paid'), findsNothing);
    });
  });

  group('Fail-closed resolution contract', () {
    test('failClosed resolves reported success to an unverified display', () {
      final fabricated = RiderPaymentPresentation.fromCard(
        _card(),
        tripEvidence: _evidence(),
      );
      expect(fabricated.canDescribeAsPaid, isTrue);
      final display = RiderPaymentStatusDisplay.failClosed(fabricated);
      expect(display.unverifiedSuccess, isTrue);
      expect(display.isSimulated, isFalse);
      expect(display.title, 'Payment status unverified');
      expect(display.markerLabel, 'Unverified');
      expect(display.amountDisplay, 'JOD 7.35');
      expect(display.message, contains('unconfirmed'));
    });

    test('failClosed leaves non-success labels unchanged', () {
      final refunded = RiderPaymentPresentation.fromCard(
        _card(status: CardPaymentStatus.refunded),
      );
      final display = RiderPaymentStatusDisplay.failClosed(refunded);
      expect(display.unverifiedSuccess, isFalse);
      expect(display.title, 'Refunded');
      expect(display.markerLabel, isNull);
    });

    test('simulated resolution is explicitly marked simulated', () {
      final fabricated = RiderPaymentPresentation.fromCard(
        _card(),
        tripEvidence: _evidence(),
      );
      final display = RiderPaymentStatusDisplay.simulated(fabricated);
      expect(display.isSimulated, isTrue);
      expect(display.unverifiedSuccess, isFalse);
      expect(display.title, 'Payment captured');
      expect(display.markerLabel, 'Simulated data');
      expect(display.message, startsWith('Simulated data:'));
    });

    testWidgets(
      'evidence for a non-completed trip never unlocks success wording',
      (tester) async {
        final presentation = RiderPaymentPresentation.fromCard(
          _card(),
          tripEvidence: _evidence(tripStatus: TripStatus.cancelledByRider),
        );
        expect(presentation.canDescribeAsPaid, isFalse);
        await _pump(
          tester,
          RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
        );
        expect(find.text('Success status reported'), findsOneWidget);
        expect(find.text('Payment captured'), findsNothing);
      },
    );

    testWidgets('simulated status card is explicitly labeled simulated', (
      tester,
    ) async {
      final fabricated = RiderPaymentPresentation.fromCard(
        _card(),
        tripEvidence: _evidence(),
      );
      await _pump(
        tester,
        RiderPaymentStatusCard.simulated(presentation: fabricated),
      );
      expect(find.text('Payment captured'), findsOneWidget);
      expect(find.text('Simulated data'), findsOneWidget);
      expect(find.textContaining('Simulated data:'), findsOneWidget);
      expect(find.text('Payment status unverified'), findsNothing);
    });
  });

  group('Record card', () {
    testWidgets('cash record shows rows and an unavailable receipt', (
      tester,
    ) async {
      await _pump(
        tester,
        RiderPaymentRecordCard.fromCash(
          _cash(
            paymentId: 'pay-canary-1',
            tripId: 'trip-canary-1',
            bookingRequestId: 'book-canary-1',
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('rider-payment-record-card')),
        findsOneWidget,
      );
      expect(find.text('Method'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Cash selected (unpaid)'), findsOneWidget);
      expect(find.text('JOD 7.35'), findsOneWidget);
      expect(find.text('Receipt'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Card brand'), findsNothing);
      expect(find.text('Card ending'), findsNothing);
      expect(find.textContaining('canary'), findsNothing);
      expect(find.byType(AppButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('authorized card record masks the last four', (tester) async {
      await _pump(
        tester,
        RiderPaymentRecordCard.fromCard(
          _card(
            status: CardPaymentStatus.cardPaymentAuthorized,
            cardBrand: 'Visa',
            cardLastFour: '4242',
          ),
        ),
      );
      expect(find.text('Authorized (not captured)'), findsOneWidget);
      expect(find.text('Card brand'), findsOneWidget);
      expect(find.text('Visa'), findsOneWidget);
      expect(find.text('Card ending'), findsOneWidget);
      expect(find.text('\u2022\u2022\u2022\u2022 4242'), findsOneWidget);
      expect(find.textContaining('4242'), findsOneWidget);
    });

    testWidgets('unknown brands never echo unvalidated text', (tester) async {
      await _pump(
        tester,
        RiderPaymentRecordCard.fromCard(
          _card(
            status: CardPaymentStatus.cardPaymentAuthorized,
            cardBrand: '4111111111111111',
          ),
        ),
      );
      expect(find.text('Card brand'), findsNothing);
      expect(find.text('Card ending'), findsNothing);
      expect(find.text('4111111111111111'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing card metadata renders no card rows', (tester) async {
      await _pump(
        tester,
        RiderPaymentRecordCard.fromCard(
          _card(status: CardPaymentStatus.cardPaymentPending),
        ),
      );
      expect(find.text('Card brand'), findsNothing);
      expect(find.text('Card ending'), findsNothing);
    });

    testWidgets('refunded record is not shown as an ordinary capture', (
      tester,
    ) async {
      await _pump(
        tester,
        RiderPaymentRecordCard.fromCard(
          _card(status: CardPaymentStatus.refunded),
        ),
      );
      expect(find.text('Refunded'), findsOneWidget);
      expect(find.text('Payment captured'), findsNothing);
      expect(find.text('Unavailable'), findsOneWidget);
    });

    testWidgets('record card fails closed for fabricated success evidence', (
      tester,
    ) async {
      await _pump(
        tester,
        RiderPaymentRecordCard.fromCard(_card(), tripEvidence: _evidence()),
      );
      expect(find.text('Payment status unverified'), findsOneWidget);
      expect(find.text('Unverified'), findsOneWidget);
      expect(find.text('Payment captured'), findsNothing);
    });

    testWidgets('receipt details are never fabricated', (tester) async {
      await _pump(
        tester,
        RiderPaymentRecordCard.fromCard(
          _card(status: CardPaymentStatus.refunded),
        ),
      );
      expect(find.textContaining('Receipt ID'), findsNothing);
      expect(find.textContaining('Receipt number'), findsNothing);
      expect(find.textContaining('Tax'), findsNothing);
      expect(find.textContaining('VAT'), findsNothing);
      expect(find.textContaining('Fare breakdown'), findsNothing);
      expect(find.textContaining('Refund transaction'), findsNothing);
      expect(find.textContaining('2026'), findsNothing);
      expect(find.textContaining('Issued'), findsNothing);
    });

    const normalizedBrands = <String, String>{
      ' VISA ': 'Visa',
      'amex': 'American Express',
      'American Express': 'American Express',
      'Diners Club': 'Diners Club',
      'mastercard': 'Mastercard',
      'discover': 'Discover',
      'jcb': 'JCB',
      'unionpay': 'UnionPay',
    };

    for (final MapEntry(key: raw, value: display) in normalizedBrands.entries) {
      testWidgets('normalizes card brand "$raw" to $display', (tester) async {
        await _pump(
          tester,
          RiderPaymentRecordCard.fromCard(
            _card(
              status: CardPaymentStatus.cardPaymentAuthorized,
              cardBrand: raw,
              cardLastFour: '4242',
            ),
          ),
        );
        expect(find.text('Card brand'), findsOneWidget);
        expect(find.text(display), findsOneWidget);
        expect(find.text('\u2022\u2022\u2022\u2022 4242'), findsOneWidget);
        expect(find.textContaining('4242'), findsOneWidget);
        if (raw.trim() != display) {
          expect(find.text(raw.trim()), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }

    test('card metadata never invents brand or ending details', () {
      final unknownBrand = RiderCardPaymentMetadata.fromCard(
        _card(cardBrand: 'TotallyMadeUpBank', cardLastFour: '4242'),
      );
      expect(unknownBrand.brandDisplay, isNull);
      expect(
        unknownBrand.maskedLastFourDisplay,
        '\u2022\u2022\u2022\u2022 4242',
      );

      final missingBrand = RiderCardPaymentMetadata.fromCard(
        _card(cardLastFour: '1234'),
      );
      expect(missingBrand.brandDisplay, isNull);
      expect(
        missingBrand.maskedLastFourDisplay,
        '\u2022\u2022\u2022\u2022 1234',
      );

      final empty = RiderCardPaymentMetadata.fromCard(_card());
      expect(empty.brandDisplay, isNull);
      expect(empty.maskedLastFourDisplay, isNull);
    });
  });

  group('Accessibility and layout', () {
    testWidgets('ready state exposes one readable semantics label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final presentation = RiderPaymentPresentation.fromCard(
        _card(),
        tripEvidence: _evidence(),
      );
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            'Card\\. Payment status unverified\\..*Amount JOD 7\\.35.*Unverified',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('read failure and unavailable states expose their titles', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const RiderPaymentStatusCard(readState: RiderPaymentReadFailure()),
      );
      expect(
        find.bySemanticsLabel(RegExp('Payment status could not be loaded')),
        findsOneWidget,
      );
      await _pump(
        tester,
        const RiderPaymentStatusCard(readState: RiderPaymentUnavailable()),
      );
      expect(
        find.bySemanticsLabel(RegExp('Payment record unavailable')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('record card exposes method, status, amount and receipt', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, RiderPaymentRecordCard.fromCash(_cash()));
      final semanticsText = _semanticsTextOf(
        tester.semantics.find(
          find.byKey(const ValueKey('rider-payment-record-card')),
        ),
      );
      expect(semanticsText, contains('Method'));
      expect(semanticsText, contains('Cash selected (unpaid)'));
      expect(semanticsText, contains('Amount'));
      expect(semanticsText, contains('JOD 7.35'));
      expect(semanticsText, contains('Receipt'));
      expect(semanticsText, contains('Unavailable'));
      handle.dispose();
    });

    testWidgets('record card never announces unverified success as captured', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        RiderPaymentRecordCard.fromCard(_card(), tripEvidence: _evidence()),
      );
      final semanticsText = _semanticsTextOf(
        tester.semantics.find(
          find.byKey(const ValueKey('rider-payment-record-card')),
        ),
      );
      expect(semanticsText, contains('Payment status unverified'));
      expect(semanticsText, contains('Unverified'));
      expect(semanticsText, isNot(contains('Payment captured')));
      expect(semanticsText, isNot(contains('Payment completed')));
      handle.dispose();
    });

    testWidgets('renders without overflow on a narrow screen', (tester) async {
      tester.view.physicalSize = const Size(280, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final presentation = RiderPaymentPresentation.fromCard(
        _card(),
        tripEvidence: _evidence(),
      );
      await _pump(
        tester,
        Column(
          children: [
            RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
            const SizedBox(height: 12),
            RiderPaymentRecordCard.fromCard(
              _card(
                status: CardPaymentStatus.cardPaymentAuthorized,
                cardBrand: 'American Express',
                cardLastFour: '0007',
              ),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Payment status unverified'), findsOneWidget);
      expect(find.text('\u2022\u2022\u2022\u2022 0007'), findsOneWidget);
    });

    testWidgets('renders with the dark theme', (tester) async {
      final presentation = RiderPaymentPresentation.fromCash(_cash());
      await _pump(
        tester,
        RiderPaymentStatusCard(readState: RiderPaymentReady(presentation)),
        theme: AppTheme.dark(),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Cash selected (unpaid)'), findsOneWidget);
    });
  });
}
