import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/route_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/route_repository.dart';

import 'helpers/recording_error_reporter.dart';

void main() {
  test('coalesces endpoint writes into one route request', () async {
    final repository = _ControlledRouteRepository();
    final container = ProviderContainer(
      overrides: [routeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(routeControllerProvider);

    container.read(bookingControllerProvider.notifier)
      ..setPickup(_location(31.95, 35.91))
      ..setDestination(_location(31.98, 35.95));
    await _flush();

    expect(repository.requests, hasLength(1));
    expect(container.read(routeControllerProvider).status, RouteStatus.loading);
  });

  test('invalidates immediately and ignores an older response', () async {
    final repository = _ControlledRouteRepository();
    final container = ProviderContainer(
      overrides: [routeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(routeControllerProvider);
    final booking = container.read(bookingControllerProvider.notifier)
      ..setPickup(_location(31.95, 35.91))
      ..setDestination(_location(31.98, 35.95));
    await _flush();
    final firstRequest = repository.requests.single;

    booking.setDestination(_location(32.02, 36.01));
    final invalidated = container.read(routeControllerProvider);
    expect(invalidated.status, RouteStatus.loading);
    expect(invalidated.result, isNull);
    await _flush();
    final secondRequest = repository.requests.last;

    repository.complete(firstRequest);
    await _flush();
    expect(container.read(routeControllerProvider).status, RouteStatus.loading);

    repository.complete(secondRequest);
    await _flush();
    final ready = container.read(routeControllerProvider);
    expect(ready.status, RouteStatus.ready);
    expect(ready.result!.request, secondRequest);
  });

  test('surfaces failures and retries the current endpoint snapshot', () async {
    final repository = _ControlledRouteRepository();
    final container = ProviderContainer(
      overrides: [routeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(routeControllerProvider);
    container.read(bookingControllerProvider.notifier)
      ..setPickup(_location(31.95, 35.91))
      ..setDestination(_location(31.98, 35.95));
    await _flush();
    final request = repository.requests.single;

    repository.fail(request);
    await _flush();
    expect(container.read(routeControllerProvider).status, RouteStatus.failure);
    expect(
        container.read(routeControllerProvider).failure, RouteFailure.timedOut);

    container.read(routeControllerProvider.notifier).retry();
    await _flush();
    expect(repository.requests, [request, request]);
    expect(container.read(routeControllerProvider).status, RouteStatus.loading);
  });

  test('retains a valid route through network failure and retry', () async {
    final repository = _ControlledRouteRepository();
    final container = ProviderContainer(
      overrides: [routeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(routeControllerProvider);
    container.read(bookingControllerProvider.notifier)
      ..setPickup(_location(31.95, 35.91))
      ..setDestination(_location(31.98, 35.95));
    await _flush();
    final request = repository.requests.single;
    repository.complete(request);
    await _flush();
    final readyResult = container.read(routeControllerProvider).result;

    container.read(routeControllerProvider.notifier).retry();
    await _flush();
    final loading = container.read(routeControllerProvider);
    expect(loading.status, RouteStatus.loading);
    expect(loading.result, readyResult);
    expect(
      loading.isReadyFor(container.read(bookingControllerProvider)),
      isFalse,
    );

    repository.fail(request, RouteFailure.networkFailure);
    await _flush();
    final failed = container.read(routeControllerProvider);
    expect(failed.status, RouteStatus.failure);
    expect(failed.failure, RouteFailure.networkFailure);
    expect(failed.result, readyResult);
    expect(
      failed.resultFor(container.read(bookingControllerProvider)),
      readyResult,
    );
    expect(
      failed.isReadyFor(container.read(bookingControllerProvider)),
      isFalse,
    );

    container.read(routeControllerProvider.notifier).retry();
    await _flush();
    repository.complete(request);
    await _flush();

    expect(
      container
          .read(routeControllerProvider)
          .isReadyFor(container.read(bookingControllerProvider)),
      isTrue,
    );

    container
        .read(bookingControllerProvider.notifier)
        .setDestination(_location(32.02, 36.01));
    final changedEndpoint = container.read(routeControllerProvider);
    expect(changedEndpoint.status, RouteStatus.loading);
    expect(changedEndpoint.result, isNull);
  });

  test('unexpected route errors are reported but never exposed in state',
      () async {
    final error = StateError(rawErrorCanary);
    final reporter = RecordingAppErrorReporter();
    final repository = _ControlledRouteRepository();
    final container = ProviderContainer(
      overrides: [
        routeRepositoryProvider.overrideWithValue(repository),
        appErrorReporterProvider.overrideWithValue(reporter),
      ],
    );
    addTearDown(container.dispose);
    container.read(routeControllerProvider);
    container.read(bookingControllerProvider.notifier)
      ..setPickup(_location(31.95, 35.91))
      ..setDestination(_location(31.98, 35.95));
    await _flush();

    repository.failRaw(repository.requests.single, error);
    await _flush();

    final state = container.read(routeControllerProvider);
    expect(state.failure, RouteFailure.unavailable);
    expect(state.toString(), isNot(contains(rawErrorCanary)));
    expect(reporter.reports.single.error, same(error));
  });
}

RideLocation _location(double latitude, double longitude) => RideLocation(
      point: LocationPoint(latitude: latitude, longitude: longitude),
      label: 'Point',
      address: '$latitude,$longitude',
      source: LocationSelectionSource.demo,
    );

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _ControlledRouteRepository implements RouteRepository {
  final requests = <RouteRequest>[];
  final _pending = <RouteRequest, List<Completer<RouteResult>>>{};

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) {
    requests.add(request);
    final completer = Completer<RouteResult>();
    _pending.putIfAbsent(request, () => []).add(completer);
    return completer.future;
  }

  void complete(RouteRequest request) {
    _take(request).complete(
      RouteResult(
        request: request,
        geometry: [request.origin, request.destination],
        distanceMeters: 5000,
        durationSeconds: 600,
      ),
    );
  }

  void fail(
    RouteRequest request, [
    RouteFailure failure = RouteFailure.timedOut,
  ]) {
    _take(request).completeError(RouteException(failure));
  }

  void failRaw(RouteRequest request, Object error) {
    _take(request).completeError(
      error,
      StackTrace.fromString(rawErrorCanary),
    );
  }

  Completer<RouteResult> _take(RouteRequest request) =>
      _pending[request]!.removeAt(0);
}
