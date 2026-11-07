part of 'package:ridex/core/models/rider_live_map_state.dart';

/// Test-only authorization data. This is deliberately not a production
/// capability and must never be populated from a Trip ID, UI role, fake
/// assignment, or Realtime event in application code.
@visibleForTesting
final class RiderLiveMapTestAuthorizationSnapshot {
  const RiderLiveMapTestAuthorizationSnapshot({
    required this.trip,
    required this.sessionLineage,
    required this.sessionGeneration,
    required this.granted,
  });

  final RiderAssignedTrip trip;
  final Object? sessionLineage;
  final int sessionGeneration;
  final bool granted;
}

/// Mutable/faultable source used only to exercise projection failure paths.
///
/// Production authorization remains disabled until a trusted issuer and
/// observable session-lineage boundary are integrated. Test activation requires
/// the explicit `RIDEX_LIVE_MAP_TEST_MODE=true` compile-time define. That define
/// is an opt-in test harness switch, not authorization evidence or a security
/// boundary against a deliberately misconfigured build.
@visibleForTesting
abstract interface class RiderLiveMapTestAuthorizationSource {
  RiderLiveMapTestAuthorizationSnapshot? read();
}

/// Deterministic projection with a permanently disabled production mode.
///
/// The default constructor cannot authorize a location. [forTesting] and its
/// test-only input methods are annotated and explicitly named, and also require
/// an explicit test-harness compile-time opt-in in a debug build. The
/// annotation is not access control. No caller-created evidence can activate
/// the production constructor.
class RiderLiveMapProjection {
  RiderLiveMapProjection({
    required DateTime Function() clock,
    Duration freshnessWindow = const Duration(seconds: 30),
  }) : this._(
          clock: clock,
          freshnessWindow: freshnessWindow,
          testMode: false,
        );

  @visibleForTesting
  RiderLiveMapProjection.forTesting({
    required DateTime Function() clock,
    Duration freshnessWindow = const Duration(seconds: 30),
  }) : this._(
          clock: clock,
          freshnessWindow: freshnessWindow,
          testMode: const bool.fromEnvironment('RIDEX_LIVE_MAP_TEST_MODE') &&
              !kReleaseMode &&
              !kProfileMode,
        );

  RiderLiveMapProjection._({
    required DateTime Function() clock,
    required Duration freshnessWindow,
    required bool testMode,
  })  : _clock = clock,
        _testMode = testMode,
        freshnessWindow = freshnessWindow {
    if (freshnessWindow <= Duration.zero) {
      throw ArgumentError.value(
        freshnessWindow,
        'freshnessWindow',
        'Must be positive.',
      );
    }
  }

  final DateTime Function() _clock;
  final bool _testMode;
  final Duration freshnessWindow;
  RiderLiveMapTestAuthorizationSource? _source;
  RiderLiveMapTestAuthorizationSnapshot? _captured;
  _RiderLiveMapDisplayLease? _lease;
  RiderLiveMapState _state = const RiderLiveMapState.unavailable();
  final Set<String> _terminalTrips = {};
  final Map<String, List<_RevokedLineage>> _revokedLineages = {};
  bool _gpsAvailable = false;
  bool _awaitingFixAfterReconnect = false;

  RiderLiveMapState get state {
    if (!_testMode) return const RiderLiveMapState.unavailable();
    if (!_refreshCurrentEvidence()) return _clear();
    return _refreshFreshness();
  }

  /// Injects explicit test evidence; unavailable in production mode.
  @visibleForTesting
  RiderLiveMapState authorizeForTesting(
    RiderLiveMapTestAuthorizationSource? source,
  ) {
    if (!_testMode || source == null) return _clearAndRevoke();
    final snapshot = _safeRead(source);
    if (snapshot != null && _snapshotIsTerminal(snapshot)) {
      _terminalTrips.add(snapshot.trip.tripId.toLowerCase());
      return _clearAndRevoke();
    }
    if (snapshot == null || !_validSnapshot(snapshot)) {
      return _clearAndRevoke();
    }

    final tripKey = snapshot.trip.tripId.toLowerCase();
    if (_terminalTrips.contains(tripKey) || _wasRevoked(snapshot)) {
      return _clearAndRevoke();
    }

    final previous = _captured;
    if (previous == null || !_sameLineage(previous, snapshot)) {
      if (previous != null) _rememberRevoked(previous);
      _source = source;
      _captured = snapshot;
      _resetAuthorizedState();
      return _state;
    }

    _source = source;
    _captured = snapshot;
    return _refreshFreshness();
  }

