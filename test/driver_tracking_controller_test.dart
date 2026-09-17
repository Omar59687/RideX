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
  late ProviderContainer container;
  late ProviderSubscription<DriverTrackingState> keepAlive;

  setUp(() {
    repository = FakeTrackingRepository();
    gps = FakeDriverGpsStreamService();
    container = ProviderContainer(
      overrides: [
        driverLocationRepositoryProvider.overrideWithValue(repository),
        driverGpsStreamServiceProvider.overrideWithValue(gps),
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
    await repository.waitForPublishes(1);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(driverTrackingControllerProvider);
    expect(state.status, DriverTrackingStatus.unavailable);
    expect(state.failure, DriverLocationFailure.staleSequence);
    expect(gps.cancelCount, 1);
  });
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
  late final _controller = StreamController<DriverLocationFix>(
    onCancel: () {
      cancelCount++;
    },
  );
  int listenCount = 0;
  int cancelCount = 0;

  @override
  Stream<DriverLocationFix> foregroundFixes() {
    listenCount++;
    return _controller.stream;
  }

  void add(DriverLocationFix fix) => _controller.add(fix);
}

class FakeTrackingRepository implements DriverLocationRepository {
  DriverAvailability? availability = const DriverAvailability(
    state: DriverAvailabilityState.available,
  );
  SavedDriverLocation? latest;
  Object? publishError;
  final published = <DriverLocationSample>[];
  final _publishWaiters = <int, Completer<void>>{};
  int availabilityCount = 0;
  int latestCount = 0;
  int publishAttempts = 0;
  int activePublishes = 0;
  int maxConcurrentPublishes = 0;

  Future<void> waitForPublishes(int count) {
    if (publishAttempts >= count) return Future<void>.value();
    final completer = Completer<void>();
    _publishWaiters[count] = completer;
    return completer.future;
  }

  @override
  Future<DriverAvailability?> fetchAvailability() async {
    availabilityCount++;
    return availability;
  }

  @override
  Future<SavedDriverLocation?> fetchLatestLocation() async {
    latestCount++;
    return latest;
  }

  @override
  Future<SavedDriverLocation> publish(DriverLocationSample sample) async {
    publishAttempts++;
    activePublishes++;
    if (activePublishes > maxConcurrentPublishes) {
      maxConcurrentPublishes = activePublishes;
    }
    await Future<void>.delayed(Duration.zero);
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
