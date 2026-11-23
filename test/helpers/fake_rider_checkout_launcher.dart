import 'dart:async';

import 'package:ridex/features/rider_payments/application/rider_checkout_launcher.dart';

class FakeRiderCheckoutLauncher implements RiderCheckoutLauncher {
  RiderCheckoutReturnSignal result = RiderCheckoutReturnSignal.returned;
  Completer<RiderCheckoutReturnSignal>? gate;
  Completer<void>? launchStarted;
  final requests = <RiderCheckoutLaunchRequest>[];

  @override
  Future<RiderCheckoutReturnSignal> launch(
    RiderCheckoutLaunchRequest request,
  ) async {
    requests.add(request);
    final started = launchStarted;
    if (started != null && !started.isCompleted) started.complete();
    final currentGate = gate;
    if (currentGate != null) {
      gate = null;
      return currentGate.future;
    }
    return result;
  }
}
