import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/providers/driver_tracking_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/repositories/driver_location_repository.dart';
import 'package:ridex/core/services/driver_location/driver_gps_stream_service.dart';
import 'package:ridex/core/services/driver_location/driver_tracking_connection.dart';

void main() {
  final startTime = DateTime.utc(2026, 9, 17, 10);

  late FakeTrackingRepository repository;
  late FakeDriverGpsStreamService gps;
  late FakeDriverTrackingLifecycle lifecycle;
  late FakeDriverTrackingConnection connection;
  late ProviderContainer container;
  late ProviderSubscription<DriverTrackingState> keepAlive;

  setUp(() {
    repository = FakeTrackingRepository();
    gps = FakeDriverGpsStreamService();
    lifecycle = FakeDriverTrackingLifecycle();
    connection = FakeDriverTrackingConnection();
    container = ProviderContainer(
      overrides: [
        driverLocationRepositoryProvider.overrideWithValue(repository),
        driverGpsStreamServiceProvider.overrideWithValue(gps),
        driverTrackingLifecycleProvider.overrideWithValue(lifecycle),
        driverTrackingConnectionProvider.overrideWithValue(connection),
      ],
    );
    keepAlive = container.listen(driverTrackingControllerProvider, (_, __) {});
  });

  tearDown(() async {
    await container.read(driverTrackingControllerProvider.notifier).stop();
    keepAlive.close();
    container.dispose();
  });

  test('does not start when canonical availability is ineligible', () async {
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.offline,
    );
    final controller =
        container.read(driverTrackingControllerProvider.notifier);

    await controller.start();

    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.unavailable);
    expect(repository.latestCount, 0);
    expect(gps.listenCount, 0);
  });

  test('starts after canonical reads and stops the owned stream', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);

    await controller.start();
    expect(repository.availabilityCount, 1);
    expect(repository.latestCount, 1);
    expect(gps.listenCount, 1);
    expect(gps.configurations.single, same(DriverGpsTrackingConfig.reduced));
    expect(gps.maxActiveSubscriptions, 1);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.sharing);

    await controller.stop();

    expect(gps.cancelCount, 1);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.stopped);
  });

  test('connection startup failure cancels the foreground stream', () async {
    connection.connectError = StateError('connection failed');
    final controller =
        container.read(driverTrackingControllerProvider.notifier);

    await controller.start();

    final state = container.read(driverTrackingControllerProvider);
    expect(state.status, DriverTrackingStatus.unavailable);
    expect(state.failure, DriverLocationFailure.unavailable);
    expect(gps.cancelCount, 1);
    expect(connection.disconnectCount, 1);
  });

  test('includes the canonical active trip when publishing onTrip fixes',
      () async {
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.onTrip,
      activeTripId: 'trip-1',
    );
    final controller =
        container.read(driverTrackingControllerProvider.notifier);

    await controller.start();
    expect(
      gps.configurations.single,
      same(DriverGpsTrackingConfig.activeTrip),
    );
    gps.add(_fix(startTime.add(const Duration(seconds: 1))));
    await repository.waitForPublishes(1);

    expect(repository.published.single.tripId, 'trip-1');
  });

  test('stop invalidates a pending start before it can open a stream',
      () async {
    final availability = Completer<DriverAvailability?>();
    repository.availabilityResult = availability.future;
    final controller =
        container.read(driverTrackingControllerProvider.notifier);

    final start = controller.start();
    await Future<void>.delayed(Duration.zero);
    await controller.stop();
    availability.complete(repository.availability);
    await start;

    expect(gps.listenCount, 0);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.stopped);
  });

  test('ignores duplicate starts and owns one stream', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);

    await Future.wait([controller.start(), controller.start()]);

    expect(repository.availabilityCount, 1);
    expect(repository.latestCount, 1);
    expect(gps.listenCount, 1);
    expect(gps.maxActiveSubscriptions, 1);
  });

  test('uses reduced tracking while canonically reserved', () async {
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.reserved,
    );
    final controller =
        container.read(driverTrackingControllerProvider.notifier);

    await controller.start();

    expect(gps.configurations.single, same(DriverGpsTrackingConfig.reduced));
  });

  test('accepts available fixes no more often than every 20 seconds', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final first = _fix(startTime.add(const Duration(seconds: 1)));
    final tooSoon = _fix(
      startTime.add(const Duration(seconds: 20)),
      latitude: 31.963258,
    );
    final due = _fix(
      startTime.add(const Duration(seconds: 21)),
      latitude: 31.963358,
    );

    gps.add(first);
    await repository.waitForPublishes(1);
    gps.add(tooSoon);
    await flush(2);
    expect(repository.publishAttempts, 1);
    gps.add(due);
    await repository.waitForPublishes(2);

    expect(repository.published.map((sample) => sample.recordedAt), [
      first.recordedAt,
      due.recordedAt,
    ]);
  });

  test('accepts onTrip fixes no more often than every 5 seconds', () async {
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.onTrip,
      activeTripId: 'trip-1',
    );
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final first = _fix(startTime.add(const Duration(seconds: 1)));
    final tooSoon = _fix(
      startTime.add(const Duration(seconds: 5)),
      latitude: 31.963258,
    );
    final due = _fix(
      startTime.add(const Duration(seconds: 6)),
      latitude: 31.963358,
    );

    gps.add(first);
    await repository.waitForPublishes(1);
    gps.add(tooSoon);
    await flush(2);
    expect(repository.publishAttempts, 1);
    gps.add(due);
    await repository.waitForPublishes(2);

    expect(repository.published.map((sample) => sample.recordedAt), [
      first.recordedAt,
      due.recordedAt,
    ]);
  });

  test('keeps one reduced stream across available to reserved sync', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.reserved,
    );

    await controller.synchronizeCanonicalState();

    expect(repository.availabilityCount, 2);
    expect(gps.listenCount, 1);
    expect(gps.cancelCount, 0);
    expect(gps.maxActiveSubscriptions, 1);
  });

  test('runs a pending canonical sync after initial start completes', () async {
    final availability = Completer<DriverAvailability?>();
    final latest = Completer<SavedDriverLocation?>();
    repository.availabilityResult = availability.future;
    repository.latestResult = latest.future;
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    final start = controller.start();
    await flush();
    availability.complete(
      const DriverAvailability(state: DriverAvailabilityState.available),
    );
    await flush(2);
    repository.availabilityResult = null;
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.onTrip,
      activeTripId: 'trip-1',
    );

    await controller.synchronizeCanonicalState();
    repository.latestResult = null;
    latest.complete(null);
    await start;
    await flush(4);

    expect(repository.availabilityCount, 2);
    expect(gps.configurations, [
      DriverGpsTrackingConfig.reduced,
      DriverGpsTrackingConfig.activeTrip,
    ]);
    expect(gps.maxActiveSubscriptions, 1);
  });

  test('replaces reduced tracking with one active-trip stream', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.onTrip,
      activeTripId: 'trip-1',
    );

    await controller.synchronizeCanonicalState();

    expect(gps.configurations, [
      same(DriverGpsTrackingConfig.reduced),
      same(DriverGpsTrackingConfig.activeTrip),
    ]);
    expect(gps.cancelCount, 1);
    expect(gps.maxActiveSubscriptions, 1);
    expect(connection.connectCount, 1);

    gps.add(_fix(startTime.add(const Duration(seconds: 1))));
    await repository.waitForPublishes(1);
    expect(repository.published.single.tripId, 'trip-1');
  });

  test('replaces active-trip tracking with one reduced stream', () async {
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.onTrip,
      activeTripId: 'trip-1',
    );
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.available,
    );

    await controller.synchronizeCanonicalState();

    expect(gps.configurations, [
      same(DriverGpsTrackingConfig.activeTrip),
      same(DriverGpsTrackingConfig.reduced),
    ]);
    expect(gps.cancelCount, 1);
    expect(gps.maxActiveSubscriptions, 1);
    expect(connection.connectCount, 1);
  });

  test('coalesces concurrent syncs with one trailing canonical read', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final availability = Completer<DriverAvailability?>();
    repository.availabilityResult = availability.future;

    final first = controller.synchronizeCanonicalState();
    final second = controller.synchronizeCanonicalState();
    await flush();
    availability.complete(
      const DriverAvailability(
        state: DriverAvailabilityState.onTrip,
        activeTripId: 'trip-1',
      ),
    );
    repository.availabilityResult = null;
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.reserved,
    );
    await Future.wait([first, second]);

    expect(repository.availabilityCount, 3);
    expect(gps.configurations, [
      DriverGpsTrackingConfig.reduced,
      DriverGpsTrackingConfig.activeTrip,
      DriverGpsTrackingConfig.reduced,
    ]);
    expect(gps.listenCount, 3);
    expect(gps.maxActiveSubscriptions, 1);
  });

  test('queues a trailing canonical sync while replacing the stream', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.onTrip,
      activeTripId: 'trip-1',
    );
    final cancellation = Completer<void>();
    gps.cancelGate = cancellation.future;

    final first = controller.synchronizeCanonicalState();
    await flush(2);
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.reserved,
    );
    final second = controller.synchronizeCanonicalState();
    cancellation.complete();
    await Future.wait([first, second]);

    expect(repository.availabilityCount, 3);
    expect(gps.configurations, [
      DriverGpsTrackingConfig.reduced,
      DriverGpsTrackingConfig.activeTrip,
      DriverGpsTrackingConfig.reduced,
    ]);
    expect(gps.maxActiveSubscriptions, 1);
  });

  test('defers reconnect recovery until canonical sync completes', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final availability = Completer<DriverAvailability?>();
    repository.availabilityResult = availability.future;
    final synchronization = controller.synchronizeCanonicalState();
    await flush();

    connection.emit(DriverTrackingConnectionStatus.channelError);
    connection.emit(DriverTrackingConnectionStatus.subscribed);
    await flush(2);
    repository.availabilityResult = null;
    availability.complete(repository.availability);
    await synchronization;
    await flush(5);

    expect(repository.availabilityCount, 3);
    expect(repository.latestCount, 2);
    expect(gps.listenCount, 2);
    expect(gps.maxActiveSubscriptions, 1);
    expect(connection.connectCount, 2);
  });

  test('runs a pending canonical sync after recovery completes', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final availability = Completer<DriverAvailability?>();
    repository.availabilityResult = availability.future;
    final recovery = controller.recoverAfterConnectivity();
    await flush(2);

    await controller.synchronizeCanonicalState();
    repository.availabilityResult = null;
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.onTrip,
      activeTripId: 'trip-1',
    );
    availability.complete(
      const DriverAvailability(state: DriverAvailabilityState.available),
    );
    await recovery;
    await flush(4);

    expect(repository.availabilityCount, 3);
    expect(repository.latestCount, 2);
    expect(gps.configurations, [
      DriverGpsTrackingConfig.reduced,
      DriverGpsTrackingConfig.reduced,
      DriverGpsTrackingConfig.activeTrip,
    ]);
    expect(gps.maxActiveSubscriptions, 1);
  });

  test('does not automatically stop tracking for an offline sync', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.offline,
    );

    await controller.synchronizeCanonicalState();

    expect(gps.listenCount, 1);
    expect(gps.cancelCount, 0);
    expect(gps.activeSubscriptions, 1);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.sharing);
  });

  test('exposes replacement failure and allows a later canonical retry',
      () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    repository.availability = const DriverAvailability(
      state: DriverAvailabilityState.onTrip,
      activeTripId: 'trip-1',
    );
    gps.foregroundError = StateError('provider');

    await controller.synchronizeCanonicalState();

    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.unavailable);
    expect(gps.activeSubscriptions, 0);

    gps.foregroundError = null;
    await controller.synchronizeCanonicalState();

    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.sharing);
    expect(gps.activeSubscriptions, 1);
    expect(gps.maxActiveSubscriptions, 1);
    expect(gps.configurations.last, same(DriverGpsTrackingConfig.activeTrip));
  });

  test('publishes valid fixes sequentially after the saved maximum', () async {
    repository.latest = _saved(7, startTime);
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final first = _fix(
      startTime.add(const Duration(seconds: 20)),
      latitude: 31.963258,
    );
    final second = _fix(
      startTime.add(const Duration(seconds: 40)),
      latitude: 31.963358,
    );

    gps.add(first);
    await repository.waitForAttempts(1);
    gps.add(second);
    await repository.waitForPublishes(2);

    expect(repository.published.map((sample) => sample.sequence), [8, 9]);
    expect(repository.maxConcurrentPublishes, 1);
  });

  test('ignores missing-accuracy and stale fixes', () async {
    repository.latest = _saved(3, startTime);
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final missingAccuracy = DriverLocationFix(
      point: LocationPoint(latitude: 1, longitude: 2),
      recordedAt: startTime.add(const Duration(seconds: 1)),
    );

    gps.add(missingAccuracy);
    gps.add(_fix(startTime));
    gps.add(_fix(
      startTime.add(const Duration(seconds: 20)),
      latitude: 31.963258,
    ));
    await repository.waitForPublishes(1);

    expect(repository.published.map((sample) => sample.sequence), [4]);
  });

  test('ignores a fix with the same timestamp as the latest accepted fix',
      () async {
    repository.latest = _saved(3, startTime);
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();

    gps.add(_fix(startTime));
    await Future<void>.delayed(Duration.zero);

    expect(repository.publishAttempts, 0);
    expect(repository.published, isEmpty);
  });

  test('does not publish duplicate location content', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();

    gps.add(_fix(startTime.add(const Duration(seconds: 1))));
    await repository.waitForPublishes(1);
    gps.add(_fix(startTime.add(const Duration(seconds: 21))));
    await flush(2);

    expect(repository.publishAttempts, 1);
    expect(repository.published, hasLength(1));
  });

  test('coalesces queued fixes to the latest location', () async {
    final publishGate = Completer<void>();
    repository.publishGate = publishGate.future;
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();

    final first = _fix(
      startTime.add(const Duration(seconds: 1)),
      latitude: 31.963158,
    );
    final second = _fix(
      startTime.add(const Duration(seconds: 21)),
      latitude: 31.963258,
    );
    final latest = _fix(
      startTime.add(const Duration(seconds: 41)),
      latitude: 31.963358,
    );
    gps.add(first);
    await repository.waitForAttempts(1);
    gps.add(second);
    gps.add(latest);
    publishGate.complete();
    await repository.waitForPublishes(2);

    expect(repository.publishAttempts, 2);
    expect(repository.published.map((sample) => sample.recordedAt), [
      first.recordedAt,
      latest.recordedAt,
    ]);
  });

  test('stops and exposes a sanitized publish failure', () async {
    repository.publishError = const DriverLocationException(
      DriverLocationFailure.unavailable,
    );
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();

    gps.add(_fix(startTime.add(const Duration(seconds: 1))));
    await repository.waitForAttempts(1);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(driverTrackingControllerProvider);
    expect(state.status, DriverTrackingStatus.unavailable);
    expect(state.failure, DriverLocationFailure.unavailable);
    expect(gps.cancelCount, 1);
  });

  test('stale sequence rejection refetches canonical sequence', () async {
    final publishGate = Completer<void>();
    repository.publishGate = publishGate.future;
    repository.publishError = const DriverLocationException(
      DriverLocationFailure.staleSequence,
    );
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();

    gps.add(_fix(startTime.add(const Duration(seconds: 1))));
    await repository.waitForAttempts(1);
    repository.latest = _saved(10, startTime.add(const Duration(seconds: 2)));
    publishGate.complete();
    await flush(5);

    expect(repository.availabilityCount, 2);
    expect(repository.latestCount, 2);
    expect(gps.listenCount, 2);

    repository.publishError = null;
    gps.add(_fix(
      startTime.add(const Duration(seconds: 22)),
      latitude: 31.963258,
    ));
    await repository.waitForPublishes(1);

    expect(repository.published.single.sequence, 11);
    expect(repository.publishAttempts, 2);
  });

  test('stop and restart discard queued fixes from the old session', () async {
    final publishGate = Completer<void>();
    repository.publishGate = publishGate.future;
    final controller =
        container.read(driverTrackingControllerProvider.notifier);

    await controller.start();
    gps.add(_fix(startTime.add(const Duration(seconds: 1))));
    await repository.waitForAttempts(1);
    gps.add(_fix(
      startTime.add(const Duration(seconds: 21)),
      latitude: 31.963258,
    ));
    await controller.stop();
    await controller.start();
    gps.add(_fix(
      startTime.add(const Duration(seconds: 41)),
      latitude: 31.963358,
    ));
    publishGate.complete();
    await repository.waitForPublishes(2);

    expect(repository.publishAttempts, 2);
    expect(repository.published.map((sample) => sample.recordedAt), [
      startTime.add(const Duration(seconds: 1)),
      startTime.add(const Duration(seconds: 41)),
    ]);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.sharing);
  });

  test(
      'background cancels the stream and foreground resumes requested tracking',
      () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();

    lifecycle.emit(DriverTrackingLifecycleState.background);
    await flush();
    expect(gps.cancelCount, 1);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.paused);

    lifecycle.emit(DriverTrackingLifecycleState.foreground);
    await flush(3);

    expect(repository.availabilityCount, 2);
    expect(repository.latestCount, 2);
    expect(gps.listenCount, 2);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.sharing);
  });

  test('repeated foreground events do not create duplicate resumes', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    lifecycle.emit(DriverTrackingLifecycleState.background);
    await flush();

    lifecycle.emit(DriverTrackingLifecycleState.foreground);
    lifecycle.emit(DriverTrackingLifecycleState.foreground);
    await flush(4);

    expect(repository.availabilityCount, 2);
    expect(gps.listenCount, 2);
  });

  test('Stop while backgrounded prevents a later foreground resume', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    lifecycle.emit(DriverTrackingLifecycleState.background);
    await flush();
    await controller.stop();
    lifecycle.emit(DriverTrackingLifecycleState.foreground);
    await flush(3);

    expect(repository.availabilityCount, 1);
    expect(gps.listenCount, 1);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.stopped);
  });

  test('sign-out clears tracking intent and prevents auto-resume', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    lifecycle.emit(DriverTrackingLifecycleState.background);
    await flush();
    await controller.stopForSignOut();
    lifecycle.emit(DriverTrackingLifecycleState.foreground);
    await flush(3);

    expect(repository.availabilityCount, 1);
    expect(gps.listenCount, 1);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.stopped);
  });

  test('recovery uses the higher canonical sequence without replaying failure',
      () async {
    repository.publishError = const DriverLocationException(
      DriverLocationFailure.unavailable,
    );
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final failedFix = _fix(startTime.add(const Duration(seconds: 1)));
    gps.add(failedFix);
    await repository.waitForAttempts(1);
    await flush();

    repository.publishError = null;
    repository.latest = _saved(10, startTime.add(const Duration(seconds: 2)));
    await controller.recoverAfterConnectivity();
    gps.add(_fix(
      startTime.add(const Duration(seconds: 22)),
      latitude: 31.963258,
    ));
    await repository.waitForPublishes(1);

    expect(repository.published.single.sequence, 11);
    expect(repository.publishAttempts, 2);
    expect(gps.listenCount, 2);
  });

  test('repeated recovery signals coalesce to one canonical restart', () async {
    repository.publishError = const DriverLocationException(
      DriverLocationFailure.unavailable,
    );
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    gps.add(_fix(startTime.add(const Duration(seconds: 1))));
    await repository.waitForAttempts(1);
    await flush();

    final availability = Completer<DriverAvailability?>();
    repository.availabilityResult = availability.future;
    repository.publishError = null;
    final first = controller.recoverAfterConnectivity();
    final second = controller.recoverAfterConnectivity();
    await flush();
    availability.complete(repository.availability);
    await Future.wait([first, second]);

    expect(repository.availabilityCount, 2);
    expect(gps.listenCount, 2);
  });

  test('Stop during recovery prevents a replacement stream', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final availability = Completer<DriverAvailability?>();
    repository.availabilityResult = availability.future;
    final recovery = controller.recoverAfterConnectivity();
    await flush();
    await controller.stop();
    availability.complete(repository.availability);
    await recovery;

    expect(gps.listenCount, 1);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.stopped);
  });

  test('disconnect followed by resubscribe recovers once', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    connection.emit(DriverTrackingConnectionStatus.subscribed);
    await flush();
    connection.emit(DriverTrackingConnectionStatus.channelError);
    connection.emit(DriverTrackingConnectionStatus.subscribed);
    await flush(4);

    expect(repository.availabilityCount, 2);
    expect(repository.latestCount, 2);
    expect(gps.listenCount, 2);
    expect(connection.connectCount, 2);
    expect(gps.maxActiveSubscriptions, 1);
  });

  test('repeated connection statuses do not duplicate recovery', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    connection.emit(DriverTrackingConnectionStatus.channelError);
    connection.emit(DriverTrackingConnectionStatus.subscribed);
    connection.emit(DriverTrackingConnectionStatus.subscribed);
    await flush(4);

    expect(repository.availabilityCount, 2);
    expect(gps.listenCount, 2);
    expect(connection.connectCount, 2);
  });

  test('Stop while disconnected prevents recovery on resubscribe', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    connection.emit(DriverTrackingConnectionStatus.channelError);
    await controller.stop();
    connection.emit(DriverTrackingConnectionStatus.subscribed);
    await flush(3);

    expect(repository.availabilityCount, 1);
    expect(gps.listenCount, 1);
    expect(connection.disconnectCount, 1);
  });

  test('background and resume clean up and recreate the connection', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    lifecycle.emit(DriverTrackingLifecycleState.background);
    await flush();
    expect(connection.disconnectCount, 1);

    lifecycle.emit(DriverTrackingLifecycleState.foreground);
    await flush(3);

    expect(connection.connectCount, 2);
    expect(gps.listenCount, 2);
  });

  test('disposal cancels the connection subscription and channel', () async {
    final localContainer = ProviderContainer(
      overrides: [
        driverLocationRepositoryProvider.overrideWithValue(repository),
        driverGpsStreamServiceProvider.overrideWithValue(gps),
        driverTrackingLifecycleProvider.overrideWithValue(lifecycle),
        driverTrackingConnectionProvider.overrideWithValue(connection),
      ],
    );
    final keepAlive =
        localContainer.listen(driverTrackingControllerProvider, (_, __) {});
    final controller =
        localContainer.read(driverTrackingControllerProvider.notifier);
    await controller.start();

    keepAlive.close();
    localContainer.dispose();
    await flush();

    expect(connection.disposeCount, 1);
  });

  test('Stop and restart ignore the removed channel status', () async {
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final oldGeneration = connection.generation;
    await controller.stop();
    await controller.start();
    connection.emitFromGeneration(
      DriverTrackingConnectionStatus.channelError,
      oldGeneration,
    );
    connection.emit(DriverTrackingConnectionStatus.subscribed);
    await flush(3);

    expect(repository.availabilityCount, 2);
    expect(gps.listenCount, 2);
  });
}

