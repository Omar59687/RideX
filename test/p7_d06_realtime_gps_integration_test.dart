import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_trip_location.dart';
import 'package:ridex/core/models/trip_realtime.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/driver_tracking_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/repositories/driver_location_repository.dart';
import 'package:ridex/core/services/driver_location/driver_gps_stream_service.dart';
import 'package:ridex/core/services/driver_location/driver_location_service.dart';
import 'package:ridex/core/services/driver_location/driver_tracking_connection.dart';
import 'package:ridex/core/services/trips/rider_trip_location_adapter.dart';
import 'package:ridex/core/services/trips/rider_trip_location_source.dart';
import 'package:ridex/core/services/trips/trip_realtime_adapter.dart';
import 'package:ridex/core/services/trips/trip_realtime_source.dart';

import 'helpers/recording_error_reporter.dart';

const _riderId = 'a1000000-0000-4000-8000-000000000001';
const _driverId = 'b1000000-0000-4000-8000-000000000001';
const _tripId = 'c1000000-0000-4000-8000-000000000001';

void main() {
  group('P7-D06 fake-backed Realtime and GPS handoff', () {
    late _IntegrationHarness harness;

    setUp(() {
      harness = _IntegrationHarness();
    });

    tearDown(() async {
      await harness.dispose();
    });

    test(
      'verifies ordered Trip state, publishes GPS, recovers missed data, and clears terminal state',
      () async {
        final tripUpdates = _EventLog<TripRealtimeUpdate>();
        final riderUpdates = _EventLog<RiderTripLocationUpdate>();
        final tripSubscription = harness.trips
            .watchTrip(_tripId)
            .listen(tripUpdates.add, onError: tripUpdates.addError);
        final riderSubscription = harness.riderLocations
            .watchTrip(_tripId)
            .listen(riderUpdates.add, onError: riderUpdates.addError);

        harness.subscriptions.add(tripSubscription.cancel);
        harness.subscriptions.add(riderSubscription.cancel);

        final initial = await tripUpdates.waitFor((update) =>
            update is VerifiedTripRealtimeEvent &&
            update.cause == TripRealtimeEventCause.initialCanonicalRead);
        expect(
          (initial as VerifiedTripRealtimeEvent).trip.status,
          DriverTripLifecycleStatus.accepted,
        );
        await riderUpdates.waitFor((update) =>
            update is RiderTripLocationConnectionUpdate &&
            update.status == RiderTripLocationChannelStatus.subscribed);
        await harness.locationSource.waitForWatchCount(1);
        await harness.locationSource.waitForReadCount(1);

        harness.tripSource.setTrip(
          status: DriverTripLifecycleStatus.driverArriving,
          version: 2,
          statusSequence: 1,
        );
        await tripUpdates.waitFor((update) =>
            update is VerifiedTripRealtimeEvent &&
            update.trip.status == DriverTripLifecycleStatus.driverArriving);

        harness.tripSource.setTrip(
          status: DriverTripLifecycleStatus.driverArrived,
          version: 3,
          statusSequence: 2,
        );
        await tripUpdates.waitFor((update) =>
            update is VerifiedTripRealtimeEvent &&
            update.trip.status == DriverTripLifecycleStatus.driverArrived);

        // These notifications arrive after sequence 2 and must not replay an
        // older status or replace the canonical snapshot.
        harness.tripSource.emitStatusSignal(1);
        harness.tripSource.emitStatusSignal(2);
        harness.tripSource.setTrip(
          status: DriverTripLifecycleStatus.inProgress,
          version: 4,
          statusSequence: 3,
        );
        await tripUpdates.waitFor((update) =>
            update is VerifiedTripRealtimeEvent &&
            update.trip.status == DriverTripLifecycleStatus.inProgress);

        expect(
          tripUpdates.events
              .whereType<VerifiedTripRealtimeEvent>()
              .where((update) =>
                  update.cause != TripRealtimeEventCause.connectionRestored)
              .map((update) => update.trip.status),
          [
            DriverTripLifecycleStatus.accepted,
            DriverTripLifecycleStatus.driverArriving,
            DriverTripLifecycleStatus.driverArrived,
            DriverTripLifecycleStatus.inProgress,
          ],
        );

        // D02 treats channel notifications as hints and rereads canonical Trip
        // state after the channel rejoins.
        final tripReadsBeforeReconnect = harness.tripSource.readCount;
        harness.tripSource.emitChannel(TripRealtimeChannelStatus.channelError);
        await tripUpdates.waitFor((update) =>
            update is TripRealtimeConnectionUpdate &&
            update.status == TripRealtimeChannelStatus.channelError);
        harness.tripSource.emitChannel(TripRealtimeChannelStatus.subscribed);
        final recoveredTrip = await tripUpdates.waitFor((update) =>
            update is VerifiedTripRealtimeEvent &&
            update.cause == TripRealtimeEventCause.connectionRestored);
        expect(
          (recoveredTrip as VerifiedTripRealtimeEvent).trip.status,
          DriverTripLifecycleStatus.inProgress,
        );
        expect(
          harness.tripSource.readCount,
          greaterThan(tripReadsBeforeReconnect),
        );

        await harness.startDriverTracking();
        harness.gps.emit(_fix(harness.clock.now, latitude: 31.95));
        await harness.locationService.waitForRecordCount(1);
        final firstLocation = await riderUpdates.waitFor((update) =>
            update is RiderTripLocationSnapshot &&
            update.location.sequence == 1);
        final firstSnapshot = firstLocation as RiderTripLocationSnapshot;
        expect(firstSnapshot.location.tripId, _tripId);
        expect(firstSnapshot.location.driverId, _driverId);

        // Hold a duplicate notification's canonical read at sequence 1. The
        // actual Phase 4 publisher then writes sequence 2; the adapter must
        // reject the stale read and reread the newest canonical row.
        final firstCanonicalLocation = harness.locationSource.latest!;
        final snapshotsBeforeDuplicate = riderUpdates.events
            .whereType<RiderTripLocationSnapshot>()
            .toList(growable: false);
        final readsBeforeDuplicate = harness.locationSource.readCount;
        final staleReadGate = Completer<void>();
        harness.locationSource.nextReadGate = staleReadGate;
        harness.locationSource.emitLocationChanged(_tripId, _driverId);
        await harness.locationSource.waitForReadCount(readsBeforeDuplicate + 1);

        harness.clock.advance(const Duration(seconds: 16));
        harness.gps.emit(_fix(harness.clock.now, latitude: 31.9502));
        await harness.locationService.waitForRecordCount(2);
        staleReadGate.complete();

        final secondLocation = await riderUpdates.waitFor((update) =>
            update is RiderTripLocationSnapshot &&
            update.location.sequence == 2);
        expect(
          (secondLocation as RiderTripLocationSnapshot).location.sequence,
          2,
        );
        expect(
          riderUpdates.events
              .whereType<RiderTripLocationSnapshot>()
              .map((update) => update.location.sequence),
          [1, 2],
        );
        expect(firstCanonicalLocation.sequence, 1);
        expect(snapshotsBeforeDuplicate.map((update) => update.location.sequence), [1]);

        // The stream is disconnected while a third real publisher update is
        // persisted. No event is delivered during the gap; the bounded retry
        // reconnect must recover it using the source's canonical reread.
        harness.locationSource.emitChannel(
          RiderTripLocationChannelStatus.channelError,
        );
        await riderUpdates.waitFor((update) =>
            update is RiderTripLocationConnectionUpdate &&
            update.status == RiderTripLocationChannelStatus.channelError);
        await riderUpdates.waitFor((update) =>
            update is RiderTripLocationCleared &&
            update.reason == RiderTripLocationClearReason.staleLocation);
        await harness.retryDelay.waitForCount(1);

        harness.clock.advance(const Duration(seconds: 16));
        harness.gps.emit(_fix(harness.clock.now, latitude: 31.9504));
        await harness.locationService.waitForRecordCount(3);
        expect(harness.locationSource.isConnected, isFalse);
        harness.retryDelay.releaseNext();

        await harness.locationSource.waitForWatchCount(2);
        final recoveredLocation = await riderUpdates.waitFor((update) =>
            update is RiderTripLocationSnapshot &&
            update.location.sequence == 3);
        expect(
          (recoveredLocation as RiderTripLocationSnapshot).location.point.latitude,
          closeTo(31.9504, 0.000001),
        );
        expect(harness.locationSource.maximumActiveSubscriptions, 1);

        // A delayed old canonical row cannot move the Rider's view backwards.
        harness.locationSource.latest = firstCanonicalLocation;
        final readsBeforeOutOfOrderRead = harness.locationSource.readCount;
        harness.locationSource.emitLocationChanged(_tripId, _driverId);
        await harness.locationSource.waitForReadCount(readsBeforeOutOfOrderRead + 1);
        // A subsequent verified Trip event is the deterministic completion
        // barrier for D02's serialized signal queue.
        harness.tripSource.setTrip(
          status: DriverTripLifecycleStatus.completed,
          version: 5,
          statusSequence: 4,
        );
        await tripUpdates.waitFor((update) =>
            update is VerifiedTripRealtimeEvent &&
            update.trip.status == DriverTripLifecycleStatus.completed);
        await riderUpdates.waitFor((update) =>
            update is RiderTripLocationCleared &&
            update.reason == RiderTripLocationClearReason.terminalTrip);

        expect(
          riderUpdates.events
              .whereType<RiderTripLocationSnapshot>()
              .map((update) => update.location.sequence),
          [1, 2, 3],
        );

        await harness.stopDriverTracking();
        await riderSubscription.cancel();
        await tripSubscription.cancel();
        expect(harness.locationSource.activeSubscriptions, 0);
        expect(harness.tripSource.activeSubscriptions, 0);
        expect(harness.gps.activeSubscriptions, 0);
      },
    );

    test('session replacement clears Rider state and cancels both adapters',
        () async {
      final riderUpdates = _EventLog<RiderTripLocationUpdate>();
      final subscription = harness.riderLocations
          .watchTrip(_tripId)
          .listen(riderUpdates.add, onError: riderUpdates.addError);
      harness.subscriptions.add(subscription.cancel);

      await riderUpdates.waitFor((update) =>
          update is RiderTripLocationConnectionUpdate &&
          update.status == RiderTripLocationChannelStatus.subscribed);
      await harness.locationSource.waitForReadCount(1);

      harness.session.identity = Object();
      harness.tripSource.emitSessionChanged();

      await riderUpdates.waitFor((update) =>
          update is RiderTripLocationCleared &&
          update.reason == RiderTripLocationClearReason.sessionChanged);
      expect(harness.locationSource.activeSubscriptions, 0);
      expect(harness.tripSource.activeSubscriptions, 0);
    });

    test('logout clears Rider state and cancels both adapters', () async {
      final riderUpdates = _EventLog<RiderTripLocationUpdate>();
      final subscription = harness.riderLocations
          .watchTrip(_tripId)
          .listen(riderUpdates.add, onError: riderUpdates.addError);
      harness.subscriptions.add(subscription.cancel);

      await riderUpdates.waitFor((update) =>
          update is RiderTripLocationConnectionUpdate &&
          update.status == RiderTripLocationChannelStatus.subscribed);
      await harness.locationSource.waitForReadCount(1);

      harness.session.userId = null;
      harness.tripSource.emitSessionChanged();

      await riderUpdates.waitFor((update) =>
          update is RiderTripLocationCleared &&
          update.reason == RiderTripLocationClearReason.sessionChanged);
      expect(harness.locationSource.activeSubscriptions, 0);
      expect(harness.tripSource.activeSubscriptions, 0);
    });

    test('consumer cancellation releases Trip and location source streams',
        () async {
      final riderUpdates = _EventLog<RiderTripLocationUpdate>();
      final subscription = harness.riderLocations
          .watchTrip(_tripId)
          .listen(riderUpdates.add, onError: riderUpdates.addError);

      await riderUpdates.waitFor((update) =>
          update is RiderTripLocationConnectionUpdate &&
          update.status == RiderTripLocationChannelStatus.subscribed);
      await harness.locationSource.waitForReadCount(1);
      expect(harness.locationSource.activeSubscriptions, 1);
      expect(harness.tripSource.activeSubscriptions, 1);

      await subscription.cancel();

      expect(harness.locationSource.activeSubscriptions, 0);
      expect(harness.locationSource.cancelCount, 1);
      expect(harness.tripSource.activeSubscriptions, 0);
      expect(harness.tripSource.cancelCount, 1);
    });
  });
}

