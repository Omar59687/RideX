import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/rider_trip_tracking_providers.dart';
import 'package:ridex/core/providers/trip_realtime_providers.dart';
import 'package:ridex/features/trips/presentation/screens/canonical_rider_trip_screen.dart';
import 'helpers/fake_rider_trip_tracking_repository.dart';

class _Session extends SessionController {
  @override
  SessionState build() => SessionState.fromUser(const AppUser(
      id: riderIdFixture,
      name: 'Rider',
      email: 'rider@example.com',
      role: RideRole.rider));
}

class _Repository extends FakeRiderTripTrackingRepository {
  _Repository() : super(trip: riderAssignedTripFixture());
  Completer<RiderAssignedTrip?>? pending;
  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) {
    if (pending case final request?) {
      tripLoadCount++;
      requestedTripIds.add(tripId);
      return request.future;
    }
    return super.findByTrip(tripId: tripId);
  }
}

void main() {
  testWidgets(
      'stale Trip has guarded read-only recovery and displays only reread identity',
      (tester) async {
    final repository = _Repository();
    final container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(_Session.new),
      riderTripTrackingRepositoryProvider.overrideWithValue(repository),
      riderTripLocationAdapterProvider.overrideWithValue(null),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const CanonicalRiderTripScreen(
                tripId: riderTripIdFixture,
                bookingRequestId: riderBookingIdFixture))));
    await tester.pumpAndSettle();
    expect(find.text('Trip ID: $riderTripIdFixture'), findsOneWidget);
    repository.emitDisconnected();
    await tester.pumpAndSettle();
    expect(find.text('Trip ID: $riderTripIdFixture'), findsNothing);
    final read = Completer<RiderAssignedTrip?>();
    repository.pending = read;
    await tester.tap(find.text('Check Trip status'));
    await tester.pump();
    expect(find.text('Checking Trip status...'), findsOneWidget);
    await tester.tap(find.text('Checking Trip status...'));
    expect(repository.tripLoadCount, 2);
    expect(repository.watchCount, 1);
    read.complete(riderAssignedTripFixture());
    await tester.pumpAndSettle();
    expect(find.text('Trip state is canonically verified.'), findsOneWidget);
    expect(find.text('Trip ID: $riderTripIdFixture'), findsOneWidget);
    expect(repository.watchCount, 1);
    repository.pending = null;
    repository.tripLoadError = StateError('read failed');
    repository.emitDisconnected();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check Trip status'));
    await tester.pumpAndSettle();
    expect(find.text('Trip ID: $riderTripIdFixture'), findsNothing);
    expect(find.text('Check Trip status'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
