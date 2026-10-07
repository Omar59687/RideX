import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/repositories/google_route_repository.dart';
import 'package:ridex/core/services/routes/route_service.dart';

import 'helpers/recording_error_reporter.dart';

void main() {
  final origin = LocationPoint(latitude: 38.5, longitude: -120.2);
  final destination = LocationPoint(latitude: 43.252, longitude: -126.453);

  test('decodes Google encoded polyline into provider-neutral points', () {
    final points = decodeGooglePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');

    expect(points, [
      origin,
      LocationPoint(latitude: 40.7, longitude: -120.95),
      destination,
    ]);
  });

  test('normalizes service route geometry and metrics', () async {
    final repository = GoogleRouteRepository(
      _FakeRouteService({
        'encodedPolyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        'distanceMeters': 9123,
        'durationSeconds': 840,
      }),
    );
    final request = RouteRequest(origin: origin, destination: destination);

    final result = await repository.calculateRoute(request);

    expect(result.request, request);
    expect(result.geometry.length, 3);
    expect(result.distanceMeters, 9123);
    expect(result.durationSeconds, 840);
  });

  test('draft request preserves ordered intermediate points', () {
    final firstStop = LocationPoint(latitude: 40, longitude: -121);
    final secondStop = LocationPoint(latitude: 41, longitude: -122);
    final request = RouteRequest.fromDraft(
      BookingDraft(
        pickup: _location(origin),
        destination: _location(destination),
        stops: [_location(firstStop), _location(secondStop)],
      ),
    );

    expect(request!.intermediatePoints, [firstStop, secondStop]);
  });

  test('result rejects incomplete geometry and non-positive metrics', () {
    final request = RouteRequest(origin: origin, destination: destination);

    expect(
      () => RouteResult(
        request: request,
        geometry: [origin],
        distanceMeters: 100,
        durationSeconds: 10,
      ),
      throwsArgumentError,
    );
    expect(
      () => RouteResult(
        request: request,
        geometry: [origin, destination],
        distanceMeters: 0,
        durationSeconds: 10,
      ),
      throwsArgumentError,
    );
  });

  test('routes with up to three distinct stops and preserves metrics',
      () async {
    final service = _FakeRouteService({
      'encodedPolyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      'distanceMeters': 9123,
      'durationSeconds': 840,
    });
    final repository = GoogleRouteRepository(service);
    final request = RouteRequest(
      origin: origin,
      destination: destination,
      intermediatePoints: [
        LocationPoint(latitude: 40, longitude: -121),
        LocationPoint(latitude: 41, longitude: -122),
      ],
    );

    final result = await repository.calculateRoute(request);

    expect(service.callCount, 1);
    expect(service.lastRequest, request);
    expect(service.lastRequest!.intermediatePoints, hasLength(2));
    expect(result.request, request);
    expect(result.geometry.length, 3);
    expect(result.distanceMeters, 9123);
    expect(result.durationSeconds, 840);
  });

  test('rejects more than three stops before calling the provider', () async {
    final service = _FakeRouteService(const {});
    final repository = GoogleRouteRepository(service);
    final request = RouteRequest(
      origin: origin,
      destination: destination,
      intermediatePoints: [
        LocationPoint(latitude: 40, longitude: -121),
        LocationPoint(latitude: 41, longitude: -122),
        LocationPoint(latitude: 42, longitude: -123),
        LocationPoint(latitude: 39, longitude: -120),
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
    final invalidRequests = [
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
          LocationPoint(latitude: 40, longitude: -121),
          LocationPoint(latitude: 40, longitude: -121),
        ],
      ),
    ];

    for (final request in invalidRequests) {
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

  test('rejects malformed provider responses', () async {
    final reporter = RecordingAppErrorReporter();
    final repository = GoogleRouteRepository(
      _FakeRouteService(const {
        'encodedPolyline': '_',
        'distanceMeters': 0,
        'durationSeconds': 10,
      }),
      errorReporter: reporter,
    );

    await expectLater(
      repository.calculateRoute(
        RouteRequest(origin: origin, destination: destination),
      ),
      throwsA(
        isA<RouteException>().having(
          (error) => error.failure,
          'failure',
          RouteFailure.invalidResponse,
        ),
      ),
    );
    expect(reporter.reports, hasLength(1));
  });
}

RideLocation _location(LocationPoint point) => RideLocation(
      point: point,
      label: 'Point',
      address: 'Address',
      source: LocationSelectionSource.demo,
    );

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
