import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/repositories/payment_repository.dart';

CashPayment cashFixture({
  String paymentId = 'payment-1',
  String bookingRequestId = 'booking-1',
  String tripId = 'trip-1',
  int amountFils = 1250,
  String currency = 'JOD',
  CashPaymentStatus status = CashPaymentStatus.cashSelected,
  int version = 1,
  String? idempotencyKey,
}) =>
    CashPayment(
      paymentId: paymentId,
      bookingRequestId: bookingRequestId,
      tripId: tripId,
      amountFils: amountFils,
      currency: currency,
      status: status,
      version: version,
      idempotencyKey: idempotencyKey,
    );

Matcher paymentFailure(PaymentFailure failure) => isA<PaymentException>()
    .having((error) => error.failure, 'failure', failure);

void main() {
  group('Backend payment vocabulary', () {
    test('round-trips both exact payment method values', () {
      expect(PaymentMethod.values.map((method) => method.backendValue),
          ['cash', 'card']);
      for (final method in PaymentMethod.values) {
        expect(PaymentMethod.fromBackendValue(method.backendValue), method);
      }
    });

    test('round-trips all exact Cash status values', () {
      expect(CashPaymentStatus.values.map((status) => status.backendValue),
          ['cashSelected', 'paid', 'cancelled']);
      for (final status in CashPaymentStatus.values) {
        expect(CashPaymentStatus.fromBackendValue(status.backendValue), status);
      }
    });

    test('rejects unknown, altered-case and snake_case backend values', () {
      for (final value in ['cash_selected', 'CASH', 'unknown', '']) {
        expect(
            () => PaymentMethod.fromBackendValue(value), throwsArgumentError);
      }
      for (final value in [
        'cash_selected',
        'cashPaid',
        'payment_cancelled',
        ''
      ]) {
        expect(
          () => CashPaymentStatus.fromBackendValue(value),
          throwsArgumentError,
        );
      }
    });
  });

  group('Cash domain lifecycle', () {
    test('cashSelected is unpaid; paid alone is paid; cancelled is terminal',
        () {
      final selected = cashFixture();
      final paid = cashFixture(status: CashPaymentStatus.paid);
      final cancelled = cashFixture(status: CashPaymentStatus.cancelled);

      expect(selected.isPaid, isFalse);
      expect(selected.isTerminal, isFalse);
      expect(paid.isPaid, isTrue);
      expect(paid.isTerminal, isTrue);
      expect(cancelled.isPaid, isFalse);
      expect(cancelled.isTerminal, isTrue);
    });

    test('only cashSelected can transition to paid or cancelled', () {
      for (final from in CashPaymentStatus.values) {
        for (final to in CashPaymentStatus.values) {
          final expected = from == CashPaymentStatus.cashSelected &&
              (to == CashPaymentStatus.paid ||
                  to == CashPaymentStatus.cancelled);
          expect(canTransitionCash(from, to), expected, reason: '$from -> $to');
        }
      }
    });

    test('transition predicate cannot settle a seeded payment', () async {
      final fake = FakePaymentRepository()..seedCashPayment(cashFixture());
      PaymentRepository repository = fake;

      expect(
          canTransitionCash(
              CashPaymentStatus.cashSelected, CashPaymentStatus.paid),
          isTrue);
      expect((await repository.readCashPayment(paymentId: 'payment-1')).status,
          CashPaymentStatus.cashSelected);
    });
  });

  group('CashPayment validation and value', () {
    test('accepts zero and integer fils in JOD', () {
      expect(cashFixture(amountFils: 0).amountFils, 0);
      expect(cashFixture(amountFils: 1251).amountFils, 1251);
      expect(cashFixture().currency, 'JOD');
    });

    test('rejects negative fils, non-JOD currency and nonpositive versions',
        () {
      expect(() => cashFixture(amountFils: -1), throwsArgumentError);
      expect(() => cashFixture(currency: 'USD'), throwsArgumentError);
      expect(() => cashFixture(version: 0), throwsArgumentError);
      expect(() => cashFixture(version: -1), throwsArgumentError);
    });

    test('rejects blank optional identifiers when provided', () {
      expect(() => cashFixture(paymentId: ' '), throwsArgumentError);
      expect(() => cashFixture(bookingRequestId: '\t'), throwsArgumentError);
      expect(() => cashFixture(tripId: ''), throwsArgumentError);
      expect(() => cashFixture(idempotencyKey: '  '), throwsArgumentError);
    });

    test('permits nullable identifiers in the domain representation', () {
      final unpersisted = CashPayment(
        amountFils: 0,
        status: CashPaymentStatus.cashSelected,
        version: 1,
      );
      expect(unpersisted.paymentId, isNull);
      expect(unpersisted.bookingRequestId, isNull);
      expect(unpersisted.tripId, isNull);
      expect(unpersisted.idempotencyKey, isNull);
    });

    test('uses immutable value fields for Equatable equality', () {
      final original = cashFixture(idempotencyKey: 'original-command');
      expect(cashFixture(idempotencyKey: 'original-command'), original);
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
          ]));
      expect(cashFixture(version: 2, idempotencyKey: 'original-command'),
          isNot(original));
      expect(
          cashFixture(
              status: CashPaymentStatus.paid,
              idempotencyKey: 'original-command'),
          isNot(original));
    });
  });

  group('Read-only payment repository fixture', () {
    test('returns seeded canonical states deterministically by payment ID',
        () async {
      final fake = FakePaymentRepository();
      final selected = cashFixture();
      final settled = cashFixture(
        paymentId: 'payment-2',
        bookingRequestId: 'booking-2',
        tripId: 'trip-2',
        status: CashPaymentStatus.paid,
        version: 2,
      );
      fake.seedCashPayment(selected);
      fake.seedCashPayment(settled);
      PaymentRepository repository = fake;

      expect(
          await repository.readCashPayment(paymentId: 'payment-1'), selected);
      expect(await repository.readCashPayment(paymentId: 'payment-2'), settled);
      expect(
          await repository.readCashPayment(paymentId: 'payment-1'), selected);
    });

    test('rejects blank read IDs with a typed invalidRequest', () async {
      PaymentRepository repository = FakePaymentRepository();
      for (final paymentId in ['', '  ']) {
        await expectLater(
          repository.readCashPayment(paymentId: paymentId),
          throwsA(paymentFailure(PaymentFailure.invalidRequest)),
        );
      }
    });

    test('rejects unknown read IDs with a typed notFound', () async {
      PaymentRepository repository = FakePaymentRepository();
      await expectLater(
        repository.readCashPayment(paymentId: 'missing'),
        throwsA(paymentFailure(PaymentFailure.notFound)),
      );
    });

    test('rejects duplicate payment, booking and Trip identities', () async {
      final fake = FakePaymentRepository()..seedCashPayment(cashFixture());
      final duplicates = [
        cashFixture(
            paymentId: 'payment-1',
            bookingRequestId: 'booking-2',
            tripId: 'trip-2'),
        cashFixture(
            paymentId: 'payment-2',
            bookingRequestId: 'booking-1',
            tripId: 'trip-2'),
        cashFixture(
            paymentId: 'payment-2',
            bookingRequestId: 'booking-2',
            tripId: 'trip-1'),
      ];
      for (final duplicate in duplicates) {
        expect(() => fake.seedCashPayment(duplicate),
            throwsA(paymentFailure(PaymentFailure.invalidRequest)));
      }
      expect(await fake.readCashPayment(paymentId: 'payment-1'), cashFixture());
      await expectLater(fake.readCashPayment(paymentId: 'payment-2'),
          throwsA(paymentFailure(PaymentFailure.notFound)));
    });

    test('rejects incomplete fixtures before changing stored state', () async {
      final fake = FakePaymentRepository()..seedCashPayment(cashFixture());
      final invalid = [
        CashPayment(
            bookingRequestId: 'booking-2',
            tripId: 'trip-2',
            amountFils: 100,
            status: CashPaymentStatus.cashSelected,
            version: 1),
        CashPayment(
            paymentId: 'payment-2',
            tripId: 'trip-2',
            amountFils: 100,
            status: CashPaymentStatus.cashSelected,
            version: 1),
        CashPayment(
            paymentId: 'payment-2',
            bookingRequestId: 'booking-2',
            amountFils: 100,
            status: CashPaymentStatus.cashSelected,
            version: 1),
      ];
      for (final fixture in invalid) {
        expect(() => fake.seedCashPayment(fixture),
            throwsA(paymentFailure(PaymentFailure.invalidRequest)));
      }
      expect(await fake.readCashPayment(paymentId: 'payment-1'), cashFixture());
      await expectLater(fake.readCashPayment(paymentId: 'payment-2'),
          throwsA(paymentFailure(PaymentFailure.notFound)));

      final valid = cashFixture(
          paymentId: 'payment-2',
          bookingRequestId: 'booking-2',
          tripId: 'trip-2');
      fake.seedCashPayment(valid);
      expect(await fake.readCashPayment(paymentId: 'payment-2'), valid);
    });
  });
}
