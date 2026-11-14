import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_trip_location.dart';
import 'package:ridex/core/models/trip_realtime.dart';
import 'package:ridex/core/services/trips/rider_trip_location_adapter.dart';
import 'package:ridex/core/services/trips/rider_trip_location_source.dart';
import 'package:ridex/core/services/trips/supabase_rider_trip_location_source.dart';
import 'package:ridex/core/services/trips/trip_realtime_adapter.dart';
import 'package:ridex/core/services/trips/trip_realtime_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _tripId = '11111111-1111-4111-8111-111111111111';
const _riderId = '22222222-2222-4222-8222-222222222222';
const _driverId = '33333333-3333-4333-8333-333333333333';
const _otherDriverId = '44444444-4444-4444-8444-444444444444';
const _foreignTripId = '55555555-5555-4555-8555-555555555555';

void main() {
  final now = DateTime.utc(2026, 11, 4, 12);
  late FakeTripRealtimeSource tripSource;
  late FakeRiderTripLocationSource locationSource;
  late TripRealtimeAdapter tripAdapter;
  late RiderTripLocationAdapter adapter;
  late List<RiderTripLocationUpdate> updates;
  late List<Object> errors;
  late Completer<void> streamDone;
  late List<
      ({
        bool Function(RiderTripLocationUpdate) matches,
        Completer<void> completed,
      })> updateWaiters;
  late StreamSubscription<RiderTripLocationUpdate> subscription;

  testWidgets(
      'polling reads canonical movement without subscribed channels and stops on session replacement',
      (tester) async {
    subscription = adapter
        .watchTrip(_tripId, pollInterval: const Duration(seconds: 5))
        .listen(updates.add, onError: errors.add);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(
        updates.whereType<RiderTripLocationSnapshot>().last.location.sequence,
        1);
    locationSource.latest = _location(sequence: 2, now: now);
    await tester.pump(const Duration(seconds: 5));
    expect(
        updates.whereType<RiderTripLocationSnapshot>().last.location.sequence,
        2);
    expect(tripSource.readCount, greaterThanOrEqualTo(3));
    locationSource.authenticatedSessionIdentity = Object();
    final reads = locationSource.readCount;
    await tester.pump(const Duration(seconds: 5));
    expect(updates.whereType<RiderTripLocationCleared>().last.reason,
        RiderTripLocationClearReason.sessionChanged);
    await tester.pump(const Duration(seconds: 10));
    expect(locationSource.readCount, reads);
    unawaited(subscription.cancel());
    await tester.pump();
  });

  testWidgets(
      'polling withholds stale observations and stops when Trip becomes terminal',
      (tester) async {
    locationSource.latest =
        _location(sequence: 1, now: now.subtract(const Duration(minutes: 2)));
    subscription = adapter
        .watchTrip(_tripId, pollInterval: const Duration(seconds: 5))
        .listen(updates.add, onError: errors.add);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(updates.whereType<RiderTripLocationSnapshot>(), isEmpty);
    tripSource.trip =
        _trip(status: DriverTripLifecycleStatus.completed, version: 2);
    final reads = locationSource.readCount;
    await tester.pump(const Duration(seconds: 5));
    expect(locationSource.readCount, reads);
    unawaited(subscription.cancel());
    await tester.pump();
  });

  testWidgets(
      'polling keeps canonical location when the Realtime channel errors without retrying',
      (tester) async {
    subscription = adapter
        .watchTrip(_tripId, pollInterval: const Duration(seconds: 5))
        .listen(updates.add, onError: errors.add);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(
        updates.whereType<RiderTripLocationSnapshot>().last.location.sequence,
        1);
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.channelError,
    ));
    await tester.pump();
    expect(updates.whereType<RiderTripLocationCleared>(), isEmpty);
    expect(locationSource.watchCount, 1);
    locationSource.latest = _location(sequence: 2, now: now);
    await tester.pump(const Duration(seconds: 5));
    expect(
        updates.whereType<RiderTripLocationSnapshot>().last.location.sequence,
        2);
    expect(locationSource.watchCount, 1);
    expect(locationSource.readCount, greaterThanOrEqualTo(3));
    expect(updates.last, isA<RiderTripLocationSnapshot>());
    locationSource.emit(const RiderTripLocationChannelSignal(
        RiderTripLocationChannelStatus.subscribed));
    await tester.pump();
    expect(updates.last, isA<RiderTripLocationSnapshot>());
    await tester.pump(const Duration(seconds: 5));
    expect(updates.last, isA<RiderTripLocationSnapshot>());
    unawaited(subscription.cancel());
    await tester.pump();
  });

  test('polling bootstraps after transient initial Trip read failure',
      () async {
    tripSource =
        FakeTripRealtimeSource(authenticatedUserId: _riderId, trip: _trip());
    locationSource = FakeRiderTripLocationSource(
        authenticatedUserId: _riderId,
        latest: _location(sequence: 1, now: now));
    adapter = RiderTripLocationAdapter(
        trips: TripRealtimeAdapter(tripSource),
        locations: locationSource,
        clock: () => now);
    tripSource.failNextRead = true;
    subscription = adapter
        .watchTrip(_tripId, pollInterval: const Duration(seconds: 5))
        .listen(updates.add, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    expect(locationSource.readCount, 0);
    await Future<void>.delayed(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    expect(updates.whereType<RiderTripLocationSnapshot>(), isNotEmpty);
    expect(errors, isEmpty);
    await subscription.cancel();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(locationSource.activeSubscriptions, 0);
    expect(tripSource.activeSubscriptions, 0);
  });

  test('an older in-flight poll cannot revoke newer verified Trip state',
      () async {
    tripSource =
        FakeTripRealtimeSource(authenticatedUserId: _riderId, trip: _trip());
    locationSource = FakeRiderTripLocationSource(
        authenticatedUserId: _riderId,
        latest: _location(sequence: 1, now: now));
    adapter = RiderTripLocationAdapter(
        trips: TripRealtimeAdapter(tripSource),
        locations: locationSource,
        clock: () => now);
    subscription = adapter
        .watchTrip(_tripId, pollInterval: const Duration(seconds: 5))
        .listen(updates.add, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    final gate = Completer<void>();
    tripSource.nextReadGate = gate;
    await Future<void>.delayed(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    tripSource.trip = _trip(version: 2);
    tripSource.emit(const TripRealtimeChangeSignal(
        tripId: _tripId, source: TripRealtimeChangeSource.tripRow));
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(errors, isEmpty);
    await Future<void>.delayed(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    expect(updates.whereType<RiderTripLocationSnapshot>(), isNotEmpty);
    expect(locationSource.activeSubscriptions, 1);
    await subscription.cancel();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(locationSource.activeSubscriptions, 0);
    expect(tripSource.activeSubscriptions, 0);
  });

  setUp(() {
    tripSource = FakeTripRealtimeSource(
      authenticatedUserId: _riderId,
      trip: _trip(),
    );
    locationSource = FakeRiderTripLocationSource(
      authenticatedUserId: _riderId,
      latest: _location(sequence: 1, now: now),
    );
    tripAdapter = TripRealtimeAdapter(tripSource);
    adapter = RiderTripLocationAdapter(
      trips: tripAdapter,
      locations: locationSource,
      clock: () => now,
    );
    updates = [];
    errors = [];
    streamDone = Completer<void>();
    updateWaiters = [];
  });

  tearDown(() async {
    if (locationSource.activeSubscriptions > 0 ||
        tripSource.activeSubscriptions > 0) {
      await subscription.cancel();
    }
  });

  Future<void> waitForUpdate(
    bool Function(RiderTripLocationUpdate update) predicate,
  ) async {
    if (updates.any(predicate)) return;
    final completed = Completer<void>();
    updateWaiters.add((matches: predicate, completed: completed));
    await completed.future;
  }

  Future<void> waitForUpdateCount(
    bool Function(RiderTripLocationUpdate update) predicate,
    int count,
  ) async {
    bool reachedCount() => updates.where(predicate).length >= count;
    if (reachedCount()) return;
    final completed = Completer<void>();
    updateWaiters.add((
      matches: (_) => reachedCount(),
      completed: completed,
    ));
    await completed.future;
  }

  Future<void> waitForLocationSource() async {
    if (locationSource.watchCount > 0) return;
    await locationSource.nextWatch.future;
  }

  void record(RiderTripLocationUpdate update) {
    updates.add(update);
    for (final waiter in updateWaiters.toList()) {
      if (waiter.matches(update)) {
        updateWaiters.remove(waiter);
        if (!waiter.completed.isCompleted) waiter.completed.complete();
      }
    }
  }

  Future<void> listen() async {
    subscription = adapter.watchTrip(_tripId).listen(
          (update) {
            record(update);
          },
          onError: (Object error, StackTrace _) => errors.add(error),
          onDone: () {
            if (!streamDone.isCompleted) streamDone.complete();
          },
        );
    await waitForLocationSource();
  }

  test('subscribes only after the canonical Trip assigns this Driver',
      () async {
    await listen();
    expect(locationSource.watchCount, 1);
    expect(locationSource.lastTripId, _tripId);
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdate((update) => update is RiderTripLocationSnapshot);

    final snapshot = updates.whereType<RiderTripLocationSnapshot>().single;
    expect(snapshot.location.tripId, _tripId);
    expect(snapshot.location.driverId, _driverId);
    expect(snapshot.location.sequence, 1);
    expect(errors, isEmpty);
  });

  test('rejects a canonical Trip belonging to a different Rider', () async {
    tripSource.trip = _trip(riderId: _otherDriverId);
    final errorReceived = Completer<void>();
    subscription = adapter.watchTrip(_tripId).listen(
      updates.add,
      onError: (Object error, StackTrace _) {
        errors.add(error);
        if (!errorReceived.isCompleted) errorReceived.complete();
      },
    );
    await tripSource.waitForReadCount(1);
    await errorReceived.future;

    expect(errors.single, isA<RiderTripLocationException>());
    expect(locationSource.watchCount, 0);
  });

  test('ignores duplicates, stale sequence, and foreign Trip or Driver rows',
      () async {
    await listen();
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdate((update) => update is RiderTripLocationSnapshot);
    final readCount = locationSource.readCount;

    locationSource.emit(const RiderTripLocationChangedSignal(
      tripId: _foreignTripId,
      driverId: _driverId,
    ));
    locationSource.emit(const RiderTripLocationChangedSignal(
      tripId: _tripId,
      driverId: _otherDriverId,
    ));
    locationSource.emit(const RiderTripLocationChangedSignal(
      tripId: _tripId,
      driverId: _driverId,
    ));
    await locationSource.waitForReadCount(readCount + 1);
    expect(locationSource.readCount, readCount + 1);
    locationSource.latest = _location(sequence: 1, now: now);
    locationSource.emit(const RiderTripLocationChangedSignal(
      tripId: _tripId,
      driverId: _driverId,
    ));
    await locationSource.waitForReadCount(readCount + 2);
    locationSource.latest = _location(sequence: 2, now: now);
    locationSource.emit(const RiderTripLocationChangedSignal(
      tripId: _tripId,
      driverId: _driverId,
    ));
    await waitForUpdate((update) =>
        update is RiderTripLocationSnapshot && update.location.sequence == 2);
    locationSource.latest = _location(sequence: 4, now: now);
    locationSource.emit(const RiderTripLocationChangedSignal(
      tripId: _tripId,
      driverId: _driverId,
    ));
    await waitForUpdate((update) =>
        update is RiderTripLocationSnapshot && update.location.sequence == 4);
    locationSource.latest = _location(sequence: 3, now: now);
    locationSource.emit(const RiderTripLocationChangedSignal(
      tripId: _tripId,
      driverId: _driverId,
    ));
    await locationSource.waitForReadCount(readCount + 5);

    expect(
        updates.whereType<RiderTripLocationSnapshot>().map(
              (update) => update.location.sequence,
            ),
        [1, 2, 4]);
  });

  test('rereads canonical location after reconnect and recovers missed event',
      () async {
    final pendingRetry = Completer<void>();
    adapter = RiderTripLocationAdapter(
      trips: tripAdapter,
      locations: locationSource,
      clock: () => now,
      delay: (_) => pendingRetry.future,
    );
    await listen();
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdate((update) => update is RiderTripLocationSnapshot);
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.channelError,
    ));
    locationSource.latest = _location(sequence: 2, now: now);
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdate((update) =>
        update is RiderTripLocationSnapshot && update.location.sequence == 2);

    expect(locationSource.readCount, 2);
  });

  test('retries a closed stream with bounded backoff and resubscribes',
      () async {
    final delayRequests = <Duration>[];
    final retryGate = Completer<void>();
    final delayRequested = Completer<void>();
    adapter = RiderTripLocationAdapter(
      trips: tripAdapter,
      locations: locationSource,
      clock: () => now,
      delay: (duration) {
        delayRequests.add(duration);
        if (!delayRequested.isCompleted) delayRequested.complete();
        return retryGate.future;
      },
    );
    await listen();
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.closed,
    ));
    await delayRequested.future;
    expect(delayRequests, [const Duration(seconds: 1)]);
    retryGate.complete();
    await locationSource.waitForWatchCount(2);
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await locationSource.waitForReadCount(1);
    expect(locationSource.readCount, 1);
    expect(locationSource.activeSubscriptions, 1);
  });

  test('disconnect invalidates a stalled read and recovers after it returns',
      () async {
    final retryGate = Completer<void>();
    final retryRequested = Completer<void>();
    adapter = RiderTripLocationAdapter(
      trips: tripAdapter,
      locations: locationSource,
      clock: () => now,
      delay: (_) {
        if (!retryRequested.isCompleted) retryRequested.complete();
        return retryGate.future;
      },
    );
    await listen();
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdate((update) => update is RiderTripLocationSnapshot);

    final stalledRead = Completer<void>();
    final stalledReadReturned = Completer<void>();
    locationSource.readGates[2] = stalledRead;
    locationSource.readReturns[2] = stalledReadReturned;
    locationSource.latest = _location(sequence: 2, now: now);
    locationSource.emit(const RiderTripLocationChangedSignal(
      tripId: _tripId,
      driverId: _driverId,
    ));
    await locationSource.waitForReadCount(2);

    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.channelError,
    ));
    await waitForUpdate(
      (update) =>
          update is RiderTripLocationCleared &&
          update.reason == RiderTripLocationClearReason.staleLocation,
    );
    await waitForUpdate(
      (update) =>
          update is RiderTripLocationConnectionUpdate &&
          update.status == RiderTripLocationChannelStatus.channelError,
    );
    await retryRequested.future;
    retryGate.complete();
    await locationSource.waitForWatchCount(2);
    await locationSource.waitForCancelCount(1);
    expect(locationSource.activeSubscriptions, 1);

    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdateCount(
      (update) =>
          update is RiderTripLocationConnectionUpdate &&
          update.status == RiderTripLocationChannelStatus.subscribed,
      2,
    );
    expect(locationSource.readCount, 2);

    locationSource.latest = _location(sequence: 3, now: now);
    stalledRead.complete();
    await stalledReadReturned.future;
    await locationSource.waitForReadCount(3);
    await waitForUpdate((update) =>
        update is RiderTripLocationSnapshot && update.location.sequence == 3);

    expect(
      updates.whereType<RiderTripLocationSnapshot>().map(
            (update) => update.location.sequence,
          ),
      [1, 3],
    );
    expect(locationSource.activeSubscriptions, 1);
  });

  test('repeated disconnects coalesce retries and location reads', () async {
    final retryGates = [Completer<void>(), Completer<void>()];
    final retryRequests = [Completer<void>(), Completer<void>()];
    final retryDurations = <Duration>[];
    adapter = RiderTripLocationAdapter(
      trips: tripAdapter,
      locations: locationSource,
      clock: () => now,
      delay: (duration) {
        final index = retryDurations.length;
        retryDurations.add(duration);
        if (!retryRequests[index].isCompleted) {
          retryRequests[index].complete();
        }
        return retryGates[index].future;
      },
    );
    await listen();
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdate((update) => update is RiderTripLocationSnapshot);

    final stalledRead = Completer<void>();
    final stalledReadReturned = Completer<void>();
    locationSource.readGates[2] = stalledRead;
    locationSource.readReturns[2] = stalledReadReturned;
    locationSource.latest = _location(sequence: 2, now: now);
    locationSource.emit(const RiderTripLocationChangedSignal(
      tripId: _tripId,
      driverId: _driverId,
    ));
    await locationSource.waitForReadCount(2);

    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.channelError,
    ));
    await retryRequests[0].future;
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.closed,
    ));
    expect(retryDurations, [const Duration(seconds: 1)]);
    retryGates[0].complete();
    await locationSource.waitForWatchCount(2);
    await locationSource.waitForCancelCount(1);
    expect(locationSource.activeSubscriptions, 1);

    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdateCount(
      (update) =>
          update is RiderTripLocationConnectionUpdate &&
          update.status == RiderTripLocationChannelStatus.subscribed,
      2,
    );
    expect(locationSource.readCount, 2);

    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.channelError,
    ));
    await retryRequests[1].future;
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.timedOut,
    ));
    expect(retryDurations, [
      const Duration(seconds: 1),
      const Duration(seconds: 1),
    ]);
    retryGates[1].complete();
    await locationSource.waitForWatchCount(3);
    await locationSource.waitForCancelCount(2);
    expect(locationSource.activeSubscriptions, 1);

    locationSource.latest = _location(sequence: 3, now: now);
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdateCount(
      (update) =>
          update is RiderTripLocationConnectionUpdate &&
          update.status == RiderTripLocationChannelStatus.subscribed,
      3,
    );
    expect(locationSource.readCount, 2);

    stalledRead.complete();
    await stalledReadReturned.future;
    await locationSource.waitForReadCount(3);
    await waitForUpdate((update) =>
        update is RiderTripLocationSnapshot && update.location.sequence == 3);

    expect(locationSource.watchCount, 3);
    expect(locationSource.activeSubscriptions, 1);
    expect(locationSource.maximumActiveSubscriptions, 1);
    expect(locationSource.readCount, 3);
    expect(
      updates.whereType<RiderTripLocationSnapshot>().map(
            (update) => update.location.sequence,
          ),
      [1, 3],
    );
  });

  test('clears state and stops location on terminal canonical Trip', () async {
    await listen();
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdate((update) => update is RiderTripLocationSnapshot);

    tripSource.trip = _trip(
      version: 2,
      status: DriverTripLifecycleStatus.completed,
    );
    tripSource.emit(const TripRealtimeChangeSignal(
      tripId: _tripId,
      source: TripRealtimeChangeSource.tripRow,
    ));
    await waitForUpdate((update) => update is RiderTripLocationCleared);
    await locationSource.waitForCancelCount(1);

    expect(
      updates.whereType<RiderTripLocationCleared>().single.reason,
      RiderTripLocationClearReason.terminalTrip,
    );
    expect(locationSource.activeSubscriptions, 0);
  });

  test('clears state and cancels subscriptions when the session changes',
      () async {
    await listen();
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await waitForUpdate((update) => update is RiderTripLocationSnapshot);

    locationSource.authenticatedSessionIdentity = Object();
    locationSource.authenticatedUserId = null;
    locationSource.emit(const RiderTripLocationSessionChangedSignal());
    await waitForUpdate((update) => update is RiderTripLocationCleared);
    await locationSource.waitForCancelCount(1);
    await tripSource.waitForCancelCount(1);

    expect(
      updates.whereType<RiderTripLocationCleared>().single.reason,
      RiderTripLocationClearReason.sessionChanged,
    );
    expect(locationSource.activeSubscriptions, 0);
    expect(tripSource.activeSubscriptions, 0);
  });

  test('rejects stale canonical locations by age even after reconnect',
      () async {
    await listen();
    locationSource.latest = _location(
      sequence: 9,
      now: now.subtract(const Duration(minutes: 2)),
    );
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await locationSource.waitForReadCount(1);

    expect(updates.whereType<RiderTripLocationSnapshot>(), isEmpty);
  });

  test('rejects a canonical row for another Driver on the same Trip', () async {
    await listen();
    locationSource.latest = _location(
      sequence: 1,
      now: now,
      driverId: _otherDriverId,
    );
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await locationSource.waitForReadCount(1);

    expect(updates.whereType<RiderTripLocationSnapshot>(), isEmpty);
  });

  test('consumer cancellation cleans up Trip and location subscriptions',
      () async {
    await listen();
    await subscription.cancel();
    await locationSource.waitForCancelCount(1);
    await tripSource.waitForCancelCount(1);

    expect(locationSource.activeSubscriptions, 0);
    expect(tripSource.activeSubscriptions, 0);
  });

  test('session replacement invalidates a pending read and rejects its result',
      () async {
    await listen();
    final readGate = Completer<void>();
    final readReturned = Completer<void>();
    locationSource.readGate = readGate;
    locationSource.readReturned = readReturned;
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await locationSource.waitForReadCount(1);

    locationSource.authenticatedUserId = null;
    locationSource.authenticatedSessionIdentity = Object();
    locationSource.emit(const RiderTripLocationSessionChangedSignal());
    await waitForUpdate((update) => update is RiderTripLocationCleared);
    await streamDone.future;
    await locationSource.waitForCancelCount(1);
    await tripSource.waitForCancelCount(1);
    expect(
      updates.whereType<RiderTripLocationCleared>().single.reason,
      RiderTripLocationClearReason.sessionChanged,
    );

    readGate.complete();
    await readReturned.future;
    await Future<void>.value();
    expect(updates.whereType<RiderTripLocationSnapshot>(), isEmpty);
    expect(locationSource.activeSubscriptions, 0);
  });

  test('terminal Trip invalidates a pending read and rejects its result',
      () async {
    await listen();
    final readGate = Completer<void>();
    final readReturned = Completer<void>();
    locationSource.readGate = readGate;
    locationSource.readReturned = readReturned;
    locationSource.emit(const RiderTripLocationChannelSignal(
      RiderTripLocationChannelStatus.subscribed,
    ));
    await locationSource.waitForReadCount(1);

    tripSource.trip = _trip(
      version: 2,
      status: DriverTripLifecycleStatus.completed,
    );
    tripSource.emit(const TripRealtimeChangeSignal(
      tripId: _tripId,
      source: TripRealtimeChangeSource.tripRow,
    ));
    await waitForUpdate((update) => update is RiderTripLocationCleared);
    await streamDone.future;
    await locationSource.waitForCancelCount(1);
    await tripSource.waitForCancelCount(1);
    expect(
      updates.whereType<RiderTripLocationCleared>().single.reason,
      RiderTripLocationClearReason.terminalTrip,
    );

    readGate.complete();
    await readReturned.future;
    await Future<void>.value();
    expect(updates.whereType<RiderTripLocationSnapshot>(), isEmpty);
    expect(locationSource.activeSubscriptions, 0);
  });

  test('cleans the auth listener when location channel creation throws',
      () async {
    await _expectLocationSetupFailure(
      channelFactory: (_) =>
          throw StateError('injected channel creation error'),
      expectedChannelRemovals: 0,
    );
  });

  test('cleans auth listener and channel when handler registration throws',
      () async {
    await _expectLocationSetupFailure(
      beforeHandlerRegistration: () =>
          throw StateError('injected handler registration error'),
      expectedChannelRemovals: 1,
    );
  });

  test('cleans auth listener and channel when subscribe setup throws',
      () async {
    await _expectLocationSetupFailure(
      beforeSubscribe: () => throw StateError('injected subscribe error'),
      expectedChannelRemovals: 1,
    );
  });
}

