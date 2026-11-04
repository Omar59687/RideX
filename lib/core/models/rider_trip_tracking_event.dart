import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';

sealed class RiderTripTrackingEvent extends Equatable {
  RiderTripTrackingEvent({required this.tripId}) {
    if (!isCanonicalTripId(tripId)) {
      throw ArgumentError.value(tripId, 'tripId', 'Must be a canonical UUID.');
    }
  }

  final String tripId;

  @override
  List<Object?> get props => [tripId];
}

class RiderTripSnapshot extends RiderTripTrackingEvent {
  RiderTripSnapshot(this.trip) : super(tripId: trip.tripId);

  final RiderAssignedTrip trip;

  @override
  List<Object?> get props => [tripId, trip];
}

class RiderTripStatusChanged extends RiderTripTrackingEvent {
  RiderTripStatusChanged({
    required super.tripId,
    required this.tripVersion,
    required this.eventSequence,
    required this.status,
    required DateTime occurredAt,
  }) : occurredAt = occurredAt.toUtc() {
    if (tripVersion <= 0) {
      throw ArgumentError.value(
        tripVersion,
        'tripVersion',
        'Must be positive.',
      );
    }
    if (eventSequence <= 0) {
      throw ArgumentError.value(
        eventSequence,
        'eventSequence',
        'Must be positive.',
      );
    }
  }

  final int tripVersion;
  final int eventSequence;
  final DriverTripLifecycleStatus status;
  final DateTime occurredAt;

  @override
  List<Object?> get props => [
        tripId,
        tripVersion,
        eventSequence,
        status,
        occurredAt,
      ];
}

class RiderTripLocationChanged extends RiderTripTrackingEvent {
  RiderTripLocationChanged({
    required super.tripId,
    required this.sample,
    required DateTime receivedAt,
  }) : receivedAt = receivedAt.toUtc() {
    if (sample.tripId?.toLowerCase() != tripId.toLowerCase()) {
      throw ArgumentError.value(
        sample.tripId,
        'sample.tripId',
        'Must match the event Trip ID.',
      );
    }
  }

  final DriverLocationSample sample;
  final DateTime receivedAt;

  int get locationSequence => sample.sequence;

  DateTime get recordedAt => sample.recordedAt;

  @override
  List<Object?> get props => [tripId, sample, receivedAt];
}

class RiderTripTrackingDisconnected extends RiderTripTrackingEvent {
  RiderTripTrackingDisconnected({
    required super.tripId,
    required DateTime disconnectedAt,
    String? reason,
  })  : disconnectedAt = disconnectedAt.toUtc(),
        reason = _optionalReason(reason);

  final DateTime disconnectedAt;
  final String? reason;

  @override
  List<Object?> get props => [tripId, disconnectedAt, reason];
}

String? _optionalReason(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 200) {
    throw ArgumentError.value(
      value,
      'reason',
      'Must be 1..200 characters after trimming.',
    );
  }
  return trimmed;
}
