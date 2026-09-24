import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/services/driver_location/driver_location_validation_policy.dart';

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

    final distanceMeters = DriverLocationValidationPolicy.distanceMeters(
      previous.point,
      current.point,
    );
    return distanceMeters >= minimumPublishDistanceMeters;
  }
}

abstract interface class DriverGpsStreamService {
  Stream<DriverLocationFix> foregroundFixes(DriverGpsTrackingConfig config);
}
