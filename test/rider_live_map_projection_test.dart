import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_live_map_state.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

const _testHarnessEnabled = bool.fromEnvironment('RIDEX_LIVE_MAP_TEST_MODE');

void main() {
  if (!_testHarnessEnabled) {
    test('test projection is unavailable without explicit test opt-in', () {
      final projection = RiderLiveMapProjection.forTesting(
        clock: () => DateTime.utc(2026, 11, 5, 12),
      );
      final source = _MutableAuthorizationSource(_snapshot());

      expect(
        projection.authorizeForTesting(source).authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable,
      );
      expect(
        projection.acceptLocationForTesting(_event(sequence: 1)).driverLocation,
        isNull,
      );
    });
    return;
  }

  late DateTime now;
  late RiderLiveMapProjection projection;
  late _MutableAuthorizationSource source;

  setUp(() {
    now = DateTime.utc(2026, 11, 5, 12);
    projection = RiderLiveMapProjection.forTesting(clock: () => now);
    source = _MutableAuthorizationSource(_snapshot());
  });

  test('missing authorization is unavailable and exposes no location', () {
    expect(projection.state.authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable);
    expect(projection.authorizeForTesting(null).driverLocation, isNull);
    expect(
        projection.acceptLocationForTesting(_event(sequence: 1)).driverLocation,
        isNull);
  });

  test('a Trip model or caller-created source cannot authorize production mode',
      () {
    final production = RiderLiveMapProjection(clock: () => now);
    expect(
      production.authorizeForTesting(source).authorizationStatus,
      RiderLiveMapAuthorizationStatus.unavailable,
    );
    expect(
      production.acceptLocationForTesting(_event(sequence: 1)).hasLiveLocation,
      isFalse,
    );
    expect(production.state.driverLocation, isNull);
  });

  test('only test-mode projection can create authorized display state', () {
    final unavailable = const RiderLiveMapState.unavailable();
    expect(unavailable.authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable);
    expect(unavailable.hasLiveLocation, isFalse);

    projection.authorizeForTesting(source);
    final live = projection.acceptLocationForTesting(_event(sequence: 1));
    expect(live.hasLiveLocation, isTrue);
  });

  test('accepts increasing coordinates for exact Trip evidence', () {
    projection.authorizeForTesting(source);
    final first = projection.acceptLocationForTesting(_event(sequence: 1));
    expect(first.locationStatus, RiderLiveMapLocationStatus.fresh);
    expect(first.driverLocation?.latitude, 31.95);

    final second = projection.acceptLocationForTesting(
      _event(sequence: 2, latitude: 31.96),
    );

    expect(second.locationSequence, 2);
    expect(second.driverLocation?.latitude, 31.96);
    expect(second.hasLiveLocation, isTrue);
    expect(
        first.authorizationStatus, RiderLiveMapAuthorizationStatus.unavailable);
    expect(first.driverLocation, isNull);
  });

  test('mismatched event Trip and mismatched sample Trip do not update state',
      () {
    projection.authorizeForTesting(source);
    final accepted = projection.acceptLocationForTesting(_event(sequence: 1));

    final foreign = projection.acceptLocationForTesting(
      _event(sequence: 2, eventTripId: secondaryRiderTripIdFixture),
    );
    expect(foreign, same(accepted));

    expect(
      () => RiderTripLocationChanged(
        tripId: riderTripIdFixture,
        sample: _sample(
          sequence: 2,
          tripId: secondaryRiderTripIdFixture,
        ),
        receivedAt: now,
      ),
      throwsArgumentError,
    );
    expect(projection.state, same(accepted));
  });

  test('duplicate, lower-sequence, and older-time events cannot regress state',
      () {
    projection.authorizeForTesting(source);
    final accepted = projection.acceptLocationForTesting(
      _event(sequence: 3, latitude: 31.97),
    );
    expect(
      projection.acceptLocationForTesting(
        _event(sequence: 3, latitude: 31.96),
      ),
      same(accepted),
    );
    expect(
      projection.acceptLocationForTesting(
        _event(sequence: 2, latitude: 31.95),
      ),
      same(accepted),
    );
    expect(
      projection.acceptLocationForTesting(
        _event(
          sequence: 4,
          latitude: 31.94,
          recordedAt: now.subtract(const Duration(seconds: 1)),
        ),
      ),
      same(accepted),
    );
  });

  test('future-dated samples do not replace point or advance sequence', () {
    projection.authorizeForTesting(source);
    final accepted = projection.acceptLocationForTesting(_event(sequence: 1));
    final future = projection.acceptLocationForTesting(
      _event(
        sequence: 2,
        latitude: 31.99,
        recordedAt: now.add(const Duration(seconds: 1)),
      ),
    );

    expect(future.driverLocation, accepted.driverLocation);
    expect(future.locationSequence, 1);
    expect(future.locationStatus, RiderLiveMapLocationStatus.fresh);
  });

  test('invalid coordinates are rejected by the canonical location model', () {
    projection.authorizeForTesting(source);
    expect(
      () => LocationPoint(latitude: double.nan, longitude: 35.91),
      throwsArgumentError,
    );
    expect(projection.state.driverLocation, isNull);
    expect(projection.state.hasLiveLocation, isFalse);
  });

  test('fresh sample becomes stale as injected clock advances', () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));
    now = now.add(const Duration(seconds: 31));

    expect(projection.state.locationStatus, RiderLiveMapLocationStatus.stale);
    expect(projection.state.hasLiveLocation, isFalse);
    expect(projection.state.driverLocation, isNotNull);
  });

  test('GPS unavailable before first sample is explicit', () {
    projection.authorizeForTesting(source);
    final state = projection.markGpsUnavailableForTesting();

    expect(state.locationStatus, RiderLiveMapLocationStatus.gpsUnavailable);
    expect(state.gpsStatus, RiderLiveMapGpsStatus.unavailable);
    expect(state.driverLocation, isNull);
    expect(state.hasLiveLocation, isFalse);
  });

  test('GPS loss after valid fix stays non-live until a new fix', () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));
    final lost = projection.markGpsUnavailableForTesting();

    expect(lost.locationStatus, RiderLiveMapLocationStatus.stale);
    expect(lost.gpsStatus, RiderLiveMapGpsStatus.unavailable);
    expect(projection.state.hasLiveLocation, isFalse);

    final recovered = projection.acceptLocationForTesting(_event(sequence: 2));
    expect(recovered.gpsStatus, RiderLiveMapGpsStatus.available);
    expect(recovered.locationStatus, RiderLiveMapLocationStatus.fresh);
    expect(recovered.hasLiveLocation, isTrue);
  });

  test('offline then reconnect stays stale until a new location arrives', () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));
    final offline = projection.setOfflineForTesting(true);
    expect(offline.hasLiveLocation, isFalse);
    expect(offline.locationStatus, RiderLiveMapLocationStatus.stale);

    final reconnected = projection.setOfflineForTesting(false);
    expect(reconnected.connectionStatus, RiderLiveMapConnectionStatus.online);
    expect(reconnected.locationStatus, RiderLiveMapLocationStatus.stale);
    expect(reconnected.hasLiveLocation, isFalse);

    final recovered = projection.acceptLocationForTesting(_event(sequence: 2));
    expect(recovered.hasLiveLocation, isTrue);
  });

  test('repeated GPS and reconnect cycles require a fresh fix each time', () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));

    projection.markGpsUnavailableForTesting();
    expect(projection.state.hasLiveLocation, isFalse);
    expect(
        projection
            .acceptLocationForTesting(_event(sequence: 2))
            .hasLiveLocation,
        isTrue);

    projection.markGpsUnavailableForTesting();
    expect(projection.state.hasLiveLocation, isFalse);
    expect(
        projection
            .acceptLocationForTesting(_event(sequence: 3))
            .hasLiveLocation,
        isTrue);

    projection.setOfflineForTesting(true);
    projection.setOfflineForTesting(false);
    expect(projection.state.hasLiveLocation, isFalse);
    expect(
        projection
            .acceptLocationForTesting(_event(sequence: 4))
            .hasLiveLocation,
        isTrue);

    projection.setOfflineForTesting(true);
    projection.setOfflineForTesting(false);
    expect(projection.state.hasLiveLocation, isFalse);
    expect(
        projection
            .acceptLocationForTesting(_event(sequence: 5))
            .hasLiveLocation,
        isTrue);
  });

  test(
      'revocation clears state and stale evidence or late events cannot restore',
      () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));
    final revoked = projection.revokeForTesting();
    expect(revoked.driverLocation, isNull);
    expect(
        projection.acceptLocationForTesting(_event(sequence: 2)).driverLocation,
        isNull);
    expect(projection.authorizeForTesting(source).driverLocation, isNull);
  });

  test('revocation of lineage B does not erase revoked lineage A', () {
    final lineageA = Object();
    final snapshotA = _snapshot(lineage: lineageA, generation: 1);
    source.snapshot = snapshotA;
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));
    projection.revokeForTesting();

    source.snapshot = _snapshot(lineage: Object(), generation: 2);
    expect(
      projection.authorizeForTesting(source).authorizationStatus,
      RiderLiveMapAuthorizationStatus.authorized,
    );
    projection.revokeForTesting();

    source.snapshot = snapshotA;
    final replay = projection.authorizeForTesting(source);
    expect(replay.authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable);
    expect(replay.driverLocation, isNull);
  });

  test('a higher Trip version cannot revive the same revoked lineage', () {
    final lineage = Object();
    final snapshotV1 = _snapshot(lineage: lineage, version: 1);
    source.snapshot = snapshotV1;
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));
    projection.revokeForTesting();

    source.snapshot = _snapshot(lineage: lineage, version: 2);
    final replay = projection.authorizeForTesting(source);
    expect(replay.authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable);
    expect(replay.driverLocation, isNull);
  });

  test('retained state reference loses access immediately on revocation', () {
    projection.authorizeForTesting(source);
    final retained = projection.acceptLocationForTesting(_event(sequence: 1));
    final copiedPoint = retained.driverLocation;
    expect(retained.hasLiveLocation, isTrue);

    projection.revokeForTesting();

    expect(retained.authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable);
    expect(retained.driverLocation, isNull);
    expect(retained.locationSequence, isNull);
    expect(retained.hasLiveLocation, isFalse);
    // A point independently copied before revocation is an ordinary Dart
    // object and cannot be erased by invalidating the projection's view.
    expect(copiedPoint, isNotNull);
  });

  test('retained state reference loses access on session change', () {
    projection.authorizeForTesting(source);
    final retained = projection.acceptLocationForTesting(_event(sequence: 1));
    source.snapshot = _snapshot(generation: 2);

    expect(retained.driverLocation, isNull);
    expect(retained.authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable);
    expect(retained.hasLiveLocation, isFalse);
  });

  test('retained state reference loses access on terminal Trip', () {
    projection.authorizeForTesting(source);
    final retained = projection.acceptLocationForTesting(_event(sequence: 1));
    source.snapshot = _snapshot(status: DriverTripLifecycleStatus.completed);

    expect(retained.authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable);
    expect(retained.driverLocation, isNull);
    expect(retained.hasLiveLocation, isFalse);
  });

  test('terminal Trip cannot be reauthorized by stale evidence or late events',
      () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));
    final terminal = projection.applyTripStatusForTesting(
      DriverTripLifecycleStatus.completed,
    );

    expect(terminal.driverLocation, isNull);
    expect(projection.authorizeForTesting(source).driverLocation, isNull);
    expect(
        projection.acceptLocationForTesting(_event(sequence: 2)).driverLocation,
        isNull);
  });

  test('terminal snapshot prevents replay of a previously active snapshot', () {
    final staleActive = source.snapshot!;
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));
    source.snapshot = _snapshot(status: DriverTripLifecycleStatus.completed);

    expect(projection.state.driverLocation, isNull);
    source.snapshot = staleActive;
    expect(projection.authorizeForTesting(source).driverLocation, isNull);
  });

  test('Rider, Trip, lineage, and generation changes clear prior location', () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));

    source.snapshot = _snapshot(riderId: unrelatedRiderIdFixture);
    expect(projection.state.driverLocation, isNull);

    source.snapshot = _snapshot(
      tripId: secondaryRiderTripIdFixture,
      bookingRequestId: secondaryRiderBookingIdFixture,
    );
    expect(projection.authorizeForTesting(source).driverLocation, isNull);
    projection.acceptLocationForTesting(
      _event(
        sequence: 1,
        eventTripId: secondaryRiderTripIdFixture,
      ),
    );

    source.snapshot = _snapshot(
      tripId: secondaryRiderTripIdFixture,
      bookingRequestId: secondaryRiderBookingIdFixture,
      lineage: Object(),
    );
    expect(projection.state.driverLocation, isNull);

    source.snapshot = _snapshot(
      tripId: secondaryRiderTripIdFixture,
      bookingRequestId: secondaryRiderBookingIdFixture,
      generation: 2,
    );
    expect(projection.state.driverLocation, isNull);
  });

  test('null, throwing, denied, and changing evidence fail closed', () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));

    source.throwOnRead = true;
    expect(projection.state.authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable);
    expect(projection.state.driverLocation, isNull);
    expect(projection.authorizeForTesting(source).driverLocation, isNull);

    source.throwOnRead = false;
    source.snapshot = null;
    expect(projection.authorizeForTesting(source).driverLocation, isNull);
    source.snapshot = _snapshot(granted: false);
    expect(projection.authorizeForTesting(source).driverLocation, isNull);

    source.snapshot = _snapshot(missingLineage: true);
    expect(projection.authorizeForTesting(source).driverLocation, isNull);
  });

  test('a null snapshot revokes a previously live projection', () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));
    source.snapshot = null;

    expect(projection.state.authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable);
    expect(projection.state.driverLocation, isNull);
  });

  test('same-lineage stale reauthorization is rejected after source change',
      () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));
    source.snapshot = _snapshot(generation: 2);

    expect(projection.state.authorizationStatus,
        RiderLiveMapAuthorizationStatus.unavailable);
    expect(projection.authorizeForTesting(source).driverLocation, isNull);
  });

  test('unchanged test source cannot detect silent SDK Session replacement',
      () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));

    // This intentionally documents the boundary: if the external source
    // cannot observe replacement and keeps vouching for old lineage, this
    // pure test projection has no SDK signal with which to discover it.
    expect(projection.state.hasLiveLocation, isTrue);
  });

  test('route and ETA remain unavailable and absent from projected state', () {
    projection.authorizeForTesting(source);
    projection.acceptLocationForTesting(_event(sequence: 1));

    expect(projection.state.routeStatus, RiderLiveMapRouteStatus.unavailable);
    // Route and ETA are not fields on this projection contract.
    expect(projection.state.routeStatus, RiderLiveMapRouteStatus.unavailable);
  });
}