DriverLocationFix _fix(DateTime time, {required double latitude}) =>
    DriverLocationFix(
      point: LocationPoint(
        latitude: latitude,
        longitude: 35.93,
        accuracyMeters: 5,
      ),
      recordedAt: time,
    );

final class _IntegrationHarness {
  _IntegrationHarness() {
    tripSource = _FakeTripRealtimeSource(session: session);
    locationSource = _FakeRiderTripLocationSource(session: session);
    trips = TripRealtimeAdapter(tripSource);
    riderLocations = RiderTripLocationAdapter(
      trips: trips,
      locations: locationSource,
      clock: () => clock.now,
      delay: retryDelay.call,
    );
    locationService = _FakeDriverLocationService(
      locations: locationSource,
      clock: clock,
    );
    gps = _FakeDriverGpsStreamService();
    lifecycle = _FakeDriverTrackingLifecycle();
    container = ProviderContainer(
      overrides: [
        driverLocationRepositoryProvider.overrideWithValue(
          ServiceDriverLocationRepository(locationService),
        ),
        driverGpsStreamServiceProvider.overrideWithValue(gps),
        driverTrackingLifecycleProvider.overrideWithValue(lifecycle),
        driverTrackingConnectionProvider.overrideWithValue(
          const NoopDriverTrackingConnection(),
        ),
        appErrorReporterProvider.overrideWithValue(RecordingAppErrorReporter()),
        driverTrackingClockProvider.overrideWithValue(() => clock.now),
      ],
    );
    keepAlive = container.listen(driverTrackingControllerProvider, (_, __) {});
  }

