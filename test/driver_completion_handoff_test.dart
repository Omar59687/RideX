import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/features/driver_flow/application/driver_completion_handoff_controller.dart';
import 'package:ridex/features/driver_flow/domain/driver_completion_handoff.dart';
import 'package:ridex/features/driver_flow/presentation/widgets/driver_completion_handoff_panel.dart';
import 'helpers/fake_driver_completion_handoff_reader.dart';
import 'helpers/fake_canonical_driver_port.dart' as f;

void main() {
  late FakeDriverCompletionHandoffReader reader;
  late ValueNotifier<bool> connected;
  late ValueNotifier<int> invalidations;
  late DriverCompletionHandoffController owner;
  setUp(() {
    reader = FakeDriverCompletionHandoffReader();
    connected = ValueNotifier(true);
    invalidations = ValueNotifier(0);
    owner = DriverCompletionHandoffController(
        tripId: f.tripId,
        reader: reader,
        connected: connected,
        authorityInvalidations: invalidations);
  });
  tearDown(() {
    owner.dispose();
    connected.dispose();
    invalidations.dispose();
  });

  test('completed Cash Trip and pending settlement are separate typed evidence',
      () async {
    await owner.refresh();
    final event = owner.event;
    expect(event.tripCompleted, isTrue);
    expect(event.trip!.version, 5);
    expect(event.scope!.owner.driverId, f.driverId);
    expect(event.scope!.owner.epoch, 1);
    expect(event.paymentState, DriverHandoffReadState.verified);
    expect((event.payment as DriverHandoffCashPayment).status,
        CashPaymentStatus.cashSelected);
    expect(event.receiptState, DriverHandoffReadState.missing);
    expect(event.receipt, isNull);
    expect(owner.canRefresh, isTrue);
  });
  for (final status in CardPaymentStatus.values) {
    test(
        'Card $status remains independent of completed Trip and missing receipt',
        () async {
      reader.method = PaymentMethod.card;
      reader.cardStatus = status;
      await owner.refresh();
      expect(owner.event.tripCompleted, isTrue);
      expect((owner.event.payment as DriverHandoffCardPayment).status, status);
      expect(owner.event.receipt, isNull);
    });
  }
  for (final state in [
    DriverHandoffReadState.missing,
    DriverHandoffReadState.unknown,
    DriverHandoffReadState.error,
    DriverHandoffReadState.unauthorized
  ]) {
    test('financial $state never becomes payment or receipt success', () async {
      reader.paymentState = state;
      reader.receiptState = state;
      await owner.refresh();
      expect(owner.event.tripCompleted, isTrue);
      expect(owner.event.paymentState, state);
      expect(owner.event.payment, isNull);
      expect(owner.event.receiptState, state);
      expect(owner.event.receipt, isNull);
    });
  }
  test('delayed independently verified receipt does not infer Cash paid',
      () async {
    await owner.refresh();
    expect(owner.event.receiptState, DriverHandoffReadState.missing);
    reader.receiptState = DriverHandoffReadState.verified;
    await owner.refresh();
    expect(owner.event.receipt!.number, 'R-005');
    expect((owner.event.payment as DriverHandoffCashPayment).status,
        CashPaymentStatus.cashSelected);
  });
  for (final scenario in [
    'foreign-payment-trip',
    'wrong-method',
    'foreign-receipt-trip',
    'wrong-receipt-method',
    'foreign-scope',
    'foreign-trip-driver',
    'foreign-trip-id'
  ]) {
    test('$scenario cannot become current financial evidence', () async {
      switch (scenario) {
        case 'foreign-payment-trip':
          reader.paymentOverride = DriverHandoffCashPayment(
              paymentId: handoffPaymentId,
              tripId: f.otherId,
              version: 7,
              status: CashPaymentStatus.paid);
        case 'wrong-method':
          reader.paymentOverride = DriverHandoffCardPayment(
              paymentId: handoffPaymentId,
              tripId: f.tripId,
              version: 7,
              status: CardPaymentStatus.cardPaymentSucceeded);
        case 'foreign-receipt-trip':
          reader.receiptState = DriverHandoffReadState.verified;
          reader.receiptOverride = DriverHandoffReceipt(
              receiptId: handoffReceiptId,
              tripId: f.otherId,
              method: PaymentMethod.cash,
              number: 'foreign');
        case 'wrong-receipt-method':
          reader.receiptState = DriverHandoffReadState.verified;
          reader.receiptOverride = DriverHandoffReceipt(
              receiptId: handoffReceiptId,
              tripId: f.tripId,
              method: PaymentMethod.card,
              number: 'foreign');
        case 'foreign-scope':
          reader.replyScope = handoffScope(driver: f.otherId);
        case 'foreign-trip-driver':
          reader.tripOverride = DriverHandoffTrip(
              tripId: f.tripId,
              driverId: f.otherId,
              status: DriverTripLifecycleStatus.completed,
              version: 5,
              method: PaymentMethod.cash);
        case 'foreign-trip-id':
          reader.tripOverride = DriverHandoffTrip(
              tripId: f.otherId,
              driverId: f.driverId,
              status: DriverTripLifecycleStatus.completed,
              version: 5,
              method: PaymentMethod.cash);
      }
      await owner.refresh();
      if (scenario.contains('receipt')) {
        expect(owner.event.receiptState, DriverHandoffReadState.error);
        expect(owner.event.receipt, isNull);
      } else if (scenario.contains('payment') || scenario == 'wrong-method') {
        expect(owner.event.paymentState, DriverHandoffReadState.error);
        expect(owner.event.payment, isNull);
      } else {
        expect(owner.event.tripCompleted, isFalse);
        expect(owner.event.payment, isNull);
        expect(reader.calls.length, 1);
      }
    });
  }
  for (final boundary in ['trip', 'payment', 'receipt']) {
    for (final change in ['logout', 'A-B-A', 'revoked']) {
      test(
          '$boundary late result after $change cannot publish into old or replacement scope',
          () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final scope = reader.currentScope;
        if (boundary == 'trip') {
          reader.tripHandler = () async {
            entered.complete();
            await release.future;
            return reader.reply(
                DriverHandoffReadState.verified,
                DriverHandoffTrip(
                    tripId: f.tripId,
                    driverId: f.driverId,
                    status: DriverTripLifecycleStatus.completed,
                    version: 5,
                    method: PaymentMethod.cash));
          };
        }
        if (boundary == 'payment') {
          reader.paymentHandler = () async {
            entered.complete();
            await release.future;
            return reader.reply(
                DriverHandoffReadState.verified, reader.payment());
          };
        }
        if (boundary == 'receipt') {
          reader.receiptHandler = () async {
            entered.complete();
            await release.future;
            return reader
                .reply<DriverHandoffReceipt>(DriverHandoffReadState.missing);
          };
        }
        final pending = owner.refresh();
        await entered.future;
        final captured = owner.event;
        switch (change) {
          case 'logout':
            reader.currentScope =
                handoffScope(driver: null, valid: false, epoch: 2);
          case 'A-B-A':
            reader.currentScope = handoffScope(driver: f.otherId, epoch: 2);
            reader.currentScope = handoffScope(epoch: 3);
          case 'revoked':
            reader.currentScope =
                handoffScope(approved: false, session: scope.sdkSession);
        }
        invalidations.value++;
        release.complete();
        await pending;
        expect(owner.event.tripCompleted, isFalse);
        expect(captured.trip, isNull);
        expect(owner.event.scope, isNull);
        expect(owner.event.payment, isNull);
      });
    }
  }
  for (final boundary in ['payment', 'receipt']) {
    test(
        '$boundary response with foreign scope cannot attach to a verified Trip',
        () async {
      final foreign = handoffScope(driver: f.otherId, epoch: 4);
      if (boundary == 'payment') {
        reader.paymentHandler = () async => DriverHandoffRead(
            scope: foreign,
            tripId: f.tripId,
            state: DriverHandoffReadState.verified,
            evidence: reader.payment());
      } else {
        reader.receiptHandler = () async => DriverHandoffRead(
            scope: foreign,
            tripId: f.tripId,
            state: DriverHandoffReadState.verified,
            evidence: DriverHandoffReceipt(
                receiptId: handoffReceiptId,
                tripId: f.tripId,
                method: PaymentMethod.cash,
                number: 'FOREIGN'));
      }
      await owner.refresh();
      expect(owner.event.tripCompleted, isTrue);
      expect(
          boundary == 'payment'
              ? owner.event.paymentState
              : owner.event.receiptState,
          DriverHandoffReadState.error);
      expect(boundary == 'payment' ? owner.event.payment : owner.event.receipt,
          isNull);
    });
  }
  for (final scenario in [
    'older',
    'same-version-status',
    'terminal-resurrection',
    'changed-method'
  ]) {
    test('canonical Trip $scenario cannot authorize financial reads', () async {
      await owner.refresh();
      reader.calls.clear();
      switch (scenario) {
        case 'older':
          reader.tripVersion = 4;
        case 'same-version-status':
          reader.status = DriverTripLifecycleStatus.inProgress;
        case 'terminal-resurrection':
          reader.tripVersion = 6;
          reader.status = DriverTripLifecycleStatus.inProgress;
        case 'changed-method':
          reader.tripVersion = 6;
          reader.method = PaymentMethod.card;
      }
      await owner.refresh();
      expect(owner.event.tripCompleted, isFalse);
      expect(owner.event.tripState, DriverHandoffReadState.error);
      expect(owner.event.payment, isNull);
      expect(reader.calls, ['trip:${f.tripId}']);
    });
  }
  test(
      'a new UNKNOWN read does not reuse prior independently verified paid status',
      () async {
    reader.cashStatus = CashPaymentStatus.paid;
    await owner.refresh();
    final previous = owner.event;
    reader.paymentState = DriverHandoffReadState.unknown;
    await owner.refresh();
    expect(previous.payment, isNull);
    expect(owner.event.tripCompleted, isTrue);
    expect(owner.event.payment, isNull);
    expect(owner.event.paymentState, DriverHandoffReadState.unknown);
  });

  test(
      'duplicate refreshes share one read sequence and reconnect rejects old callbacks',
      () async {
    final entered = Completer<void>();
    final delayed = Completer<DriverHandoffRead<DriverHandoffPayment>>();
    reader.paymentHandler = () {
      entered.complete();
      return delayed.future;
    };
    final old = owner.refresh();
    expect(identical(old, owner.refresh()), isTrue);
    await entered.future;
    connected.value = false;
    expect(owner.event.payment, isNull);
    reader.paymentHandler = null;
    reader.paymentVersion = 9;
    connected.value = true;
    await owner.refresh();
    final current = owner.event;
    delayed.complete(reader.reply(
        DriverHandoffReadState.verified,
        DriverHandoffCashPayment(
            paymentId: handoffPaymentId,
            tripId: f.tripId,
            version: 7,
            status: CashPaymentStatus.paid)));
    await old;
    expect(current.payment, same(owner.event.payment));
    expect(owner.event.payment!.version, 9);
    expect((owner.event.payment as DriverHandoffCashPayment).status,
        CashPaymentStatus.cashSelected);
  });
  for (final scenario in [
    'older',
    'same-version-status',
    'payment-id',
    'terminal-regression'
  ]) {
    test('rejects $scenario without replacing Payment high-water evidence',
        () async {
      reader.cashStatus = CashPaymentStatus.paid;
      await owner.refresh();
      switch (scenario) {
        case 'older':
          reader.paymentVersion = 6;
        case 'same-version-status':
          reader.cashStatus = CashPaymentStatus.cashSelected;
        case 'payment-id':
          reader.paymentOverride = DriverHandoffCashPayment(
              paymentId: f.otherId,
              tripId: f.tripId,
              version: 8,
              status: CashPaymentStatus.paid);
        case 'terminal-regression':
          reader.paymentVersion = 8;
          reader.cashStatus = CashPaymentStatus.cashSelected;
      }
      await owner.refresh();
      expect(owner.event.paymentState, DriverHandoffReadState.error);
      expect(owner.event.payment, isNull);
      expect(owner.event.tripCompleted, isTrue);
    });
  }
  test(
      'fresh owner after restart rereads completion, Payment and Receipt independently',
      () async {
    reader.paymentState = DriverHandoffReadState.unknown;
    await owner.refresh();
    owner.retire();
    final replacement = DriverCompletionHandoffController(
        tripId: f.tripId,
        reader: reader,
        connected: connected,
        authorityInvalidations: invalidations);
    try {
      expect(replacement.event.tripCompleted, isFalse);
      await replacement.refresh();
      expect(replacement.event.tripCompleted, isTrue);
      expect(replacement.event.paymentState, DriverHandoffReadState.unknown);
      expect(replacement.event.receipt, isNull);
    } finally {
      replacement.dispose();
    }
  });
  test('noncompleted canonical Trip cannot trigger any financial reads',
      () async {
    reader.status = DriverTripLifecycleStatus.inProgress;
    await owner.refresh();
    expect(owner.event.tripCompleted, isFalse);
    expect(reader.calls, ['trip:${f.tripId}']);
  });
  test('typed read cannot carry fabricated success data in UNKNOWN/error', () {
    expect(
        () => DriverHandoffRead(
            scope: reader.currentScope,
            tripId: f.tripId,
            state: DriverHandoffReadState.unknown,
            evidence: reader.payment()),
        throwsArgumentError);
    expect(
        () => DriverHandoffTrip(
            tripId: f.tripId,
            driverId: f.driverId,
            status: DriverTripLifecycleStatus.completed,
            version: 0,
            method: PaymentMethod.cash),
        throwsArgumentError);
  });

  for (final scenario in [
    'cash-pending',
    'card-pending',
    'card-failed',
    'payment-unknown',
    'payment-error',
    'card-captured-no-receipt',
    'receipt-available-with-unknown-payment'
  ]) {
    testWidgets(
        '$scenario widget never infers Paid or issued receipt from Trip',
        (tester) async {
      switch (scenario) {
        case 'card-pending':
          reader.method = PaymentMethod.card;
        case 'card-failed':
          reader.method = PaymentMethod.card;
          reader.cardStatus = CardPaymentStatus.cardPaymentFailed;
        case 'payment-unknown':
          reader.paymentState = DriverHandoffReadState.unknown;
        case 'payment-error':
          reader.paymentState = DriverHandoffReadState.error;
        case 'card-captured-no-receipt':
          reader.method = PaymentMethod.card;
          reader.cardStatus = CardPaymentStatus.cardPaymentSucceeded;
        case 'receipt-available-with-unknown-payment':
          reader.paymentState = DriverHandoffReadState.unknown;
          reader.receiptState = DriverHandoffReadState.verified;
      }
      await tester.runAsync(owner.refresh);
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: Scaffold(
                  body: DriverCompletionHandoffPanel(controller: owner)))));
      expect(find.text('Trip completion verified.'), findsOneWidget);
      expect(find.text('Paid'), findsNothing);
      expect(find.text('Receipt issued'), findsNothing);
      final expected = switch (scenario) {
        'cash-pending' => 'Cash settlement pending.',
        'card-pending' => 'Card authorized. Capture pending.',
        'card-failed' => 'Card payment failed. Capture not confirmed.',
        'payment-unknown' ||
        'receipt-available-with-unknown-payment' =>
          'Payment outcome UNKNOWN. Recheck later.',
        'payment-error' => 'Payment verification failed.',
        _ => 'Card capture verified.',
      };
      expect(find.text(expected), findsOneWidget);
      expect(
          find.text('Receipt available: R-005'),
          scenario == 'receipt-available-with-unknown-payment'
              ? findsOneWidget
              : findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('unconfigured handoff remains unavailable without a reader',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child:
            MaterialApp(home: Scaffold(body: DriverCompletionHandoffPanel()))));
    expect(find.text('Payment status is unavailable.'), findsOneWidget);
    expect(reader.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
