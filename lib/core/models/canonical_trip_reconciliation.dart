import 'package:ridex/core/models/driver_trip_completion.dart';

/// Authority snapshot from the authenticated transport, never from a command.
/// The integration owner must advance [epoch] on logout, account replacement
/// (including A-B-A), approval loss and lifecycle replacement. Never reset an
/// epoch while reads from the previous lifecycle can still finish.
final class CanonicalTripReadSession {
  const CanonicalTripReadSession({
    required this.driverId,
    required this.backendNamespace,
    required this.epoch,
    required this.isApprovedDriver,
  });

  final String? driverId;
  final String backendNamespace;
  final int epoch;
  final bool isApprovedDriver;

  bool sameAuthority(CanonicalTripReadSession other) =>
      driverId?.toLowerCase() == other.driverId?.toLowerCase() &&
      backendNamespace == other.backendNamespace &&
      epoch == other.epoch &&
      isApprovedDriver == other.isApprovedDriver;
}

/// Trip truth only. Completion is never payment or receipt evidence.
final class CanonicalTripEvidence {
  CanonicalTripEvidence({
    required this.tripId,
    required this.driverId,
    required this.status,
    required this.backendVersion,
  }) {
    if (!isCanonicalTripId(tripId) ||
        !isCanonicalTripId(driverId) ||
        backendVersion <= 0) {
      throw ArgumentError(
          'Canonical UUIDs and positive Trip version required.');
    }
  }

  final String tripId;
  final String driverId;
  final DriverTripLifecycleStatus status;
  final int backendVersion;
}

enum CanonicalTripReadFailure {
  invalidRequest,
  authorizationDenied,
  sessionInvalidated,
  transportUncertain,
  malformedEvidence,
  foreignEvidence,
  unsupportedStatus,
  invalidVersion,
}

sealed class CanonicalTripReadOutcome {
  const CanonicalTripReadOutcome();
}

final class CanonicalTripVisible extends CanonicalTripReadOutcome {
  const CanonicalTripVisible(this.trip, this.session);
  final CanonicalTripEvidence trip;

  /// Captured authority for a future consumer's own publication checks.
  final CanonicalTripReadSession session;
}

/// Absence under RLS says nothing about deletion, cancellation or prior writes.
final class CanonicalTripNotVisible extends CanonicalTripReadOutcome {
  const CanonicalTripNotVisible();
}

/// Closed, log-safe outcome; never carries raw database or transport errors.
final class CanonicalTripReadFailed extends CanonicalTripReadOutcome {
  const CanonicalTripReadFailed(this.failure);
  final CanonicalTripReadFailure failure;
}
