import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/repositories/canonical_payment_repository.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_mapper.dart';
import 'package:ridex/features/history/presentation/models/rider_payment_presentation.dart';
import 'package:ridex/features/history/presentation/widgets/rider_payment_status_card.dart';

const id = 'c7000000-0000-0000-0000-000000000001';
const booking = 'c7000000-0000-0000-0000-000000000002';
const trip = 'c7000000-0000-0000-0000-000000000003';
Map<String, dynamic> row() => {
      'id': id,
      'booking_request_id': booking,
      'trip_id': trip,
      'rider_id': 'c7000000-0000-0000-0000-000000000004',
      'final_amount_fils': 13300,
      'version': 7,
      'currency': 'JOD',
      'card_brand': 'Visa',
      'card_last_four': '4242',
    };
const callerEvidence = RiderPaymentTripEvidence(
    paymentId: id,
    tripId: trip,
    bookingRequestId: booking,
    tripStatus: TripStatus.completed);

// Cross-component fixture acceptance, never live settlement or issued receipt evidence.
void main() {
  for (final status in CashPaymentStatus.values) {
    test(
        'canonical Cash ${status.name} reaches Admin/Rider without invented authority',
        () {
      final record = CanonicalPaymentRecord.fromRow({
        ...row(),
        'method': 'cash',
        'cash_status': status.backendValue,
        'card_status': null
      }) as CanonicalCashPayment;
      expect(record.payment.version, 7);
      expect(record.payment.bookingRequestId, booking);
      expect(record.payment.idempotencyKey, isNull);
      expect(mapCashPaymentForAdmin(record.payment).amountDisplay, 'JOD 13.30');
      final presentation = RiderPaymentPresentation.fromCash(record.payment,
          tripEvidence: callerEvidence);
      expect(presentation.issuedReceiptExists, isNull);
      final display = RiderPaymentStatusDisplay.failClosed(presentation);
      expect(display.title, isNot('Payment completed'));
      if (status == CashPaymentStatus.paid) {
        expect(display.unverifiedSuccess, isTrue);
      }
    });
  }
  for (final status in CardPaymentStatus.values) {
    test(
        'canonical Card ${status.name} reaches Admin/Rider without inferring capture',
        () {
      final record = CanonicalPaymentRecord.fromRow({
        ...row(),
        'method': 'card',
        'cash_status': null,
        'card_status': status.backendValue
      }) as CanonicalCardPayment;
      final admin = mapCardPaymentForAdmin(record.payment);
      expect(admin.amountDisplay, 'JOD 13.30');
      expect(admin.maskedCardLastFourDisplay, contains('4242'));
      final presentation = RiderPaymentPresentation.fromCard(record.payment,
          tripEvidence: callerEvidence);
      expect(presentation.amountFils, 13300);
      expect(presentation.issuedReceiptExists, isNull);
      final display = RiderPaymentStatusDisplay.failClosed(presentation);
      expect(display.title, isNot('Payment captured'));
      if (status == CardPaymentStatus.cardPaymentSucceeded) {
        expect(display.unverifiedSuccess, isTrue);
      }
    });
  }
}
