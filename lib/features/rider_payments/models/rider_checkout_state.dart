import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';

/// Minimal canonical Trip fields needed by Rider checkout.
///
/// This is a provider-neutral read contract. A production implementation must
/// populate it from an authenticated, participant-scoped canonical Trip read;
/// constructing this value in Flutter does not authorize payment activity.
final class RiderCheckoutTrip {
  RiderCheckoutTrip({
    required this.tripId,
    required this.bookingRequestId,
    required this.riderId,
    required this.driverId,
    required this.version,
    required this.status,
    required this.paymentMethod,
  }) {
    for (final entry in {
      'tripId': tripId,
      'bookingRequestId': bookingRequestId,
      'riderId': riderId,
      'driverId': driverId,
    }.entries) {
      if (!isCanonicalTripId(entry.value)) {
        throw ArgumentError.value(entry.value, entry.key, 'Must be a UUID.');
      }
    }
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'Must be positive.');
    }
  }

  final String tripId;
  final String bookingRequestId;
  final String riderId;
  final String driverId;
  final int version;
  final DriverTripLifecycleStatus status;
  final PaymentMethod paymentMethod;

  bool get isTerminal => switch (status) {
    DriverTripLifecycleStatus.completed ||
    DriverTripLifecycleStatus.cancelledByRider ||
    DriverTripLifecycleStatus.cancelledByDriver ||
    DriverTripLifecycleStatus.cancelledByAdmin ||
    DriverTripLifecycleStatus.failed => true,
    _ => false,
  };

  bool get isEligibleAssignedCardTrip =>
      paymentMethod == PaymentMethod.card &&
      switch (status) {
        DriverTripLifecycleStatus.accepted ||
        DriverTripLifecycleStatus.driverArriving ||
        DriverTripLifecycleStatus.driverArrived ||
        DriverTripLifecycleStatus.inProgress => true,
        _ => false,
      };
}

enum RiderCheckoutTripReadFailure { unauthorized, unavailable, invalidResponse }

final class RiderCheckoutTripReadException implements Exception {
  const RiderCheckoutTripReadException(this.failure);
  final RiderCheckoutTripReadFailure failure;
}

enum RiderCheckoutPaymentReadFailure {
  unauthorized,
  unavailable,
  unknownOutcome,
  invalidResponse,
}

final class RiderCheckoutPaymentReadException implements Exception {
  const RiderCheckoutPaymentReadException(this.failure);
  final RiderCheckoutPaymentReadFailure failure;
}

/// Provider-neutral read seam for one Trip and its Card Payment.
///
/// B05 may implement this only after Yousuf publishes an approved backend
/// contract. This interface intentionally names no RPC, Payment ID, provider,
/// secret, or payment command.
abstract interface class RiderCheckoutReader {
  Future<RiderCheckoutTrip?> readTrip({required String tripId});

  /// Called only after [readTrip] returns an eligible canonical Card Trip.
  Future<CardPayment?> readCardPayment({required String tripId});
}

/// Safe default until B05 provides a reviewed authenticated backend reader.
final class UnavailableRiderCheckoutReader implements RiderCheckoutReader {
  const UnavailableRiderCheckoutReader();

  @override
  Future<RiderCheckoutTrip?> readTrip({required String tripId}) async => null;

  @override
  Future<CardPayment?> readCardPayment({required String tripId}) async => null;
}

sealed class RiderCheckoutTripState {
  const RiderCheckoutTripState();
}

final class RiderCheckoutTripUnavailable extends RiderCheckoutTripState {
  const RiderCheckoutTripUnavailable();
}

final class RiderCheckoutTripLoading extends RiderCheckoutTripState {
  const RiderCheckoutTripLoading();
}

final class RiderCheckoutTripEligible extends RiderCheckoutTripState {
  const RiderCheckoutTripEligible(this.trip);
  final RiderCheckoutTrip trip;
}

final class RiderCheckoutTripIneligible extends RiderCheckoutTripState {
  const RiderCheckoutTripIneligible();
}

