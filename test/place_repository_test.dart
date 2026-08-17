import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/errors/place_exception.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/repositories/google_place_repository.dart';
import 'package:ridex/core/services/places/place_service.dart';

void main() {
  test('parses predictions and selected place coordinates', () async {
    final service = _FakeService();
    final repository = GooglePlaceRepository(service);
    final predictions = await repository.autocomplete(
      query: 'Abdali',
      sessionToken: 'session-token-1234567890',
    );

    expect(predictions.single.primaryText, 'Abdali Mall');
    final location = await repository.resolvePrediction(
      prediction: predictions.single,
      sessionToken: 'session-token-1234567890',
    );
    expect(location.point.latitude, 31.9632);
    expect(location.providerPlaceReference, 'place-1');
    expect(location.source, LocationSelectionSource.search);
  });

  test('forward geocoding supports empty results', () async {
    final service = _FakeService()..forward = {'results': <Object>[]};
    final results = await GooglePlaceRepository(service).forwardGeocode(
      address: 'Unknown address',
    );
    expect(results, isEmpty);
  });

  test('reverse failure preserves requested coordinate at controller boundary',
      () async {
    final service = _FakeService()
      ..reverse = {
        'results': [
          {
            'placeId': 'reverse-1',
            'address': 'Nearby address',
            'location': {'latitude': 0.0, 'longitude': 0.0},
          }
        ]
      };
    final point = LocationPoint(latitude: 31.95, longitude: 35.91);
    final location = await GooglePlaceRepository(service).reverseGeocode(
      point: point,
      source: LocationSelectionSource.map,
    );
    expect(location?.point, point);
  });

  test('rejects invalid provider coordinates with sanitized failure', () async {
    final service = _FakeService()
      ..details = {
        'place': {
          'placeId': 'place-1',
          'label': 'Invalid',
          'address': 'Invalid',
          'location': {'latitude': 100, 'longitude': 0},
        }
      };
    final repository = GooglePlaceRepository(service);
    final prediction = (await repository.autocomplete(
      query: 'Invalid',
      sessionToken: 'session-token-1234567890',
    ))
        .single;
    expect(
      () => repository.resolvePrediction(
        prediction: prediction,
        sessionToken: 'session-token-1234567890',
      ),
      throwsA(
        isA<PlaceException>().having(
          (error) => error.failure,
          'failure',
          PlaceFailure.invalidResponse,
        ),
      ),
    );
  });
}

class _FakeService implements PlaceService {
  Map<String, dynamic> predictions = {
    'suggestions': [
      {
        'placeId': 'place-1',
        'primaryText': 'Abdali Mall',
        'secondaryText': 'Amman, Jordan',
      }
    ]
  };
  Map<String, dynamic> details = {
    'place': {
      'placeId': 'place-1',
      'label': 'Abdali Mall',
      'address': 'Abdali Boulevard, Amman',
      'location': {'latitude': 31.9632, 'longitude': 35.9084},
    }
  };
  Map<String, dynamic> forward = {
    'results': [
      {
        'placeId': 'forward-1',
        'address': 'Amman, Jordan',
        'location': {'latitude': 31.95, 'longitude': 35.91},
      }
    ]
  };
  Map<String, dynamic> reverse = {'results': <Object>[]};

  @override
  Future<Map<String, dynamic>> autocomplete({
    required String query,
    required String sessionToken,
    LocationPoint? bias,
  }) async =>
      predictions;

  @override
  Future<Map<String, dynamic>> forwardGeocode({
    required String address,
    LocationPoint? bias,
  }) async =>
      forward;

  @override
  Future<Map<String, dynamic>> placeDetails({
    required String placeId,
    required String sessionToken,
  }) async =>
      details;

  @override
  Future<Map<String, dynamic>> reverseGeocode(LocationPoint point) async =>
      reverse;
}
