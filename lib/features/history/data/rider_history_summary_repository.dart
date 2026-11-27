import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';

/// The subset actually returned by `user_trip_history_v1`. This intentionally
/// does not pretend the RPC contains booking, route, fare, or Rider fields.
final class RiderHistorySummary {
  RiderHistorySummary({
    required this.tripId,
    required this.version,
    required this.status,
    required this.createdAt,
    required this.paymentId,
    required this.paymentVersion,
    required this.paymentMethod,
  }) {
    if (!isCanonicalTripId(tripId) ||
        version < 1 ||
        (paymentId != null && !isCanonicalTripId(paymentId!)) ||
        (paymentVersion != null && paymentVersion! < 1) ||
        ((paymentId == null) != (paymentVersion == null)) ||
        (paymentId != null && paymentMethod == null)) {
      throw const FormatException('Invalid Rider history summary.');
    }
  }

  final String tripId;
  final int version;
  final DriverTripLifecycleStatus status;
  final DateTime createdAt;
  final String? paymentId;
  final int? paymentVersion;
  final PaymentMethod? paymentMethod;
}

final class RiderHistorySummaryCursor {
  const RiderHistorySummaryCursor({
    required this.createdAt,
    required this.tripId,
  });
  final DateTime createdAt;
  final String tripId;
}

final class RiderHistorySummaryPage {
  RiderHistorySummaryPage({
    required List<RiderHistorySummary> rows,
    this.nextCursor,
  }) : rows = List.unmodifiable(rows);
  final List<RiderHistorySummary> rows;
  final RiderHistorySummaryCursor? nextCursor;
}

final class RiderHistorySummarySessionChanged implements Exception {
  const RiderHistorySummarySessionChanged();
}

abstract interface class RiderHistorySummaryReader {
  Future<RiderHistorySummaryPage> readPage({
    int limit = 20,
    RiderHistorySummaryCursor? cursor,
  });
  Future<RiderHistorySummary?> readExactTrip(String tripId);
}