Future<void> flush([int count = 1]) async {
  for (var index = 0; index < count; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

DriverLocationFix _fix(
  DateTime recordedAt, {
  double latitude = 31.963158,
}) =>
    DriverLocationFix(
      point: LocationPoint(
        latitude: latitude,
        longitude: 35.930359,
        accuracyMeters: 6,
      ),
      recordedAt: recordedAt,
    );

SavedDriverLocation _saved(int sequence, DateTime recordedAt) =>
    SavedDriverLocation(
      point: LocationPoint(
        latitude: 31.963158,
        longitude: 35.930359,
        accuracyMeters: 6,
      ),
      sequence: sequence,
      recordedAt: recordedAt,
      receivedAt: recordedAt,
    );

class FakeDriverGpsStreamService implements DriverGpsStreamService {
  StreamController<DriverLocationFix>? _controller;
  final configurations = <DriverGpsTrackingConfig>[];
  Object? foregroundError;
  Future<void>? cancelGate;
  int listenCount = 0;
  int cancelCount = 0;
  int activeSubscriptions = 0;
  int maxActiveSubscriptions = 0;

  @override
  Stream<DriverLocationFix> foregroundFixes(DriverGpsTrackingConfig config) {
    configurations.add(config);
    listenCount++;
    if (foregroundError case final error?) throw error;
    final controller = StreamController<DriverLocationFix>.broadcast(
      onListen: () {
        activeSubscriptions++;
        if (activeSubscriptions > maxActiveSubscriptions) {
          maxActiveSubscriptions = activeSubscriptions;
        }
      },
      onCancel: () async {
        cancelCount++;
        activeSubscriptions--;
        await cancelGate;
      },
    );
    _controller = controller;
    return controller.stream;
  }

  void add(DriverLocationFix fix) => _controller!.add(fix);
}

class FakeDriverTrackingLifecycle implements DriverTrackingLifecycle {
  final _controller =
      StreamController<DriverTrackingLifecycleState>.broadcast();

  @override
  Stream<DriverTrackingLifecycleState> get changes => _controller.stream;

  void emit(DriverTrackingLifecycleState state) => _controller.add(state);

  @override
  void dispose() {}
}

class FakeDriverTrackingConnection implements DriverTrackingConnection {
  final _controller =
      StreamController<DriverTrackingConnectionEvent>.broadcast();
  int connectCount = 0;
  int disconnectCount = 0;
  int disposeCount = 0;
  int generation = 0;
  Object? connectError;

  @override
  Stream<DriverTrackingConnectionEvent> get events => _controller.stream;

  @override
  Future<int> connect() async {
    connectCount++;
    if (connectError case final error?) throw error;
    generation++;
    return generation;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
  }

  void emit(DriverTrackingConnectionStatus status) =>
      emitFromGeneration(status, generation);

  void emitFromGeneration(
    DriverTrackingConnectionStatus status,
    int generation,
  ) =>
      _controller.add(DriverTrackingConnectionEvent(status, generation));

  @override
  Future<void> dispose() async {
    disposeCount++;
    await _controller.close();
  }
}

class FakeTrackingRepository implements DriverLocationRepository {
  DriverAvailability? availability = const DriverAvailability(
    state: DriverAvailabilityState.available,
  );
  SavedDriverLocation? latest;
  Object? publishError;
  Future<void>? publishGate;
  Future<DriverAvailability?>? availabilityResult;
  Future<SavedDriverLocation?>? latestResult;
  final published = <DriverLocationSample>[];
  final _publishWaiters = <int, Completer<void>>{};
  final _attemptWaiters = <int, Completer<void>>{};
  int availabilityCount = 0;
  int latestCount = 0;
  int publishAttempts = 0;
  int activePublishes = 0;
  int maxConcurrentPublishes = 0;

  Future<void> waitForPublishes(int count) {
    if (published.length >= count) return Future<void>.value();
    final completer = Completer<void>();
    _publishWaiters[count] = completer;
    return completer.future;
  }

  Future<void> waitForAttempts(int count) {
    if (publishAttempts >= count) return Future<void>.value();
    final completer = Completer<void>();
    _attemptWaiters[count] = completer;
    return completer.future;
  }

  @override
  Future<DriverAvailability?> fetchAvailability() async {
    availabilityCount++;
    return availabilityResult ?? availability;
  }

  @override
  Future<SavedDriverLocation?> fetchLatestLocation() async {
    latestCount++;
    return latestResult ?? latest;
  }

  @override
  Future<SavedDriverLocation> publish(DriverLocationSample sample) async {
    publishAttempts++;
    for (final entry in _attemptWaiters.entries) {
      if (publishAttempts >= entry.key && !entry.value.isCompleted) {
        entry.value.complete();
      }
    }
    activePublishes++;
    if (activePublishes > maxConcurrentPublishes) {
      maxConcurrentPublishes = activePublishes;
    }
    await Future<void>.delayed(Duration.zero);
    await publishGate;
    activePublishes--;
    for (final entry in _publishWaiters.entries) {
      if (publishAttempts >= entry.key && !entry.value.isCompleted) {
        entry.value.complete();
      }
    }
    if (publishError case final error?) throw error;
    published.add(sample);
    return _saved(sample.sequence, sample.recordedAt);
  }
}
