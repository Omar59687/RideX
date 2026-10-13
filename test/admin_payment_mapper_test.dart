import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_mapper.dart';

/// P6-08 Slice B mapper unit tests.
///
/// Verifies the allowlist mapping from the canonical P6-01/P6-03 domain
/// objects to the sanitized Admin display model, using synthetic fixtures
/// only. Widget rendering is covered in `admin_payment_visibility_test.dart`.
void main() {
  CashPayment cashFixture({
    CashPaymentStatus status = CashPaymentStatus.cashSelected,
    int amountFils = 4200,
  }) {
    return CashPayment(
      paymentId: 'pay-cash-1',
      bookingRequestId: 'booking-1',
      tripId: 'trip-1',
      amountFils: amountFils,
      status: status,
      version: 2,
      idempotencyKey: 'idem-cash-1',
    );
  }

  CardPayment cardFixture({
    CardPaymentStatus status = CardPaymentStatus.cardPaymentPending,
    int amountFils = 4200,
    String? cardBrand = 'Visa',
    String? cardLastFour = '4242',
  }) {
    return CardPayment(
      paymentId: 'pay-card-1',
      bookingRequestId: 'booking-2',
      tripId: 'trip-2',
      amountFils: amountFils,
      status: status,
      version: 3,
      idempotencyKey: 'idem-card-1',
      cardBrand: cardBrand,
      cardLastFour: cardLastFour,
    );
  }

  List<String?> displayFields(AdminSanitizedPayment payment) => [
        payment.methodLabel,
        payment.statusLabel,
        payment.amountDisplay,
        payment.currencyDisplay,
        payment.cardBrandDisplay,
        payment.maskedCardLastFourDisplay,
      ];

  group('method and status labels', () {
    test('covers all three canonical Cash statuses', () {
      expect(
        mapCashPaymentForAdmin(
          cashFixture(status: CashPaymentStatus.cashSelected),
        ).statusLabel,
        'Selected (unpaid)',
      );
      expect(
        mapCashPaymentForAdmin(
          cashFixture(status: CashPaymentStatus.paid),
        ).statusLabel,
        'Paid',
      );
      expect(
        mapCashPaymentForAdmin(
          cashFixture(status: CashPaymentStatus.cancelled),
        ).statusLabel,
        'Cancelled',
      );
    });

    test('cashSelected is never displayed as paid', () {
      final payment = cashFixture(status: CashPaymentStatus.cashSelected);
      expect(payment.isPaid, isFalse);

      final display = mapCashPaymentForAdmin(payment);
      expect(display.methodLabel, 'Cash');
      expect(display.statusLabel, isNot('Paid'));
      expect(display.statusLabel, contains('unpaid'));
    });

    test('covers all seven canonical Card statuses', () {
      const expected = {
        CardPaymentStatus.cardPaymentPending: 'Pending',
        CardPaymentStatus.cardPaymentAuthorized: 'Authorized',
        CardPaymentStatus.cardPaymentSucceeded: 'Succeeded',
        CardPaymentStatus.cardPaymentFailed: 'Failed',
        CardPaymentStatus.paymentCancelled: 'Cancelled',
        CardPaymentStatus.refundPending: 'Refund pending',
        CardPaymentStatus.refunded: 'Refunded',
      };
      for (final entry in expected.entries) {
        expect(
          mapCardPaymentForAdmin(cardFixture(status: entry.key)).statusLabel,
          entry.value,
          reason: entry.key.name,
        );
      }
      expect(
        mapCardPaymentForAdmin(cardFixture()).methodLabel,
        'Card',
      );
    });

    test('method labels follow the canonical PaymentMethod enum', () {
      expect(
        adminPaymentMethodLabel(PaymentMethod.cash),
        mapCashPaymentForAdmin(cashFixture()).methodLabel,
      );
      expect(
        adminPaymentMethodLabel(PaymentMethod.card),
        mapCardPaymentForAdmin(cardFixture()).methodLabel,
      );
    });
  });

  group('money formatting', () {
    test('formats integer fils as JOD at 1000 fils per dinar', () {
      expect(
        mapCashPaymentForAdmin(cashFixture(amountFils: 0)).amountDisplay,
        'JOD 0.00',
      );
      expect(
        mapCashPaymentForAdmin(cashFixture(amountFils: 4200)).amountDisplay,
        'JOD 4.20',
      );
      expect(
        mapCardPaymentForAdmin(cardFixture(amountFils: 1990)).amountDisplay,
        'JOD 1.99',
      );
      expect(
        mapCardPaymentForAdmin(cardFixture(amountFils: 5)).amountDisplay,
        'JOD 0.01',
      );
    });

    test('displays the validated canonical currency', () {
      expect(
        mapCashPaymentForAdmin(cashFixture()).currencyDisplay,
        'JOD',
      );
      expect(
        mapCardPaymentForAdmin(cardFixture()).currencyDisplay,
        'JOD',
      );
    });
  });

  group('card metadata', () {
    test('optional brand follows the actual model constructor rules', () {
      expect(cardFixture(cardBrand: null).cardBrand, isNull);
      expect(() => cardFixture(cardBrand: ''), throwsArgumentError);
      expect(() => cardFixture(cardBrand: '   '), throwsArgumentError);
      expect(() => cardFixture(cardBrand: 'x' * 33), throwsArgumentError);
      expect(
        mapCardPaymentForAdmin(cardFixture(cardBrand: ' Visa '))
            .cardBrandDisplay,
        'Visa',
      );
    });

    test('unknown and sensitive brand strings are omitted', () {
      for (final brand in [
        'Unknown brand',
        'sk_test_secret',
        'service_role',
        '4242424242424242',
        'raw payload',
      ]) {
        // These strings pass the domain length check, so display sanitization
        // must still exclude them.
        final display =
            AdminSanitizedPayment.fromCard(cardFixture(cardBrand: brand));
        expect(display.cardBrandDisplay, isNull);
        expect(display.maskedCardLastFourDisplay, '•••• 4242');
      }
    });

    test('last four can be displayed without a brand', () {
      final display = mapCardPaymentForAdmin(cardFixture(cardBrand: null));
      expect(display.cardBrandDisplay, isNull);
      expect(display.maskedCardLastFourDisplay, '•••• 4242');
    });
    test('shows brand and masked last four', () {
      final display = mapCardPaymentForAdmin(cardFixture());

      expect(display.cardBrandDisplay, 'Visa');
      expect(display.maskedCardLastFourDisplay, '•••• 4242');
    });

    test('omits card rows when metadata is absent', () {
      final display = mapCardPaymentForAdmin(
        cardFixture(cardBrand: null, cardLastFour: null),
      );

      expect(display.cardBrandDisplay, isNull);
      expect(display.maskedCardLastFourDisplay, isNull);
    });

    test('cash never carries card metadata', () {
      final display = mapCashPaymentForAdmin(cashFixture());

      expect(display.cardBrandDisplay, isNull);
      expect(display.maskedCardLastFourDisplay, isNull);
    });
  });

  group('sanitization boundary', () {
    test('typed factories reject raw strings and payload maps', () {
      for (final input in <dynamic>[
        'sk_test_secret',
        {'statusLabel': 'sk_test_secret'},
      ]) {
        expect(() => AdminSanitizedPayment.fromCash(input),
            throwsA(isA<TypeError>()));
        expect(() => AdminSanitizedPayment.fromCard(input),
            throwsA(isA<TypeError>()));
      }
    });

    test('typed factories expose no free-form display arguments', () {
      for (final field in [
        #methodLabel,
        #statusLabel,
        #amountDisplay,
        #currencyDisplay,
        #cardBrandDisplay,
        #maskedCardLastFourDisplay,
      ]) {
        expect(
          () => Function.apply(AdminSanitizedPayment.fromCash, [cashFixture()],
              {field: 'sk_test_secret'}),
          throwsNoSuchMethodError,
        );
        expect(
          () => Function.apply(AdminSanitizedPayment.fromCard, [cardFixture()],
              {field: 'sk_test_secret'}),
          throwsNoSuchMethodError,
        );
      }
    });

    test('mask rejects invalid input with runtime errors and no input echo',
        () {
      for (final input in [
        '',
        '123',
        '12345',
        '4242424242424242',
        '１２３４',
        '12a4',
        '1234\n',
        'sk_test_secret',
      ]) {
        expect(
          () => maskCardLastFour(input),
          throwsA(isA<ArgumentError>()
              .having((error) => error.message, 'message',
                  'Expected exactly four ASCII digits.')
              .having((error) => error.invalidValue, 'invalidValue', isNull)),
        );
      }
      expect(maskCardLastFour('0000'), '•••• 0000');
    });
    test('never emits identifiers, versions, or idempotency keys', () {
      const secrets = [
        'pay-cash-1',
        'pay-card-1',
        'booking-1',
        'booking-2',
        'trip-1',
        'trip-2',
        'idem-cash-1',
        'idem-card-1',
      ];
      final displays = [
        mapCashPaymentForAdmin(cashFixture()),
        mapCardPaymentForAdmin(cardFixture()),
      ];
      for (final display in displays) {
        for (final field in displayFields(display)) {
          if (field == null) continue;
          for (final secret in secrets) {
            expect(field, isNot(contains(secret)), reason: field);
          }
        }
      }
    });

    test('never emits raw card numbers', () {
      final display = mapCardPaymentForAdmin(cardFixture());
      for (final field in displayFields(display)) {
        if (field == null) continue;
        expect(field, isNot(contains('4242424242424242')));
        // Only the masked last four may appear, never bare digits.
        expect(field.contains('4242'), field.contains('••••'));
      }
    });

    test('mapper accepts only typed domain objects', () {
      // Invalid domain input fails at the contract constructor, before the
      // mapper ever runs: no untrusted-string path exists.
      expect(
        () => cardFixture(cardLastFour: '4242424242424242'),
        throwsArgumentError,
      );
      expect(() => cashFixture(amountFils: -1), throwsArgumentError);
    });
  });
}
