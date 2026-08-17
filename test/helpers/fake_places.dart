import 'dart:async';

import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_prediction.dart';
import 'package:ridex/core/repositories/place_repository.dart';

class FakePlaceRepository implements PlaceRepository {
  List<PlacePrediction> predictions = const [];
  RideLocation? resolvedPrediction;
  List<RideLocation> forwardResults = const [];
  RideLocation? reversedLocation;
  Object? autocompleteError;
  Object? resolveError;
  Object? forwardError;
  Object? reverseError;
  Future<List<PlacePrediction>>? autocompleteResult;
  Future<RideLocation>? resolveResult;
  Future<List<RideLocation>>? forwardResult;
  Future<RideLocation?>? reverseResult;
  int autocompleteCalls = 0;
  int resolveCalls = 0;
  int forwardCalls = 0;
  int reverseCalls = 0;
  final List<String> queries = [];
  final List<String> sessionTokens = [];

  @override
  Future<List<PlacePrediction>> autocomplete({
    required String query,
    required String sessionToken,
    LocationPoint? bias,
  }) async {
    autocompleteCalls++;
    queries.add(query);
    sessionTokens.add(sessionToken);
    if (autocompleteError != null) throw autocompleteError!;
    return autocompleteResult ?? predictions;
  }

  @override
  Future<List<RideLocation>> forwardGeocode({
    required String address,
    LocationPoint? bias,
  }) async {
    forwardCalls++;
    if (forwardError != null) throw forwardError!;
    return forwardResult ?? forwardResults;
  }

  @override
  Future<RideLocation?> reverseGeocode({
    required LocationPoint point,
    required LocationSelectionSource source,
  }) async {
    reverseCalls++;
    if (reverseError != null) throw reverseError!;
    return reverseResult ?? reversedLocation;
  }

  @override
  Future<RideLocation> resolvePrediction({
    required PlacePrediction prediction,
    required String sessionToken,
  }) async {
    resolveCalls++;
    sessionTokens.add(sessionToken);
    if (resolveError != null) throw resolveError!;
    if (resolveResult != null) return resolveResult!;
    return resolvedPrediction!;
  }
}

RideLocation testLocation({
  required double latitude,
  required double longitude,
  String label = 'Test place',
  String address = 'Test address',
  LocationSelectionSource source = LocationSelectionSource.search,
}) {
  return RideLocation(
    point: LocationPoint(latitude: latitude, longitude: longitude),
    label: label,
    address: address,
    source: source,
    providerName: 'test',
    providerPlaceReference: 'test-$latitude-$longitude',
  );
}
