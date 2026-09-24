import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/location_providers.dart';

import 'helpers/fake_location.dart';
import 'helpers/recording_error_reporter.dart';

void main() {
  test('loads current location through the repository', () async {
    final point = LocationPoint(latitude: 31.95, longitude: 35.91);
    final repository = FakeLocationRepository(
      inspectedState: CurrentLocationState(
        status: CurrentLocationStatus.available,
        permission: LocationPermissionStatus.granted,
        point: point,
      ),
    );
    final container = ProviderContainer(
      overrides: [locationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      currentLocationControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await flushLocationTasks();

    expect(container.read(currentLocationControllerProvider).point, point);
    expect(repository.inspectCount, 1);
  });

  test('preserves the last point through a temporary failure and recovers',
      () async {
    final firstPoint = LocationPoint(latitude: 31.95, longitude: 35.91);
    final recoveredPoint = LocationPoint(latitude: 31.96, longitude: 35.92);
    final repository = FakeLocationRepository(
      inspectedState: CurrentLocationState(
        status: CurrentLocationStatus.available,
        permission: LocationPermissionStatus.granted,
        point: firstPoint,
      ),
    );
    final container = ProviderContainer(
      overrides: [locationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      currentLocationControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await flushLocationTasks();

    final failure = Completer<CurrentLocationState>();
    repository.inspectResult = failure.future;
    final controller =
        container.read(currentLocationControllerProvider.notifier);
    final refresh = controller.refresh();

    expect(container.read(currentLocationControllerProvider).status,
        CurrentLocationStatus.checking);
    expect(container.read(currentLocationControllerProvider).point, firstPoint);

    failure.complete(const CurrentLocationState(
      status: CurrentLocationStatus.unavailable,
      permission: LocationPermissionStatus.granted,
      failure: LocationFailure.locationNotFound,
    ));
    await refresh;

    final failed = container.read(currentLocationControllerProvider);
    expect(failed.failure, LocationFailure.locationNotFound);
    expect(failed.point, firstPoint);

    repository.inspectResult = Future.value(CurrentLocationState(
      status: CurrentLocationStatus.available,
      permission: LocationPermissionStatus.granted,
      point: recoveredPoint,
    ));
    await controller.refresh();

    final recovered = container.read(currentLocationControllerProvider);
    expect(recovered.status, CurrentLocationStatus.available);
    expect(recovered.point, recoveredPoint);
    expect(recovered.failure, isNull);

    repository.inspectResult = Future.value(const CurrentLocationState(
      status: CurrentLocationStatus.unavailable,
      permission: LocationPermissionStatus.denied,
      failure: LocationFailure.permissionDenied,
    ));
    await controller.refresh();

    expect(container.read(currentLocationControllerProvider).point, isNull);
  });

  test('deduplicates simultaneous permission requests', () async {
    final requestCompleter = Completer<CurrentLocationState>();
    final repository = FakeLocationRepository()
      ..requestResult = requestCompleter.future;
    final container = ProviderContainer(
      overrides: [locationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      currentLocationControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await flushLocationTasks();
    final controller =
        container.read(currentLocationControllerProvider.notifier);

    final firstRequest = controller.requestPermission();
    final duplicateRequest = controller.requestPermission();
    expect(repository.requestCount, 1);

    requestCompleter.complete(const CurrentLocationState(
      status: CurrentLocationStatus.unavailable,
      permission: LocationPermissionStatus.denied,
      failure: LocationFailure.permissionDenied,
    ));
    await Future.wait([firstRequest, duplicateRequest]);

    expect(repository.requestCount, 1);
    expect(
      container.read(currentLocationControllerProvider).permission,
      LocationPermissionStatus.denied,
    );
  });

  test('disposes cached coordinates after the map loses all listeners',
      () async {
    final point = LocationPoint(latitude: 31.95, longitude: 35.91);
    final repository = FakeLocationRepository(
      inspectedState: CurrentLocationState(
        status: CurrentLocationStatus.available,
        permission: LocationPermissionStatus.granted,
        point: point,
      ),
    );
    final container = ProviderContainer(
      overrides: [locationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final firstSubscription = container.listen(
      currentLocationControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    await flushLocationTasks();
    expect(container.read(currentLocationControllerProvider).point, point);

    firstSubscription.close();
    await flushLocationTasks();

    final secondSubscription = container.listen(
      currentLocationControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(secondSubscription.close);
    await flushLocationTasks();

    expect(repository.inspectCount, 2);
  });

  test('reports raw failures without storing technical details', () async {
    final error = StateError(rawErrorCanary);
    final stackTrace = StackTrace.fromString(rawErrorCanary);
    final reporter = RecordingAppErrorReporter();
    final result = Completer<CurrentLocationState>();
    final repository = FakeLocationRepository()..inspectResult = result.future;
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(repository),
        appErrorReporterProvider.overrideWithValue(reporter),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      currentLocationControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    result.completeError(error, stackTrace);
    await flushLocationTasks();

    final state = container.read(currentLocationControllerProvider);
    expect(state.failure, LocationFailure.gpsUnavailable);
    expect(state.toString(), isNot(contains(rawErrorCanary)));
    expect(reporter.reports, hasLength(1));
    expect(reporter.reports.single.error, same(error));
    expect(reporter.reports.single.stackTrace, same(stackTrace));
  });

  test('late location failures remain reportable after auto-dispose', () async {
    final reporter = RecordingAppErrorReporter();
    final result = Completer<CurrentLocationState>();
    final error = StateError(rawErrorCanary);
    final repository = FakeLocationRepository()..inspectResult = result.future;
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(repository),
        appErrorReporterProvider.overrideWithValue(reporter),
      ],
    );
    final subscription = container.listen(
      currentLocationControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);

    subscription.close();
    container.dispose();
    result.completeError(error, StackTrace.fromString(rawErrorCanary));
    await Future<void>.delayed(Duration.zero);

    expect(reporter.reports.single.error, same(error));
  });
}
