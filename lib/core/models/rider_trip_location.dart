import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';

/// A location row verified against the canonical active Trip and its assigned
/// Driver. Realtime payloads are hints and never construct this model.
final class RiderTripLocation {
  RiderTripLocation({
    required this.tripId,
    required this.driverId,
    required this.sequence,
    required this.point,
    required DateTime recordedAt,
    required DateTime receivedAt,
    this.headingDegrees,
    this.speedMetersPerSecond,
  })  : recordedAt = recordedAt.toUtc(),
        receivedAt = receivedAt.toUtc() {
    if (!isCanonicalTripId(tripId) || !isCanonicalTripId(driverId)) {
      throw ArgumentError('Canonical Trip and Driver IDs are required.');
    }
    if (sequence <= 0) {
      throw ArgumentError.value(sequence, 'sequence', 'Must be positive.');
    }
    if (headingDegrees case final heading?) {
      if (!heading.isFinite || heading < 0 || heading >= 360) {
        throw ArgumentError.value(heading, 'headingDegrees');
      }
    }
    if (speedMetersPerSecond case final speed?) {
      if (!speed.isFinite || speed < 0) {
        throw ArgumentError.value(speed, 'speedMetersPerSecond');
      }
    }
  }

  final String tripId;
  final String driverId;
  final int sequence;
  final LocationPoint point;
  final DateTime recordedAt;
  final DateTime receivedAt;
  final double? headingDegrees;
  final double? speedMetersPerSecond;

  static RiderTripLocation fromRow(Map<dynamic, dynamic> row) {
    final tripId = row['trip_id'];
    final driverId = row['driver_id'];
    final sequence = row['sequence'];
    final latitude = row['latitude'];
    final longitude = row['longitude'];
    final accuracy = row['accuracy_meters'];
    if (tripId is! String ||
        driverId is! String ||
        sequence is! int ||
        latitude is! num ||
        longitude is! num ||
        accuracy is! num) {
      throw const FormatException('Malformed driver location row.');
    }
    return RiderTripLocation(
      tripId: tripId,
      driverId: driverId,
      sequence: sequence,
      point: LocationPoint(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        accuracyMeters: accuracy.toDouble(),
      ),
      recordedAt: _parseTimestamp(row['recorded_at']),
      receivedAt: _parseTimestamp(row['received_at']),
      headingDegrees: _optionalFiniteNumber(row['heading_degrees']),
      speedMetersPerSecond:
          _optionalFiniteNumber(row['speed_meters_per_second']),
    );
  }

  static DateTime _parseTimestamp(Object? value) {
    if (value is! String) throw const FormatException();
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw const FormatException();
    return parsed.toUtc();
  }

  static double? _optionalFiniteNumber(Object? value) {
    if (value == null) return null;
    if (value is! num || !value.isFinite) throw const FormatException();
    return value.toDouble();
  }
}

enum RiderTripLocationChannelStatus {
  connecting,
  subscribed,
  channelError,
  closed,
  timedOut,
}

sealed class RiderTripLocationSourceSignal {
  const RiderTripLocationSourceSignal();
}

final class RiderTripLocationChangedSignal
    extends RiderTripLocationSourceSignal {
  const RiderTripLocationChangedSignal({
    required this.tripId,
    required this.driverId,
  });

  final String tripId;
  final String driverId;
}

final class RiderTripLocationChannelSignal
    extends RiderTripLocationSourceSignal {
  const RiderTripLocationChannelSignal(this.status);

  final RiderTripLocationChannelStatus status;
}

final class RiderTripLocationSessionChangedSignal
    extends RiderTripLocationSourceSignal {
  const RiderTripLocationSessionChangedSignal();
}

enum RiderTripLocationClearReason {
  terminalTrip,
  sessionChanged,
  assignmentChanged,
  authorizationRevoked,
  noLongerActive,
  staleLocation,
}

sealed class RiderTripLocationUpdate {
  const RiderTripLocationUpdate();
}

final class RiderTripLocationSnapshot extends RiderTripLocationUpdate {
  const RiderTripLocationSnapshot(this.location);

  final RiderTripLocation location;
}

final class RiderTripLocationCleared extends RiderTripLocationUpdate {
  const RiderTripLocationCleared(this.reason);

  final RiderTripLocationClearReason reason;
}

final class RiderTripLocationConnectionUpdate extends RiderTripLocationUpdate {
  const RiderTripLocationConnectionUpdate(this.status);

  final RiderTripLocationChannelStatus status;
}

final class RiderTripLocationVerificationUpdate extends RiderTripLocationUpdate {
  const RiderTripLocationVerificationUpdate(this.failure);

  final RiderTripLocationFailure failure;
}

enum RiderTripLocationFailure {
  invalidTripId,
  unauthenticated,
  notAuthorized,
  sessionChanged,
  malformedLocation,
  sourceUnavailable,
}

final class RiderTripLocationException implements Exception {
  const RiderTripLocationException(this.failure);

  final RiderTripLocationFailure failure;

  @override
  String toString() => 'RiderTripLocationException($failure)';
}

bool isRiderTripLocationActive(DriverTripLifecycleStatus status) => switch (
      status
    ) {
      DriverTripLifecycleStatus.accepted ||
      DriverTripLifecycleStatus.driverArriving ||
      DriverTripLifecycleStatus.driverArrived ||
      DriverTripLifecycleStatus.inProgress => true,
      _ => false,
    };

bool isRiderTripLocationTerminal(DriverTripLifecycleStatus status) => switch (
      status
    ) {
      DriverTripLifecycleStatus.completed ||
      DriverTripLifecycleStatus.cancelledByRider ||
      DriverTripLifecycleStatus.cancelledByDriver ||
      DriverTripLifecycleStatus.cancelledByAdmin ||
      DriverTripLifecycleStatus.failed => true,
      _ => false,
    };
