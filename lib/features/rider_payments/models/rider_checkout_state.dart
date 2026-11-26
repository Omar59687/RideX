import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';

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
    required this.currentFareFils,
    required this.currency,
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
    if (currentFareFils < 0 || currentFareFils > 2147483647) {
      throw ArgumentError.value(
        currentFareFils,
        'currentFareFils',
        'Must be nonnegative.',
      );
    }
    if (currency != 'JOD') {
      throw ArgumentError.value(currency, 'currency', 'Only JOD is supported.');
    }
  }

  final String tripId;
  final String bookingRequestId;
  final String riderId;
  final String driverId;
  final int version;
  final int currentFareFils;
  final String currency;
  final DriverTripLifecycleStatus status;
  final PaymentMethod paymentMethod;

  bool get isTerminal => switch (status) {
        DriverTripLifecycleStatus.completed ||
        DriverTripLifecycleStatus.cancelledByRider ||
        DriverTripLifecycleStatus.cancelledByDriver ||
        DriverTripLifecycleStatus.cancelledByAdmin ||
        DriverTripLifecycleStatus.failed =>
          true,
        _ => false,
      };

  bool get isEligibleAssignedCardTrip =>
      paymentMethod == PaymentMethod.card &&
      switch (status) {
        DriverTripLifecycleStatus.accepted ||
        DriverTripLifecycleStatus.driverArriving ||
        DriverTripLifecycleStatus.driverArrived ||
        DriverTripLifecycleStatus.inProgress =>
          true,
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

  /// Called only after [readTrip] returns an eligible canonical Card Trip or
  /// a completed Card Trip being read for historical payment evidence.
  ///
  /// Implementations must return [RiderCheckoutPaymentFound] only for a
  /// canonical, linked Payment. [RiderCheckoutPaymentActionRequiredRead] is
  /// an explicit read outcome, not a null/missing-row fallback; a future
  /// production adapter may emit it only when its reviewed backend contract
  /// proves that checkout is safe to begin and no prior effect is uncertain.
  /// Malformed, hidden, unauthorized, or uncertain responses must throw a
  /// typed read exception instead of being represented as action-required.
  Future<RiderCheckoutPaymentReadResult> readCardPayment({
    required String tripId,
  });
}

/// Typed outcomes of an authenticated canonical Payment read. These are
/// client-side read results, not new database or provider status values.
sealed class RiderCheckoutPaymentReadResult {
  const RiderCheckoutPaymentReadResult();
}

final class RiderCheckoutPaymentFound extends RiderCheckoutPaymentReadResult {
  const RiderCheckoutPaymentFound(this.payment);

  final CardPayment payment;
}

/// The backend contract explicitly established that no Payment action has
/// started and no uncertain attempt exists. Null, hidden rows, and failed
/// reads must never be mapped to this result.
final class RiderCheckoutPaymentActionRequiredRead
    extends RiderCheckoutPaymentReadResult {
  const RiderCheckoutPaymentActionRequiredRead();
}

/// Safe default until B05 provides a reviewed authenticated backend reader.
final class UnavailableRiderCheckoutReader implements RiderCheckoutReader {
  const UnavailableRiderCheckoutReader();

  @override
  Future<RiderCheckoutTrip?> readTrip({required String tripId}) async => null;

  @override
  Future<RiderCheckoutPaymentReadResult> readCardPayment({
    required String tripId,
  }) async {
    throw const RiderCheckoutPaymentReadException(
      RiderCheckoutPaymentReadFailure.unavailable,
    );
  }
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

/// Trip, Payment and receipt state are intentionally independent dimensions.
final class RiderCheckoutState {
  const RiderCheckoutState({
    required this.trip,
    required this.payment,
    this.receipt = const RiderReceiptUnavailable(),
    this.receiptCheckAttempted = false,
  });

  const RiderCheckoutState.unavailable()
      : trip = const RiderCheckoutTripUnavailable(),
        payment = const RiderCheckoutPaymentUnavailable(),
        receipt = const RiderReceiptUnavailable(),
        receiptCheckAttempted = false;

  final RiderCheckoutTripState trip;
  final RiderCheckoutPaymentState payment;

  /// Independent receipt evidence; never inferred from [payment].
  final RiderReceiptState receipt;

  /// Distinguishes a completed receipt read that was unavailable from the
  /// default no-reader state.
  final bool receiptCheckAttempted;
}

RiderCheckoutPaymentState riderCheckoutPaymentState(
  CardPayment payment,
) =>
    switch (payment.status) {
      CardPaymentStatus.cardPaymentPending =>
        RiderCheckoutPaymentPending(payment),
      CardPaymentStatus.cardPaymentAuthorized =>
        RiderCheckoutAuthorized(payment),
      CardPaymentStatus.cardPaymentSucceeded => RiderCheckoutCaptured(payment),
      CardPaymentStatus.cardPaymentFailed =>
        RiderCheckoutPaymentFailed(payment),
      CardPaymentStatus.paymentCancelled =>
        RiderCheckoutPaymentCancelled(payment),
      CardPaymentStatus.refundPending => RiderCheckoutRefundPending(payment),
      CardPaymentStatus.refunded => RiderCheckoutRefunded(payment),
    };
