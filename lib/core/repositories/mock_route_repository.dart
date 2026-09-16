import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/repositories/route_repository.dart';

class MockRouteRepository implements RouteRepository {
  const MockRouteRepository();

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    if (request.intermediatePoints.isNotEmpty) {
      throw const RouteException(RouteFailure.unsupportedStops);
    }
    if (!request.hasDistinctEndpoints) {
      throw const RouteException(RouteFailure.notFound);
    }
    return RouteResult(
      request: request,
      geometry: [request.origin, request.destination],
      distanceMeters: 5400,
      durationSeconds: 720,
    );
  }
}
