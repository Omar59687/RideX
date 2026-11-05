import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_live_map_state.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';
import 'package:ridex/features/trips/presentation/screens/rider_live_map_screen.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

const _testHarnessEnabled = bool.fromEnvironment('RIDEX_LIVE_MAP_TEST_MODE');

late DateTime now;
late RiderLiveMapProjection _projectionUnderTest;
late _MutableAuthorizationSource _authorizationUnderTest;
late ChangeNotifier _stateInvalidations;

void main() {
  if (!_testHarnessEnabled) {
    testWidgets('screen safely renders without production authorization',
        (tester) async {
      final invalidations = ChangeNotifier();
      addTearDown(invalidations.dispose);
      await tester.pumpWidget(_app(
        const RiderLiveMapState.unavailable(),
        mapConfigured: true,
        rendererBuilder: _fakeRenderer,
        stateInvalidations: invalidations,
      ));

      expect(find.byKey(const ValueKey('fake-map-renderer')), findsNothing);
      expect(find.byKey(const ValueKey('fake-driver-marker')), findsNothing);
      expect(
          find.textContaining('authorization is unavailable'), findsOneWidget);
    });
    return;
  }

  setUp(() {
    now = DateTime.utc(2026, 11, 5, 12);
    _projectionUnderTest = RiderLiveMapProjection.forTesting(clock: () => now);
    _authorizationUnderTest = _MutableAuthorizationSource(_snapshot());
    _stateInvalidations = ChangeNotifier();
    addTearDown(_stateInvalidations.dispose);
  });

  testWidgets('no authorization never invokes renderer or shows marker',
      (tester) async {
    await tester.pumpWidget(_app(
      const RiderLiveMapState.unavailable(),
      mapConfigured: true,
      rendererBuilder: _fakeRenderer,
    ));

    expect(find.byKey(const ValueKey('fake-map-renderer')), findsNothing);
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsNothing);
    expect(find.textContaining('Trip authorization is unavailable'),
        findsOneWidget);
  });

  testWidgets('fresh authorized state renders marker through fake renderer',
      (tester) async {
    final state = _authorizedFix();
    var rendererBuilds = 0;

    await tester.pumpWidget(_app(
      state,
      mapConfigured: true,
      rendererBuilder: (context, mapState) {
        rendererBuilds++;
        return _fakeRenderer(context, mapState);
      },
    ));

    expect(rendererBuilds, 1);
    expect(find.byKey(const ValueKey('fake-map-renderer')), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsOneWidget);
    expect(find.text('Driver location is live.'), findsOneWidget);
    expect(find.textContaining('31.95'), findsNothing);
  });

  testWidgets('stale location is marked stale and never labeled live',
      (tester) async {
    final state = _authorizedFix();
    now = now.add(const Duration(seconds: 31));

    await tester.pumpWidget(_app(
      state,
      mapConfigured: true,
      rendererBuilder: _fakeRenderer,
    ));

    expect(find.byKey(const ValueKey('fake-driver-marker')), findsOneWidget);
    expect(find.textContaining('location is stale'), findsOneWidget);
    expect(find.text('Driver location is live.'), findsNothing);
  });

  testWidgets('GPS unavailable before first fix is explicit', (tester) async {
    _projectionUnderTest.authorizeForTesting(_authorizationUnderTest);
    final state = _projectionUnderTest.markGpsUnavailableForTesting();

    await tester.pumpWidget(_app(
      state,
      mapConfigured: true,
      rendererBuilder: _fakeRenderer,
    ));

    expect(find.textContaining('Driver GPS is unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsNothing);
  });

  testWidgets('offline state is explicit and not labeled live', (tester) async {
    _authorizedFix();
    _projectionUnderTest.authorizeForTesting(_authorizationUnderTest);
    _projectionUnderTest.acceptLocationForTesting(_event(sequence: 1));
    final state = _projectionUnderTest.setOfflineForTesting(true);

    await tester.pumpWidget(_app(
      state,
      mapConfigured: true,
      rendererBuilder: _fakeRenderer,
    ));

    expect(find.byKey(const ValueKey('fake-driver-marker')), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.textContaining('location is stale'), findsOneWidget);
    expect(find.text('Driver location is live.'), findsNothing);
  });

  testWidgets('revocation notification removes marker without parent rebuild',
      (tester) async {
    final state = _authorizedFix();
    var rendererBuilds = 0;
    Widget renderer(BuildContext context, RiderLiveMapState mapState) {
      rendererBuilds++;
      return _fakeRenderer(context, mapState);
    }

    await tester.pumpWidget(_app(
      state,
      mapConfigured: true,
      rendererBuilder: renderer,
    ));
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsOneWidget);

    _projectionUnderTest.revokeForTesting();
    _stateInvalidations.notifyListeners();
    await tester.pump();

    expect(rendererBuilds, 1);
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsNothing);
    expect(find.textContaining('authorization is unavailable'), findsOneWidget);
  });

  testWidgets('session and Trip changes invalidate previously rendered marker',
      (tester) async {
    final state = _authorizedFix();

    await tester.pumpWidget(_app(
      state,
      mapConfigured: true,
      rendererBuilder: _fakeRenderer,
    ));
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsOneWidget);

    _authorizationUnderTest.snapshot = _snapshot(generation: 2);
    _stateInvalidations.notifyListeners();
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsNothing);

    final nextTripProjection = RiderLiveMapProjection.forTesting(
      clock: () => now,
    );
    final nextSource = _MutableAuthorizationSource(
      _snapshot(tripId: secondaryRiderTripIdFixture),
    );
    nextTripProjection.authorizeForTesting(nextSource);
    final nextState = nextTripProjection.acceptLocationForTesting(
      _event(sequence: 1, tripId: secondaryRiderTripIdFixture),
    );
    await tester.pumpWidget(_app(
      nextState,
      mapConfigured: true,
      rendererBuilder: _fakeRenderer,
    ));
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsOneWidget);
  });

  testWidgets('Trip switch notification removes retained previous marker',
      (tester) async {
    final oldState = _authorizedFix();
    await tester.pumpWidget(_app(
      oldState,
      mapConfigured: true,
      rendererBuilder: _fakeRenderer,
    ));
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsOneWidget);

    _authorizationUnderTest.snapshot = _snapshot(
      tripId: secondaryRiderTripIdFixture,
      bookingRequestId: secondaryRiderBookingIdFixture,
    );
    _stateInvalidations.notifyListeners();
    await tester.pump();

    expect(find.byKey(const ValueKey('fake-driver-marker')), findsNothing);
  });

  testWidgets('freshness timer removes live status without parent rebuild',
      (tester) async {
    final state = _authorizedFix();
    await tester.pumpWidget(_app(
      state,
      mapConfigured: true,
      rendererBuilder: _fakeRenderer,
    ));
    expect(find.text('Driver location is live.'), findsOneWidget);

    now = now.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 31));

    expect(find.textContaining('location is stale'), findsOneWidget);
    expect(find.text('Driver location is live.'), findsNothing);
  });

  testWidgets('disposal cancels invalidation listener and expiry timer',
      (tester) async {
    final state = _authorizedFix();
    await tester.pumpWidget(_app(
      state,
      mapConfigured: true,
      rendererBuilder: _fakeRenderer,
    ));
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    _projectionUnderTest.revokeForTesting();
    _stateInvalidations.notifyListeners();
    now = now.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 31));

    expect(tester.takeException(), isNull);
  });

  testWidgets('route remains unavailable with no synthetic polyline or ETA',
      (tester) async {
    final state = _authorizedFix();
    await tester.pumpWidget(_app(
      state,
      mapConfigured: true,
      rendererBuilder: _fakeRenderer,
    ));

    expect(find.text('Route unavailable'), findsOneWidget);
    expect(find.textContaining('Route geometry and ETA are not available'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('fake-route-polyline')), findsNothing);
    expect(find.textContaining(RegExp(r'\d+\s*(min|minutes)')), findsNothing);
  });

  testWidgets('unconfigured map renders accessible non-geographic fallback',
      (tester) async {
    final state = _authorizedFix();
    var rendererBuilds = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_app(
      state,
      mapConfigured: false,
      rendererBuilder: (context, mapState) {
        rendererBuilds++;
        return _fakeRenderer(context, mapState);
      },
    ));

    expect(rendererBuilds, 0);
    expect(find.byKey(const ValueKey('rider-live-map-fallback-marker')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('not geographically plotted')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('fake-driver-marker')), findsNothing);
    semantics.dispose();
  });
}