  final session = _FakeSession();
  final clock = _ManualClock(DateTime.utc(2026, 11, 5, 12));
  final retryDelay = _ControlledRetryDelay();
  final subscriptions = <Future<void> Function()>[];
  late final _FakeTripRealtimeSource tripSource;
  late final _FakeRiderTripLocationSource locationSource;
  late final TripRealtimeAdapter trips;
  late final RiderTripLocationAdapter riderLocations;
  late final _FakeDriverLocationService locationService;
  late final _FakeDriverGpsStreamService gps;
  late final _FakeDriverTrackingLifecycle lifecycle;
  late final ProviderContainer container;
  late final ProviderSubscription<DriverTrackingState> keepAlive;

  Future<void> startDriverTracking() =>
      container.read(driverTrackingControllerProvider.notifier).start();

  Future<void> stopDriverTracking() =>
      container.read(driverTrackingControllerProvider.notifier).stop();

  Future<void> dispose() async {
    for (final cancel in subscriptions) {
      await cancel();
    }
    await stopDriverTracking();
    keepAlive.close();
    container.dispose();
    await lifecycle.close();
    await gps.close();
    await tripSource.close();
  }
}

final class _FakeSession {
  String? userId = _riderId;
  Object? identity = Object();
}

final class _FakeTripRealtimeSource implements TripRealtimeSource {
  _FakeTripRealtimeSource({required this.session});

