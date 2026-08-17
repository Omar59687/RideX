import 'package:ridex/core/errors/place_exception.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_prediction.dart';
import 'package:ridex/core/repositories/place_repository.dart';

class MockPlaceRepository implements PlaceRepository {
  @override
  Future<List<PlacePrediction>> autocomplete({
    required String query,
    required String sessionToken,
    LocationPoint? bias,
  }) async {
    final normalized = query.trim().toLowerCase();
    return MockData.locations
        .where(
          (location) =>
              location.label.toLowerCase().contains(normalized) ||
              location.address.toLowerCase().contains(normalized),
        )
        .map(
          (location) => PlacePrediction(
            placeId: location.providerPlaceReference!,
            primaryText: location.label,
            secondaryText: location.address,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<RideLocation>> forwardGeocode({
    required String address,
    LocationPoint? bias,
  }) async {
    final predictions = await autocomplete(
      query: address,
      sessionToken: 'demo-forward',
      bias: bias,
    );
    if (predictions.isEmpty) return const [];
    return [
      await resolvePrediction(
        prediction: predictions.first,
        sessionToken: 'demo-forward',
      )
    ];
  }

  @override
  Future<RideLocation> resolvePrediction({
    required PlacePrediction prediction,
    required String sessionToken,
  }) async {
    for (final location in MockData.locations) {
      if (location.providerPlaceReference == prediction.placeId) {
        return RideLocation(
          point: location.point,
          label: location.label,
          address: location.address,
          source: LocationSelectionSource.search,
          providerName: location.providerName,
          providerPlaceReference: location.providerPlaceReference,
        );
      }
    }
    throw const PlaceException(PlaceFailure.notFound);
  }

  @override
  Future<RideLocation?> reverseGeocode({
    required LocationPoint point,
    required LocationSelectionSource source,
  }) async {
    for (final location in MockData.locations) {
      if (location.point.latitude == point.latitude &&
          location.point.longitude == point.longitude) {
        return RideLocation(
          point: point,
          label: source == LocationSelectionSource.gps
              ? 'Current location'
              : location.label,
          address: location.address,
          source: source,
          providerName: location.providerName,
          providerPlaceReference: location.providerPlaceReference,
        );
      }
    }
    return RideLocation(
      point: point,
      label: source == LocationSelectionSource.gps
          ? 'Current location'
          : 'Dropped pin',
      address: 'Address unavailable in demo mode',
      source: source,
      providerName: 'demo',
    );
  }
}