Future<void> _expectLocationSetupFailure({
  RiderLocationChannelFactory? channelFactory,
  void Function()? beforeHandlerRegistration,
  void Function()? beforeSubscribe,
  required int expectedChannelRemovals,
}) async {
  final client = SupabaseClient(
    'https://rider-location.unit-test.invalid',
    'unit-test-anon-key',
  );
  final authEvents = StreamController<Object?>();
  var activeAuthListeners = 0;
  var authListenerCancellations = 0;
  authEvents.onListen = () {
    activeAuthListeners++;
  };
  authEvents.onCancel = () {
    activeAuthListeners--;
    authListenerCancellations++;
  };
  final removedChannels = <RealtimeChannel>[];
  final source = SupabaseRiderTripLocationSource(
    client,
    authStreamFactory: () => authEvents.stream,
    channelFactory: channelFactory ?? client.channel,
    channelRemover: (channel) async {
      removedChannels.add(channel);
      await client.removeChannel(channel);
    },
    beforeHandlerRegistration: beforeHandlerRegistration,
    beforeSubscribe: beforeSubscribe,
  );
  final failure = Completer<RiderTripLocationException>();
  final subscription = source.watchTripLocation(_tripId).listen(
    (_) {},
    onError: (Object error, StackTrace _) {
      if (error is RiderTripLocationException && !failure.isCompleted) {
        failure.complete(error);
      }
    },
  );

  try {
    final error = await failure.future;
    expect(error.failure, RiderTripLocationFailure.sourceUnavailable);
    expect(authListenerCancellations, 1);
    expect(activeAuthListeners, 0);
    expect(authEvents.hasListener, isFalse);
    expect(removedChannels, hasLength(expectedChannelRemovals));

    await subscription.cancel();
    expect(authListenerCancellations, 1);
    expect(activeAuthListeners, 0);
    expect(removedChannels, hasLength(expectedChannelRemovals));
  } finally {
    await subscription.cancel();
    await authEvents.close();
    await client.dispose();
  }
}

