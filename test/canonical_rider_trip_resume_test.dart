import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_trip_location.dart';
import 'package:ridex/core/models/trip_realtime.dart';
import 'package:ridex/core/providers/rider_trip_tracking_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/trip_realtime_providers.dart';
import 'package:ridex/core/services/rider_trip_lifecycle_signals.dart';
import 'package:ridex/core/services/trips/rider_trip_location_adapter.dart';
import 'package:ridex/core/services/trips/rider_trip_location_source.dart';
import 'package:ridex/core/services/trips/trip_realtime_adapter.dart';
import 'package:ridex/core/services/trips/trip_realtime_source.dart';
import 'package:ridex/features/trips/presentation/screens/canonical_rider_trip_screen.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

void main() {
  testWidgets(
    'resume without a build while paused starts a fresh location watch',
    (tester) async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
        authenticatedRiderId: riderIdFixture,
      );
      final tripSource = _FakeTripSource(
        TripRealtimeTrip(
          tripId: riderTripIdFixture,
          riderId: riderIdFixture,
          driverId: riderDriverIdFixture,
          status: DriverTripLifecycleStatus.accepted,
          version: 3,
        ),
      );
      final locationSource = _FakeLocationSource();
      final adapter = RiderTripLocationAdapter(
        trips: TripRealtimeAdapter(tripSource),
        locations: locationSource,
      );
      final container = ProviderContainer(
        overrides: [
          riderTripTrackingRepositoryProvider.overrideWithValue(repository),
          riderTripLocationAdapterProvider.overrideWithValue(adapter),
          riderTripAppLifecycleSignalSourceProvider.overrideWithValue(
            const NoopRiderTripAppLifecycleSignalSource(),
          ),
          riderTripConnectionSignalSourceProvider.overrideWithValue(
            const NoopRiderTripConnectionSignalSource(),
          ),
          sessionControllerProvider.overrideWith(
            () => _WidgetSessionController(),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await tripSource.close();
        await locationSource.close();
        await repository.close();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CanonicalRiderTripScreen(
              tripId: riderTripIdFixture,
              bookingRequestId: riderBookingIdFixture,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trip state is canonically verified.'), findsOneWidget);
      expect(locationSource.watchCount, 1);

      // A backgrounded app can skip building the paused state, so no frame
      // separates these lifecycle callbacks. The old stream key survives and
      // is reused on resume unless the screen explicitly invalidates it.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var index = 0; index < 10; index++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pumpAndSettle();

      expect(locationSource.watchCount, 2);
      expect(locationSource.activeSubscriptions, greaterThanOrEqualTo(1));
      expect(find.text('Trip state is canonically verified.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _WidgetSessionController extends SessionController {
  _WidgetSessionController()
      : _initialState = SessionState.fromUser(
          const AppUser(
            id: riderIdFixture,
            name: 'Local Rider',
            email: 'rider@example.invalid',
            role: RideRole.rider,
          ),
        );

  final SessionState _initialState;

  @override
  SessionState build() => _initialState;
}

final class _FakeTripSource implements TripRealtimeSource {
  _FakeTripSource(this.trip);

  final TripRealtimeTrip trip;
  final _signals = StreamController<TripRealtimeSourceSignal>.broadcast();
  int watchCount = 0;

  @override
  String? get authenticatedUserId => riderIdFixture;

  @override
  Object? get authenticatedSessionIdentity => _session;

  final _session = Object();

  @override
  Stream<TripRealtimeSourceSignal> watchTrip(String tripId) {
    watchCount++;
    return _signals.stream;
  }

  @override
  Future<TripRealtimeTrip?> readCanonicalTrip(String tripId) async => trip;

  Future<void> close() => _signals.close();
}

final class _FakeLocationSource implements RiderTripLocationSource {
  final _signals = StreamController<RiderTripLocationSourceSignal>.broadcast();
  int watchCount = 0;
  int activeSubscriptions = 0;

  @override
  String? get authenticatedUserId => riderIdFixture;

  @override
  Object? get authenticatedSessionIdentity => _session;

  final _session = Object();

  @override
  Stream<RiderTripLocationSourceSignal> watchTripLocation(String tripId) =>
      Stream<RiderTripLocationSourceSignal>.multi((controller) {
        watchCount++;
        activeSubscriptions++;
        final inner = _signals.stream.listen(controller.add);
        controller.onCancel = () async {
          await inner.cancel();
          activeSubscriptions--;
        };
      });

  @override
  Future<RiderTripLocation?> readLatestTripLocation({
    required String tripId,
    required String driverId,
  }) async =>
      null;

  Future<void> close() => _signals.close();
}
