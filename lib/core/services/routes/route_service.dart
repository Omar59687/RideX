import 'package:ridex/core/models/route_models.dart';

abstract class RouteService {
  Future<Map<String, dynamic>> calculateRoute(RouteRequest request);
}
