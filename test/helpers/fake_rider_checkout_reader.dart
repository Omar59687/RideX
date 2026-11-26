import 'dart:async';

import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';

class FakeRiderCheckoutReader implements RiderCheckoutReader {
  RiderCheckoutTrip? trip;
  RiderCheckoutPaymentReadResult paymentRead =
      const RiderCheckoutPaymentActionRequiredRead();
  Object? tripError;
  Object? paymentError;
  Completer<RiderCheckoutTrip?>? tripGate;
  Completer<RiderCheckoutPaymentReadResult>? paymentGate;
  Completer<void>? paymentReadStarted;
  final tripReads = <String>[];
  final paymentReads = <String>[];

  @override
  Future<RiderCheckoutTrip?> readTrip({required String tripId}) async {
    tripReads.add(tripId);
    final gate = tripGate;
    if (gate != null) {
      tripGate = null;
      return gate.future;
    }
    final error = tripError;
    tripError = null;
    if (error != null) throw error;
    return trip;
  }

  @override
  Future<RiderCheckoutPaymentReadResult> readCardPayment({
    required String tripId,
  }) async {
    paymentReads.add(tripId);
    final started = paymentReadStarted;
    if (started != null && !started.isCompleted) started.complete();
    final gate = paymentGate;
    if (gate != null) {
      paymentGate = null;
      return gate.future;
    }
    final error = paymentError;
    paymentError = null;
    if (error != null) throw error;
    return paymentRead;
  }

  set payment(CardPayment payment) {
    paymentRead = RiderCheckoutPaymentFound(payment);
  }
}

class FakeRiderReceiptReader implements RiderReceiptReader {
  RiderCanonicalReceiptReadResult receiptRead =
      const RiderCanonicalReceiptNotIssued();
  Object? error;
  Completer<RiderCanonicalReceiptReadResult>? gate;
  Completer<void>? readStarted;
  final reads = <({String tripId, String paymentId})>[];

  @override
  Future<RiderCanonicalReceiptReadResult> readReceipt({
    required String tripId,
    required String paymentId,
  }) async {
    reads.add((tripId: tripId, paymentId: paymentId));
    final started = readStarted;
    if (started != null && !started.isCompleted) started.complete();
    final currentGate = gate;
    if (currentGate != null) {
      gate = null;
      return currentGate.future;
    }
    final currentError = error;
    error = null;
    if (currentError != null) throw currentError;
    return receiptRead;
  }

  set receipt(RiderVerifiedReceipt receipt) {
    receiptRead = RiderCanonicalReceiptFound(receipt);
  }
}