TripRealtimeTrip _trip({
  String riderId = _riderId,
  String driverId = _driverId,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
  int version = 1,
}) =>
    TripRealtimeTrip(
      tripId: _tripId,
      riderId: riderId,
      driverId: driverId,
      status: status,
      version: version,
    );

RiderTripLocation _location({
  required int sequence,
  required DateTime now,
  String driverId = _driverId,
}) =>
    RiderTripLocation(
      tripId: _tripId,
      driverId: driverId,
      sequence: sequence,
      point: LocationPoint(
        latitude: 31.95 + sequence / 100000,
        longitude: 35.91,
        accuracyMeters: 8,
      ),
      recordedAt: now.subtract(Duration(seconds: 10 - sequence)),
      receivedAt: now.subtract(Duration(seconds: 10 - sequence)),
    );

final class FakeTripRealtimeSource implements TripRealtimeSource {
  FakeTripRealtimeSource(
      {required this.authenticatedUserId, required this.trip});

  @override
  String? authenticatedUserId;
  @override
  Object? authenticatedSessionIdentity = Object();
  TripRealtimeTrip trip;
  bool failNextRead = false;
  Completer<void>? nextReadGate;
  final _signals = StreamController<TripRealtimeSourceSignal>.broadcast();
  int readCount = 0;
  int activeSubscriptions = 0;
  int cancelCount = 0;
  Completer<void> nextRead = Completer<void>();
  Completer<void> nextCancel = Completer<void>();

