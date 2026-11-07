import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_live_map_marker.dart';
import 'package:ridex/core/models/rider_live_map_state.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';
import 'package:ridex/core/widgets/google_rider_live_map_renderer.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

const _testHarnessEnabled = bool.fromEnvironment('RIDEX_LIVE_MAP_TEST_MODE');

late DateTime _now;
late RiderLiveMapProjection _projection;
late _AuthorizationSource _source;
ValueChanged<RiderLiveMapCameraPort>? _onMapCreated;
RiderLiveMapMarkerData? _renderedMarker;

void main() {
  if (!_testHarnessEnabled) {
    test('marker projection remains unavailable without test opt-in', () {
      expect(
        RiderLiveMapMarkerData.project(const RiderLiveMapState.unavailable()),
        isNull,
      );
    });
    return;
  }

  setUp(() {
    _now = DateTime.utc(2026, 11, 5, 12);
    _projection = RiderLiveMapProjection.forTesting(clock: () => _now);
    _source = _AuthorizationSource(_snapshot());
    _onMapCreated = null;
    _renderedMarker = null;
  });

  test('no authorization produces no Driver marker', () {
    expect(
      RiderLiveMapMarkerData.project(const RiderLiveMapState.unavailable()),
      isNull,
    );
    expect(
      googleRiderDriverMarkers(const RiderLiveMapState.unavailable()),
      isEmpty,
    );
  });

  test('fresh authorized state projects exactly one live Driver marker', () {
    final state = _authorizedLocation();
    final projection = RiderLiveMapMarkerData.project(state)!;
    final markers = googleRiderDriverMarkers(state);

    expect(projection.freshness, RiderLiveMapMarkerFreshness.live);
    expect(projection.point.latitude, 31.95);
    expect(projection.point.longitude, 35.91);
    expect(projection.accessibleLabel, 'Live Driver location marker');
    expect(markers, hasLength(1));
    expect(markers.single.markerId, const MarkerId('ridex-authorized-driver'));
    expect(markers.single.position, const LatLng(31.95, 35.91));
    expect(markers.single.infoWindow.title, 'Live Driver location marker');
    expect(markers.single.icon.toJson(),
        ['defaultMarker', BitmapDescriptor.hueAzure]);
  });

  test('stale authorized location is last-known and gets a distinct marker',
      () {
    final state = _authorizedLocation();
    _now = _now.add(const Duration(seconds: 31));

    final projected = RiderLiveMapMarkerData.project(state)!;
    final markers = googleRiderDriverMarkers(state);

    expect(projected.freshness, RiderLiveMapMarkerFreshness.lastKnown);
    expect(projected.isLive, isFalse);
    expect(projected.accessibleLabel, 'Last known Driver location marker');
    expect(markers, hasLength(1));
    expect(
        markers.single.infoWindow.title, 'Last known Driver location marker');
    expect(markers.single.icon.toJson(),
        ['defaultMarker', BitmapDescriptor.hueOrange]);
  });

  test('offline marker remains last-known, not live', () {
    _authorizedLocation();
    final state = _projection.setOfflineForTesting(true);

    final projected = RiderLiveMapMarkerData.project(state)!;
    expect(projected.freshness, RiderLiveMapMarkerFreshness.lastKnown);
    expect(googleRiderDriverMarkers(state).single.infoWindow.title,
        'Last known Driver location marker');
  });

  test('revocation and session/Trip replacement remove marker projection', () {
    final previous = _authorizedLocation();
    expect(googleRiderDriverMarkers(previous), hasLength(1));

    _projection.revokeForTesting();
    expect(RiderLiveMapMarkerData.project(previous), isNull);
    expect(googleRiderDriverMarkers(previous), isEmpty);

    final next = _authorizedLocation();
    _source.snapshot = _snapshot(generation: 2);
    expect(RiderLiveMapMarkerData.project(next), isNull);
    expect(googleRiderDriverMarkers(next), isEmpty);
  });

  test('terminal and changed Trip state cannot yield a prior marker', () {
    final previous = _authorizedLocation();
    _projection.applyTripStatusForTesting(DriverTripLifecycleStatus.completed);
    expect(googleRiderDriverMarkers(previous), isEmpty);

    final otherProjection =
        RiderLiveMapProjection.forTesting(clock: () => _now);
    final otherSource = _AuthorizationSource(
      _snapshot(tripId: secondaryRiderTripIdFixture),
    );
    otherProjection.authorizeForTesting(otherSource);
    final otherState = otherProjection.acceptLocationForTesting(
      _locationEvent(tripId: secondaryRiderTripIdFixture),
    );
    expect(googleRiderDriverMarkers(otherState), hasLength(1));
    expect(googleRiderDriverMarkers(previous), isEmpty);
  });

  testWidgets('Google renderer fallback does not create a platform map',
      (tester) async {
    final state = _authorizedLocation();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: GoogleRiderLiveMapRenderer(
            state: state,
            configured: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('google-rider-map-unavailable')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('google-rider-live-map')), findsNothing);
    expect(find.text('Marker not plotted'), findsOneWidget);
    expect(find.textContaining('not geographically plotted'), findsOneWidget);
  });

  testWidgets('authorized A to B update moves camera once and deduplicates',
      (tester) async {
    final stateA = _authorizedLocation();
    await tester.pumpWidget(_rendererApp(stateA));
    final camera = _FakeCameraPort();
    _onMapCreated!(camera);

    expect(_renderedMarker!.point.latitude, 31.95);
    expect(camera.targets, isEmpty); // Initial camera already targets A.

    final stateB = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 2, latitude: 32.01),
    );
    await tester.pumpWidget(_rendererApp(stateB));
    await tester.pump();
    expect(camera.targets.map((point) => point.latitude), [32.01]);

    final samePosition = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 3, latitude: 32.01),
    );
    await tester.pumpWidget(_rendererApp(samePosition));
    await tester.pump();
    expect(camera.targets.map((point) => point.latitude), [32.01]);
  });

  testWidgets('updates while camera is not ready coalesce to latest target',
      (tester) async {
    await tester.pumpWidget(_rendererApp(_authorizedLocation()));
    final firstReadyCallback = _onMapCreated!;
    final stateB = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 2, latitude: 32.0),
    );
    await tester.pumpWidget(_rendererApp(stateB));
    final delayedReadyCallback = _onMapCreated!;

    final stateC = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 3, latitude: 32.1),
    );
    await tester.pumpWidget(_rendererApp(stateC));

    final camera = _FakeCameraPort();
    delayedReadyCallback(camera);
    await tester.pump();
    expect(camera.targets.map((point) => point.latitude), [32.1]);
    // A callback from the first build sees the active state/surface and must
    // not queue another move after the latest point has already been applied.
    firstReadyCallback(camera);
    await tester.pump();
    expect(camera.targets.map((point) => point.latitude), [32.1]);
  });

  testWidgets('surface replacement rejects old ready callbacks and controllers',
      (tester) async {
    late ValueChanged<RiderLiveMapCameraPort> readyA;
    late ValueChanged<RiderLiveMapCameraPort> readyB;
    Widget surfaceA(
      BuildContext context, {
      required RiderLiveMapMarkerData marker,
      required ValueChanged<RiderLiveMapCameraPort> onMapCreated,
    }) {
      readyA = onMapCreated;
      return _namedSurface('surface-a', marker);
    }

    Widget surfaceB(
      BuildContext context, {
      required RiderLiveMapMarkerData marker,
      required ValueChanged<RiderLiveMapCameraPort> onMapCreated,
    }) {
      readyB = onMapCreated;
      return _namedSurface('surface-b', marker);
    }

    await tester.pumpWidget(_rendererApp(
      _authorizedLocation(),
      surfaceBuilder: surfaceA,
    ));
    final obsoleteReady = readyA;
    final stateB = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 2, latitude: 32.5),
    );
    await tester.pumpWidget(_rendererApp(stateB, surfaceBuilder: surfaceB));

    final cameraB = _FakeCameraPort();
    readyB(cameraB);
    await tester.pump();
    final obsoleteCamera = _FakeCameraPort();
    obsoleteReady(obsoleteCamera);
    // A duplicate callback in the active generation with a different port is
    // ignored; the active controller remains B.
    readyB(obsoleteCamera);
    await tester.pump();

    final stateC = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 3, latitude: 32.6),
    );
    await tester.pumpWidget(_rendererApp(stateC, surfaceBuilder: surfaceB));
    await tester.pump();

    expect(_renderedMarker?.point.latitude, 32.6);
    expect(cameraB.targets.map((point) => point.latitude), [32.6]);
    expect(obsoleteCamera.targets, isEmpty);
  });

  testWidgets('surface replacement invalidates queued older camera targets',
      (tester) async {
    late ValueChanged<RiderLiveMapCameraPort> readyA;
    late ValueChanged<RiderLiveMapCameraPort> readyB;
    Widget surfaceA(
      BuildContext context, {
      required RiderLiveMapMarkerData marker,
      required ValueChanged<RiderLiveMapCameraPort> onMapCreated,
    }) {
      readyA = onMapCreated;
      return _namedSurface('queued-surface-a', marker);
    }

    Widget surfaceB(
      BuildContext context, {
      required RiderLiveMapMarkerData marker,
      required ValueChanged<RiderLiveMapCameraPort> onMapCreated,
    }) {
      readyB = onMapCreated;
      return _namedSurface('queued-surface-b', marker);
    }

    await tester.pumpWidget(_rendererApp(
      _authorizedLocation(),
      surfaceBuilder: surfaceA,
    ));
    final cameraA = _FakeCameraPort()..gate = Completer<void>();
    readyA(cameraA);

    final stateB = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 2, latitude: 32.7),
    );
    await tester.pumpWidget(_rendererApp(stateB, surfaceBuilder: surfaceA));
    await tester.pump();
    expect(cameraA.targets.map((point) => point.latitude), [32.7]);

    final stateC = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 3, latitude: 32.8),
    );
    await tester.pumpWidget(_rendererApp(stateC, surfaceBuilder: surfaceA));

    // Replacing the surface discards the pending C target from controller A.
    await tester.pumpWidget(_rendererApp(stateC, surfaceBuilder: surfaceB));
    final cameraB = _FakeCameraPort();
    readyB(cameraB);
    await tester.pump();

    cameraA.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(cameraA.targets.map((point) => point.latitude), [32.7]);

    final stateD = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 4, latitude: 32.9),
    );
    await tester.pumpWidget(_rendererApp(stateD, surfaceBuilder: surfaceB));
    await tester.pump();
    expect(cameraB.targets.map((point) => point.latitude), [32.9]);
  });

  testWidgets('Trip replacement camera command uses only the new Trip point',
      (tester) async {
    await tester.pumpWidget(_rendererApp(_authorizedLocation()));
    final lateReady = _onMapCreated!;

    _source.snapshot = _snapshot(
      tripId: secondaryRiderTripIdFixture,
      bookingRequestId: secondaryRiderBookingIdFixture,
    );
    _projection.authorizeForTesting(_source);
    final nextTrip = _projection.acceptLocationForTesting(
      _locationEvent(tripId: secondaryRiderTripIdFixture, latitude: 32.2),
    );
    await tester.pumpWidget(_rendererApp(nextTrip));

    final camera = _FakeCameraPort();
    // A map-ready callback from the first build must use the current marker,
    // never the old Trip's copied position.
    lateReady(camera);
    await tester.pump();
    expect(camera.targets.map((point) => point.latitude), [32.2]);
  });

  testWidgets('revocation before camera readiness prevents late movement',
      (tester) async {
    final state = _authorizedLocation();
    await tester.pumpWidget(_rendererApp(state));
    final lateReady = _onMapCreated!;

    _projection.revokeForTesting();
    await tester.pumpWidget(_rendererApp(state));
    final camera = _FakeCameraPort();
    lateReady(camera);
    await tester.pump();

    expect(camera.targets, isEmpty);
    expect(find.byKey(const ValueKey('google-rider-map-unavailable')),
        findsOneWidget);
  });

  testWidgets('queued camera movement is invalidated by revocation',
      (tester) async {
    await tester.pumpWidget(_rendererApp(_authorizedLocation()));
    final camera = _FakeCameraPort()..gate = Completer<void>();
    _onMapCreated!(camera);

    final stateB = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 2, latitude: 32.3),
    );
    await tester.pumpWidget(_rendererApp(stateB));
    await tester.pump();
    expect(camera.targets.map((point) => point.latitude), [32.3]);

    final stateC = _projection.acceptLocationForTesting(
      _locationEvent(sequence: 3, latitude: 32.4),
    );
    await tester.pumpWidget(_rendererApp(stateC));
    _projection.revokeForTesting();
    await tester.pumpWidget(_rendererApp(stateC));

    camera.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(camera.targets.map((point) => point.latitude), [32.3]);
  });

  testWidgets('disposal ignores a late camera-ready callback', (tester) async {
    await tester.pumpWidget(_rendererApp(_authorizedLocation()));
    final lateReady = _onMapCreated!;
    await tester.pumpWidget(const SizedBox.shrink());

    final camera = _FakeCameraPort();
    lateReady(camera);
    await tester.pump();
    expect(camera.targets, isEmpty);
  });

  test('unavailable and terminal state cannot create a Google marker', () {
    final state = _authorizedLocation();
    _projection.revokeForTesting();
    expect(googleRiderDriverMarkers(state), isEmpty);
    expect(googleRiderDriverMarkers(const RiderLiveMapState.unavailable()),
        isEmpty);
  });
}

