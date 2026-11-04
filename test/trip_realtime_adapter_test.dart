import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/trip_realtime.dart';
import 'package:ridex/core/services/trips/supabase_trip_realtime_source.dart';
import 'package:ridex/core/services/trips/trip_realtime_adapter.dart';
import 'package:ridex/core/services/trips/trip_realtime_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _tripId = '11111111-1111-4111-8111-111111111111';
const _riderId = '22222222-2222-4222-8222-222222222222';
const _driverId = '33333333-3333-4333-8333-333333333333';
const _otherId = '44444444-4444-4444-8444-444444444444';
const _foreignTripId = '55555555-5555-4555-8555-555555555555';

void main() {
  late FakeTripRealtimeSource source;
  late TripRealtimeAdapter adapter;
  late List<TripRealtimeUpdate> updates;
  late List<Object> errors;
  late StreamSubscription<TripRealtimeUpdate> subscription;
  late List<({
    bool Function(TripRealtimeUpdate) matches,
    Completer<void> completed,
  })> updateWaiters;
  final errorWaiters = <Completer<void>>[];

  setUp(() {
    source = FakeTripRealtimeSource(
      authenticatedUserId: _riderId,
      trip: _trip(version: 1),
    );
    adapter = TripRealtimeAdapter(source);
    updates = [];
    errors = [];
    updateWaiters = [];
    errorWaiters.clear();
  });

  void recordUpdate(TripRealtimeUpdate update) {
    updates.add(update);
    for (final waiter in updateWaiters.toList()) {
      if (waiter.matches(update)) {
        updateWaiters.remove(waiter);
        waiter.completed.complete();
      }
    }
  }

  Future<void> waitForUpdate(
    bool Function(TripRealtimeUpdate) matches,
  ) {
    if (updates.any(matches)) return Future<void>.value();
    final completed = Completer<void>();
    updateWaiters.add((matches: matches, completed: completed));
    return completed.future;
  }

  Future<void> waitForError() async {
    if (errors.isNotEmpty) return;
    final completed = Completer<void>();
    errorWaiters.add(completed);
    await completed.future;
  }

  void recordError(Object error) {
    errors.add(error);
    for (final waiter in errorWaiters.toList()) {
      errorWaiters.remove(waiter);
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Future<void> listen(String tripId) async {
    final initialSnapshotOrError = Completer<void>();
    subscription = adapter.watchTrip(tripId).listen(
      (update) {
        recordUpdate(update);
        if (update is VerifiedTripRealtimeEvent &&
            update.cause == TripRealtimeEventCause.initialCanonicalRead &&
            !initialSnapshotOrError.isCompleted) {
          initialSnapshotOrError.complete();
        }
      },
      onError: (Object error, StackTrace _) {
        recordError(error);
        if (!initialSnapshotOrError.isCompleted) {
          initialSnapshotOrError.complete();
        }
      },
    );
    await initialSnapshotOrError.future;
  }

  tearDown(() async {
    if (source.active) await subscription.cancel();
  });

  test('subscribes before emitting the initial canonical snapshot', () async {
    expect(adapter.watchTrip(_tripId).isBroadcast, isFalse);
    expect(source.watchTrip(_tripId).isBroadcast, isFalse);
    await listen(_tripId);

    expect(source.watchCount, 1);
    expect(source.readCount, 1);
    expect(source.readStartedAfterSubscription, isTrue);
    expect(updates.first, isA<TripRealtimeConnectionUpdate>());
    final initial = updates.whereType<VerifiedTripRealtimeEvent>().single;
    expect(initial.trip.tripId, _tripId);
    expect(initial.trip.status, DriverTripLifecycleStatus.accepted);
    expect(initial.trip.version, 1);
    expect(initial.cause, TripRealtimeEventCause.initialCanonicalRead);
    expect(errors, isEmpty);
  });

  test('rejects malformed Trip IDs without opening a subscription', () async {
    await listen('trip-42');

    expect(
      errors.single,
      isA<TripRealtimeException>().having(
        (error) => error.failure,
        'failure',
        TripRealtimeFailure.invalidTripId,
      ),
    );
    expect(source.watchCount, 0);
  });

  test('rejects a visible Trip that does not belong to the authenticated user',
      () async {
    source.trip = _trip(riderId: _otherId, version: 1);
    await listen(_tripId);

    expect(
      errors.single,
      isA<TripRealtimeException>().having(
        (error) => error.failure,
        'failure',
        TripRealtimeFailure.notVisible,
      ),
    );
    await source.waitForCancelCount(1);
    expect(source.cancelCount, 1);
    expect(updates.whereType<VerifiedTripRealtimeEvent>(), isEmpty);
  });

  test('authorizes the Driver assigned to the canonical Trip', () async {
    source.authenticatedUserId = _driverId;
    source.trip = _trip(riderId: _riderId, driverId: _driverId, version: 1);
    await listen(_tripId);

    final initial = updates.whereType<VerifiedTripRealtimeEvent>().single;
    expect(initial.trip.driverId, _driverId);
    expect(initial.trip.riderId, _riderId);
    expect(errors, isEmpty);
  });

  test('rejects a different Driver from the one assigned to the Trip',
      () async {
    source.authenticatedUserId = _otherId;
    source.trip = _trip(driverId: _driverId, version: 1);
    await listen(_tripId);

    expect(
      errors.single,
      isA<TripRealtimeException>().having(
        (error) => error.failure,
        'failure',
        TripRealtimeFailure.notVisible,
      ),
    );
    await source.waitForCancelCount(1);
    expect(source.cancelCount, 1);
    expect(updates.whereType<VerifiedTripRealtimeEvent>(), isEmpty);
  });

  test('ignores notifications for foreign Trip IDs', () async {
    await listen(_tripId);
    final readsBefore = source.readCount;
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _foreignTripId,
        source: TripRealtimeChangeSource.tripRow,
      ),
    );
    source.trip = _trip(
      version: 2,
      status: DriverTripLifecycleStatus.inProgress,
    );
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.tripRow,
      ),
    );
    await waitForUpdate(
      (update) =>
          update is VerifiedTripRealtimeEvent && update.trip.version == 2,
    );

    expect(source.readCount, readsBefore + 1);
    expect(updates.whereType<VerifiedTripRealtimeEvent>(), hasLength(2));
  });

  test('uses notifications only as hints and ignores duplicate or stale state',
      () async {
    await listen(_tripId);
    source.trip = _trip(
      version: 2,
      status: DriverTripLifecycleStatus.inProgress,
    );
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.tripRow,
      ),
    );
    await waitForUpdate(
      (update) =>
          update is VerifiedTripRealtimeEvent && update.trip.version == 2,
    );

    final accepted = updates.whereType<VerifiedTripRealtimeEvent>().toList();
    expect(accepted, hasLength(2));
    expect(accepted.last.trip.status, DriverTripLifecycleStatus.inProgress);
    expect(accepted.last.trip.version, 2);

    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.tripRow,
      ),
    );
    await source.waitForReadCount(3);
    source.trip = _trip(version: 1);
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.tripRow,
      ),
    );
    await source.waitForReadCount(4);
    source.trip = _trip(
      version: 3,
      status: DriverTripLifecycleStatus.driverArrived,
    );
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.tripRow,
      ),
    );
    await waitForUpdate(
      (update) =>
          update is VerifiedTripRealtimeEvent && update.trip.version == 3,
    );

    expect(updates.whereType<VerifiedTripRealtimeEvent>(), hasLength(3));
    expect(source.readCount, 5);
  });

  test('drops duplicate and out-of-order status history sequences', () async {
    await listen(_tripId);
    source.trip = _trip(
      version: 2,
      status: DriverTripLifecycleStatus.driverArriving,
    );
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.statusHistory,
        statusEventSequence: 2,
      ),
    );
    await waitForUpdate(
      (update) =>
          update is VerifiedTripRealtimeEvent && update.trip.version == 2,
    );
    final afterFirst = source.readCount;

    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.statusHistory,
        statusEventSequence: 2,
      ),
    );
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.statusHistory,
        statusEventSequence: 1,
      ),
    );
    source.trip = _trip(
      version: 3,
      status: DriverTripLifecycleStatus.driverArrived,
    );
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.statusHistory,
        statusEventSequence: 3,
      ),
    );
    await waitForUpdate(
      (update) =>
          update is VerifiedTripRealtimeEvent && update.trip.version == 3,
    );

    expect(source.readCount, afterFirst + 1);
    final events = updates.whereType<VerifiedTripRealtimeEvent>().toList();
    expect(events, hasLength(3));
    expect(events.last.statusEventSequence, 3);
  });

  test('does not consume a status sequence before canonical state advances',
      () async {
    await listen(_tripId);
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.statusHistory,
        statusEventSequence: 2,
      ),
    );
    await source.waitForReadCount(2);

    source.trip = _trip(
      version: 2,
      status: DriverTripLifecycleStatus.inProgress,
    );
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.statusHistory,
        statusEventSequence: 2,
      ),
    );
    await waitForUpdate(
      (update) =>
          update is VerifiedTripRealtimeEvent && update.trip.version == 2,
    );

    final events = updates.whereType<VerifiedTripRealtimeEvent>().toList();
    expect(events, hasLength(2));
    expect(events.last.trip.version, 2);
    expect(events.last.statusEventSequence, 2);
    expect(source.readCount, 3);
  });

  test('rereads canonical state after disconnect and resubscription', () async {
    await listen(_tripId);
    source.emit(
      const TripRealtimeChannelSignal(TripRealtimeChannelStatus.channelError),
    );
    source.emit(
      const TripRealtimeChannelSignal(TripRealtimeChannelStatus.timedOut),
    );
    source.trip = _trip(
      version: 2,
      status: DriverTripLifecycleStatus.inProgress,
    );
    source.emit(
      const TripRealtimeChannelSignal(TripRealtimeChannelStatus.subscribed),
    );
    await waitForUpdate(
      (update) =>
          update is VerifiedTripRealtimeEvent &&
          update.trip.version == 2 &&
          update.cause == TripRealtimeEventCause.connectionRestored,
    );

    expect(
      updates
          .whereType<TripRealtimeConnectionUpdate>()
          .map((event) => event.status),
      containsAll([
        TripRealtimeChannelStatus.channelError,
        TripRealtimeChannelStatus.timedOut,
        TripRealtimeChannelStatus.subscribed,
      ]),
    );
    final recovered = updates.whereType<VerifiedTripRealtimeEvent>().last;
    expect(recovered.trip.version, 2);
    expect(recovered.cause, TripRealtimeEventCause.connectionRestored);
  });

  test('keeps listening after a transient verification error for later rejoin',
      () async {
    await listen(_tripId);
    source.failNextRead = true;
    source.emit(
      const TripRealtimeChannelSignal(TripRealtimeChannelStatus.channelError),
    );
    source.emit(
      const TripRealtimeChannelSignal(TripRealtimeChannelStatus.subscribed),
    );
    await waitForUpdate(
      (update) => update is TripRealtimeVerificationUpdate,
    );
    expect(errors, isEmpty);
    expect(
      updates.whereType<TripRealtimeVerificationUpdate>().last.reason,
      TripRealtimeFailure.sourceUnavailable,
    );

    source.trip = _trip(
      version: 2,
      status: DriverTripLifecycleStatus.inProgress,
    );
    source.emit(
      const TripRealtimeChannelSignal(TripRealtimeChannelStatus.subscribed),
    );
    await waitForUpdate(
      (update) =>
          update is VerifiedTripRealtimeEvent && update.trip.version == 2,
    );

    expect(updates.whereType<VerifiedTripRealtimeEvent>().last.trip.version, 2);
  });

  test('session replacement during verification fails closed', () async {
    await listen(_tripId);
    final readGate = Completer<void>();
    source.blockNextRead = readGate.future;
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.tripRow,
      ),
    );
    await source.waitForReadCount(2);
    source.authenticatedSessionIdentity = Object();
    readGate.complete();
    await waitForError();
    await source.waitForCancelCount(1);

    expect(errors, hasLength(1));
    expect(
      errors.single,
      isA<TripRealtimeException>().having(
        (error) => error.failure,
        'failure',
        TripRealtimeFailure.sessionChanged,
      ),
    );
    expect(source.cancelCount, 1);
  });

  test('same-user session replacement terminates the live subscription',
      () async {
    await listen(_tripId);
    source.authenticatedSessionIdentity = Object();
    source.emit(const TripRealtimeSessionChangedSignal());
    await waitForError();
    await source.waitForCancelCount(1);

    expect(errors, hasLength(1));
    expect(
      errors.single,
      isA<TripRealtimeException>().having(
        (error) => error.failure,
        'failure',
        TripRealtimeFailure.sessionChanged,
      ),
    );
    expect(source.cancelCount, 1);
  });

  test('cancelling while idle completes and removes the source subscription',
      () async {
    await listen(_tripId);
    await subscription.cancel();
    final updateCount = updates.length;
    source.emit(
      const TripRealtimeChangeSignal(
        tripId: _tripId,
        source: TripRealtimeChangeSource.tripRow,
      ),
    );
    expect(source.cancelCount, 1);
    expect(updates, hasLength(updateCount));
  });

  test('cleans up the auth listener when channel creation throws', () async {
    await _expectSetupFailure(
      channelFactory: (_) => throw StateError('injected channel failure'),
      expectedChannelRemovals: 0,
    );
  });

  test('cleans up auth listener and partial channel when handler setup throws',
      () async {
    await _expectSetupFailure(
      beforeHandlerRegistration: () =>
          throw StateError('injected handler failure'),
      expectedChannelRemovals: 1,
    );
  });

  test('cleans up auth listener and channel when subscribe setup throws',
      () async {
    await _expectSetupFailure(
      beforeSubscribe: () => throw StateError('injected subscribe failure'),
      expectedChannelRemovals: 1,
    );
  });
}

