import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/location_point.dart';

class DriverLocationSample extends Equatable {
  DriverLocationSample({
    required this.point,
    required this.sequence,
    required DateTime recordedAt,
    this.tripId,
    this.headingDegrees,
    this.speedMetersPerSecond,
  }) : recordedAt = recordedAt.toUtc() {
    if (sequence <= 0) {
      throw ArgumentError.value(sequence, 'sequence', 'Must be positive.');
    }
    if (point.accuracyMeters == null) {
      throw ArgumentError.value(point, 'point', 'Accuracy is required.');
    }
    if (headingDegrees case final heading?) {
      if (!heading.isFinite || heading < 0 || heading >= 360) {
        throw ArgumentError.value(
          headingDegrees,
          'headingDegrees',
          'Must be finite and from 0 to 360.',
        );
      }
    }
    if (speedMetersPerSecond case final speed?) {
      if (!speed.isFinite || speed < 0) {
        throw ArgumentError.value(
          speedMetersPerSecond,
          'speedMetersPerSecond',
          'Must be finite and nonnegative.',
        );
      }
    }
  }

  final LocationPoint point;
  final int sequence;
  final DateTime recordedAt;
  final String? tripId;
  final double? headingDegrees;
  final double? speedMetersPerSecond;

  @override
  List<Object?> get props => [
        point,
        sequence,
        recordedAt,
        tripId,
        headingDegrees,
        speedMetersPerSecond,
      ];
}

class SavedDriverLocation extends Equatable {
  SavedDriverLocation({
    required this.point,
    required this.sequence,
    required DateTime recordedAt,
    required DateTime receivedAt,
    this.tripId,
    this.headingDegrees,
    this.speedMetersPerSecond,
  })  : recordedAt = recordedAt.toUtc(),
        receivedAt = receivedAt.toUtc() {
    if (sequence <= 0) {
      throw ArgumentError.value(sequence, 'sequence', 'Must be positive.');
    }
  }

  final LocationPoint point;
  final int sequence;
  final DateTime recordedAt;
  final DateTime receivedAt;
  final String? tripId;
  final double? headingDegrees;
  final double? speedMetersPerSecond;

  @override
  List<Object?> get props => [
        point,
        sequence,
        recordedAt,
        receivedAt,
        tripId,
        headingDegrees,
        speedMetersPerSecond,
      ];
}
