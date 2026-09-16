import 'package:ridex/core/models/route_models.dart';

abstract class RouteRepository {
  Future<RouteResult> calculateRoute(RouteRequest request);
}
