import 'package:ridex/core/models/location_point.dart';

abstract class PlaceService {
  Future<Map<String, dynamic>> autocomplete({
    required String query,
    required String sessionToken,
    LocationPoint? bias,
  });

  Future<Map<String, dynamic>> placeDetails({
    required String placeId,
    required String sessionToken,
  });

  Future<Map<String, dynamic>> forwardGeocode({
    required String address,
    LocationPoint? bias,
  });

  Future<Map<String, dynamic>> reverseGeocode(LocationPoint point);
}
