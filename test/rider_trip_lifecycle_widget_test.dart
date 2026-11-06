import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_lifecycle_state.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';
import 'package:ridex/core/providers/rider_trip_tracking_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

void main() {
  testWidgets(
    'pause/resume hides verified Trip until one canonical read succeeds',
    (tester) async {
      final initial = riderAssignedTripFixture();
      final resumed = riderAssignedTripFixture(
        version: 4,
        status: DriverTripLifecycleStatus.driverArriving,
      );
      final repository = _DelayedResumeRepository(trip: initial);
      final request = RiderTripLifecycleRequest(
        tripId: riderTripIdFixture,
        bookingRequestId: riderBookingIdFixture,
      );
      final container = ProviderContainer(
        overrides: [
          riderTripTrackingRepositoryProvider.overrideWithValue(repository),
          sessionControllerProvider.overrideWith(
            () => _WidgetSessionController(),
          ),
        ],
      );
      final subscription = container.listen(
        riderTripLifecycleControllerProvider(request),
        (_, __) {},
      );
      var resumeSignals = 0;
      final lifecycleSubscription = container
          .read(riderTripAppLifecycleSignalSourceProvider)
          .resumed
          .listen((_) => resumeSignals++);
      addTearDown(() async {
        await lifecycleSubscription.cancel();
        subscription.close();
        container.dispose();
        await _settle();
        await repository.close();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: _LifecycleProbe(request: request)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Trip accepted'), findsOneWidget);
      expect(repository.tripLoadCount, 1);

      // A resumed notification with no observed non-resumed transition is not
      // sufficient evidence for a foreground return.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(resumeSignals, 0);
      expect(repository.tripLoadCount, 1);

      final resumedRead = Completer<RiderAssignedTrip?>();
      repository.nextRead = resumedRead;
      repository.trip = resumed;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var index = 0; index < 10; index++) {
        await tester.pump(const Duration(milliseconds: 1));
      }

      expect(resumeSignals, 1);
      expect(
        container.read(riderTripLifecycleControllerProvider(request)).phase,
        RiderTripLifecyclePhase.stale,
      );
      expect(repository.tripLoadCount, 2);
      expect(find.text('Trip hidden'), findsOneWidget);
      expect(
        container.read(riderTripLifecycleControllerProvider(request)).trip,
        isNull,
      );

      // A repeated resumed notification without an intervening background
      // transition is not another reconciliation signal.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(repository.tripLoadCount, 2);
      expect(find.text('Trip hidden'), findsOneWidget);

      resumedRead.complete(resumed);
      await tester.pumpAndSettle();
      expect(find.text('Trip driverArriving'), findsOneWidget);
      expect(
        container.read(riderTripLifecycleControllerProvider(request)).trip,
        resumed,
      );
      expect(repository.tripLoadCount, 2);
    },
  );
}

class _LifecycleProbe extends ConsumerWidget {
  const _LifecycleProbe({required this.request});

  final RiderTripLifecycleRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(riderTripLifecycleControllerProvider(request)).trip;
    return Scaffold(
      body: Center(
        child: Text(trip == null ? 'Trip hidden' : 'Trip ${trip.status.name}'),
      ),
    );
  }
}

class _WidgetSessionController extends SessionController {
  @override
  SessionState build() => SessionState.fromUser(
        const AppUser(
          id: riderIdFixture,
          name: 'Local Rider',
          email: 'rider@example.invalid',
          role: RideRole.rider,
        ),
      );
}

class _DelayedResumeRepository extends FakeRiderTripTrackingRepository {
  _DelayedResumeRepository({required super.trip});

  Completer<RiderAssignedTrip?>? nextRead;

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) {
    final pending = nextRead;
    if (pending == null) return super.findByTrip(tripId: tripId);
    nextRead = null;
    tripLoadCount++;
    requestedTripIds.add(tripId);
    return pending.future;
  }

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) {
    watchCount++;
    watchedTripIds.add(tripId);
    return _ImmediateCancelStream<RiderTripTrackingEvent>();
  }
}

class _ImmediateCancelStream<T> extends Stream<T> {
  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _ImmediateCancelSubscription<T>();
}

class _ImmediateCancelSubscription<T> implements StreamSubscription<T> {
  bool _paused = false;

  @override
  Future<void> cancel() async {}

  @override
  void onData(void Function(T data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {
    _paused = true;
    resumeSignal?.whenComplete(resume);
  }

  @override
  void resume() => _paused = false;

  @override
  bool get isPaused => _paused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;
}

Future<void> _settle() async {
  for (var index = 0; index < 6; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
