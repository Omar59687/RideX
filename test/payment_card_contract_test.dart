import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/repositories/card_payment_repository.dart';
import 'package:ridex/core/repositories/payment_repository.dart';

CardPayment cardFixture({
  String? paymentId = 'payment-1',
  String? bookingRequestId = 'booking-1',
  String? tripId = 'trip-1',
  int amountFils = 1250,
  String currency = 'JOD',
  CardPaymentStatus status = CardPaymentStatus.cardPaymentPending,
  int version = 1,
  String? idempotencyKey,
  String? cardBrand,
  String? cardLastFour,
}) =>
    CardPayment(
      paymentId: paymentId,
      bookingRequestId: bookingRequestId,
      tripId: tripId,
      amountFils: amountFils,
      currency: currency,
      status: status,
      version: version,
      idempotencyKey: idempotencyKey,
      cardBrand: cardBrand,
      cardLastFour: cardLastFour,
    );

Matcher paymentFailure(PaymentFailure failure) => isA<PaymentException>()
    .having((error) => error.failure, 'failure', failure);

/// Approved canonical Card lifecycle edges. Every other pair must be false.
bool expectedCardTransition(CardPaymentStatus from, CardPaymentStatus to) {
  return switch (from) {
    CardPaymentStatus.cardPaymentPending =>
      to == CardPaymentStatus.cardPaymentAuthorized ||
          to == CardPaymentStatus.cardPaymentFailed ||
          to == CardPaymentStatus.paymentCancelled,
    CardPaymentStatus.cardPaymentAuthorized =>
      to == CardPaymentStatus.cardPaymentPending ||
          to == CardPaymentStatus.cardPaymentSucceeded ||
          to == CardPaymentStatus.cardPaymentFailed ||
          to == CardPaymentStatus.paymentCancelled,
    CardPaymentStatus.cardPaymentFailed =>
      to == CardPaymentStatus.cardPaymentPending ||
          to == CardPaymentStatus.cardPaymentSucceeded ||
          to == CardPaymentStatus.paymentCancelled,
    CardPaymentStatus.cardPaymentSucceeded =>
      to == CardPaymentStatus.refundPending,
    CardPaymentStatus.refundPending => to == CardPaymentStatus.refunded,
    CardPaymentStatus.paymentCancelled => false,
    CardPaymentStatus.refunded => false,
  };
}

