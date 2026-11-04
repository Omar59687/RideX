import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';

/// Exact `public.booking_request_status` values; timeout is a UI state only.
enum RiderBookingSearchStatus {
  draft,
  confirmed,
  searching,
  matched,
  cancelled,
  expired,
  failed;

  String get backendValue => name;

  static RiderBookingSearchStatus fromBackendValue(String value) =>
      switch (value) {
        'draft' => RiderBookingSearchStatus.draft,
        'confirmed' => RiderBookingSearchStatus.confirmed,
        'searching' => RiderBookingSearchStatus.searching,
        'matched' => RiderBookingSearchStatus.matched,
        'cancelled' => RiderBookingSearchStatus.cancelled,
        'expired' => RiderBookingSearchStatus.expired,
        'failed' => RiderBookingSearchStatus.failed,
        _ =>
          throw ArgumentError.value(value, 'value', 'Unknown booking status.'),
      };
}

/// Booking status projection; the reader/session must verify authorization.
/// This model is never a command or proof of an assigned Trip.
class RiderBookingSearchSnapshot extends Equatable {
  RiderBookingSearchSnapshot({
    required String bookingRequestId,
    required String riderId,
    required this.version,
    required this.status,
    required this.paymentMethod,
  })  : bookingRequestId = _canonicalId(bookingRequestId, 'bookingRequestId'),
        riderId = _canonicalId(riderId, 'riderId') {
    if (version <= 0) {
      throw ArgumentError.value(version, 'version', 'Must be positive.');
    }
    if (paymentMethod != PaymentMethod.cash) {
      throw ArgumentError.value(
        paymentMethod,
        'paymentMethod',
        'Rider booking search is Cash-only.',
      );
    }
  }

  final String bookingRequestId;
  final String riderId;
  final int version;
  final RiderBookingSearchStatus status;
  final PaymentMethod paymentMethod;

  @override
  List<Object?> get props => [
        bookingRequestId,
        riderId,
        version,
        status,
        paymentMethod,
      ];
}

String _canonicalId(String value, String name) {
  if (!isCanonicalTripId(value)) {
    throw ArgumentError.value(value, name, 'Must be a canonical UUID.');
  }
  return value;
}
