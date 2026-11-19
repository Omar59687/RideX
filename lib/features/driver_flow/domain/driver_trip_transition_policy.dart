import 'package:ridex/core/models/driver_trip_completion.dart';

/// Driver-requestable status changes: intersection of RPC 014's allowlist and
/// 008's enforce_trip_transition trigger. Same-status RPC acknowledgement is
/// recovery evidence, not a new action. This policy grants no write authority.
abstract final class DriverTripTransitionPolicy {
  static bool allows(
    DriverTripLifecycleStatus from,
    DriverTripLifecycleStatus to,
  ) => switch (from) {
    DriverTripLifecycleStatus.accepted =>
      to == DriverTripLifecycleStatus.driverArriving ||
          to == DriverTripLifecycleStatus.cancelledByDriver,
    DriverTripLifecycleStatus.driverArriving =>
      to == DriverTripLifecycleStatus.driverArrived ||
          to == DriverTripLifecycleStatus.cancelledByDriver,
    DriverTripLifecycleStatus.driverArrived =>
      to == DriverTripLifecycleStatus.inProgress ||
          to == DriverTripLifecycleStatus.cancelledByDriver,
    DriverTripLifecycleStatus.inProgress =>
      to == DriverTripLifecycleStatus.completed,
    _ => false,
  };
}
