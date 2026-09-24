import 'dart:math' as math;

import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';

enum DriverGpsAccuracy { low, medium, high }

class DriverGpsTrackingConfig {
  const DriverGpsTrackingConfig._({
    required this.accuracy,
    required this.distanceFilterMeters,
    required this.minimumUpdateInterval,
    required this.minimumPublishDistanceMeters,
    required this.maximumPublishInterval,
  });

  static const available = DriverGpsTrackingConfig._(
    accuracy: DriverGpsAccuracy.low,
    distanceFilterMeters: 50,
    minimumUpdateInterval: Duration(seconds: 30),
    minimumPublishDistanceMeters: 50,
    maximumPublishInterval: Duration(minutes: 2),
  );

  static const reserved = DriverGpsTrackingConfig._(
    accuracy: DriverGpsAccuracy.medium,
    distanceFilterMeters: 25,
    minimumUpdateInterval: Duration(seconds: 20),
    minimumPublishDistanceMeters: 25,
    maximumPublishInterval: Duration(minutes: 1),
  );

  static const activeTrip = DriverGpsTrackingConfig._(
    accuracy: DriverGpsAccuracy.high,
    distanceFilterMeters: 10,
    minimumUpdateInterval: Duration(seconds: 5),
    minimumPublishDistanceMeters: 10,
    maximumPublishInterval: Duration(seconds: 15),
  );

  final DriverGpsAccuracy accuracy;
  final int distanceFilterMeters;
  final Duration minimumUpdateInterval;
  final int minimumPublishDistanceMeters;
  final Duration maximumPublishInterval;

  static DriverGpsTrackingConfig? forAvailability(
    DriverAvailabilityState state,
  ) =>
      switch (state) {
        DriverAvailabilityState.available => available,
        DriverAvailabilityState.reserved => reserved,
        DriverAvailabilityState.onTrip => activeTrip,
        DriverAvailabilityState.offline => null,
      };

  bool isMeaningfulUpdate(
    DriverLocationFix current,
    DriverLocationFix? previous,
  ) {
    if (previous == null ||
        current.recordedAt.difference(previous.recordedAt) >=
            maximumPublishInterval) {
      return true;
    }

    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(
      current.point.latitude - previous.point.latitude,
    );
    final longitudeDelta = _radians(
      current.point.longitude - previous.point.longitude,
    );
    final previousLatitude = _radians(previous.point.latitude);
    final currentLatitude = _radians(current.point.latitude);
    final latitudeSin = math.sin(latitudeDelta / 2);
    final longitudeSin = math.sin(longitudeDelta / 2);
    final haversine = latitudeSin * latitudeSin +
        math.cos(previousLatitude) *
            math.cos(currentLatitude) *
            longitudeSin *
            longitudeSin;
    final distanceMeters =
        2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(haversine)));
    return distanceMeters >= minimumPublishDistanceMeters;
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}

abstract interface class DriverGpsStreamService {
  Stream<DriverLocationFix> foregroundFixes(DriverGpsTrackingConfig config);
}