  final _FakeSession session;
  final _consumers = <MultiStreamController<TripRealtimeSourceSignal>>[];
  TripRealtimeTrip canonicalTrip = TripRealtimeTrip(
    tripId: _tripId,
    riderId: _riderId,
    driverId: _driverId,
    status: DriverTripLifecycleStatus.accepted,
    version: 1,
  );
  int readCount = 0;
  int activeSubscriptions = 0;
  int maximumActiveSubscriptions = 0;
  int cancelCount = 0;

  @override
  String? get authenticatedUserId => session.userId;

  @override
  Object? get authenticatedSessionIdentity => session.identity;

  @override
  Stream<TripRealtimeSourceSignal> watchTrip(String tripId) =>
      Stream<TripRealtimeSourceSignal>.multi((controller) {
        activeSubscriptions++;
        if (activeSubscriptions > maximumActiveSubscriptions) {
          maximumActiveSubscriptions = activeSubscriptions;
        }
        _consumers.add(controller);
        controller.add(
          const TripRealtimeChannelSignal(TripRealtimeChannelStatus.connecting),
        );
        controller.add(
          const TripRealtimeChannelSignal(TripRealtimeChannelStatus.subscribed),
        );
        controller.onCancel = () {
          _consumers.remove(controller);
          activeSubscriptions--;
          cancelCount++;
        };
      }, isBroadcast: false);