  /// Accepts one event only while the captured test evidence remains current.
  @visibleForTesting
  RiderLiveMapState acceptLocationForTesting(
    RiderTripLocationChanged event,
  ) {
    if (!_testMode || !_refreshCurrentEvidence()) return _clearAndRevoke();
    final evidence = _captured!;
    final trip = evidence.trip;
    if (!_matchesTrip(event.tripId, trip.tripId)) return _refreshFreshness();

    final sample = event.sample;
    final previousSequence = _state.locationSequence;
    final previousRecordedAt = _state.locationRecordedAt;
    final connectionStatus = _state.connectionStatus;
    final now = _clock().toUtc();
    if (!_matchesTrip(sample.tripId, trip.tripId) ||
        !_hasValidCoordinates(sample.point) ||
        sample.recordedAt.isAfter(now) ||
        (previousSequence != null && sample.sequence <= previousSequence) ||
        (previousRecordedAt != null &&
            sample.recordedAt.isBefore(previousRecordedAt))) {
      return _refreshFreshness();
    }

    _gpsAvailable = true;
    if (connectionStatus == RiderLiveMapConnectionStatus.online) {
      _awaitingFixAfterReconnect = false;
    }
    final fresh = connectionStatus == RiderLiveMapConnectionStatus.online &&
        !_awaitingFixAfterReconnect &&
        _isFresh(sample.recordedAt, now);
    _state = RiderLiveMapState._authorized(
      lease: _renewLease(),
      locationStatus: fresh
          ? RiderLiveMapLocationStatus.fresh
          : RiderLiveMapLocationStatus.stale,
      gpsStatus: RiderLiveMapGpsStatus.available,
      connectionStatus: connectionStatus,
      driverLocation: sample.point,
      locationSequence: sample.sequence,
      locationRecordedAt: sample.recordedAt,
    );
    return _state;
  }

  /// Records Driver-source GPS loss independently from sample age.
  @visibleForTesting
  RiderLiveMapState markGpsUnavailableForTesting() {
    if (!_testMode || !_refreshCurrentEvidence()) return _clearAndRevoke();
    _gpsAvailable = false;
    final point = _state.driverLocation;
    final connectionStatus = _state.connectionStatus;
    final sequence = _state.locationSequence;
    final recordedAt = _state.locationRecordedAt;
    _state = RiderLiveMapState._authorized(
      lease: _renewLease(),
      locationStatus: point == null
          ? RiderLiveMapLocationStatus.gpsUnavailable
          : RiderLiveMapLocationStatus.stale,
      gpsStatus: RiderLiveMapGpsStatus.unavailable,
      connectionStatus: connectionStatus,
      driverLocation: point,
      locationSequence: sequence,
      locationRecordedAt: recordedAt,
    );
    return _state;
  }

  /// Updates transport state. Reconnect alone cannot refresh GPS evidence.
  @visibleForTesting
  RiderLiveMapState setOfflineForTesting(bool offline) {
    if (!_testMode || !_refreshCurrentEvidence()) return _clearAndRevoke();
    final wasOffline =
        _state.connectionStatus == RiderLiveMapConnectionStatus.offline;
    final connection = offline
        ? RiderLiveMapConnectionStatus.offline
        : RiderLiveMapConnectionStatus.online;
    if (wasOffline && !offline) _awaitingFixAfterReconnect = true;
    final point = _state.driverLocation;
    final previousLocationStatus = _state.locationStatus;
    final sequence = _state.locationSequence;
    final recordedAt = _state.locationRecordedAt;
    final canRemainFresh = !offline &&
        !wasOffline &&
        _gpsAvailable &&
        !_awaitingFixAfterReconnect &&
        point != null &&
        _isFresh(recordedAt!, _clock().toUtc());
    _state = RiderLiveMapState._authorized(
      lease: _renewLease(),
      locationStatus: point == null
          ? previousLocationStatus
          : canRemainFresh
              ? RiderLiveMapLocationStatus.fresh
              : RiderLiveMapLocationStatus.stale,
      gpsStatus: _gpsAvailable
          ? RiderLiveMapGpsStatus.available
          : RiderLiveMapGpsStatus.unavailable,
      connectionStatus: connection,
      driverLocation: point,
      locationSequence: sequence,
      locationRecordedAt: recordedAt,
    );
    return _state;
  }

