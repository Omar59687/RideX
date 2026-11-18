import 'package:ridex/core/models/driver_trip_completion.dart';

/// P8-D01: feature-local, read-only canonical Trip history contract.
/// Backend adapters must independently verify Rider session and participant RLS.
enum RiderHistoryFailure {
  unauthorized,
  unavailable,
  invalidResponse,
  staleSession,
}

final class RiderHistoryException implements Exception {
  const RiderHistoryException(this.failure);
  final RiderHistoryFailure failure;
  @override
  String toString() => 'Rider history unavailable ($failure)';
}

/// Stable descending keyset: (createdAt DESC, tripId DESC).
final class RiderHistoryCursor {
  RiderHistoryCursor({required this.createdAt, required this.tripId}) {
    if (!isCanonicalTripId(tripId)) throw ArgumentError.value(tripId, 'tripId');
  }

  final DateTime createdAt;
  final String tripId;
}

final class RiderHistoryTrip {
  RiderHistoryTrip({
    required this.tripId,
    required this.bookingRequestId,
    required this.riderId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.lockedFareFils,
    required this.currency,
    this.paymentId,
    this.verifiedReceiptIssued = false,
  }) {
    if (!isCanonicalTripId(tripId) ||
        !isCanonicalTripId(bookingRequestId) ||
        !isCanonicalTripId(riderId) ||
        (paymentId != null && !isCanonicalTripId(paymentId!))) {
      throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
    }
    if (lockedFareFils < 0 || currency != 'JOD') {
      throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
    }
    if (createdAt.isAfter(updatedAt)) {
      throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
    }
    if (pickupLabel.trim().isEmpty || destinationLabel.trim().isEmpty) {
      throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
    }
    // Receipt evidence must come from an independent authorized receipt read;
    // the mere existence of a completed Trip is never sufficient.
    if (verifiedReceiptIssued && paymentId == null) {
      throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
    }
  }

  final String tripId;
  final String bookingRequestId;
  final String riderId;
  final DriverTripLifecycleStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String pickupLabel;
  final String destinationLabel;
  final int lockedFareFils;
  final String currency;

  /// Nullable: must be obtained from a backend-issued Trip/payment linkage.
  final String? paymentId;

  /// True ONLY after independently verified participant-safe receipt evidence.
  final bool verifiedReceiptIssued;

  bool get isTerminal => switch (status) {
        DriverTripLifecycleStatus.completed ||
        DriverTripLifecycleStatus.cancelledByRider ||
        DriverTripLifecycleStatus.cancelledByDriver ||
        DriverTripLifecycleStatus.cancelledByAdmin ||
        DriverTripLifecycleStatus.failed => true,
        _ => false,
      };
}

enum RiderHistoryFilter { all, completed, cancelled }

final class RiderHistoryRequest {
  RiderHistoryRequest({
    required this.riderId,
    this.cursor,
    this.limit = 20,
    this.filter = RiderHistoryFilter.all,
  }) {
    if (!isCanonicalTripId(riderId) || limit < 1 || limit > 50) {
      throw ArgumentError('Invalid Rider history request.');
    }
  }
  final String riderId;
  final RiderHistoryCursor? cursor;
  final int limit;
  final RiderHistoryFilter filter;
}

final class RiderHistoryPage {
  RiderHistoryPage({
    required List<RiderHistoryTrip> trips,
    required this.nextCursor,
  }) : trips = List.unmodifiable(trips);

  final List<RiderHistoryTrip> trips;
  final RiderHistoryCursor? nextCursor;
}

/// Client-facing interface only. Implementations must enforce session pinning,
/// participant-scoped reads and post-await Rider identity checks.
abstract interface class RiderTripHistoryRepository {
  Future<RiderHistoryPage> readPage(RiderHistoryRequest request);
  Future<RiderHistoryTrip?> readExactTrip({
    required String riderId,
    required String tripId,
  });
}
