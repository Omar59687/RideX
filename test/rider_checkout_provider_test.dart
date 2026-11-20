import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_controller.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';
import 'package:ridex/features/rider_payments/presentation/providers/rider_checkout_controller_provider.dart';

import 'helpers/fake_rider_checkout_reader.dart';

const _tripId = 'a1b2c3d4-e5f6-4a1b-8c2d-a1b2c3d4e5f6';
const _bookingId = '22222222-2222-4222-8222-222222222222';
const _riderId = '33333333-3333-4333-8333-333333333333';
const _driverId = '44444444-4444-4444-8444-444444444444';
const _paymentId = '55555555-5555-4555-8555-555555555555';

final _rider = AppUser(
  id: _riderId,
  name: 'Rider',
  email: 'rider@example.test',
  role: RideRole.rider,
);

class _TestSessionController extends SessionController {
  @override
  SessionState build() => SessionState.fromUser(_rider);
}

RiderCheckoutTrip _trip() => RiderCheckoutTrip(
      tripId: _tripId,
      bookingRequestId: _bookingId,
      riderId: _riderId,
      driverId: _driverId,
      version: 3,
      status: DriverTripLifecycleStatus.accepted,
      paymentMethod: PaymentMethod.card,
    );

CardPayment _capturedPayment() => CardPayment(
      paymentId: _paymentId,
      bookingRequestId: _bookingId,
      tripId: _tripId,
      amountFils: 7450,
      status: CardPaymentStatus.cardPaymentSucceeded,
      version: 2,
    );

RiderVerifiedReceipt _receipt() => RiderVerifiedReceipt(
      receiptId: '66666666-6666-4666-8666-666666666666',
      receiptNumber: 'RDX-PROVIDER-001',
      tripId: _tripId,
      paymentId: _paymentId,
      amountPaidFils: 7450,
      currency: 'JOD',
      paymentMethod: PaymentMethod.card,
      issuedAt: DateTime.utc(2026, 11, 20),
    );

void main() {
  test('default receipt reader remains unavailable', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final reader = container.read(riderReceiptReaderProvider);

    expect(reader, isA<UnavailableRiderReceiptReader>());
    await expectLater(
      reader.readReceipt(tripId: _tripId, paymentId: _paymentId),
      throwsA(isA<RiderReceiptUnavailableException>()),
    );
  });

  test('feature provider injects receipt reads without shared wiring', () async {
    final checkoutReader = FakeRiderCheckoutReader()
      ..trip = _trip()
      ..payment = _capturedPayment();
    final receiptReader = FakeRiderReceiptReader()..receipt = _receipt();
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        riderCheckoutReaderProvider.overrideWithValue(checkoutReader),
        riderReceiptReaderProvider.overrideWithValue(receiptReader),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(riderCheckoutControllerProvider);
    await controller.refresh(tripId: _tripId);

    expect(controller.state.receipt, isA<RiderReceiptVerified>());
    expect(receiptReader.reads, [(tripId: _tripId, paymentId: _paymentId)]);
  });
}
