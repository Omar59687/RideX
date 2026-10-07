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
import 'package:ridex/core/repositories/google_route_repository.dart';
import 'package:ridex/core/repositories/mock_route_repository.dart';
import 'package:ridex/core/repositories/route_repository.dart';
import 'package:ridex/core/services/routes/route_service.dart';

import 'helpers/fake_places.dart';

void main() {
  LocationPoint point(double lat, double lng) =>
      LocationPoint(latitude: lat, longitude: lng);

  RideLocation location(double lat, double lng, String label) => testLocation(
        latitude: lat,
        longitude: lng,
        label: label,
      );

  group('with-stops request mapping', () {
    test('fromDraft preserves ordered stops and service receives them',
        () async {
      final origin = point(31.95, 35.91);
      final destination = point(32.02, 36.01);
      final firstStop = point(31.97, 35.95);
      final secondStop = point(31.99, 35.98);
      final service = _FakeRouteService({
        'encodedPolyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        'distanceMeters': 9100,
        'durationSeconds': 800,
      });
      final repository = GoogleRouteRepository(service);
      final request = RouteRequest.fromDraft(
        BookingDraft(
          pickup: _rideLocation(origin),
          destination: _rideLocation(destination),
          stops: [
            _rideLocation(firstStop),
            _rideLocation(secondStop),
          ],
        ),
      )!;

      final result = await repository.calculateRoute(request);

      expect(service.lastRequest, request);
      expect(
        service.lastRequest!.intermediatePoints,
        [firstStop, secondStop],
      );
      expect(result.request, request);
      expect(result.geometry.length, greaterThanOrEqualTo(2));
      expect(result.distanceMeters, 9100);
      expect(result.durationSeconds, 800);
    });

    test('mock repository includes stops in geometry in order', () async {
      const repository = MockRouteRepository();
      final origin = point(31.95, 35.91);
      final destination = point(32.02, 36.01);
      final stop = point(31.98, 35.95);
      final request = RouteRequest(
        origin: origin,
        destination: destination,
        intermediatePoints: [stop],
      );

      final result = await repository.calculateRoute(request);

      expect(result.geometry, [origin, stop, destination]);
      expect(result.distanceMeters, greaterThan(0));
      expect(result.durationSeconds, greaterThan(0));
    });
  });

  group('with-stops validation', () {
    test('rejects more than three stops without calling the service', () async {
      final service = _FakeRouteService(const {});
      final repository = GoogleRouteRepository(service);
      final request = RouteRequest(
        origin: point(31.95, 35.91),
        destination: point(32.02, 36.01),
        intermediatePoints: [
          point(31.90, 35.90),
          point(31.91, 35.91),
          point(31.92, 35.92),
          point(31.93, 35.93),
        ],
      );

      await expectLater(
        repository.calculateRoute(request),
        throwsA(
          isA<RouteException>().having(
            (error) => error.failure,
            'failure',
            RouteFailure.unsupportedStops,
          ),
        ),
      );
      expect(service.callCount, 0);
    });

    test('rejects stops duplicating endpoints or each other', () async {
      final service = _FakeRouteService(const {});
      final repository = GoogleRouteRepository(service);
      final origin = point(31.95, 35.91);
      final destination = point(32.02, 36.01);
      final requests = [
        RouteRequest(
          origin: origin,
          destination: destination,
          intermediatePoints: [origin],
        ),
        RouteRequest(
          origin: origin,
          destination: destination,
          intermediatePoints: [destination],
        ),
        RouteRequest(
          origin: origin,
          destination: destination,
          intermediatePoints: [
            point(31.98, 35.95),
            point(31.98, 35.95),
          ],
        ),
      ];

      for (final request in requests) {
        await expectLater(
          repository.calculateRoute(request),
          throwsA(
            isA<RouteException>().having(
              (error) => error.failure,
              'failure',
              RouteFailure.unsupportedStops,
            ),
          ),
        );
      }
      expect(service.callCount, 0);
    });
  });

  group('RouteController with stops', () {
    test('recalculates when the stop list changes and invalidates old route',
        () async {
      final repository = _ControlledRouteRepository();
      final container = ProviderContainer(
        overrides: [routeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      container.read(routeControllerProvider);
      final booking = container.read(bookingControllerProvider.notifier)
        ..setPickup(location(31.95, 35.91, 'Pickup'))
        ..setDestination(location(32.02, 36.01, 'Destination'));
      await _flush();
      final firstRequest = repository.requests.single;
      expect(firstRequest.intermediatePoints, isEmpty);

      repository.complete(firstRequest);
      await _flush();
      expect(container.read(routeControllerProvider).status, RouteStatus.ready);

      expect(booking.addStop(location(31.98, 35.95, 'Stop 1')), isTrue);
      await _flush();

      final withStop = container.read(routeControllerProvider);
      expect(withStop.status, RouteStatus.loading);
      expect(withStop.result, isNull);
      expect(repository.requests, hasLength(2));
      final secondRequest = repository.requests.last;
      expect(secondRequest.intermediatePoints, hasLength(1));
      expect(secondRequest.origin, firstRequest.origin);
      expect(secondRequest.destination, firstRequest.destination);

      repository.complete(secondRequest);
      await _flush();
      final ready = container.read(routeControllerProvider);
      expect(ready.status, RouteStatus.ready);
      expect(ready.result!.request, secondRequest);
      expect(
        ready.isReadyFor(container.read(bookingControllerProvider)),
        isTrue,
      );
    });

    test('stale with-stops responses do not replace the current route',
        () async {
      final repository = _ControlledRouteRepository();
      final container = ProviderContainer(
        overrides: [routeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      container.read(routeControllerProvider);
      final booking = container.read(bookingControllerProvider.notifier)
        ..setPickup(location(31.95, 35.91, 'Pickup'))
        ..setDestination(location(32.02, 36.01, 'Destination'));
      await _flush();
      expect(booking.addStop(location(31.97, 35.93, 'Stop 1')), isTrue);
      await _flush();
      final firstRequest = repository.requests.last;

      expect(booking.addStop(location(31.99, 35.98, 'Stop 2')), isTrue);
      await _flush();
      final secondRequest = repository.requests.last;
      expect(secondRequest, isNot(firstRequest));
      expect(secondRequest.intermediatePoints, hasLength(2));

      repository.complete(firstRequest);
      await _flush();
      expect(
          container.read(routeControllerProvider).status, RouteStatus.loading);

      repository.complete(secondRequest);
      await _flush();
      final ready = container.read(routeControllerProvider);
      expect(ready.status, RouteStatus.ready);
      expect(ready.result!.request, secondRequest);
    });

    test('retry repeats the current with-stops request', () async {
      final repository = _ControlledRouteRepository();
      final container = ProviderContainer(
        overrides: [routeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      container.read(routeControllerProvider);
      container.read(bookingControllerProvider.notifier)
        ..setPickup(location(31.95, 35.91, 'Pickup'))
        ..setDestination(location(32.02, 36.01, 'Destination'))
        ..addStop(location(31.98, 35.95, 'Stop 1'));
      await _flush();
      final request = repository.requests.single;
      expect(request.intermediatePoints, hasLength(1));

      repository.fail(request);
      await _flush();
      expect(
          container.read(routeControllerProvider).status, RouteStatus.failure);

      container.read(routeControllerProvider.notifier).retry();
      await _flush();
      expect(repository.requests, [request, request]);
      expect(
          container.read(routeControllerProvider).status, RouteStatus.loading);

      repository.complete(request);
      await _flush();
      expect(
        container
            .read(routeControllerProvider)
            .isReadyFor(container.read(bookingControllerProvider)),
        isTrue,
      );
    });

    test('resultFor keys on the full request including stops', () async {
      final origin = point(31.95, 35.91);
      final destination = point(32.02, 36.01);
      final stop = point(31.98, 35.95);
      final request = RouteRequest(
        origin: origin,
        destination: destination,
        intermediatePoints: [stop],
      );
      final result = RouteResult(
        request: request,
        geometry: [origin, stop, destination],
        distanceMeters: 5000,
        durationSeconds: 600,
      );
      final state = RouteState.ready(result);

      final matching = BookingDraft(
        pickup: _rideLocation(origin),
        destination: _rideLocation(destination),
        stops: [_rideLocation(stop)],
      );
      final missingStop = BookingDraft(
        pickup: _rideLocation(origin),
        destination: _rideLocation(destination),
      );

      expect(state.resultFor(matching), result);
      expect(state.isReadyFor(matching), isTrue);
      expect(state.resultFor(missingStop), isNull);
      expect(state.isReadyFor(missingStop), isFalse);
    });
  });
}

RideLocation _rideLocation(LocationPoint point) => RideLocation(
      point: point,
      label: 'Point',
      address: 'Address',
      source: LocationSelectionSource.demo,
    );

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeRouteService implements RouteService {
  _FakeRouteService(this.response);

  final Map<String, dynamic> response;
  int callCount = 0;
  RouteRequest? lastRequest;

  @override
  Future<Map<String, dynamic>> calculateRoute(RouteRequest request) async {
    callCount++;
    lastRequest = request;
    return response;
  }
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
        geometry: [
          request.origin,
          ...request.intermediatePoints,
          request.destination
        ],
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

  Completer<RouteResult> _take(RouteRequest request) =>
      _pending[request]!.removeAt(0);
}
