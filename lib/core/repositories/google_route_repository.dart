import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/repositories/route_repository.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/services/routes/route_service.dart';

class GoogleRouteRepository implements RouteRepository {
  const GoogleRouteRepository(
    this._service, {
    AppErrorReporter errorReporter = const NoopAppErrorReporter(),
  }) : _errorReporter = errorReporter;

  final RouteService _service;
  final AppErrorReporter _errorReporter;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    if (request.intermediatePoints.isNotEmpty) {
      throw const RouteException(RouteFailure.unsupportedStops);
    }
    if (!request.hasDistinctEndpoints) {
      throw const RouteException(RouteFailure.notFound);
    }

    try {
      final data = await _service.calculateRoute(request);
      final encoded = data['encodedPolyline'];
      final distance = data['distanceMeters'];
      final duration = data['durationSeconds'];
      if (encoded is! String ||
          distance is! int ||
          duration is! int ||
          distance <= 0 ||
          duration <= 0) {
        throw const RouteException(RouteFailure.invalidResponse);
      }
      return RouteResult(
        request: request,
        geometry: decodeGooglePolyline(encoded),
        distanceMeters: distance,
        durationSeconds: duration,
      );
    } on ArgumentError catch (error, stackTrace) {
      final failure = const RouteException(RouteFailure.invalidResponse);
      _errorReporter.report(
        operation: 'parsing a route-service response',
        error: error,
        stackTrace: stackTrace,
      );
      throw failure;
    } on RouteException catch (error, stackTrace) {
      if (error.failure == RouteFailure.invalidResponse) {
        _errorReporter.report(
          operation: 'parsing a route-service response',
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }
  }
}

List<LocationPoint> decodeGooglePolyline(String encoded) {
  if (encoded.isEmpty) throw ArgumentError('Encoded polyline is empty.');
  final points = <LocationPoint>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;

  while (index < encoded.length) {
    final latitudeValue = _decodeValue(encoded, index);
    index = latitudeValue.nextIndex;
    latitude += latitudeValue.delta;
    if (index >= encoded.length) {
      throw ArgumentError('Encoded polyline is incomplete.');
    }
    final longitudeValue = _decodeValue(encoded, index);
    index = longitudeValue.nextIndex;
    longitude += longitudeValue.delta;
    points.add(
      LocationPoint(
        latitude: latitude / 1e5,
        longitude: longitude / 1e5,
      ),
    );
  }

  if (points.length < 2) throw ArgumentError('Route geometry is incomplete.');
  return List.unmodifiable(points);
}

({int delta, int nextIndex}) _decodeValue(String encoded, int startIndex) {
  var result = 0;
  var shift = 0;
  var index = startIndex;
  int byte;
  do {
    if (index >= encoded.length || shift > 30) {
      throw ArgumentError('Encoded polyline is invalid.');
    }
    byte = encoded.codeUnitAt(index++) - 63;
    if (byte < 0 || byte > 63) {
      throw ArgumentError('Encoded polyline is invalid.');
    }
    result |= (byte & 0x1f) << shift;
    shift += 5;
  } while (byte >= 0x20);
  final delta = result.isOdd ? ~(result >> 1) : result >> 1;
  return (delta: delta, nextIndex: index);
}
