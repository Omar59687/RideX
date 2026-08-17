import 'package:ridex/core/errors/place_exception.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/services/places/place_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabasePlaceService implements PlaceService {
  const SupabasePlaceService(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> autocomplete({
    required String query,
    required String sessionToken,
    LocationPoint? bias,
  }) {
    return _invoke({
      'operation': 'autocomplete',
      'input': query,
      'sessionToken': sessionToken,
      if (bias != null) 'bias': _pointJson(bias),
    });
  }

  @override
  Future<Map<String, dynamic>> placeDetails({
    required String placeId,
    required String sessionToken,
  }) {
    return _invoke({
      'operation': 'placeDetails',
      'placeId': placeId,
      'sessionToken': sessionToken,
    });
  }

  @override
  Future<Map<String, dynamic>> forwardGeocode({
    required String address,
    LocationPoint? bias,
  }) {
    return _invoke({
      'operation': 'forwardGeocode',
      'address': address,
      if (bias != null) 'bias': _pointJson(bias),
    });
  }

  @override
  Future<Map<String, dynamic>> reverseGeocode(LocationPoint point) {
    return _invoke({
      'operation': 'reverseGeocode',
      ..._pointJson(point),
    });
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke('places', body: body);
      final envelope = _map(response.data);
      return _map(envelope['data']);
    } on FunctionException catch (error) {
      throw PlaceException(switch (error.status) {
        401 || 403 => PlaceFailure.unauthorized,
        504 => PlaceFailure.timedOut,
        _ => PlaceFailure.unavailable,
      });
    } on PlaceException {
      rethrow;
    } catch (_) {
      throw const PlaceException(PlaceFailure.unavailable);
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const PlaceException(PlaceFailure.invalidResponse);
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static Map<String, double> _pointJson(LocationPoint point) => {
        'latitude': point.latitude,
        'longitude': point.longitude,
      };
}
