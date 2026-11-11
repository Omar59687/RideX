import 'package:ridex/core/models/driver_trip_completion.dart';

/// A validated snapshot read from `public.trips` through the authenticated
/// client. Realtime payloads never construct this model directly.
final class TripRealtimeTrip {
  TripRealtimeTrip({
    required this.tripId,
    required this.riderId,
    required this.driverId,
    required this.status,
    required this.version,
  }) {
    if (!isCanonicalTripId(tripId) ||
        !isCanonicalTripId(riderId) ||
        !isCanonicalTripId(driverId) ||
        version <= 0) {
      throw ArgumentError('Canonical Trip identity and version are required.');
    }
  }

  final String tripId;
  final String riderId;
  final String driverId;
  final DriverTripLifecycleStatus status;
  final int version;

  bool hasSameStateAs(TripRealtimeTrip other) =>
      tripId.toLowerCase() == other.tripId.toLowerCase() &&
      riderId.toLowerCase() == other.riderId.toLowerCase() &&
      driverId.toLowerCase() == other.driverId.toLowerCase() &&
      status == other.status &&
      version == other.version;

  static TripRealtimeTrip fromRow(Map<String, dynamic> row) {
    final tripId = row['id'];
    final riderId = row['rider_id'];
    final driverId = row['driver_id'];
    final rawStatus = row['status'];
    final version = row['version'];
    if (tripId is! String ||
        riderId is! String ||
        driverId is! String ||
        rawStatus is! String ||
        version is! int) {
      throw const FormatException('Malformed canonical Trip row.');
    }
    return TripRealtimeTrip(
      tripId: tripId,
      riderId: riderId,
      driverId: driverId,
      status: DriverTripLifecycleStatus.fromBackendValue(rawStatus),
      version: version,
    );
  }
}

enum TripRealtimeChangeSource { tripRow, statusHistory }

enum TripRealtimeChannelStatus {
  connecting,
  subscribed,
  channelError,
  closed,
  timedOut,
}

sealed class TripRealtimeSourceSignal {
  const TripRealtimeSourceSignal();
}

final class TripRealtimeSessionChangedSignal extends TripRealtimeSourceSignal {
  const TripRealtimeSessionChangedSignal();
}

final class TripRealtimeChangeSignal extends TripRealtimeSourceSignal {
  const TripRealtimeChangeSignal({
    required this.tripId,
    required this.source,
    this.statusEventSequence,
  });

  final String tripId;
  final TripRealtimeChangeSource source;

  /// Per-Trip sequence from `trip_status_events`; absent for `trips` changes.
  final int? statusEventSequence;
}

final class TripRealtimeChannelSignal extends TripRealtimeSourceSignal {
  const TripRealtimeChannelSignal(this.status);

  final TripRealtimeChannelStatus status;
}

enum TripRealtimeEventCause {
  initialCanonicalRead,
  tripRowChanged,
  statusHistoryChanged,
  connectionRestored,
}

sealed class TripRealtimeUpdate {
  const TripRealtimeUpdate();
}

/// Canonical, authenticated state observed after a realtime signal or recovery.
final class VerifiedTripRealtimeEvent extends TripRealtimeUpdate {
  const VerifiedTripRealtimeEvent({
    required this.trip,
    required this.cause,
    this.statusEventSequence,
  });

  final TripRealtimeTrip trip;
  final TripRealtimeEventCause cause;
  final int? statusEventSequence;
}

/// Transport health only. It carries no Trip or financial state.
final class TripRealtimeConnectionUpdate extends TripRealtimeUpdate {
  const TripRealtimeConnectionUpdate(this.status);

  final TripRealtimeChannelStatus status;
}

/// Indicates a canonical read could not verify a notification or recovery.
/// Consumers must retain the last verified Trip state.
final class TripRealtimeVerificationUpdate extends TripRealtimeUpdate {
  const TripRealtimeVerificationUpdate(this.reason);

  final TripRealtimeFailure reason;
}

enum TripRealtimeFailure {
  invalidTripId,
  unauthenticated,
  notVisible,
  sessionChanged,
  malformedCanonicalState,
  inconsistentVersion,
  sourceUnavailable,
}

/// Sanitized failure; never contains a raw PostgREST, channel, or auth error.
final class TripRealtimeException implements Exception {
  const TripRealtimeException(this.failure);

  final TripRealtimeFailure failure;

  @override
  String toString() => 'TripRealtimeException($failure)';
}
