import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/mock_trip.dart' show TripStatus;
import 'package:ridex/core/repositories/card_payment_repository.dart';
import 'package:ridex/core/repositories/payment_repository.dart';
import 'package:ridex/features/history/presentation/models/rider_payment_presentation.dart';

CashPayment _cash({
  CashPaymentStatus status = CashPaymentStatus.paid,
  String? paymentId = 'payment-1',
  String? tripId = 'trip-1',
  String? bookingRequestId = 'booking-1',
  int amountFils = 7350,
  String? idempotencyKey,
}) => CashPayment(
  paymentId: paymentId,
  tripId: tripId,
  bookingRequestId: bookingRequestId,
  amountFils: amountFils,
  status: status,
  version: 3,
  idempotencyKey: idempotencyKey,
);

CardPayment _card({
  CardPaymentStatus status = CardPaymentStatus.cardPaymentSucceeded,
  String? paymentId = 'payment-1',
  String? tripId = 'trip-1',
  String? bookingRequestId = 'booking-1',
  int amountFils = 7350,
  String? idempotencyKey,
  String? cardBrand,
  String? cardLastFour,
}) => CardPayment(
  paymentId: paymentId,
  tripId: tripId,
  bookingRequestId: bookingRequestId,
  amountFils: amountFils,
  status: status,
  version: 3,
  idempotencyKey: idempotencyKey,
  cardBrand: cardBrand,
  cardLastFour: cardLastFour,
);

Map<String, Object?> _cashValues(CashPayment payment) => {
  'paymentId': payment.paymentId,
  'bookingRequestId': payment.bookingRequestId,
  'tripId': payment.tripId,
  'amountFils': payment.amountFils,
  'currency': payment.currency,
  'status': payment.status,
  'version': payment.version,
  'idempotencyKey': payment.idempotencyKey,
};

Map<String, Object?> _cardValues(CardPayment payment) => {
  'paymentId': payment.paymentId,
  'bookingRequestId': payment.bookingRequestId,
  'tripId': payment.tripId,
  'amountFils': payment.amountFils,
  'currency': payment.currency,
  'status': payment.status,
  'version': payment.version,
  'idempotencyKey': payment.idempotencyKey,
  'cardBrand': payment.cardBrand,
  'cardLastFour': payment.cardLastFour,
};

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

void _expectUnverified(RiderPaymentPresentation presentation) {
  expect(presentation.canDescribeAsPaid, isFalse);
  expect(
    presentation.statusLabel,
    isNot(isIn(['Payment completed', 'Payment captured'])),
  );
  expect(presentation.issuedReceiptExists, isNull);
}