Future<void> _expectSetupFailure({
  TripRealtimeChannelFactory? channelFactory,
  void Function()? beforeHandlerRegistration,
  void Function()? beforeSubscribe,
  required int expectedChannelRemovals,
}) async {
  final client = SupabaseClient(
    'https://trip-realtime.unit-test.invalid',
    'unit-test-anon-key',
  );
  final authEvents = StreamController<Object?>();
  var authListenerCancellations = 0;
  authEvents.onCancel = () {
    authListenerCancellations++;
  };
  final removedChannels = <RealtimeChannel>[];
  final source = SupabaseTripRealtimeSource(
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
  final failure = Completer<TripRealtimeException>();
  final subscription = source.watchTrip(_tripId).listen(
    (_) {},
    onError: (Object error, StackTrace _) {
      if (error is TripRealtimeException && !failure.isCompleted) {
        failure.complete(error);
      }
    },
  );

  final error = await failure.future;
  expect(error.failure, TripRealtimeFailure.sourceUnavailable);
  expect(authListenerCancellations, 1);
  expect(removedChannels, hasLength(expectedChannelRemovals));
  await subscription.cancel();
  expect(authListenerCancellations, 1);
  expect(removedChannels, hasLength(expectedChannelRemovals));
  await authEvents.close();
  await client.dispose();
}

TripRealtimeTrip _trip({
  String tripId = _tripId,
  String riderId = _riderId,
  String driverId = _driverId,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
  int version = 1,
}) =>
    TripRealtimeTrip(
      tripId: tripId,
      riderId: riderId,
      driverId: driverId,
      status: status,
      version: version,
    );

final class FakeTripRealtimeSource implements TripRealtimeSource {
  FakeTripRealtimeSource({
    required this.authenticatedUserId,
    required this.trip,
  }) : authenticatedSessionIdentity = Object();

  @override
  String? authenticatedUserId;

  @override
  Object? authenticatedSessionIdentity;
  TripRealtimeTrip? trip;
  int watchCount = 0;
  int readCount = 0;
  int cancelCount = 0;
  bool readStartedAfterSubscription = false;
  bool failNextRead = false;
  Future<void>? blockNextRead;
  MultiStreamController<TripRealtimeSourceSignal>? _controller;
  final Completer<void> _subscriptionReady = Completer<void>();
  final Map<int, Completer<void>> _readCountWaiters = {};
  final Map<int, Completer<void>> _cancelCountWaiters = {};

  bool get active => _controller != null;

  Future<void> waitForReadCount(int count) {
    if (readCount >= count) return Future<void>.value();
    return (_readCountWaiters[count] ??= Completer<void>()).future;
  }

  Future<void> waitForCancelCount(int count) {
    if (cancelCount >= count) return Future<void>.value();
    return (_cancelCountWaiters[count] ??= Completer<void>()).future;
  }

  void _completeReadyWaiters(
    Map<int, Completer<void>> waiters,
    int currentCount,
  ) {
    final completedCounts = waiters.keys
        .where((requestedCount) => requestedCount <= currentCount)
        .toList();
    for (final requestedCount in completedCounts) {
      waiters.remove(requestedCount)?.complete();
    }
  }

  @override
  Stream<TripRealtimeSourceSignal> watchTrip(String tripId) {
    return Stream<TripRealtimeSourceSignal>.multi((controller) {
      watchCount++;
      _controller = controller;
      controller.onCancel = () {
        if (identical(_controller, controller)) _controller = null;
        cancelCount++;
        _completeReadyWaiters(_cancelCountWaiters, cancelCount);
      };
      if (!_subscriptionReady.isCompleted) _subscriptionReady.complete();
      controller.add(
        const TripRealtimeChannelSignal(TripRealtimeChannelStatus.connecting),
      );
    }, isBroadcast: false);
  }

  @override
  Future<TripRealtimeTrip?> readCanonicalTrip(String tripId) async {
    readCount++;
    readStartedAfterSubscription = _subscriptionReady.isCompleted;
    _completeReadyWaiters(_readCountWaiters, readCount);
    final barrier = blockNextRead;
    blockNextRead = null;
    if (barrier != null) await barrier;
    if (failNextRead) {
      failNextRead = false;
      throw StateError('test-only read failure');
    }
    return trip;
  }

  void emit(TripRealtimeSourceSignal signal) {
    _controller?.add(signal);
  }
}