  @override
  Stream<TripRealtimeSourceSignal> watchTrip(String tripId) =>
      Stream<TripRealtimeSourceSignal>.multi((controller) {
        activeSubscriptions++;
        final inner = _signals.stream.listen(controller.add);
        controller.onCancel = () async {
          await inner.cancel();
          activeSubscriptions--;
          cancelCount++;
          if (!nextCancel.isCompleted) nextCancel.complete();
        };
      });

  @override
  Future<TripRealtimeTrip?> readCanonicalTrip(String tripId) async {
    readCount++;
    if (!nextRead.isCompleted) nextRead.complete();
    if (failNextRead) {
      failNextRead = false;
      throw const TripRealtimeException(TripRealtimeFailure.sourceUnavailable);
    }
    final snapshot = trip;
    final gate = nextReadGate;
    nextReadGate = null;
    if (gate != null) await gate.future;
    return snapshot;
  }

  void emit(TripRealtimeSourceSignal signal) => _signals.add(signal);

  Future<void> waitForReadCount(int count) async {
    while (readCount < count) {
      nextRead = Completer<void>();
      await nextRead.future;
    }
  }

  Future<void> waitForCancelCount(int count) async {
    while (cancelCount < count) {
      nextCancel = Completer<void>();
      await nextCancel.future;
    }
  }
}

