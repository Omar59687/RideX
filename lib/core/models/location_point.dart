import 'package:equatable/equatable.dart';

class LocationPoint extends Equatable {
  factory LocationPoint({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(
          latitude, 'latitude', 'Must be from -90 to 90.');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'Must be from -180 to 180.',
      );
    }
    if (accuracyMeters != null &&
        (!accuracyMeters.isFinite || accuracyMeters < 0)) {
      throw ArgumentError.value(
        accuracyMeters,
        'accuracyMeters',
        'Must be finite and nonnegative.',
      );
    }

    return LocationPoint._(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
    );
  }

  const LocationPoint._({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  @override
  List<Object?> get props => [latitude, longitude, accuracyMeters];
}
