import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/rider_booking_cancellation.dart';
import 'package:ridex/core/repositories/rider_booking_cancellation_repository.dart';

/// One recorded cancellation attempt; the fake never retries on its own.
class FakeCancellationRequest {
  const FakeCancellationRequest({
    required this.bookingRequestId,
    required this.expectedVersion,
    required this.reasonCode,
  });

  final String bookingRequestId;
  final int expectedVersion;
  final String reasonCode;

  @override
  String toString() =>
      'FakeCancellationRequest($bookingRequestId, v$expectedVersion, '
      '$reasonCode)';
}

/// Deterministic cancellation adapter.
///
/// [onCancel] may delay, fail, or return any typed outcome. When it is absent,
/// [result] is returned synchronously.
class FakeRiderBookingCancellationRepository
    implements RiderBookingCancellationRepository {
  FakeRiderBookingCancellationRepository({
    this.result = const RiderBookingCancellationUnknown(),
    this.onCancel,
  });

  RiderBookingCancellationResult result;

  /// Overrides scoped cancellation to inject delays, errors, or custom outcomes.
  Future<RiderBookingCancellationResult> Function(
    FakeCancellationRequest request,
  )? onCancel;

  final List<FakeCancellationRequest> requests = [];
  int get cancelCount => requests.length;

  @override
  Future<RiderBookingCancellationResult> cancelBooking({
    required String bookingRequestId,
    required int expectedVersion,
    required String reasonCode,
  }) {
    if (!isCanonicalTripId(bookingRequestId)) {
      throw ArgumentError.value(bookingRequestId, 'bookingRequestId');
    }
    final request = FakeCancellationRequest(
      bookingRequestId: bookingRequestId,
      expectedVersion: expectedVersion,
      reasonCode: reasonCode,
    );
    requests.add(request);
    final override = onCancel;
    if (override != null) return override(request);
    return Future<RiderBookingCancellationResult>.value(result);
  }
}
