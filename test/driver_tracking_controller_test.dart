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

void main() {
  final startTime = DateTime.utc(2026, 9, 17, 10);

  late FakeTrackingRepository repository;
  late FakeDriverGpsStreamService gps;
  late FakeDriverTrackingLifecycle lifecycle;
  late ProviderContainer container;
  late ProviderSubscription<DriverTrackingState> keepAlive;

  setUp(() {
    repository = FakeTrackingRepository();
    gps = FakeDriverGpsStreamService();
    lifecycle = FakeDriverTrackingLifecycle();
    container = ProviderContainer(
      overrides: [
        driverLocationRepositoryProvider.overrideWithValue(repository),
        driverGpsStreamServiceProvider.overrideWithValue(gps),
        driverTrackingLifecycleProvider.overrideWithValue(lifecycle),
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
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.sharing);

    await controller.stop();

    expect(gps.cancelCount, 1);
    expect(container.read(driverTrackingControllerProvider).status,
        DriverTrackingStatus.stopped);
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
  });

  test('publishes valid fixes sequentially after the saved maximum', () async {
    repository.latest = _saved(7, startTime);
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();
    final first = _fix(startTime.add(const Duration(seconds: 1)));
    final second = _fix(startTime.add(const Duration(seconds: 2)));

    gps.add(first);
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
    gps.add(_fix(startTime.add(const Duration(seconds: 1))));
    await repository.waitForPublishes(1);

    expect(repository.published.map((sample) => sample.sequence), [4]);
  });

  test('stops and exposes a sanitized publish failure', () async {
    repository.publishError = const DriverLocationException(
      DriverLocationFailure.staleSequence,
    );
    final controller =
        container.read(driverTrackingControllerProvider.notifier);
    await controller.start();

    gps.add(_fix(startTime.add(const Duration(seconds: 1))));
    await repository.waitForAttempts(1);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(driverTrackingControllerProvider);
    expect(state.status, DriverTrackingStatus.unavailable);
    expect(state.failure, DriverLocationFailure.staleSequence);
    expect(gps.cancelCount, 1);
  });

  test('stop and restart discard queued fixes from the old session', () async {
    final publishGate = Completer<void>();
    repository.publishGate = publishGate.future;
    final controller =
        container.read(driverTrackingControllerProvider.notifier);

    await controller.start();
    gps.add(_fix(startTime.add(const Duration(seconds: 1))));
    gps.add(_fix(startTime.add(const Duration(seconds: 2))));
    await repository.waitForAttempts(1);
    await controller.stop();
    await controller.start();
    gps.add(_fix(startTime.add(const Duration(seconds: 3))));
    publishGate.complete();
    await repository.waitForPublishes(2);

    expect(repository.publishAttempts, 2);
    expect(repository.published.map((sample) => sample.recordedAt), [
      startTime.add(const Duration(seconds: 1)),
      startTime.add(const Duration(seconds: 3)),
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
        DriverTrackingStatus.stopped);

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
    gps.add(_fix(startTime.add(const Duration(seconds: 3))));
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
}

Future<void> flush([int count = 1]) async {
  for (var index = 0; index < count; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

DriverLocationFix _fix(DateTime recordedAt) => DriverLocationFix(
      point: LocationPoint(
        latitude: 31.963158,
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
  int listenCount = 0;
  int cancelCount = 0;

  @override
  Stream<DriverLocationFix> foregroundFixes() {
    listenCount++;
    final controller = StreamController<DriverLocationFix>.broadcast(
      onCancel: () {
        cancelCount++;
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

class FakeTrackingRepository implements DriverLocationRepository {
  DriverAvailability? availability = const DriverAvailability(
    state: DriverAvailabilityState.available,
  );
  SavedDriverLocation? latest;
  Object? publishError;
  Future<void>? publishGate;
  Future<DriverAvailability?>? availabilityResult;
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
    return latest;
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