void main() {
  group('Backend Card payment vocabulary', () {
    test('round-trips all seven exact Card status values', () {
      expect(CardPaymentStatus.values.map((status) => status.backendValue), [
        'cardPaymentPending',
        'cardPaymentAuthorized',
        'cardPaymentSucceeded',
        'cardPaymentFailed',
        'paymentCancelled',
        'refundPending',
        'refunded',
      ]);
      for (final status in CardPaymentStatus.values) {
        expect(CardPaymentStatus.fromBackendValue(status.backendValue), status);
      }
    });

    test('rejects unknown, altered-case and snake_case backend values', () {
      for (final value in [
        'card_payment_pending',
        'card_payment_authorized',
        'card_payment_succeeded',
        'card_payment_failed',
        'payment_cancelled',
        'refund_pending',
        'cardPaymentpending',
        'CARDPAYMENTPENDING',
        'unknown',
        '',
      ]) {
        expect(
          () => CardPaymentStatus.fromBackendValue(value),
          throwsArgumentError,
        );
      }
    });
  });

  group('Card domain lifecycle', () {
    test('terminal states are paymentCancelled and refunded only', () {
      for (final status in CardPaymentStatus.values) {
        final expected = status == CardPaymentStatus.paymentCancelled ||
            status == CardPaymentStatus.refunded;
        expect(cardFixture(status: status).isTerminal, expected,
            reason: '$status');
      }
    });

    test('matches the approved transition for all 49 status pairs', () {
      for (final from in CardPaymentStatus.values) {
        for (final to in CardPaymentStatus.values) {
          expect(canTransitionCard(from, to), expectedCardTransition(from, to),
              reason: '$from -> $to');
        }
      }
    });

    test('terminal states have no outgoing transitions', () {
      for (final from in [
        CardPaymentStatus.paymentCancelled,
        CardPaymentStatus.refunded
      ]) {
        for (final to in CardPaymentStatus.values) {
          expect(canTransitionCard(from, to), isFalse, reason: '$from -> $to');
        }
      }
    });

    test('transition predicate cannot change a seeded payment', () async {
      final fake = FakeCardPaymentRepository()..seedCardPayment(cardFixture());
      CardPaymentRepository repository = fake;

      expect(
          canTransitionCard(CardPaymentStatus.cardPaymentPending,
              CardPaymentStatus.cardPaymentAuthorized),
          isTrue);
      expect((await repository.readCardPayment(paymentId: 'payment-1')).status,
          CardPaymentStatus.cardPaymentPending);
    });
  });

  group('CardPayment validation and value', () {
    test('accepts zero and integer fils in JOD', () {
      expect(cardFixture(amountFils: 0).amountFils, 0);
      expect(cardFixture(amountFils: 1251).amountFils, 1251);
      expect(cardFixture().currency, 'JOD');
    });

    test('rejects negative fils, non-JOD currency and nonpositive versions',
        () {
      expect(() => cardFixture(amountFils: -1), throwsArgumentError);
      expect(() => cardFixture(currency: 'USD'), throwsArgumentError);
      expect(() => cardFixture(version: 0), throwsArgumentError);
      expect(() => cardFixture(version: -1), throwsArgumentError);
    });

    test('rejects blank optional identifiers when provided', () {
      expect(() => cardFixture(paymentId: ' '), throwsArgumentError);
      expect(() => cardFixture(bookingRequestId: '\t'), throwsArgumentError);
      expect(() => cardFixture(tripId: ''), throwsArgumentError);
      expect(() => cardFixture(idempotencyKey: '  '), throwsArgumentError);
    });

    test('permits nullable identifiers in the domain representation', () {
      final unpersisted = CardPayment(
        amountFils: 0,
        status: CardPaymentStatus.cardPaymentPending,
        version: 1,
      );
      expect(unpersisted.paymentId, isNull);
      expect(unpersisted.bookingRequestId, isNull);
      expect(unpersisted.tripId, isNull);
      expect(unpersisted.idempotencyKey, isNull);
      expect(unpersisted.cardBrand, isNull);
      expect(unpersisted.cardLastFour, isNull);
    });

    test('accepts sanitized card brand and last four', () {
      final payment = cardFixture(cardBrand: 'Visa', cardLastFour: '4242');
      expect(payment.cardBrand, 'Visa');
      expect(payment.cardLastFour, '4242');
    });

    test('rejects overlong or blank card brands', () {
      expect(() => cardFixture(cardBrand: ''), throwsArgumentError);
      expect(() => cardFixture(cardBrand: '   '), throwsArgumentError);
      expect(() => cardFixture(cardBrand: List.filled(33, 'V').join()),
          throwsArgumentError);
      expect(cardFixture(cardBrand: List.filled(32, 'V').join()).cardBrand,
          hasLength(32));
    });

    test('rejects invalid card last-four formats', () {
      for (final lastFour in [
        '',
        '123',
        '12345',
        '12a4',
        ' 424',
        '424 ',
        '+424',
        '٤٢٤٢'
      ]) {
        expect(() => cardFixture(cardLastFour: lastFour), throwsArgumentError);
      }
    });

    test('uses immutable value fields for Equatable equality', () {
      final original = cardFixture(
        idempotencyKey: 'original-command',
        cardBrand: 'Visa',
        cardLastFour: '4242',
      );
      expect(
          cardFixture(
            idempotencyKey: 'original-command',
            cardBrand: 'Visa',
            cardLastFour: '4242',
          ),
          original);
      expect(
          original.props,
          containsAll([
            original.paymentId,
            original.bookingRequestId,
            original.tripId,
            original.amountFils,
            original.currency,
            original.status,
            original.version,
            original.idempotencyKey,
            original.cardBrand,
            original.cardLastFour,
          ]));
      expect(
          cardFixture(
            version: 2,
            idempotencyKey: 'original-command',
            cardBrand: 'Visa',
            cardLastFour: '4242',
          ),
          isNot(original));
      expect(
          cardFixture(
            status: CardPaymentStatus.cardPaymentAuthorized,
            idempotencyKey: 'original-command',
            cardBrand: 'Visa',
            cardLastFour: '4242',
          ),
          isNot(original));
      expect(
          cardFixture(
            idempotencyKey: 'original-command',
            cardBrand: 'Visa',
            cardLastFour: '0005',
          ),
          isNot(original));
    });
  });

  group('Card attempt-limit contract metadata', () {
    test('exposes the approved server-enforced attempt boundaries', () {
      expect(CardAttemptLimits.maxAuthorizationAttempts, 2);
      expect(CardAttemptLimits.maxCaptureAttempts, 3);
      expect(CardAttemptLimits.maxRefundAttempts, 3);
      // Attempt-completion timeout, not authorization expiry.
      expect(CardAttemptLimits.authorizationAttemptTimeout,
          const Duration(minutes: 2));
    });
  });

  group('Read-only Card payment repository fixture', () {
    test('returns seeded canonical states deterministically by payment ID',
        () async {
      final fake = FakeCardPaymentRepository();
      final pending = cardFixture();
      final authorized = cardFixture(
        paymentId: 'payment-2',
        bookingRequestId: 'booking-2',
        tripId: 'trip-2',
        status: CardPaymentStatus.cardPaymentAuthorized,
        version: 2,
        cardBrand: 'Visa',
        cardLastFour: '4242',
      );
      fake.seedCardPayment(pending);
      fake.seedCardPayment(authorized);
      CardPaymentRepository repository = fake;

      expect(await repository.readCardPayment(paymentId: 'payment-1'), pending);
      expect(
          await repository.readCardPayment(paymentId: 'payment-2'), authorized);
      expect(await repository.readCardPayment(paymentId: 'payment-1'), pending);
    });

    test('rejects blank read IDs with a typed invalidRequest', () async {
      CardPaymentRepository repository = FakeCardPaymentRepository();
      for (final paymentId in ['', '  ']) {
        await expectLater(
          repository.readCardPayment(paymentId: paymentId),
          throwsA(paymentFailure(PaymentFailure.invalidRequest)),
        );
      }
    });

    test('rejects unknown read IDs with a typed notFound', () async {
      CardPaymentRepository repository = FakeCardPaymentRepository();
      await expectLater(
        repository.readCardPayment(paymentId: 'missing'),
        throwsA(paymentFailure(PaymentFailure.notFound)),
      );
    });

    test('rejects duplicate payment, booking and Trip identities', () async {
      final fake = FakeCardPaymentRepository()..seedCardPayment(cardFixture());
      final duplicates = [
        cardFixture(
            paymentId: 'payment-1',
            bookingRequestId: 'booking-2',
            tripId: 'trip-2'),
        cardFixture(
            paymentId: 'payment-2',
            bookingRequestId: 'booking-1',
            tripId: 'trip-2'),
        cardFixture(
            paymentId: 'payment-2',
            bookingRequestId: 'booking-2',
            tripId: 'trip-1'),
      ];
      for (final duplicate in duplicates) {
        expect(() => fake.seedCardPayment(duplicate),
            throwsA(paymentFailure(PaymentFailure.invalidRequest)));
      }
      expect(await fake.readCardPayment(paymentId: 'payment-1'), cardFixture());
      await expectLater(fake.readCardPayment(paymentId: 'payment-2'),
          throwsA(paymentFailure(PaymentFailure.notFound)));
    });

    test('rejects incomplete fixtures before changing stored state', () async {
      final fake = FakeCardPaymentRepository()..seedCardPayment(cardFixture());
      final invalid = [
        CardPayment(
            bookingRequestId: 'booking-2',
            tripId: 'trip-2',
            amountFils: 100,
            status: CardPaymentStatus.cardPaymentPending,
            version: 1),
        CardPayment(
            paymentId: 'payment-2',
            tripId: 'trip-2',
            amountFils: 100,
            status: CardPaymentStatus.cardPaymentPending,
            version: 1),
        CardPayment(
            paymentId: 'payment-2',
            bookingRequestId: 'booking-2',
            amountFils: 100,
            status: CardPaymentStatus.cardPaymentPending,
            version: 1),
      ];
      for (final fixture in invalid) {
        expect(() => fake.seedCardPayment(fixture),
            throwsA(paymentFailure(PaymentFailure.invalidRequest)));
      }
      expect(await fake.readCardPayment(paymentId: 'payment-1'), cardFixture());
      await expectLater(fake.readCardPayment(paymentId: 'payment-2'),
          throwsA(paymentFailure(PaymentFailure.notFound)));

      final valid = cardFixture(
          paymentId: 'payment-2',
          bookingRequestId: 'booking-2',
          tripId: 'trip-2');
      fake.seedCardPayment(valid);
      expect(await fake.readCardPayment(paymentId: 'payment-2'), valid);
    });
  });
}
