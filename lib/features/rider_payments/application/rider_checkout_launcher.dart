/// A small provider-neutral request for an already verified Card Trip.
///
/// It contains no Payment ID, card data, provider token, or secret. A real
/// implementation must obtain any required secure handoff from an approved
/// backend contract; this package intentionally provides no live launcher.
final class RiderCheckoutLaunchRequest {
  const RiderCheckoutLaunchRequest({
    required this.tripId,
    required this.expectedTripVersion,
  });

  final String tripId;
  final int expectedTripVersion;
}

/// Checkout adapters report only that control returned to the app. These
/// values are advisory and never represent authorization or payment success.
enum RiderCheckoutReturnSignal {
  returned,
  cancelled,
  malformedReturn,
  networkFailure,
  unavailable,
}

/// Boundary for an approved hosted checkout or PaymentSheet integration.
/// Implementations must never ask Flutter for raw card numbers or CVV.
abstract interface class RiderCheckoutLauncher {
  Future<RiderCheckoutReturnSignal> launch(
    RiderCheckoutLaunchRequest request,
  );
}

/// Default-off implementation until the backend/provider contract is reviewed.
final class DisabledRiderCheckoutLauncher implements RiderCheckoutLauncher {
  const DisabledRiderCheckoutLauncher();

  @override
  Future<RiderCheckoutReturnSignal> launch(
    RiderCheckoutLaunchRequest request,
  ) async =>
      RiderCheckoutReturnSignal.unavailable;
}