RiderLiveMapTestAuthorizationSnapshot _snapshot({
  String tripId = riderTripIdFixture,
  String bookingRequestId = riderBookingIdFixture,
  String riderId = riderIdFixture,
  Object? lineage,
  int generation = 1,
  int version = 3,
  bool granted = true,
  bool missingLineage = false,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
}) {
  return RiderLiveMapTestAuthorizationSnapshot(
    trip: riderAssignedTripFixture(
      tripId: tripId,
      bookingRequestId: bookingRequestId,
      riderId: riderId,
      version: version,
      status: status,
    ),
    sessionLineage: missingLineage ? null : lineage ?? _defaultLineage,
    sessionGeneration: generation,
    granted: granted,
  );
}

final Object _defaultLineage = Object();

RiderTripLocationChanged _event({
  required int sequence,
  double latitude = 31.95,
  String? eventTripId,
  DateTime? recordedAt,
}) {
  final tripId = eventTripId ?? riderTripIdFixture;
  return RiderTripLocationChanged(
    tripId: tripId,
    sample: _sample(
        sequence: sequence,
        latitude: latitude,
        tripId: tripId,
        recordedAt: recordedAt),
    receivedAt: recordedAt ?? DateTime.utc(2026, 11, 5, 12),
  );
}

DriverLocationSample _sample({
  required int sequence,
  String tripId = riderTripIdFixture,
  double latitude = 31.95,
  DateTime? recordedAt,
}) {
  return DriverLocationSample(
    point: LocationPoint(
      latitude: latitude,
      longitude: 35.91,
      accuracyMeters: 8,
    ),
    sequence: sequence,
    recordedAt: recordedAt ?? DateTime.utc(2026, 11, 5, 12),
    tripId: tripId,
  );
}

final class _MutableAuthorizationSource
    implements RiderLiveMapTestAuthorizationSource {
  _MutableAuthorizationSource(this.snapshot);

  RiderLiveMapTestAuthorizationSnapshot? snapshot;
  bool throwOnRead = false;

  @override
  RiderLiveMapTestAuthorizationSnapshot? read() {
    if (throwOnRead) throw StateError('test source unavailable');
    return snapshot;
  }
}
