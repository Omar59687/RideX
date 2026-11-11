import 'package:ridex/core/models/rider_assigned_trip.dart';

enum RiderTripCancellationRejection {
  staleVersion,
  notCancellable,
  notFound,
  blockedOrDenied,
  backend,
}

sealed class RiderTripCancellationResult {
  const RiderTripCancellationResult();
}

final class RiderTripCancellationAccepted extends RiderTripCancellationResult {
  const RiderTripCancellationAccepted(this.trip);
  final RiderAssignedTrip trip;
}

final class RiderTripCancellationRejected extends RiderTripCancellationResult {
  const RiderTripCancellationRejected(this.rejection);
  final RiderTripCancellationRejection rejection;
}

final class RiderTripCancellationUnknown extends RiderTripCancellationResult {
  const RiderTripCancellationUnknown();
}

abstract interface class RiderTripCancellationRepository {
  Future<RiderTripCancellationResult> cancelTrip({
    required String tripId,
    required int expectedVersion,
    required String reasonCode,
  });
}
