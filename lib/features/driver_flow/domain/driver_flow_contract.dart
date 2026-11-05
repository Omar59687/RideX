import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';

/// B01 presentation boundary only. Neither source grants backend authority.
/// A future canonical adapter needs a separately reviewed integration contract.
enum DriverFlowSource { simulated, unconfigured }

enum DriverFlowPhase {
  loading,
  ready,
  pending,
  unavailable,
  unauthorized,
  stale,
  unknown,
  completionBlocked,
}

enum DriverFlowOutcome {
  observed,
  simulated,
  rejected,
  expired,
  stale,
  unauthorized,
  unavailable,
  unknown,
  unsupported,
}

/// Local scope identity, never an SDK session or eligibility assertion.
final class DriverFlowSession {
  DriverFlowSession(this.driverId, this.generation) {
    _identity(driverId);
    if (generation < 0) throw ArgumentError('Negative session generation.');
  }

  final String driverId;
  final int generation;

  bool sameSession(DriverFlowSession other) =>
      driverId == other.driverId && generation == other.generation;
}

final class DriverFlowAvailability {
  DriverFlowAvailability({
    required this.state,
    required this.version,
    this.vehicleId,
    this.bookingId,
    this.tripId,
  }) {
    _version(version);
    for (final id in [vehicleId, bookingId, tripId]) {
      if (id != null) _identity(id);
    }
    if ((state != DriverAvailabilityState.offline && vehicleId == null) ||
        (state == DriverAvailabilityState.reserved) != (bookingId != null) ||
        (state == DriverAvailabilityState.onTrip) != (tripId != null)) {
      throw ArgumentError('Inconsistent availability references.');
    }
  }

  final DriverAvailabilityState state;
  final int version;
  final String? vehicleId;
  final String? bookingId;
  final String? tripId;
}

/// Display details supplied by a repository, never a Rider draft or fare input.
final class DriverFlowJourney {
  DriverFlowJourney({
    required this.pickup,
    required this.destination,
    required this.vehicleId,
    required this.vehicleLabel,
    required this.lockedFareFils,
    required this.distanceMeters,
    required this.durationSeconds,
    this.paymentMethod = PaymentMethod.cash,
    List<RideLocation> stops = const [],
  }) : stops = List.unmodifiable(stops) {
    _identity(vehicleId);
    _identity(vehicleLabel);
    if (paymentMethod != PaymentMethod.cash ||
        lockedFareFils < 0 ||
        distanceMeters <= 0 ||
        durationSeconds <= 0) {
      throw ArgumentError('Cash journey with valid route metrics required.');
    }
  }

  final RideLocation pickup;
  final RideLocation destination;
  final List<RideLocation> stops;
  final String vehicleId;
  final String vehicleLabel;
  final int lockedFareFils;
  final int distanceMeters;
  final int durationSeconds;
  final PaymentMethod paymentMethod;
}

final class DriverFlowOffer {
  DriverFlowOffer({
    required this.id,
    required this.bookingId,
    required this.quoteId,
    required this.version,
    required DateTime expiresAt,
    required this.journey,
  }) : expiresAt = expiresAt.toUtc() {
    for (final value in [id, bookingId, quoteId]) {
      _identity(value);
    }
    _version(version);
  }

  final String id;
  final String bookingId;
  final String quoteId;
  final int version;
  final DateTime expiresAt;
  final DriverFlowJourney journey;

  bool isExpiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt);
}

/// Reuses backend lifecycle vocabulary only, never canonical evidence.
/// Pre-trip loading/search/offer states belong to the phase/offer boundary.
/// Terminal presentation (including completed) never proves payment/receipt.
final class DriverFlowTrip {
  DriverFlowTrip({
    required this.id,
    required this.version,
    required this.status,
    required this.journey,
  }) {
    _identity(id);
    _version(version);
  }

  final String id;
  final int version;
  final DriverTripLifecycleStatus status;
  final DriverFlowJourney journey;
}

/// Revision orders events within a session; distinct from all entity versions.
final class DriverFlowSnapshot {
  DriverFlowSnapshot({
    required this.session,
    required this.revision,
    required this.phase,
    required this.source,
    this.availability,
    this.offer,
    this.trip,
  }) {
    if (revision < 0) throw ArgumentError('Negative event revision.');
    if (source == DriverFlowSource.unconfigured &&
        (availability != null || offer != null || trip != null)) {
      throw ArgumentError('Unconfigured source cannot carry journey data.');
    }
  }

  final DriverFlowSession session;
  final int revision;
  final DriverFlowPhase phase;
  final DriverFlowSource source;
  final DriverFlowAvailability? availability;
  final DriverFlowOffer? offer;
  final DriverFlowTrip? trip;
}

/// No command for completion, settlement, receipts, or payment authorization.
sealed class DriverFlowCommand {
  DriverFlowCommand({
    required this.session,
    required this.targetId,
    required this.expectedVersion,
    required this.idempotencyToken,
  }) {
    _identity(targetId);
    _version(expectedVersion);
    _identity(idempotencyToken); // Preserve the original token verbatim.
  }

  final DriverFlowSession session;
  final String targetId;
  final int expectedVersion;
  final String idempotencyToken;
}

final class DriverFlowSetAvailability extends DriverFlowCommand {
  DriverFlowSetAvailability({
    required super.session,
    required super.targetId,
    required super.expectedVersion,
    required super.idempotencyToken,
    required this.state,
    this.vehicleId,
  }) {
    if (state != DriverAvailabilityState.offline &&
        state != DriverAvailabilityState.available) {
      throw ArgumentError('Only offline/available may be requested.');
    }
    if (state == DriverAvailabilityState.available) _identity(vehicleId ?? '');
  }

  final DriverAvailabilityState state;
  final String? vehicleId;
}

enum DriverFlowOfferDecision { accept, decline }

/// A local intent; decline has no assumed backend RPC mapping.
final class DriverFlowDecideOffer extends DriverFlowCommand {
  DriverFlowDecideOffer({
    required super.session,
    required super.targetId,
    required super.expectedVersion,
    required super.idempotencyToken,
    required this.decision,
  });

  final DriverFlowOfferDecision decision;
}

final class DriverFlowProgressTrip extends DriverFlowCommand {
  DriverFlowProgressTrip({
    required super.session,
    required super.targetId,
    required super.expectedVersion,
    required super.idempotencyToken,
    required this.status,
  }) {
    if (!{
      DriverTripLifecycleStatus.driverArriving,
      DriverTripLifecycleStatus.driverArrived,
      DriverTripLifecycleStatus.inProgress,
    }.contains(status)) {
      throw ArgumentError('Only nonfinancial Trip progression is supported.');
    }
  }

  final DriverTripLifecycleStatus status;
}

final class DriverFlowResult {
  const DriverFlowResult(this.outcome, [this.snapshot]);

  final DriverFlowOutcome outcome;
  final DriverFlowSnapshot? snapshot;
}

abstract interface class DriverFlowRepository {
  Future<DriverFlowResult> read(DriverFlowSession session);
  Stream<DriverFlowSnapshot> watch(DriverFlowSession session);
  Future<DriverFlowResult> execute(DriverFlowCommand command);
}

void _identity(String value) {
  if (value.trim().isEmpty) throw ArgumentError('Nonempty identity required.');
}

void _version(int value) {
  if (value < 1) throw ArgumentError('Positive entity version required.');
}
