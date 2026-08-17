import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/location_point.dart';

void main() {
  test('accepts valid provider-independent coordinates', () {
    final point = LocationPoint(
      latitude: 31.963158,
      longitude: 35.930359,
      accuracyMeters: 6.5,
    );

    expect(point.latitude, 31.963158);
    expect(point.longitude, 35.930359);
    expect(point.accuracyMeters, 6.5);
  });

  test('rejects invalid coordinate and accuracy values', () {
    expect(
      () => LocationPoint(latitude: double.nan, longitude: 0),
      throwsArgumentError,
    );
    expect(
      () => LocationPoint(latitude: 91, longitude: 0),
      throwsArgumentError,
    );
    expect(
      () => LocationPoint(latitude: 0, longitude: -181),
      throwsArgumentError,
    );
    expect(
      () => LocationPoint(
        latitude: 0,
        longitude: 0,
        accuracyMeters: -1,
      ),
      throwsArgumentError,
    );
  });
}
