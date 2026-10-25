import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/repositories/supabase_admin_payment_reader.dart';

Map<String, Object?> row({
  String method = 'cash',
  Object? cashStatus = 'cashSelected',
  Object? cardStatus,
  Object? cardBrand,
  Object? cardLastFour,
}) => {
  'id': 'private-payment-id',
  'booking_request_id': 'private-booking-id',
  'trip_id': 'private-trip-id',
  'rider_id': 'private-rider-id',
  'method': method,
  'final_amount_fils': 4200,
  'currency': 'JOD',
  'cash_status': cashStatus,
  'card_status': cardStatus,
  'version': 2,
  'card_brand': cardBrand,
  'card_last_four': cardLastFour,
};

void main() {
  test('cashSelected stays unpaid; identifiers never reach display fields', () {
    final payments = parseAdminCanonicalPayments([row()]);
    expect(payments, hasLength(1));
    final payment = payments.single;
    expect(payment.methodLabel, 'Cash');
    expect(payment.statusLabel, 'Selected (unpaid)');
    expect(payment.amountDisplay, 'JOD 4.20');
    expect(payment.currencyDisplay, 'JOD');
    expect(payment.cardBrandDisplay, isNull);
    expect(payment.maskedCardLastFourDisplay, isNull);
    expect(payment.toString(), isNot(contains('private-payment-id')));
  });

  test('card fields are allowlisted and last four masked', () {
    final payments = parseAdminCanonicalPayments([
      row(
        method: 'card',
        cashStatus: null,
        cardStatus: 'cardPaymentSucceeded',
        cardBrand: 'Visa',
        cardLastFour: '4242',
      ),
    ]);
    expect(payments.single.methodLabel, 'Card');
    expect(payments.single.statusLabel, 'Succeeded');
    expect(payments.single.cardBrandDisplay, 'Visa');
    expect(payments.single.maskedCardLastFourDisplay, '•••• 4242');
  });

  test('unknown card brand is not passed through', () {
    final payments = parseAdminCanonicalPayments([
      row(
        method: 'card',
        cashStatus: null,
        cardStatus: 'cardPaymentPending',
        cardBrand: 'sk_secret_brand',
      ),
    ]);
    expect(payments.single.cardBrandDisplay, isNull);
  });

  test('empty list is an authorized empty result', () {
    expect(parseAdminCanonicalPayments([]), isEmpty);
  });

  test('rejects malformed responses and incomplete rows', () {
    expect(() => parseAdminCanonicalPayments(null), throwsFormatException);
    expect(() => parseAdminCanonicalPayments({}), throwsFormatException);
    expect(() => parseAdminCanonicalPayments([1]), throwsFormatException);
    expect(
      () => parseAdminCanonicalPayments([{
        ...row(),
        'final_amount_fils': '4200',
      }]),
      throwsFormatException,
    );
    expect(
      () => parseAdminCanonicalPayments([{
        ...row(),
        'trip_id': null,
      }]),
      throwsFormatException,
    );
    expect(
      () => parseAdminCanonicalPayments([{
        ...row(),
        'card_status': 'cardPaymentSucceeded',
      }]),
      throwsFormatException,
    );
  });

  test('rejects invalid statuses, currency and unmasked card data', () {
    expect(
      () => parseAdminCanonicalPayments([row(cashStatus: 'paid_fake')]),
      throwsArgumentError,
    );
    expect(
      () => parseAdminCanonicalPayments([{
        ...row(),
        'currency': 'USD',
      }]),
      throwsArgumentError,
    );
    expect(
      () => parseAdminCanonicalPayments([
        row(
          method: 'card',
          cashStatus: null,
          cardStatus: 'cardPaymentPending',
          cardLastFour: '4242424242424242',
        ),
      ]),
      throwsArgumentError,
    );
  });

  test('refuses responses exceeding server limit', () {
    expect(
      () => parseAdminCanonicalPayments(List.generate(51, (_) => row())),
      throwsFormatException,
    );
  });
}