  @override
  Future<TripRealtimeTrip?> readCanonicalTrip(String tripId) async {
    readCount++;
    if (tripId.toLowerCase() != _tripId) return null;
    return canonicalTrip;
  }

  void setTrip({
    required DriverTripLifecycleStatus status,
    required int version,
    required int statusSequence,
    bool notify = true,
  }) {
    canonicalTrip = TripRealtimeTrip(
      tripId: _tripId,
      riderId: _riderId,
      driverId: _driverId,
      status: status,
      version: version,
    );
    if (notify) emitStatusSignal(statusSequence);
  }

  void emitStatusSignal(int sequence) => _emit(
        TripRealtimeChangeSignal(
          tripId: _tripId,
          source: TripRealtimeChangeSource.statusHistory,
          statusEventSequence: sequence,
        ),
      );

  void emitChannel(TripRealtimeChannelStatus status) =>
      _emit(TripRealtimeChannelSignal(status));

  void emitSessionChanged() =>
      _emit(const TripRealtimeSessionChangedSignal());

  void _emit(TripRealtimeSourceSignal signal) {
    for (final consumer in List<MultiStreamController<TripRealtimeSourceSignal>>.of(
      _consumers,
    )) {
      consumer.add(signal);
    }
  }

  Future<void> close() async {
    for (final consumer in List<MultiStreamController<TripRealtimeSourceSignal>>.of(
      _consumers,
    )) {
      await consumer.close();
    }
  }
}

final class _FakeRiderTripLocationSource implements RiderTripLocationSource {
  _FakeRiderTripLocationSource({required this.session});

  final _FakeSession session;
  final _consumers = <MultiStreamController<RiderTripLocationSourceSignal>>[];
  final _watchWaiters = <int, Completer<void>>{};
  final _readWaiters = <int, Completer<void>>{};
  final _cancelWaiters = <int, Completer<void>>{};
  RiderTripLocation? latest;
  Completer<void>? nextReadGate;
  int watchCount = 0;
  int readCount = 0;
  int activeSubscriptions = 0;
  int maximumActiveSubscriptions = 0;
  int cancelCount = 0;
  bool isConnected = false;

  @override
  String? get authenticatedUserId => session.userId;

  @override
  Object? get authenticatedSessionIdentity => session.identity;

  @override
  Stream<RiderTripLocationSourceSignal> watchTripLocation(String tripId) =>
      Stream<RiderTripLocationSourceSignal>.multi((controller) {
        watchCount++;
        activeSubscriptions++;
        if (activeSubscriptions > maximumActiveSubscriptions) {
          maximumActiveSubscriptions = activeSubscriptions;
        }
        _consumers.add(controller);
        isConnected = true;
        controller.add(
          const RiderTripLocationChannelSignal(
            RiderTripLocationChannelStatus.connecting,
          ),
        );
        controller.add(
          const RiderTripLocationChannelSignal(
            RiderTripLocationChannelStatus.subscribed,
          ),
        );
        _completeReached(_watchWaiters, watchCount);
        controller.onCancel = () {
          _consumers.remove(controller);
          activeSubscriptions--;
          cancelCount++;
          isConnected = false;
          _completeReached(_cancelWaiters, cancelCount);
        };
      }, isBroadcast: false);

