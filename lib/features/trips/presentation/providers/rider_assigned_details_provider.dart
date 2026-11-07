import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';

enum RiderAssignedDetailsStatus { loading, unavailable, verified }

/// Production C03 cannot publish Driver or Vehicle evidence until the SDK
/// exposes an approved observable session-lineage boundary.
final class RiderAssignedDetailsState {
  const RiderAssignedDetailsState.unavailable()
      : status = RiderAssignedDetailsStatus.unavailable;

  final RiderAssignedDetailsStatus status;
}

/// The exact requested Trip is explicit; a repository cannot confer authority.
typedef RiderAssignedDetailsRequest = ({
  String tripId,
  RiderTripTrackingRepository repository,
});

/// Read-only production boundary: no repository operation or enabled notifier.
/// A null Supabase client does not select a fake mode. Fake-backed reconciliation
/// exists only as a private prototype in the test library.
final riderAssignedDetailsProvider = Provider.autoDispose
    .family<RiderAssignedDetailsState, RiderAssignedDetailsRequest>(
        (ref, request) {
  if (!isCanonicalTripId(request.tripId)) {
    throw ArgumentError.value(
        request.tripId, 'tripId', 'Must be a canonical UUID.');
  }
  return const RiderAssignedDetailsState.unavailable();
});
