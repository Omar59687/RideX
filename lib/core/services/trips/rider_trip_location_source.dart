import 'package:ridex/core/models/rider_trip_location.dart';

/// Read-only, authenticated location access for one canonical Trip.
/// Implementations must use normal user credentials and database RLS.
abstract interface class RiderTripLocationSource {
  String? get authenticatedUserId;

  /// Must change whenever the authenticated session is replaced or refreshed.
  Object? get authenticatedSessionIdentity;

  Stream<RiderTripLocationSourceSignal> watchTripLocation(String tripId);

  /// Reads the latest row for both exact Trip and assigned Driver.
  Future<RiderTripLocation?> readLatestTripLocation({
    required String tripId,
    required String driverId,
  });
}