  @override
  Future<RiderTripLocation?> readLatestTripLocation({
    required String tripId,
    required String driverId,
  }) async {
    readCount++;
    final result = tripId.toLowerCase() == _tripId &&
            driverId.toLowerCase() == _driverId
        ? latest
        : null;
    _completeReached(_readWaiters, readCount);
    final gate = nextReadGate;
    nextReadGate = null;
    if (gate != null) await gate.future;
    return result;
  }

  Future<void> waitForWatchCount(int count) =>
      _waitForCount(watchCount, count, _watchWaiters);

  Future<void> waitForReadCount(int count) =>
      _waitForCount(readCount, count, _readWaiters);

  Future<void> waitForCancelCount(int count) =>
      _waitForCount(cancelCount, count, _cancelWaiters);

  void setLatest(RiderTripLocation location, {bool notify = true}) {
    latest = location;
    if (notify && isConnected) {
      emitLocationChanged(location.tripId, location.driverId);
    }
  }

  void emitLocationChanged(String tripId, String driverId) {
    if (!isConnected) return;
    _emit(RiderTripLocationChangedSignal(
      tripId: tripId,
      driverId: driverId,
    ));
  }

  void emitChannel(RiderTripLocationChannelStatus status) {
    isConnected = status == RiderTripLocationChannelStatus.subscribed;
    _emit(RiderTripLocationChannelSignal(status));
  }

  void _emit(RiderTripLocationSourceSignal signal) {
    for (final consumer
        in List<MultiStreamController<RiderTripLocationSourceSignal>>.of(
      _consumers,
    )) {
      consumer.add(signal);
    }
  }

  Future<void> _waitForCount(
    int current,
    int target,
    Map<int, Completer<void>> waiters,
  ) {
    if (current >= target) return Future<void>.value();
    final completer = Completer<void>();
    waiters[target] = completer;
    return completer.future;
  }

  void _completeReached(Map<int, Completer<void>> waiters, int current) {
    final reached = waiters.keys.where((target) => current >= target).toList();
    for (final target in reached) {
      waiters.remove(target)!.complete();
    }
  }
}

final class _FakeDriverLocationService implements DriverLocationService {
  _FakeDriverLocationService({required this.locations, required this.clock});

  final _FakeRiderTripLocationSource locations;
  final _ManualClock clock;
  final _recordWaiters = <int, Completer<void>>{};
  final published = <DriverLocationSample>[];
  DriverAvailability? availability = const DriverAvailability(
    state: DriverAvailabilityState.onTrip,
    activeTripId: _tripId,
  );
  SavedDriverLocation? latest;

  @override
  Future<DriverAvailability?> fetchAvailability() async => availability;

  @override
  Future<SavedDriverLocation?> fetchLatestLocation() async => latest;

  @override
  Future<SavedDriverLocation> recordLocation(
    DriverLocationSample sample,
  ) async {
    published.add(sample);
    final receivedAt = clock.now;
    final saved = SavedDriverLocation(
      point: sample.point,
      sequence: sample.sequence,
      recordedAt: sample.recordedAt,
      receivedAt: receivedAt,
      tripId: sample.tripId,
      headingDegrees: sample.headingDegrees,
      speedMetersPerSecond: sample.speedMetersPerSecond,
    );
    latest = saved;
    final tripId = sample.tripId;
    if (tripId == null || tripId.toLowerCase() != _tripId) {
      throw StateError('The D03 publisher must include the active Trip ID.');
    }
    locations.setLatest(
      RiderTripLocation(
        tripId: tripId,
        driverId: _driverId,
        sequence: sample.sequence,
        point: sample.point,
        recordedAt: sample.recordedAt,
        receivedAt: receivedAt,
        headingDegrees: sample.headingDegrees,
        speedMetersPerSecond: sample.speedMetersPerSecond,
      ),
    );
    final reached = _recordWaiters.keys
        .where((count) => published.length >= count)
        .toList();
    for (final count in reached) {
      _recordWaiters.remove(count)!.complete();
    }
    return saved;
  }

