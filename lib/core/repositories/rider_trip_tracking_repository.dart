import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';

/// Provider-neutral read/watch boundary for the authenticated Rider's Trip.
///
/// Implementations must resolve the current Rider from the authenticated
/// session. No method accepts a caller-supplied Rider ID as authorization, and
/// a Trip owned by another Rider must be indistinguishable from a missing Trip
/// (`null` or an empty stream). Row Level Security remains the final defense.
/// Repository instances and subscriptions are session-scoped and must be
/// disposed on sign-out or Rider identity change.
///
/// All identifiers must be canonical UUIDs. A future adapter should reject
/// non-canonical identifiers with [ArgumentError] rather than treating them as
/// missing records.
///
/// [watch] emits events only for the requested Trip. It does not guarantee an
/// automatic initial snapshot and does not close automatically when a Trip
/// becomes terminal. Consumers must perform a fresh canonical read with
/// [findByTrip] or [findByBooking] on startup and reconnect and treat that read
/// as authoritative. Stream snapshots and ordering are advisory; they never
/// establish authorization or final Trip state.
abstract interface class RiderTripTrackingRepository {
  /// Returns the current Trip for [bookingRequestId], or `null` when absent or
  /// not owned by the authenticated Rider.
  Future<RiderAssignedTrip?> findByBooking({required String bookingRequestId});

  /// Returns the current Trip for [tripId], or `null` when absent or not owned
  /// by the authenticated Rider.
  Future<RiderAssignedTrip?> findByTrip({required String tripId});

  /// Watches display events for [tripId].
  ///
  /// Delivery may include duplicate, stale, or out-of-order events. Consumers
  /// reconcile them against a fresh canonical read and the version/sequence
  /// fields supplied by the event models.
  Stream<RiderTripTrackingEvent> watch({required String tripId});
}
