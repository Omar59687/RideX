import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_controller.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_launcher.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';

import 'helpers/fake_rider_checkout_launcher.dart';
import 'helpers/fake_rider_checkout_reader.dart';

const _tripId = 'a1b2c3d4-e5f6-4a1b-8c2d-a1b2c3d4e5f6';
const _bookingId = '22222222-2222-4222-8222-222222222222';
const _riderId = '33333333-3333-4333-8333-333333333333';
const _driverId = '44444444-4444-4444-8444-444444444444';

final _rider = AppUser(
  id: _riderId,
  name: 'Rider',
  email: 'rider@example.test',
  role: RideRole.rider,
);

RiderCheckoutTrip _trip({PaymentMethod method = PaymentMethod.card}) =>
    RiderCheckoutTrip(
      tripId: _tripId,
      bookingRequestId: _bookingId,
      riderId: _riderId,
      driverId: _driverId,
      version: 4,
      status: DriverTripLifecycleStatus.accepted,
      paymentMethod: method,
    );

void main() {
  test(
    'return signal is advisory and canonical reread remains authoritative',
    () async {
      final reader = FakeRiderCheckoutReader()..trip = _trip();
      final launcher = FakeRiderCheckoutLauncher()
        ..result = RiderCheckoutReturnSignal.returned;
      final session = SessionState.fromUser(_rider);
      final controller = RiderCheckoutController(
        reader: reader,
        launcher: launcher,
        readSession: () => session,
      );
      addTearDown(controller.dispose);

      await controller.refresh(tripId: _tripId);
      expect(controller.state.payment, isA<RiderCheckoutActionRequired>());
      await controller.startCheckout();

      expect(launcher.requests, hasLength(1));
      expect(launcher.requests.single.tripId, _tripId);
      expect(launcher.requests.single.expectedTripVersion, 4);
      expect(controller.state.payment, isA<RiderCheckoutActionRequired>());
      // Initial read, pre-handoff check, and mandatory post-return reconciliation.
      expect(reader.paymentReads, [_tripId, _tripId, _tripId]);
    },
  );

  test(
    'duplicate handoff calls share one launch and cannot relaunch',
    () async {
      final reader = FakeRiderCheckoutReader()..trip = _trip();
      final started = Completer<void>();
      final gate = Completer<RiderCheckoutReturnSignal>();
      final launcher = FakeRiderCheckoutLauncher()
        ..launchStarted = started
        ..gate = gate;
      final session = SessionState.fromUser(_rider);
      final controller = RiderCheckoutController(
        reader: reader,
        launcher: launcher,
        readSession: () => session,
      );
      addTearDown(controller.dispose);

      await controller.refresh(tripId: _tripId);
      final first = controller.startCheckout();
      await started.future;
      final duplicate = controller.startCheckout();
      expect(duplicate, same(first));
      gate.complete(RiderCheckoutReturnSignal.returned);
      await first;
      await controller.startCheckout();

      expect(launcher.requests, hasLength(1));
    },
  );

  test(
    'cancelled, malformed, and network returns only trigger canonical reads',
    () async {
      final results = <RiderCheckoutReturnSignal>[
        RiderCheckoutReturnSignal.cancelled,
        RiderCheckoutReturnSignal.malformedReturn,
        RiderCheckoutReturnSignal.networkFailure,
      ];
      for (final result in results) {
        final reader = FakeRiderCheckoutReader()..trip = _trip();
        final launcher = FakeRiderCheckoutLauncher()..result = result;
        final session = SessionState.fromUser(_rider);
        final controller = RiderCheckoutController(
          reader: reader,
          launcher: launcher,
          readSession: () => session,
        );
        await controller.refresh(tripId: _tripId);
        await controller.startCheckout();
        expect(controller.state.payment, isA<RiderCheckoutActionRequired>());
        // Every advisory return must trigger an additional canonical re-read.
        expect(reader.paymentReads, [_tripId, _tripId, _tripId]);
        controller.dispose();
      }
    },
  );

  test(
    'Cash Trip and default disabled launcher cannot start checkout',
    () async {
      final reader = FakeRiderCheckoutReader()
        ..trip = _trip(method: PaymentMethod.cash);
      final session = SessionState.fromUser(_rider);
      final controller = RiderCheckoutController(
        reader: reader,
        readSession: () => session,
      );
      addTearDown(controller.dispose);

      await controller.refresh(tripId: _tripId);
      await controller.startCheckout();

      expect(controller.state.trip, isA<RiderCheckoutTripIneligible>());
      expect(reader.paymentReads, isEmpty);
    },
  );

  test(
    'app resume re-reads canonical status without another handoff',
    () async {
      final reader = FakeRiderCheckoutReader()..trip = _trip();
      final launcher = FakeRiderCheckoutLauncher();
      final session = SessionState.fromUser(_rider);
      final controller = RiderCheckoutController(
        reader: reader,
        launcher: launcher,
        readSession: () => session,
      );
      addTearDown(controller.dispose);

      await controller.refresh(tripId: _tripId);
      await controller.startCheckout();
      final launchCount = launcher.requests.length;
      await controller.onAppResumed();

      // Initial, pre-handoff, post-return, and explicit app-resume read.
      expect(reader.paymentReads, [_tripId, _tripId, _tripId, _tripId]);
      expect(launcher.requests, hasLength(launchCount));
    },
  );

  test('logout during provider UI fences its late return signal', () async {
    final reader = FakeRiderCheckoutReader()..trip = _trip();
    final started = Completer<void>();
    final gate = Completer<RiderCheckoutReturnSignal>();
    final launcher = FakeRiderCheckoutLauncher()
      ..launchStarted = started
      ..gate = gate;
    var session = SessionState.fromUser(_rider);
    final controller = RiderCheckoutController(
      reader: reader,
      launcher: launcher,
      readSession: () => session,
    );
    addTearDown(controller.dispose);

    await controller.refresh(tripId: _tripId);
    final pending = controller.startCheckout();
    await started.future;
    session = const SessionState.unauthenticated();
    controller.sessionChanged();
    gate.complete(RiderCheckoutReturnSignal.returned);
    await pending;

    expect(controller.state.trip, isA<RiderCheckoutTripUnavailable>());
    expect(controller.state.payment, isA<RiderCheckoutPaymentUnavailable>());
    // Initial and pre-handoff canonical reads only; the late callback causes
    // no read after the Rider session has been revoked.
    expect(reader.paymentReads, [_tripId, _tripId]);
  });

  test(
    'provider return forces a fresh read after an earlier app-resume read',
    () async {
      final reader = FakeRiderCheckoutReader()..trip = _trip();
      final started = Completer<void>();
      final gate = Completer<RiderCheckoutReturnSignal>();
      final launcher = FakeRiderCheckoutLauncher()
        ..launchStarted = started
        ..gate = gate;
      final session = SessionState.fromUser(_rider);
      final controller = RiderCheckoutController(
        reader: reader,
        launcher: launcher,
        readSession: () => session,
      );
      addTearDown(controller.dispose);

      await controller.refresh(tripId: _tripId);
      final pending = controller.startCheckout();
      await started.future;
      await controller.onAppResumed();
      gate.complete(RiderCheckoutReturnSignal.returned);
      await pending;

      expect(reader.paymentReads, [_tripId, _tripId, _tripId, _tripId]);
      expect(controller.state.payment, isA<RiderCheckoutActionRequired>());
    },
  );

  test(
    'session epoch fences return when A to B to A reuses the same object',
    () async {
      final reader = FakeRiderCheckoutReader()..trip = _trip();
      final started = Completer<void>();
      final gate = Completer<RiderCheckoutReturnSignal>();
      final launcher = FakeRiderCheckoutLauncher()
        ..launchStarted = started
        ..gate = gate;
      final sessionA = SessionState.fromUser(_rider);
      var session = sessionA;
      final controller = RiderCheckoutController(
        reader: reader,
        launcher: launcher,
        readSession: () => session,
      );
      addTearDown(controller.dispose);

      await controller.refresh(tripId: _tripId);
      final oldHandoff = controller.startCheckout();
      await started.future;
      session = SessionState.fromUser(
        AppUser(
          id: '66666666-6666-4666-8666-666666666666',
          name: 'Other Rider',
          email: 'other@example.test',
          role: RideRole.rider,
        ),
      );
      controller.sessionChanged();
      session = sessionA;
      controller.sessionChanged();
      await controller.refresh(tripId: _tripId);
      final paymentReadCountBeforeOldReturn = reader.paymentReads.length;

      gate.complete(RiderCheckoutReturnSignal.returned);
      await oldHandoff;

      expect(reader.paymentReads, hasLength(paymentReadCountBeforeOldReturn));
      expect(controller.state.trip, isA<RiderCheckoutTripEligible>());
      expect(controller.state.payment, isA<RiderCheckoutActionRequired>());
    },
  );
}
