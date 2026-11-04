import 'package:ridex/core/models/trip_realtime.dart';

/// Injectable boundary for participant-authorized Trip reads and Realtime
/// notifications. Implementations must use the same authenticated identity for
/// both operations and must not use a service-role client.
abstract interface class TripRealtimeSource {
  String? get authenticatedUserId;

  /// Stable identity for the current authenticated session, including token
  /// refresh/replacement for the same user. Must change when the session does.
  Object? get authenticatedSessionIdentity;

  /// Emits connection state and filtered notifications for one Trip.
  Stream<TripRealtimeSourceSignal> watchTrip(String tripId);

  /// Reads exactly one canonical Trip through the caller's normal RLS context.
  Future<TripRealtimeTrip?> readCanonicalTrip(String tripId);
}