Widget _app(
  RiderLiveMapState state, {
  required bool mapConfigured,
  Listenable? stateInvalidations,
  RiderLiveMapRendererBuilder? rendererBuilder,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: RiderLiveMapScreen(
      state: state,
      stateInvalidations: stateInvalidations ?? _stateInvalidations,
      mapConfigured: mapConfigured,
      rendererBuilder: rendererBuilder,
      clock: () => now,
      freshnessWindow: const Duration(seconds: 30),
    ),
  );
}

Widget _fakeRenderer(BuildContext context, RiderLiveMapState state) {
  final hasMarker = state.driverLocation != null &&
      state.authorizationStatus == RiderLiveMapAuthorizationStatus.authorized;
  return ColoredBox(
    key: const ValueKey('fake-map-renderer'),
    color: Colors.blueGrey,
    child: Center(
      child: hasMarker
          ? Semantics(
              label: 'Driver marker',
              image: true,
              child: Icon(
                Icons.directions_car_filled_rounded,
                key: ValueKey('fake-driver-marker'),
                color: Colors.white,
              ),
            )
          : const Text('No Driver marker'),
    ),
  );
}

RiderLiveMapState _authorizedFix() {
  _projectionUnderTest.authorizeForTesting(_authorizationUnderTest);
  return _projectionUnderTest.acceptLocationForTesting(_event(sequence: 1));
}

RiderLiveMapTestAuthorizationSnapshot _snapshot({
  String tripId = riderTripIdFixture,
  String bookingRequestId = riderBookingIdFixture,
  String riderId = riderIdFixture,
  Object? lineage,
  int generation = 1,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
}) {
  return RiderLiveMapTestAuthorizationSnapshot(
    trip: riderAssignedTripFixture(
      tripId: tripId,
      bookingRequestId: bookingRequestId,
      riderId: riderId,
      status: status,
    ),
    sessionLineage: lineage ?? _defaultLineage,
    sessionGeneration: generation,
    granted: true,
  );
}

final Object _defaultLineage = Object();

RiderTripLocationChanged _event({
  required int sequence,
  String tripId = riderTripIdFixture,
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

final class _MutableAuthorizationSource
    implements RiderLiveMapTestAuthorizationSource {
  _MutableAuthorizationSource(this.snapshot);

  RiderLiveMapTestAuthorizationSnapshot? snapshot;

  @override
  RiderLiveMapTestAuthorizationSnapshot? read() => snapshot;
}