void main() {
  group('Cash state presentation', () {
    const cases = {
      CashPaymentStatus.cashSelected: (
        'Cash selected (unpaid)',
        'Cash is selected; payment is still unpaid.',
        false,
      ),
      CashPaymentStatus.paid: (
        'Payment completed',
        'Cash payment is confirmed for this completed trip.',
        true,
      ),
      CashPaymentStatus.cancelled: (
        'Payment cancelled',
        'Cash payment was cancelled; it is not a paid payment.',
        false,
      ),
    };

    for (final status in CashPaymentStatus.values) {
      test('maps ${status.name} with completed-Trip evidence', () {
        final presentation = RiderPaymentPresentation.fromCash(
          _cash(status: status),
          tripEvidence: _evidence(),
        );
        final (label, description, paid) = cases[status]!;

        expect(presentation.methodLabel, 'Cash');
        expect(presentation.statusLabel, label);
        expect(presentation.statusDescription, description);
        expect(presentation.canDescribeAsPaid, paid);
        expect(presentation.issuedReceiptExists, isNull);
      });
    }

    test('paid status alone does not confirm Cash payment', () {
      final presentation = RiderPaymentPresentation.fromCash(_cash());

      _expectUnverified(presentation);
      expect(presentation.statusLabel, 'Paid status reported');
      expect(presentation.statusDescription, contains('evidence must match'));
    });

    test(
      'canonical nullable Trip linkage is retained without success proof',
      () {
        final presentation = RiderPaymentPresentation.fromCash(
          _cash(tripId: null),
        );

        expect(presentation.tripNotLinked, isTrue);
        expect(presentation.canDescribeAsPaid, isFalse);
        expect(presentation.issuedReceiptExists, isNull);
      },
    );
  });

  group('Card state presentation', () {
    const cases = {
      CardPaymentStatus.cardPaymentPending: (
        'Payment pending',
        'Card payment is pending; capture is not confirmed.',
        false,
      ),
      CardPaymentStatus.cardPaymentAuthorized: (
        'Authorized (not captured)',
        'Card payment is authorized; authorization is not capture.',
        false,
      ),
      CardPaymentStatus.cardPaymentSucceeded: (
        'Payment captured',
        'Card payment was successfully captured for this completed trip.',
        true,
      ),
      CardPaymentStatus.cardPaymentFailed: (
        'Payment failed',
        'Card payment failed. Trip completion is a separate state.',
        false,
      ),
      CardPaymentStatus.paymentCancelled: (
        'Payment cancelled',
        'Card payment was cancelled; it is not a paid payment.',
        false,
      ),
      CardPaymentStatus.refundPending: (
        'Refund pending',
        'A refund is pending for this card payment.',
        false,
      ),
      CardPaymentStatus.refunded: (
        'Refunded',
        'Card payment is refunded; it is not a current completed payment.',
        false,
      ),
    };

    for (final status in CardPaymentStatus.values) {
      test('maps ${status.name} with completed-Trip evidence', () {
        final presentation = RiderPaymentPresentation.fromCard(
          _card(status: status),
          tripEvidence: _evidence(),
        );
        final (label, description, paid) = cases[status]!;

        expect(presentation.methodLabel, 'Card');
        expect(presentation.statusLabel, label);
        expect(presentation.statusDescription, description);
        expect(presentation.canDescribeAsPaid, paid);
        expect(presentation.issuedReceiptExists, isNull);
      });
    }

    test('success status alone does not confirm capture', () {
      final presentation = RiderPaymentPresentation.fromCard(_card());

      _expectUnverified(presentation);
      expect(presentation.statusLabel, 'Success status reported');
      expect(
        presentation.statusDescription,
        contains('before confirming capture'),
      );
    });

    test('failed payment leaves completed-Trip evidence intact', () {
      final evidence = _evidence();
      final payment = _card(status: CardPaymentStatus.cardPaymentFailed);

      final presentation = RiderPaymentPresentation.fromCard(
        payment,
        tripEvidence: evidence,
      );

      expect(presentation.statusLabel, 'Payment failed');
      expect(presentation.statusDescription, contains('separate state'));
      expect(evidence.tripStatus, TripStatus.completed);
      expect(payment.status, CardPaymentStatus.cardPaymentFailed);
      _expectUnverified(presentation);
    });
  });

  group('Independent identity and Trip completion guards', () {
    for (final field in ['paymentId', 'tripId', 'bookingRequestId']) {
      test('missing payment record $field rejects paid presentation', () {
        final cash = _cash(
          paymentId: field == 'paymentId' ? null : 'payment-1',
          tripId: field == 'tripId' ? null : 'trip-1',
          bookingRequestId: field == 'bookingRequestId' ? null : 'booking-1',
        );
        final card = _card(
          paymentId: field == 'paymentId' ? null : 'payment-1',
          tripId: field == 'tripId' ? null : 'trip-1',
          bookingRequestId: field == 'bookingRequestId' ? null : 'booking-1',
        );

        _expectUnverified(
          RiderPaymentPresentation.fromCash(cash, tripEvidence: _evidence()),
        );
        _expectUnverified(
          RiderPaymentPresentation.fromCard(card, tripEvidence: _evidence()),
        );
      });

      const invalidIds = {
        'missing': null,
        'empty': '',
        'blank': ' \t ',
        'different': 'another-id',
      };
      for (final entry in invalidIds.entries) {
        test('${entry.key} evidence $field rejects paid presentation', () {
          final evidence = _evidence(
            paymentId: field == 'paymentId' ? entry.value : 'payment-1',
            tripId: field == 'tripId' ? entry.value : 'trip-1',
            bookingRequestId: field == 'bookingRequestId'
                ? entry.value
                : 'booking-1',
          );

          _expectUnverified(
            RiderPaymentPresentation.fromCash(_cash(), tripEvidence: evidence),
          );
          _expectUnverified(
            RiderPaymentPresentation.fromCard(_card(), tripEvidence: evidence),
          );
        });
      }

      test('mismatched payment record $field rejects paid presentation', () {
        final cash = _cash(
          paymentId: field == 'paymentId' ? 'another-payment' : 'payment-1',
          tripId: field == 'tripId' ? 'another-trip' : 'trip-1',
          bookingRequestId: field == 'bookingRequestId'
              ? 'another-booking'
              : 'booking-1',
        );
        final card = _card(
          paymentId: field == 'paymentId' ? 'another-payment' : 'payment-1',
          tripId: field == 'tripId' ? 'another-trip' : 'trip-1',
          bookingRequestId: field == 'bookingRequestId'
              ? 'another-booking'
              : 'booking-1',
        );

        _expectUnverified(
          RiderPaymentPresentation.fromCash(cash, tripEvidence: _evidence()),
        );
        _expectUnverified(
          RiderPaymentPresentation.fromCard(card, tripEvidence: _evidence()),
        );
      });
    }

    test('identity matching does not trim or change case', () {
      for (final paymentId in [' payment-1 ', 'PAYMENT-1']) {
        final evidence = _evidence(paymentId: paymentId);
        _expectUnverified(
          RiderPaymentPresentation.fromCash(_cash(), tripEvidence: evidence),
        );
        _expectUnverified(
          RiderPaymentPresentation.fromCard(_card(), tripEvidence: evidence),
        );
      }
    });

    for (final status in TripStatus.values) {
      if (status == TripStatus.completed) continue;
      test('${status.name} Trip rejects both successful payment claims', () {
        final evidence = _evidence(tripStatus: status);

        _expectUnverified(
          RiderPaymentPresentation.fromCash(_cash(), tripEvidence: evidence),
        );
        _expectUnverified(
          RiderPaymentPresentation.fromCard(_card(), tripEvidence: evidence),
        );
      });
    }
  });

  group('Canonical amount formatting', () {
    const amounts = {
      0: 'JOD 0.00',
      4: 'JOD 0.00',
      5: 'JOD 0.01',
      1251: 'JOD 1.25',
      1255: 'JOD 1.26',
      7350: 'JOD 7.35',
      1234567: 'JOD 1234.57',
      2147483647: 'JOD 2147483.65',
    };
    for (final entry in amounts.entries) {
      test('preserves ${entry.key} fils with existing display rounding', () {
        final cash = _cash(amountFils: entry.key);
        final card = _card(amountFils: entry.key);
        final presentations = [
          RiderPaymentPresentation.fromCash(cash),
          RiderPaymentPresentation.fromCard(card),
        ];

        for (final presentation in presentations) {
          expect(presentation.amountFils, entry.key);
          expect(presentation.currency, 'JOD');
          expect(presentation.formattedAmount, entry.value);
        }
        expect(cash.amountFils, entry.key);
        expect(card.amountFils, entry.key);
      });
    }
  });

  group('Read-only canonical fixtures', () {
    test(
      'mapping Cash records never settles or cancels their source',
      () async {
        for (final status in CashPaymentStatus.values) {
          final payment = _cash(status: status, idempotencyKey: 'cash-idem');
          final fake = FakePaymentRepository()..seedCashPayment(payment);
          PaymentRepository repository = fake;
          final before = await repository.readCashPayment(
            paymentId: 'payment-1',
          );
          final beforeValues = _cashValues(before);

          RiderPaymentPresentation.fromCash(before, tripEvidence: _evidence());

          final after = await repository.readCashPayment(
            paymentId: 'payment-1',
          );
          final afterValues = _cashValues(after);

          expect(afterValues, equals(beforeValues));
          expect(after.paymentId, 'payment-1');
          expect(after.bookingRequestId, 'booking-1');
          expect(after.tripId, 'trip-1');
          expect(after.amountFils, 7350);
          expect(after.currency, 'JOD');
          expect(after.status, status);
          expect(after.version, 3);
          expect(after.idempotencyKey, 'cash-idem');
        }
      },
    );

    test('mapping Card records never performs a payment transition', () async {
      for (final status in CardPaymentStatus.values) {
        final payment = _card(
          status: status,
          idempotencyKey: 'card-idem',
          cardBrand: 'Visa',
          cardLastFour: '4242',
        );
        final fake = FakeCardPaymentRepository()..seedCardPayment(payment);
        CardPaymentRepository repository = fake;
        final before = await repository.readCardPayment(paymentId: 'payment-1');
        final beforeValues = _cardValues(before);

        RiderPaymentPresentation.fromCard(before, tripEvidence: _evidence());

        final after = await repository.readCardPayment(paymentId: 'payment-1');
        final afterValues = _cardValues(after);

        expect(afterValues, equals(beforeValues));
        expect(after.paymentId, 'payment-1');
        expect(after.bookingRequestId, 'booking-1');
        expect(after.tripId, 'trip-1');
        expect(after.amountFils, 7350);
        expect(after.currency, 'JOD');
        expect(after.status, status);
        expect(after.version, 3);
        expect(after.idempotencyKey, 'card-idem');
        expect(after.cardBrand, 'Visa');
        expect(after.cardLastFour, '4242');
      }
    });
  });
}