  Future<void> waitForRecordCount(int count) {
    if (published.length >= count) return Future<void>.value();
    final completer = Completer<void>();
    _recordWaiters[count] = completer;
    return completer.future;
  }
}

final class _FakeDriverGpsStreamService implements DriverGpsStreamService {
  final configurations = <DriverGpsTrackingConfig>[];
  StreamController<DriverLocationFix>? _fixes;
  int activeSubscriptions = 0;
  int maximumActiveSubscriptions = 0;
  int cancelCount = 0;

  @override
  Stream<DriverLocationFix> foregroundFixes(
    DriverGpsTrackingConfig config,
  ) {
    configurations.add(config);
    final controller = StreamController<DriverLocationFix>.broadcast(
      sync: true,
      onListen: () {
        activeSubscriptions++;
        if (activeSubscriptions > maximumActiveSubscriptions) {
          maximumActiveSubscriptions = activeSubscriptions;
        }
      },
      onCancel: () {
        activeSubscriptions--;
        cancelCount++;
      },
    );
    _fixes = controller;
    return controller.stream;
  }

  void emit(DriverLocationFix fix) => _fixes!.add(fix);

  Future<void> close() async {
    final controller = _fixes;
    if (controller != null) await controller.close();
  }
}

final class _FakeDriverTrackingLifecycle implements DriverTrackingLifecycle {
  final _changes = StreamController<DriverTrackingLifecycleState>.broadcast();

  @override
  Stream<DriverTrackingLifecycleState> get changes => _changes.stream;

  @override
  void dispose() {
    unawaited(_changes.close());
  }

  Future<void> close() => _changes.close();
}

final class _ManualClock {
  _ManualClock(this.now);

  DateTime now;

  void advance(Duration duration) {
    now = now.add(duration);
  }
}

final class _ControlledRetryDelay {
  final durations = <Duration>[];
  final _gates = <Completer<void>>[];
  final _waiters = <int, Completer<void>>{};

  Future<void> call(Duration duration) {
    durations.add(duration);
    final gate = Completer<void>();
    _gates.add(gate);
    _completeReached(durations.length);
    return gate.future;
  }

  Future<void> waitForCount(int count) {
    if (durations.length >= count) return Future<void>.value();
    final completer = Completer<void>();
    _waiters[count] = completer;
    return completer.future;
  }

  void releaseNext() => _gates.removeAt(0).complete();

  void _completeReached(int current) {
    final reached = _waiters.keys.where((count) => current >= count).toList();
    for (final count in reached) {
      _waiters.remove(count)!.complete();
    }
  }
}

final class _EventLog<T> {
  final events = <T>[];
  final errors = <Object>[];
  final _waiters = <_EventWaiter<T>>[];

  void add(T event) {
    events.add(event);
    final completed = <_EventWaiter<T>>[];
    for (final waiter in _waiters) {
      if (waiter.predicate(event)) {
        waiter.completer.complete(event);
        completed.add(waiter);
      }
    }
    _waiters.removeWhere(completed.contains);
  }

  void addError(Object error, [StackTrace? stackTrace]) {
    errors.add(error);
  }

  Future<T> waitFor(bool Function(T event) predicate) {
    for (final event in events) {
      if (predicate(event)) return Future<T>.value(event);
    }
    final completer = Completer<T>();
    _waiters.add(_EventWaiter(predicate, completer));
    return completer.future;
  }
}

final class _EventWaiter<T> {
  _EventWaiter(this.predicate, this.completer);

  final bool Function(T event) predicate;
  final Completer<T> completer;
}
