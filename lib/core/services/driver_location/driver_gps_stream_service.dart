import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';

enum DriverGpsAccuracy { reduced, high }

class DriverGpsTrackingConfig {
  const DriverGpsTrackingConfig._({
    required this.accuracy,
    required this.distanceFilterMeters,
    required this.minimumUpdateInterval,
  });

  static const reduced = DriverGpsTrackingConfig._(
    accuracy: DriverGpsAccuracy.reduced,
    distanceFilterMeters: 25,
    minimumUpdateInterval: Duration(seconds: 20),
  );

  static const activeTrip = DriverGpsTrackingConfig._(
    accuracy: DriverGpsAccuracy.high,
    distanceFilterMeters: 10,
    minimumUpdateInterval: Duration(seconds: 5),
  );

  final DriverGpsAccuracy accuracy;
  final int distanceFilterMeters;
  final Duration minimumUpdateInterval;

  static DriverGpsTrackingConfig? forAvailability(
    DriverAvailabilityState state,
  ) =>
      switch (state) {
        DriverAvailabilityState.available ||
        DriverAvailabilityState.reserved =>
          reduced,
        DriverAvailabilityState.onTrip => activeTrip,
        DriverAvailabilityState.offline => null,
      };
}

abstract interface class DriverGpsStreamService {
  Stream<DriverLocationFix> foregroundFixes(DriverGpsTrackingConfig config);
}
