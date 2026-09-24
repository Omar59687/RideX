import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/services/routes/route_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseRouteService implements RouteService {
  const SupabaseRouteService(this._client, this._errorReporter);

  final SupabaseClient _client;
  final AppErrorReporter _errorReporter;

  @override
  Future<Map<String, dynamic>> calculateRoute(RouteRequest request) async {
    try {
      final response = await _client.functions.invoke(
        'places',
        body: {
          'operation': 'route',
          'origin': _pointJson(request.origin),
          'destination': _pointJson(request.destination),
          'intermediates': [
            for (final point in request.intermediatePoints) _pointJson(point),
          ],
        },
      );
      final envelope = _map(response.data);
      return _map(envelope['data']);
    } on FunctionException catch (error, stackTrace) {
      _report(error, stackTrace);
      throw RouteException(switch (error.status) {
        401 || 403 => RouteFailure.unauthorized,
        404 => RouteFailure.notFound,
        502 || 503 => RouteFailure.networkFailure,
        504 => RouteFailure.timedOut,
        _ => RouteFailure.unavailable,
      });
    } on RouteException {
      rethrow;
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      throw const RouteException(RouteFailure.networkFailure);
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const RouteException(RouteFailure.invalidResponse);
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static Map<String, double> _pointJson(LocationPoint point) => {
        'latitude': point.latitude,
        'longitude': point.longitude,
      };

  void _report(Object error, StackTrace stackTrace) {
    _errorReporter.report(
      operation: 'calling the route service',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