final class FakeRiderTripLocationSource implements RiderTripLocationSource {
  FakeRiderTripLocationSource({
    required this.authenticatedUserId,
    required this.latest,
  });

  @override
  String? authenticatedUserId;
  @override
  Object? authenticatedSessionIdentity = Object();
  RiderTripLocation? latest;
  final _signals = StreamController<RiderTripLocationSourceSignal>.broadcast();
  int watchCount = 0;
  int readCount = 0;
  int activeSubscriptions = 0;
  int maximumActiveSubscriptions = 0;
  int cancelCount = 0;
  String? lastTripId;
  Completer<void> nextWatch = Completer<void>();
  Completer<void> nextRead = Completer<void>();
  Completer<void> nextCancel = Completer<void>();
  Completer<void>? readGate;
  Completer<void>? readReturned;
  final Map<int, Completer<void>> readGates = {};
  final Map<int, Completer<void>> readReturns = {};

  @override
  Stream<RiderTripLocationSourceSignal> watchTripLocation(String tripId) {
    watchCount++;
    lastTripId = tripId;
    if (!nextWatch.isCompleted) nextWatch.complete();
    return Stream<RiderTripLocationSourceSignal>.multi((controller) {
      activeSubscriptions++;
      if (activeSubscriptions > maximumActiveSubscriptions) {
        maximumActiveSubscriptions = activeSubscriptions;
      }
      final inner = _signals.stream.listen(controller.add);
      controller.onCancel = () async {
        await inner.cancel();
        activeSubscriptions--;
        cancelCount++;
        if (!nextCancel.isCompleted) nextCancel.complete();
      };
    });
  }

  @override
  Future<RiderTripLocation?> readLatestTripLocation({
    required String tripId,
    required String driverId,
  }) async {
    readCount++;
    final readNumber = readCount;
    if (!nextRead.isCompleted) nextRead.complete();
    final snapshot = latest;
    final gate = readGates[readNumber] ?? (readNumber == 1 ? readGate : null);
    if (gate != null) {
      await gate.future;
      readGates.remove(readNumber);
      if (readNumber == 1) readGate = null;
    }
    final returned =
        readReturns[readNumber] ?? (readNumber == 1 ? readReturned : null);
    if (returned != null && !returned.isCompleted) returned.complete();
    return snapshot;
  }

  void emit(RiderTripLocationSourceSignal signal) => _signals.add(signal);

  Future<void> waitForWatchCount(int count) async {
    while (watchCount < count) {
      nextWatch = Completer<void>();
      await nextWatch.future;
    }
  }

  Future<void> waitForReadCount(int count) async {
    while (readCount < count) {
      nextRead = Completer<void>();
      await nextRead.future;
    }
  }

  Future<void> waitForCancelCount(int count) async {
    while (cancelCount < count) {
      nextCancel = Completer<void>();
      await nextCancel.future;
    }
  }
}
