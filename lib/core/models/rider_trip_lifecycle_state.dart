import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';

/// The exact identifiers needed to reconcile one authenticated Rider Trip.
///
/// Rider identity is deliberately not supplied here: authorization comes from
/// the current application session and the session-scoped repository.
class RiderTripLifecycleRequest extends Equatable {
  RiderTripLifecycleRequest({
    required this.tripId,
    required this.bookingRequestId,
  }) {
    if (!isCanonicalTripId(tripId)) {
      throw ArgumentError.value(tripId, 'tripId', 'Must be a canonical UUID.');
    }
    if (!isCanonicalTripId(bookingRequestId)) {
      throw ArgumentError.value(
        bookingRequestId,
        'bookingRequestId',
        'Must be a canonical UUID.',
      );
    }
  }

  final String tripId;
  final String bookingRequestId;

  @override
  List<Object?> get props => [
        tripId.toLowerCase(),
        bookingRequestId.toLowerCase(),
      ];
}

enum RiderTripLifecyclePhase { loading, verified, stale, unavailable, terminal }

/// Sanitized reasons why the latest canonical status is not currently usable.
enum RiderTripLifecycleFailure {
  authorizationUnavailable,
  repositoryUnavailable,
  tripUnavailable,
  invalidCanonicalData,
  readFailed,
  disconnected,
  staleCanonicalRead,
  conflictingCanonicalVersion,
  invalidStatusTransition,
}

/// Rider-facing lifecycle state whose status is verified only by a canonical
/// repository read.
///
/// A stale state never exposes the last canonical Trip. The controller may
/// retain it privately for version and transition validation. Event payloads
/// never populate [trip].
class RiderTripLifecycleState extends Equatable {
  const RiderTripLifecycleState._({
    required this.phase,
    this.trip,
    this.verifiedAt,
    this.failure,
    this.latestEventSequence,
  });

  const RiderTripLifecycleState.loading({int? latestEventSequence})
      : this._(
          phase: RiderTripLifecyclePhase.loading,
          latestEventSequence: latestEventSequence,
        );

  factory RiderTripLifecycleState.verified({
    required RiderAssignedTrip trip,
    required DateTime verifiedAt,
    int? latestEventSequence,
  }) {
    if (trip.isTerminal) {
      throw ArgumentError.value(
          trip.status, 'trip.status', 'Must be nonterminal.');
    }
    return RiderTripLifecycleState._(
      phase: RiderTripLifecyclePhase.verified,
      trip: trip,
      verifiedAt: verifiedAt,
      latestEventSequence: latestEventSequence,
    );
  }

  factory RiderTripLifecycleState.terminal({
    required RiderAssignedTrip trip,
    required DateTime verifiedAt,
    int? latestEventSequence,
  }) {
    if (!trip.isTerminal) {
      throw ArgumentError.value(
          trip.status, 'trip.status', 'Must be terminal.');
    }
    return RiderTripLifecycleState._(
      phase: RiderTripLifecyclePhase.terminal,
      trip: trip,
      verifiedAt: verifiedAt,
      latestEventSequence: latestEventSequence,
    );
  }

  const RiderTripLifecycleState.stale({
    DateTime? verifiedAt,
    required RiderTripLifecycleFailure failure,
    int? latestEventSequence,
  }) : this._(
          phase: RiderTripLifecyclePhase.stale,
          verifiedAt: verifiedAt,
          failure: failure,
          latestEventSequence: latestEventSequence,
        );

  const RiderTripLifecycleState.unavailable({
    required RiderTripLifecycleFailure failure,
    int? latestEventSequence,
  }) : this._(
          phase: RiderTripLifecyclePhase.unavailable,
          failure: failure,
          latestEventSequence: latestEventSequence,
        );

  final RiderTripLifecyclePhase phase;
  final RiderAssignedTrip? trip;

  /// Time of the last successful, validated canonical read, in UTC.
  final DateTime? verifiedAt;

  /// Fixed reason code only; raw backend or transport errors are never stored.
  final RiderTripLifecycleFailure? failure;

  /// Highest accepted status-event sequence, independent of Trip version.
  final int? latestEventSequence;

  int? get canonicalTripVersion => trip?.version;

  bool get isVerified =>
      phase == RiderTripLifecyclePhase.verified ||
      phase == RiderTripLifecyclePhase.terminal;

  bool get isTerminal => phase == RiderTripLifecyclePhase.terminal;

  RiderTripLifecycleState withEventSequence(int sequence) {
    return RiderTripLifecycleState._(
      phase: phase,
      trip: trip,
      verifiedAt: verifiedAt,
      failure: failure,
      latestEventSequence: sequence,
    );
  }

  RiderTripLifecycleState markStale(
    RiderTripLifecycleFailure reason, {
    int? eventSequence,
  }) {
    return RiderTripLifecycleState.stale(
      verifiedAt: verifiedAt,
      failure: reason,
      latestEventSequence: eventSequence ?? latestEventSequence,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        trip,
        verifiedAt,
        failure,
        latestEventSequence,
      ];
}
