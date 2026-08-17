import 'package:ridex/core/errors/place_exception.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_prediction.dart';
import 'package:ridex/core/repositories/place_repository.dart';
import 'package:ridex/core/services/places/place_service.dart';

class GooglePlaceRepository implements PlaceRepository {
  const GooglePlaceRepository(this._service);

  final PlaceService _service;

  @override
  Future<List<PlacePrediction>> autocomplete({
    required String query,
    required String sessionToken,
    LocationPoint? bias,
  }) async {
    final data = await _service.autocomplete(
      query: query,
      sessionToken: sessionToken,
      bias: bias,
    );
    final suggestions = data['suggestions'];
    if (suggestions is! List) throw _invalidResponse();
    return suggestions.map(_prediction).toList(growable: false);
  }

  @override
  Future<RideLocation> resolvePrediction({
    required PlacePrediction prediction,
    required String sessionToken,
  }) async {
    final data = await _service.placeDetails(
      placeId: prediction.placeId,
      sessionToken: sessionToken,
    );
    final place = _record(data['place']);
    return _location(
      place,
      source: LocationSelectionSource.search,
      fallbackLabel: prediction.primaryText,
    );
  }

  @override
  Future<List<RideLocation>> forwardGeocode({
    required String address,
    LocationPoint? bias,
  }) async {
    final data = await _service.forwardGeocode(address: address, bias: bias);
    final results = data['results'];
    if (results is! List) throw _invalidResponse();
    return results
        .map(
          (result) => _location(
            _record(result),
            source: LocationSelectionSource.search,
            fallbackLabel: address,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<RideLocation?> reverseGeocode({
    required LocationPoint point,
    required LocationSelectionSource source,
  }) async {
    final data = await _service.reverseGeocode(point);
    final results = data['results'];
    if (results is! List) throw _invalidResponse();
    if (results.isEmpty) return null;
    final result = _record(results.first);
    final resolved = _location(
      result,
      source: source,
      fallbackLabel: source == LocationSelectionSource.gps
          ? 'Current location'
          : 'Dropped pin',
    );
    return RideLocation(
      point: point,
      label: resolved.label,
      address: resolved.address,
      source: source,
      providerName: resolved.providerName,
      providerPlaceReference: resolved.providerPlaceReference,
    );
  }

  static PlacePrediction _prediction(Object? value) {
    final record = _record(value);
    return PlacePrediction(
      placeId: _string(record['placeId']),
      primaryText: _string(record['primaryText']),
      secondaryText: _string(record['secondaryText'], allowEmpty: true),
    );
  }

  static RideLocation _location(
    Map<String, dynamic> record, {
    required LocationSelectionSource source,
    required String fallbackLabel,
  }) {
    final pointRecord = _record(record['location']);
    final latitude = pointRecord['latitude'];
    final longitude = pointRecord['longitude'];
    if (latitude is! num || longitude is! num) throw _invalidResponse();
    late final LocationPoint point;
    try {
      point = LocationPoint(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      );
    } on ArgumentError {
      throw _invalidResponse();
    }
    final address = _string(record['address']);
    final providerLabel = record['label'];
    return RideLocation(
      point: point,
      label: providerLabel is String && providerLabel.trim().isNotEmpty
          ? providerLabel.trim()
          : fallbackLabel,
      address: address,
      source: source,
      providerName: 'google',
      providerPlaceReference: _string(record['placeId']),
    );
  }

  static Map<String, dynamic> _record(Object? value) {
    if (value is! Map) throw _invalidResponse();
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _string(Object? value, {bool allowEmpty = false}) {
    if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
      throw _invalidResponse();
    }
    return value.trim();
  }

  static PlaceException _invalidResponse() =>
      const PlaceException(PlaceFailure.invalidResponse);
}