Widget _rendererApp(
  RiderLiveMapState state, {
  GoogleRiderLiveMapSurfaceBuilder? surfaceBuilder,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: GoogleRiderLiveMapRenderer(
        state: state,
        configured: true,
        surfaceBuilder: surfaceBuilder ?? _fakeMapSurface,
      ),
    ),
  );
}

Widget _namedSurface(String key, RiderLiveMapMarkerData marker) {
  _renderedMarker = marker;
  return ColoredBox(
    key: ValueKey(key),
    color: Colors.blueGrey,
    child: Text(marker.accessibleLabel),
  );
}

Widget _fakeMapSurface(
  BuildContext context, {
  required RiderLiveMapMarkerData marker,
  required ValueChanged<RiderLiveMapCameraPort> onMapCreated,
}) {
  _renderedMarker = marker;
  _onMapCreated = onMapCreated;
  return ColoredBox(
    key: const ValueKey('fake-google-map-surface'),
    color: Colors.blueGrey,
    child: Text(marker.accessibleLabel),
  );
}

RiderLiveMapState _authorizedLocation() {
  _projection.authorizeForTesting(_source);
  return _projection.acceptLocationForTesting(_locationEvent());
}

RiderLiveMapTestAuthorizationSnapshot _snapshot({
  String tripId = riderTripIdFixture,
  String bookingRequestId = riderBookingIdFixture,
  String riderId = riderIdFixture,
  int generation = 1,
}) {
  return RiderLiveMapTestAuthorizationSnapshot(
    trip: riderAssignedTripFixture(
      tripId: tripId,
      bookingRequestId: bookingRequestId,
      riderId: riderId,
    ),
    sessionLineage: _lineage,
    sessionGeneration: generation,
    granted: true,
  );
}

RiderTripLocationChanged _locationEvent({
  String tripId = riderTripIdFixture,
  int sequence = 1,
  double latitude = 31.95,
}) {
  return RiderTripLocationChanged(
    tripId: tripId,
    sample: DriverLocationSample(
      point: LocationPoint(
        latitude: latitude,
        longitude: 35.91,
        accuracyMeters: 8,
      ),
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 11, 5, 12),
      tripId: tripId,
    ),
    receivedAt: DateTime.utc(2026, 11, 5, 12),
  );
}

final Object _lineage = Object();

final class _AuthorizationSource
    implements RiderLiveMapTestAuthorizationSource {
  _AuthorizationSource(this.snapshot);

  RiderLiveMapTestAuthorizationSnapshot? snapshot;

  @override
  RiderLiveMapTestAuthorizationSnapshot? read() => snapshot;
}

final class _FakeCameraPort implements RiderLiveMapCameraPort {
  final List<LocationPoint> targets = [];
  Completer<void>? gate;

  @override
  Future<void> moveTo(LocationPoint point) {
    targets.add(point);
    return gate?.future ?? Future<void>.value();
  }
}
