import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_controller.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';

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

RiderCheckoutTrip _trip({
  String tripId = _tripId,
  String riderId = _riderId,
  int version = 4,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
  PaymentMethod method = PaymentMethod.card,
}) => RiderCheckoutTrip(
      tripId: tripId,
      bookingRequestId: _bookingId,
      riderId: riderId,
      driverId: _driverId,
      version: version,
      status: status,
      paymentMethod: method,
    );

CardPayment _payment({
  CardPaymentStatus status = CardPaymentStatus.cardPaymentAuthorized,
  int version = 2,
}) => CardPayment(
      paymentId: _paymentId,
      bookingRequestId: _bookingId,
      tripId: _tripId,
      amountFils: 7450,
      status: status,
      version: version,
    );

void main() {
  test('missing Trip never reads Payment', () async {
    final reader = FakeRiderCheckoutReader();
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);

    expect(controller.state.trip, isA<RiderCheckoutTripUnavailable>());
    expect(controller.state.payment, isA<RiderCheckoutPaymentUnavailable>());
    expect(reader.paymentReads, isEmpty);
  });

  test('Cash Trip cannot read or initiate Card checkout', () async {
    final reader = FakeRiderCheckoutReader()
      ..trip = _trip(method: PaymentMethod.cash);
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);

    expect(controller.state.trip, isA<RiderCheckoutTripIneligible>());
    expect(controller.state.payment, isA<RiderCheckoutPaymentUnavailable>());
    expect(reader.paymentReads, isEmpty);
  });

  test('eligible assigned Card Trip maps canonical authorization separately',
      () async {
    final reader = FakeRiderCheckoutReader()
      ..trip = _trip()
      ..payment = _payment();
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);

    expect(controller.state.trip, isA<RiderCheckoutTripEligible>());
    expect(controller.state.payment, isA<RiderCheckoutAuthorized>());
    expect(reader.paymentReads, [_tripId]);
  });

  test('terminal Trip clears checkout and never reads Card status', () async {
    final reader = FakeRiderCheckoutReader()
      ..trip = _trip(status: DriverTripLifecycleStatus.cancelledByRider);
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);

    expect(controller.state.trip, isA<RiderCheckoutTripTerminal>());
    expect(controller.state.payment, isA<RiderCheckoutPaymentUnavailable>());
    expect(reader.paymentReads, isEmpty);
  });

  test('older Trip version is stale and cannot restore Payment state', () async {
    final reader = FakeRiderCheckoutReader()
      ..trip = _trip(version: 5)
      ..payment = _payment();
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);
    reader.trip = _trip(version: 4);
    await controller.refresh(tripId: _tripId);

    expect(controller.state.trip, isA<RiderCheckoutTripStale>());
    expect(controller.state.payment, isA<RiderCheckoutPaymentUnavailable>());
    expect(reader.paymentReads, [_tripId]);
  });

  test('unknown Payment read stays unknown and retry is read-only', () async {
    final reader = FakeRiderCheckoutReader()
      ..trip = _trip()
      ..paymentError = const RiderCheckoutPaymentReadException(
        RiderCheckoutPaymentReadFailure.unknownOutcome,
      );
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);
    expect(controller.state.payment, isA<RiderCheckoutPaymentUnknown>());
    await controller.retry();

    expect(controller.state.payment, isA<RiderCheckoutActionRequired>());
    expect(reader.paymentReads, [_tripId, _tripId]);
  });

  test('duplicate refresh shares the outstanding canonical read', () async {
    final tripGate = Completer<RiderCheckoutTrip?>();
    final reader = FakeRiderCheckoutReader()..tripGate = tripGate;
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    final first = controller.refresh(tripId: _tripId);
    final duplicate = controller.refresh(tripId: _tripId);
    expect(duplicate, same(first));
    expect(reader.tripReads, [_tripId]);
    tripGate.complete(_trip());
    await first;

    expect(reader.tripReads, [_tripId]);
    expect(controller.state.payment, isA<RiderCheckoutActionRequired>());
  });

  test('session replacement fences a pending Payment read', () async {
    final paymentGate = Completer<CardPayment?>();
    final paymentReadStarted = Completer<void>();
    final reader = FakeRiderCheckoutReader()
      ..trip = _trip()
      ..paymentGate = paymentGate
      ..paymentReadStarted = paymentReadStarted;
    var session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    final pending = controller.refresh(tripId: _tripId);
    await paymentReadStarted.future;
    session = const SessionState.unauthenticated();
    controller.sessionChanged();
    paymentGate.complete(_payment());
    await pending;

    expect(controller.state.trip, isA<RiderCheckoutTripUnavailable>());
    expect(controller.state.payment, isA<RiderCheckoutPaymentUnavailable>());
  });

  test('Rider A to B to A replacement fences the first session response',
      () async {
    final paymentGate = Completer<CardPayment?>();
    final paymentStarted = Completer<void>();
    final reader = FakeRiderCheckoutReader()
      ..trip = _trip()
      ..paymentGate = paymentGate
      ..paymentReadStarted = paymentStarted;
    var session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    final firstSessionRead = controller.refresh(tripId: _tripId);
    await paymentStarted.future;
    session = SessionState.fromUser(AppUser(
      id: '66666666-6666-4666-8666-666666666666',
      name: 'Other Rider',
      email: 'other@example.test',
      role: RideRole.rider,
    ));
    controller.sessionChanged();
    session = SessionState.fromUser(_rider);
    controller.sessionChanged();
    paymentGate.complete(_payment());
    await firstSessionRead;

    expect(controller.state.trip, isA<RiderCheckoutTripUnavailable>());
    expect(controller.state.payment, isA<RiderCheckoutPaymentUnavailable>());
    expect(reader.paymentReads, [_tripId]);
  });

  test('older Payment version is unknown and cannot replace newer status',
      () async {
    final reader = FakeRiderCheckoutReader()
      ..trip = _trip()
      ..payment = _payment(version: 3);
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);
    reader.payment = _payment(version: 2, status: CardPaymentStatus.cardPaymentPending);
    await controller.refresh(tripId: _tripId);

    expect(controller.state.payment, isA<RiderCheckoutPaymentUnknown>());
    expect(reader.paymentReads, [_tripId, _tripId]);
  });

  test('trip read failure can be retried without payment actions', () async {
    final reader = FakeRiderCheckoutReader()
      ..tripError = const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.unavailable,
      );
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);
    expect(controller.state.trip, isA<RiderCheckoutTripReadError>());
    reader.trip = _trip();
    await controller.retry();

    expect(controller.state.trip, isA<RiderCheckoutTripEligible>());
    expect(controller.state.payment, isA<RiderCheckoutActionRequired>());
    expect(reader.paymentReads, [_tripId]);
  });

  test('blocked Rider cannot read or view Trip Payment data', () async {
    final blocked = AppUser(
      id: _riderId,
      name: 'Blocked Rider',
      email: 'blocked@example.test',
      role: RideRole.rider,
      isBlocked: true,
    );
    final reader = FakeRiderCheckoutReader()..trip = _trip();
    final session = SessionState.fromUser(blocked);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);

    expect(controller.state.trip, isA<RiderCheckoutTripUnavailable>());
    expect(reader.tripReads, isEmpty);
    expect(reader.paymentReads, isEmpty);
  });

  test('Trip owned by another Rider is unavailable and Payment is not read',
      () async {
    final reader = FakeRiderCheckoutReader()
      ..trip = _trip(riderId: '66666666-6666-4666-8666-666666666666');
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);

    expect(controller.state.trip, isA<RiderCheckoutTripUnavailable>());
    expect(reader.paymentReads, isEmpty);
  });

  test('late read for previous Trip cannot replace selected Trip state',
      () async {
    const otherTripId = '77777777-7777-4777-8777-777777777777';
    final firstTripGate = Completer<RiderCheckoutTrip?>();
    final reader = FakeRiderCheckoutReader()
      ..trip = _trip(tripId: otherTripId)
      ..tripGate = firstTripGate;
    final session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    final oldRead = controller.refresh(tripId: _tripId);
    final currentRead = controller.refresh(tripId: otherTripId);
    await currentRead;
    firstTripGate.complete(_trip());
    await oldRead;

    final state = controller.state.trip;
    if (state is RiderCheckoutTripEligible) {
      expect(state.trip.tripId, otherTripId);
    } else {
      fail('Expected the current Trip to remain eligible.');
    }
  });
}
