import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/repositories/rider_booking_search_repository.dart';

import 'fake_rider_trip_tracking_repository.dart';

class FakeRiderBookingSearchRepository implements RiderBookingSearchRepository {
  FakeRiderBookingSearchRepository({
    required this.authenticatedRiderId,
    this.booking,
    this.onRead,
  });

  final String authenticatedRiderId;
  RiderBookingSearchSnapshot? booking;

  /// Overrides scoped reads to inject delayed, malformed, or failed responses.
  Future<RiderBookingSearchSnapshot?> Function(String bookingRequestId)? onRead;
  final List<String> requestedBookingIds = [];
  int get readCount => requestedBookingIds.length;

  @override
  Future<RiderBookingSearchSnapshot?> readBooking({
    required String bookingRequestId,
  }) async {
    if (!isCanonicalTripId(bookingRequestId)) {
      throw ArgumentError.value(bookingRequestId, 'bookingRequestId');
    }
    requestedBookingIds.add(bookingRequestId);
    final override = onRead;
    if (override != null) return override(bookingRequestId);
    final current = booking;
    if (current?.bookingRequestId.toLowerCase() !=
            bookingRequestId.toLowerCase() ||
        current?.riderId.toLowerCase() != authenticatedRiderId.toLowerCase()) {
      return null;
    }
    return current;
  }
}

RiderBookingSearchSnapshot riderBookingSearchFixture({
  String bookingRequestId = riderBookingIdFixture,
  String riderId = riderIdFixture,
  int version = 3,
  RiderBookingSearchStatus status = RiderBookingSearchStatus.searching,
  PaymentMethod paymentMethod = PaymentMethod.cash,
}) =>
    RiderBookingSearchSnapshot(
      bookingRequestId: bookingRequestId,
      riderId: riderId,
      version: version,
      status: status,
      paymentMethod: paymentMethod,
    );
