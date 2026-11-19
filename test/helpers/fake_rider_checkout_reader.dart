import 'dart:async';

import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';

class FakeRiderCheckoutReader implements RiderCheckoutReader {
  RiderCheckoutTrip? trip;
  CardPayment? payment;
  Object? tripError;
  Object? paymentError;
  Completer<RiderCheckoutTrip?>? tripGate;
  Completer<CardPayment?>? paymentGate;
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
  Future<CardPayment?> readCardPayment({required String tripId}) async {
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
    return payment;
  }
}