  /// Applies Trip status to the currently captured Trip only.
  @visibleForTesting
  RiderLiveMapState applyTripStatusForTesting(
    DriverTripLifecycleStatus status,
  ) {
    if (!_testMode || !_refreshCurrentEvidence()) return _clearAndRevoke();
    final terminal = switch (status) {
      DriverTripLifecycleStatus.completed ||
      DriverTripLifecycleStatus.cancelledByRider ||
      DriverTripLifecycleStatus.cancelledByDriver ||
      DriverTripLifecycleStatus.cancelledByAdmin ||
      DriverTripLifecycleStatus.failed =>
        true,
      DriverTripLifecycleStatus.accepted ||
      DriverTripLifecycleStatus.driverArriving ||
      DriverTripLifecycleStatus.driverArrived ||
      DriverTripLifecycleStatus.inProgress =>
        false,
    };
    if (terminal) {
      _terminalTrips.add(_captured!.trip.tripId.toLowerCase());
      return _clearAndRevoke();
    }
    return _refreshFreshness();
  }

  /// Clears active map data and blocks replay of the same evidence lineage.
  @visibleForTesting
  RiderLiveMapState revokeForTesting() => _clearAndRevoke();

  bool _refreshCurrentEvidence() {
    final source = _source;
    final captured = _captured;
    if (source == null || captured == null) return false;
    final current = _safeRead(source);
    if (current != null && _snapshotIsTerminal(current)) {
      _terminalTrips.add(current.trip.tripId.toLowerCase());
      _rememberRevoked(captured);
      _clear();
      return false;
    }
    if (current == null ||
        !_validSnapshot(current) ||
        !_sameLineage(captured, current)) {
      _rememberRevoked(captured);
      _clear();
      return false;
    }
    if (_terminalTrips.contains(current.trip.tripId.toLowerCase())) {
      _clear();
      return false;
    }
    _captured = current;
    return true;
  }

  RiderLiveMapTestAuthorizationSnapshot? _safeRead(
    RiderLiveMapTestAuthorizationSource source,
  ) {
    try {
      return source.read();
    } on Object {
      return null;
    }
  }

  bool _validSnapshot(RiderLiveMapTestAuthorizationSnapshot snapshot) {
    try {
      return snapshot.granted &&
          snapshot.sessionLineage != null &&
          snapshot.sessionGeneration > 0 &&
          !snapshot.trip.isTerminal;
    } on Object {
      return false;
    }
  }

  bool _snapshotIsTerminal(RiderLiveMapTestAuthorizationSnapshot snapshot) {
    try {
      return snapshot.trip.isTerminal;
    } on Object {
      return false;
    }
  }

  bool _sameLineage(
    RiderLiveMapTestAuthorizationSnapshot left,
    RiderLiveMapTestAuthorizationSnapshot right,
  ) {
    try {
      return left.trip.tripId.toLowerCase() ==
              right.trip.tripId.toLowerCase() &&
          left.trip.riderId.toLowerCase() == right.trip.riderId.toLowerCase() &&
          identical(left.sessionLineage, right.sessionLineage) &&
          left.sessionGeneration == right.sessionGeneration;
    } on Object {
      return false;
    }
  }

  bool _wasRevoked(RiderLiveMapTestAuthorizationSnapshot snapshot) {
    final revoked = _revokedLineages[snapshot.trip.tripId.toLowerCase()];
    if (revoked == null) return false;
    return revoked.any((lineage) =>
        identical(lineage.sessionLineage, snapshot.sessionLineage) &&
        lineage.sessionGeneration == snapshot.sessionGeneration &&
        lineage.riderId.toLowerCase() == snapshot.trip.riderId.toLowerCase());
  }

