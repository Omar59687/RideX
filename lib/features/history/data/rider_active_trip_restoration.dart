import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';

/// A dedicated bounded, participant-scoped read, NOT a history-page shortcut.
/// Backend implementation must query *all* canonical nonterminal Trip states,
/// return at most two records, and signal ambiguity when more than one exists.
/// It must never decide to return only an arbitrary first Trip.
abstract interface class RiderActiveTripReadPort {
  Future<List<RiderHistoryTrip>> findActiveCandidates({
    required String riderId,
    required int limit,
  });

  /// A fresh exact-ID authorized reread after candidate discovery.
  Future<RiderHistoryTrip?> rereadExact({
    required String riderId,
    required String tripId,
  });
}

enum RiderActiveRestoreFailure {
  unauthorized,
  staleSession,
  invalidResponse,
  ambiguous,
  unavailable,
}

final class RiderActiveRestoreException implements Exception {
  const RiderActiveRestoreException(this.failure);
  final RiderActiveRestoreFailure failure;

  @override
  String toString() => 'Active Trip restoration unavailable.';
}

final class RiderActiveTripSnapshot {
  const RiderActiveTripSnapshot(this.trip);
  final RiderHistoryTrip trip;
  String get tripId => trip.tripId;
}

/// Safe read-only restoration for login, restart, resume and reconnect.
///
/// Requires a genuine SDK session epoch (identity-changing opaque object),
/// Rider authorization, and an owner-scoped port. The adapter still must
/// enforce RLS, profile block/role checks, SDK pinning around every await,
/// and bounded reads; this coordinator is a second defense.
final class RiderActiveTripRestorer {
  const RiderActiveTripRestorer({
    required this.reader,
    required this.currentRiderId,
    required this.isAuthorized,
    required this.sessionEpoch,
  });

  final RiderActiveTripReadPort reader;
  final String? Function() currentRiderId;
  final bool Function() isAuthorized;
  final Object? Function() sessionEpoch;

  bool _current(String riderId, Object? epoch) =>
      isCanonicalTripId(riderId) &&
      currentRiderId() == riderId &&
      isAuthorized() &&
      identical(sessionEpoch(), epoch);

  Never _fail(RiderActiveRestoreFailure failure) =>
      throw RiderActiveRestoreException(failure);

  Future<RiderActiveTripSnapshot?> restore(String riderId) async {
    final epoch = sessionEpoch();
    if (!_current(riderId, epoch)) {
      _fail(RiderActiveRestoreFailure.unauthorized);
    }

    List<RiderHistoryTrip> candidates;
    try {
      candidates = await reader.findActiveCandidates(riderId: riderId, limit: 2);
    } on RiderActiveRestoreException {
      rethrow;
    } on Object {
      if (!_current(riderId, epoch)) {
        _fail(RiderActiveRestoreFailure.staleSession);
      }
      _fail(RiderActiveRestoreFailure.unavailable);
    }
    if (!_current(riderId, epoch)) {
      _fail(RiderActiveRestoreFailure.staleSession);
    }
    if (candidates.length > 2) _fail(RiderActiveRestoreFailure.invalidResponse);
    if (candidates.length > 1) _fail(RiderActiveRestoreFailure.ambiguous);
    if (candidates.isEmpty) return null;

    final discovered = candidates.single;
    if (!_validTrip(discovered, riderId) || discovered.isTerminal) {
      _fail(RiderActiveRestoreFailure.invalidResponse);
    }

    RiderHistoryTrip? fresh;
    try {
      fresh = await reader.rereadExact(
        riderId: riderId,
        tripId: discovered.tripId,
      );
    } on RiderActiveRestoreException {
      rethrow;
    } on Object {
      if (!_current(riderId, epoch)) {
        _fail(RiderActiveRestoreFailure.staleSession);
      }
      _fail(RiderActiveRestoreFailure.unavailable);
    }
    if (!_current(riderId, epoch)) {
      _fail(RiderActiveRestoreFailure.staleSession);
    }
    // A vanished or terminal Trip must not be restored as active.
    if (fresh == null || fresh.isTerminal) return null;
    if (!_validTrip(fresh, riderId) ||
        fresh.tripId != discovered.tripId ||
        fresh.bookingRequestId != discovered.bookingRequestId ||
        fresh.updatedAt.isBefore(discovered.updatedAt)) {
      _fail(RiderActiveRestoreFailure.invalidResponse);
    }
    return RiderActiveTripSnapshot(fresh);
  }

  bool _validTrip(RiderHistoryTrip trip, String riderId) =>
      trip.riderId == riderId &&
      isCanonicalTripId(trip.tripId) &&
      isCanonicalTripId(trip.bookingRequestId) &&
      switch (trip.status) {
        DriverTripLifecycleStatus.accepted ||
        DriverTripLifecycleStatus.driverArriving ||
        DriverTripLifecycleStatus.driverArrived ||
        DriverTripLifecycleStatus.inProgress => true,
        _ => false,
      };
}
