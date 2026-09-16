import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/route_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/route_repository.dart';

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

    container.read(routeControllerProvider.notifier).retry();
    await _flush();
    expect(repository.requests, [request, request]);
    expect(container.read(routeControllerProvider).status, RouteStatus.loading);
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

  void fail(RouteRequest request) {
    _take(request).completeError(const RouteException(RouteFailure.timedOut));
  }

  Completer<RouteResult> _take(RouteRequest request) =>
      _pending[request]!.removeAt(0);
}
