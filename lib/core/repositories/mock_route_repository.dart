import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/repositories/route_repository.dart';

bool _hasValidStops(RouteRequest request) {
  final stops = request.intermediatePoints;
  if (stops.length > 3) return false;
  bool samePoint(LocationPoint a, LocationPoint b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;
  for (final stop in stops) {
    if (samePoint(stop, request.origin) ||
        samePoint(stop, request.destination)) {
      return false;
    }
  }
  for (var i = 0; i < stops.length; i++) {
    for (var j = i + 1; j < stops.length; j++) {
      if (samePoint(stops[i], stops[j])) return false;
    }
  }
  return true;
}

class MockRouteRepository implements RouteRepository {
  const MockRouteRepository();

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    if (!_hasValidStops(request)) {
      throw const RouteException(RouteFailure.unsupportedStops);
    }
    if (!request.hasDistinctEndpoints) {
      throw const RouteException(RouteFailure.notFound);
    }
    return RouteResult(
      request: request,
      geometry: [
        request.origin,
        ...request.intermediatePoints,
        request.destination
      ],
      distanceMeters: 5400,
      durationSeconds: 720,
    );
  }
}