  RiderLiveMapState _refreshFreshness() {
    final point = _state.driverLocation;
    if (point == null) return _state;
    final connectionStatus = _state.connectionStatus;
    final sequence = _state.locationSequence;
    final recordedAt = _state.locationRecordedAt!;
    final fresh = connectionStatus == RiderLiveMapConnectionStatus.online &&
        _gpsAvailable &&
        !_awaitingFixAfterReconnect &&
        _isFresh(recordedAt, _clock().toUtc());
    final nextStatus = fresh
        ? RiderLiveMapLocationStatus.fresh
        : RiderLiveMapLocationStatus.stale;
    final gpsStatus = _gpsAvailable
        ? RiderLiveMapGpsStatus.available
        : RiderLiveMapGpsStatus.unavailable;
    if (nextStatus == _state.locationStatus && gpsStatus == _state.gpsStatus) {
      return _state;
    }
    _state = RiderLiveMapState._authorized(
      lease: _renewLease(),
      locationStatus: nextStatus,
      gpsStatus: gpsStatus,
      connectionStatus: connectionStatus,
      driverLocation: point,
      locationSequence: sequence,
      locationRecordedAt: recordedAt,
    );
    return _state;
  }

  bool _isFresh(DateTime recordedAt, DateTime now) {
    final age = now.difference(recordedAt.toUtc());
    return age >= Duration.zero && age <= freshnessWindow;
  }

  static bool _matchesTrip(String? actual, String expected) =>
      actual != null && actual.toLowerCase() == expected.toLowerCase();

  static bool _hasValidCoordinates(LocationPoint point) =>
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude >= -90 &&
      point.latitude <= 90 &&
      point.longitude >= -180 &&
      point.longitude <= 180;

  void _resetAuthorizedState() {
    _gpsAvailable = false;
    _awaitingFixAfterReconnect = false;
    final lease = _renewLease();
    _state = RiderLiveMapState._authorized(
      lease: lease,
      locationStatus: RiderLiveMapLocationStatus.unknown,
      gpsStatus: RiderLiveMapGpsStatus.unknown,
      connectionStatus: RiderLiveMapConnectionStatus.online,
      driverLocation: null,
      locationSequence: null,
      locationRecordedAt: null,
    );
  }

  _RiderLiveMapDisplayLease _renewLease() {
    _lease?.invalidate();
    final lease = _RiderLiveMapDisplayLease(
      isAuthorized: _refreshCurrentEvidence,
      clock: _clock,
      freshnessWindow: freshnessWindow,
    );
    _lease = lease;
    return lease;
  }

  void _rememberRevoked(RiderLiveMapTestAuthorizationSnapshot snapshot) {
    final records = _revokedLineages.putIfAbsent(
      snapshot.trip.tripId.toLowerCase(),
      () => <_RevokedLineage>[],
    );
    final alreadyRecorded = records.any((record) =>
        identical(record.sessionLineage, snapshot.sessionLineage) &&
        record.sessionGeneration == snapshot.sessionGeneration &&
        record.riderId.toLowerCase() == snapshot.trip.riderId.toLowerCase());
    if (alreadyRecorded) return;
    records.add(_RevokedLineage(
      riderId: snapshot.trip.riderId,
      sessionLineage: snapshot.sessionLineage,
      sessionGeneration: snapshot.sessionGeneration,
    ));
  }

  RiderLiveMapState _clearAndRevoke() {
    final captured = _captured;
    if (captured != null) _rememberRevoked(captured);
    return _clear();
  }

  RiderLiveMapState _clear() {
    _lease?.invalidate();
    _lease = null;
    _source = null;
    _captured = null;
    _gpsAvailable = false;
    _awaitingFixAfterReconnect = false;
    _state = const RiderLiveMapState.unavailable();
    return _state;
  }
}

final class _RevokedLineage {
  const _RevokedLineage({
    required this.riderId,
    required this.sessionLineage,
    required this.sessionGeneration,
  });

  final String riderId;
  final Object? sessionLineage;
  final int sessionGeneration;
}