final class RiderCheckoutTripStale extends RiderCheckoutTripState {
  const RiderCheckoutTripStale();
}

final class RiderCheckoutTripTerminal extends RiderCheckoutTripState {
  const RiderCheckoutTripTerminal(this.trip);
  final RiderCheckoutTrip trip;
}

final class RiderCheckoutTripReadError extends RiderCheckoutTripState {
  const RiderCheckoutTripReadError(this.failure);
  final RiderCheckoutTripReadFailure failure;
}

sealed class RiderCheckoutPaymentState {
  const RiderCheckoutPaymentState();
}

final class RiderCheckoutPaymentUnavailable extends RiderCheckoutPaymentState {
  const RiderCheckoutPaymentUnavailable();
}

final class RiderCheckoutPaymentLoading extends RiderCheckoutPaymentState {
  const RiderCheckoutPaymentLoading();
}

/// The Trip is eligible, but no canonical Payment record has been returned.
/// This state never means that authorization started or payment succeeded.
final class RiderCheckoutActionRequired extends RiderCheckoutPaymentState {
  const RiderCheckoutActionRequired();
}

final class RiderCheckoutPaymentPending extends RiderCheckoutPaymentState {
  const RiderCheckoutPaymentPending(this.payment);
  final CardPayment payment;
}

final class RiderCheckoutPaymentUnknown extends RiderCheckoutPaymentState {
  const RiderCheckoutPaymentUnknown();
}

final class RiderCheckoutAuthorized extends RiderCheckoutPaymentState {
  const RiderCheckoutAuthorized(this.payment);
  final CardPayment payment;
}

final class RiderCheckoutCaptured extends RiderCheckoutPaymentState {
  const RiderCheckoutCaptured(this.payment);
  final CardPayment payment;
}

final class RiderCheckoutPaymentFailed extends RiderCheckoutPaymentState {
  const RiderCheckoutPaymentFailed(this.payment);
  final CardPayment payment;
}

final class RiderCheckoutPaymentCancelled extends RiderCheckoutPaymentState {
  const RiderCheckoutPaymentCancelled(this.payment);
  final CardPayment payment;
}

final class RiderCheckoutRefundPending extends RiderCheckoutPaymentState {
  const RiderCheckoutRefundPending(this.payment);
  final CardPayment payment;
}

final class RiderCheckoutRefunded extends RiderCheckoutPaymentState {
  const RiderCheckoutRefunded(this.payment);
  final CardPayment payment;
}

final class RiderCheckoutPaymentReadError extends RiderCheckoutPaymentState {
  const RiderCheckoutPaymentReadError(this.failure);
  final RiderCheckoutPaymentReadFailure failure;
}

/// Trip and Payment state are intentionally independent dimensions.
final class RiderCheckoutState {
  const RiderCheckoutState({required this.trip, required this.payment});

  const RiderCheckoutState.unavailable()
    : trip = const RiderCheckoutTripUnavailable(),
      payment = const RiderCheckoutPaymentUnavailable();

  final RiderCheckoutTripState trip;
  final RiderCheckoutPaymentState payment;
}

RiderCheckoutPaymentState riderCheckoutPaymentState(
  CardPayment payment,
) => switch (payment.status) {
  CardPaymentStatus.cardPaymentPending => RiderCheckoutPaymentPending(payment),
  CardPaymentStatus.cardPaymentAuthorized => RiderCheckoutAuthorized(payment),
  CardPaymentStatus.cardPaymentSucceeded => RiderCheckoutCaptured(payment),
  CardPaymentStatus.cardPaymentFailed => RiderCheckoutPaymentFailed(payment),
  CardPaymentStatus.paymentCancelled => RiderCheckoutPaymentCancelled(payment),
  CardPaymentStatus.refundPending => RiderCheckoutRefundPending(payment),
  CardPaymentStatus.refunded => RiderCheckoutRefunded(payment),
};
