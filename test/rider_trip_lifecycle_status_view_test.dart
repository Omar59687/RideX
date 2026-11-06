import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_lifecycle_state.dart';
import 'package:ridex/features/trips/presentation/widgets/rider_trip_lifecycle_status_view.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

const _sentinelRiderId = '99999999-9999-4999-8999-999999999999';
const _sentinelDriverId = '88888888-8888-4888-8888-888888888888';
const _sentinelDriverName = 'SENTINEL_DRIVER_NAME';
const _sentinelPickup = 'SENTINEL_PICKUP_PLACE';
const _sentinelDestination = 'SENTINEL_DESTINATION_PLACE';
const _sentinelLatitude = 89.123456;
const _sentinelLongitude = 179.654321;
const _sentinelOriginalFareFils = 987654321;
const _sentinelCurrentFareFils = 876543210;

final _verifiedAt = DateTime.utc(2026, 11, 6, 12);

void main() {
  group('RiderTripLifecycleStatusView', () {
    testWidgets('loading shows its generic status message', (tester) async {
      await _pumpState(tester, const RiderTripLifecycleState.loading());

      expect(find.text('Checking trip status'), findsOneWidget);
      _expectSensitiveValuesHidden(tester);
    });

    testWidgets('verified states display only their canonical status', (
      tester,
    ) async {
      const statuses = <DriverTripLifecycleStatus, String>{
        DriverTripLifecycleStatus.accepted: 'Trip accepted',
        DriverTripLifecycleStatus.driverArriving: 'Driver arriving',
        DriverTripLifecycleStatus.driverArrived: 'Driver arrived',
        DriverTripLifecycleStatus.inProgress: 'Trip in progress',
      };

      for (final entry in statuses.entries) {
        await _pumpState(tester, _stateFor(entry.key));

        expect(find.text(entry.value), findsOneWidget);
        _expectSensitiveValuesHidden(tester);
      }
    });

    testWidgets('stale and unavailable states show generic copy', (
      tester,
    ) async {
      await _pumpState(
        tester,
        const RiderTripLifecycleState.stale(
          failure: RiderTripLifecycleFailure.disconnected,
        ),
      );
      expect(find.text('Verifying current trip status'), findsOneWidget);
      expect(find.text('Trip accepted'), findsNothing);
      _expectSensitiveValuesHidden(tester);

      await _pumpState(
        tester,
        const RiderTripLifecycleState.unavailable(
          failure: RiderTripLifecycleFailure.readFailed,
        ),
      );
      expect(find.text('Trip status unavailable'), findsOneWidget);
      expect(find.text('readFailed'), findsNothing);
      _expectSensitiveValuesHidden(tester);
    });

    testWidgets('stale state hides prior status and recovers from fresh state',
        (
      tester,
    ) async {
      final accepted = _stateFor(DriverTripLifecycleStatus.accepted);
      await _pumpState(tester, accepted);
      expect(find.text('Trip accepted'), findsOneWidget);

      await _pumpState(
        tester,
        accepted.markStale(RiderTripLifecycleFailure.disconnected),
      );
      expect(find.text('Verifying current trip status'), findsOneWidget);
      expect(find.text('Trip accepted'), findsNothing);
      _expectSensitiveValuesHidden(tester);

      await _pumpState(tester, _stateFor(DriverTripLifecycleStatus.inProgress));
      expect(find.text('Trip in progress'), findsOneWidget);
      expect(find.text('Trip accepted'), findsNothing);
      _expectSensitiveValuesHidden(tester);
    });

    testWidgets('completed is not presented as payment or receipt success', (
      tester,
    ) async {
      await _pumpState(tester, _stateFor(DriverTripLifecycleStatus.completed));

      expect(find.text('Trip completed'), findsOneWidget);
      expect(
        find.text(
          'Trip completion does not confirm payment or receipt.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('paid'), findsNothing);
      expect(find.textContaining('settled'), findsNothing);
      expect(find.textContaining('receipt issued'), findsNothing);
      _expectSensitiveValuesHidden(tester);
    });

    testWidgets('cancellation sources retain their canonical distinction', (
      tester,
    ) async {
      const cancelledStatuses = <DriverTripLifecycleStatus, String>{
        DriverTripLifecycleStatus.cancelledByRider: 'Trip cancelled by rider',
        DriverTripLifecycleStatus.cancelledByDriver: 'Trip cancelled by driver',
        DriverTripLifecycleStatus.cancelledByAdmin: 'Trip cancelled by admin',
      };

      for (final entry in cancelledStatuses.entries) {
        await _pumpState(tester, _stateFor(entry.key));

        expect(find.text(entry.value), findsOneWidget);
        expect(find.text('Trip failed'), findsNothing);
        _expectSensitiveValuesHidden(tester);
      }
    });

    testWidgets('failed is distinct from cancellation', (tester) async {
      await _pumpState(tester, _stateFor(DriverTripLifecycleStatus.failed));

      expect(find.text('Trip failed'), findsOneWidget);
      expect(find.textContaining('cancelled'), findsNothing);
      _expectSensitiveValuesHidden(tester);
    });

    testWidgets('verified and terminal states without a Trip fail closed', (
      tester,
    ) async {
      await _pumpState(tester, _MissingTripLifecycleState.verified());
      expect(find.text('Trip status unavailable'), findsOneWidget);

      await _pumpState(tester, _MissingTripLifecycleState.terminal());
      expect(find.text('Trip status unavailable'), findsOneWidget);
      _expectSensitiveValuesHidden(tester);
    });

    testWidgets('exposes one live-region announcement per status', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpState(tester, _stateFor(DriverTripLifecycleStatus.accepted));

        final labelFinder = find.bySemanticsLabel('Trip accepted');
        expect(labelFinder, findsOneWidget);
        final data = tester.getSemantics(labelFinder).getSemanticsData();
        expect(data.label, 'Trip accepted');
        expect(data.flagsCollection.isLiveRegion, isTrue);
        expect(find.text('Trip accepted'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('wraps long copy at increased text scale on narrow width', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(280, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpState(
        tester,
        _stateFor(DriverTripLifecycleStatus.completed),
        textScaler: const TextScaler.linear(2),
      );

      expect(find.text('Trip completed'), findsOneWidget);
      expect(
        find.text('Trip completion does not confirm payment or receipt.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

RiderTripLifecycleState _stateFor(DriverTripLifecycleStatus status) {
  final trip = _trip(status);
  if (trip.isTerminal) {
    return RiderTripLifecycleState.terminal(
      trip: trip,
      verifiedAt: _verifiedAt,
    );
  }
  return RiderTripLifecycleState.verified(
    trip: trip,
    verifiedAt: _verifiedAt,
  );
}

RiderAssignedTrip _trip(DriverTripLifecycleStatus status) {
  return riderAssignedTripFixture(
    riderId: _sentinelRiderId,
    driverId: _sentinelDriverId,
    driverDisplayName: _sentinelDriverName,
    status: status,
    pickup: RiderTripPlace(
      point: LocationPoint(
        latitude: _sentinelLatitude,
        longitude: _sentinelLongitude,
      ),
      label: _sentinelPickup,
    ),
    destination: RiderTripPlace(
      point: LocationPoint(
        latitude: -_sentinelLatitude,
        longitude: -_sentinelLongitude,
      ),
      label: _sentinelDestination,
    ),
    originalFareFils: _sentinelOriginalFareFils,
    currentFareFils: _sentinelCurrentFareFils,
  );
}

Future<void> _pumpState(
  WidgetTester tester,
  RiderTripLifecycleState state, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RiderTripLifecycleStatusView(state: state),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectSensitiveValuesHidden(WidgetTester tester) {
  for (final value in [
    _sentinelRiderId,
    _sentinelDriverId,
    _sentinelDriverName,
    _sentinelPickup,
    _sentinelDestination,
    '$_sentinelLatitude',
    '$_sentinelLongitude',
    '$_sentinelOriginalFareFils',
    '$_sentinelCurrentFareFils',
  ]) {
    expect(find.textContaining(value), findsNothing, reason: value);
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(value))),
      findsNothing,
      reason: value,
    );
  }
}

class _MissingTripLifecycleState implements RiderTripLifecycleState {
  _MissingTripLifecycleState.verified()
      : phase = RiderTripLifecyclePhase.verified;

  _MissingTripLifecycleState.terminal()
      : phase = RiderTripLifecyclePhase.terminal;

  @override
  final RiderTripLifecyclePhase phase;

  @override
  RiderAssignedTrip? get trip => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
