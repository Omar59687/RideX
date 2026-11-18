import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';

/// Synthetic, deterministic test fake. Never used as a configured-backend
/// fallback, and never creates payment/receipt evidence.
final class FakeRiderTripHistoryRepository
    implements RiderTripHistoryRepository {
  FakeRiderTripHistoryRepository({
    required List<RiderHistoryTrip> records,
    required this.currentRiderId,
  }) : _records = List.unmodifiable(records);

  final List<RiderHistoryTrip> _records;
  final String? Function() currentRiderId;

  void _authorize(String riderId) {
    if (!isCanonicalTripId(riderId) ||
        currentRiderId()?.toLowerCase() != riderId.toLowerCase()) {
      throw const RiderHistoryException(RiderHistoryFailure.unauthorized);
    }
  }

  @override
  Future<RiderHistoryPage> readPage(RiderHistoryRequest request) async {
    _authorize(request.riderId);
    final selected = _records.where((trip) {
      if (trip.riderId.toLowerCase() != request.riderId.toLowerCase()) {
        return false;
      }
      return switch (request.filter) {
        RiderHistoryFilter.all => true,
        RiderHistoryFilter.completed =>
          trip.status == DriverTripLifecycleStatus.completed,
        RiderHistoryFilter.cancelled =>
          trip.status == DriverTripLifecycleStatus.cancelledByRider ||
              trip.status == DriverTripLifecycleStatus.cancelledByDriver ||
              trip.status == DriverTripLifecycleStatus.cancelledByAdmin,
      };
    }).toList()
      ..sort((a, b) {
        final date = b.createdAt.compareTo(a.createdAt);
        return date == 0 ? b.tripId.compareTo(a.tripId) : date;
      });

    final cursor = request.cursor;
    final visible = cursor == null
        ? selected
        : selected.where((trip) {
            final difference = trip.createdAt.compareTo(cursor.createdAt);
            return difference < 0 ||
                (difference == 0 && trip.tripId.compareTo(cursor.tripId) < 0);
          }).toList();

    final page = visible.take(request.limit).toList();
    // A fake read cannot outlive its Rider authorization context.
    _authorize(request.riderId);
    final more = visible.length > page.length;
    final last = page.isEmpty ? null : page.last;
    return RiderHistoryPage(
      trips: page,
      nextCursor: more && last != null
          ? RiderHistoryCursor(createdAt: last.createdAt, tripId: last.tripId)
          : null,
    );
  }

  @override
  Future<RiderHistoryTrip?> readExactTrip({
    required String riderId,
    required String tripId,
  }) async {
    _authorize(riderId);
    if (!isCanonicalTripId(tripId)) {
      throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
    }
    RiderHistoryTrip? found;
    for (final trip in _records) {
      if (trip.riderId.toLowerCase() == riderId.toLowerCase() &&
          trip.tripId.toLowerCase() == tripId.toLowerCase()) {
        found = trip;
        break;
      }
    }
    _authorize(riderId);
    return found;
  }
}
