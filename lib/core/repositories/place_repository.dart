import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_prediction.dart';

abstract class PlaceRepository {
  Future<List<PlacePrediction>> autocomplete({
    required String query,
    required String sessionToken,
    LocationPoint? bias,
  });

  Future<RideLocation> resolvePrediction({
    required PlacePrediction prediction,
    required String sessionToken,
  });

  Future<List<RideLocation>> forwardGeocode({
    required String address,
    LocationPoint? bias,
  });

  Future<RideLocation?> reverseGeocode({
    required LocationPoint point,
    required LocationSelectionSource source,
  });
}
