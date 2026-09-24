import 'dart:math' as math;

import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/location_point.dart';

enum DriverLocationRejection {
  missingAccuracy,
  expired,
  futureDated,
  outOfOrder,
  accuracyRegression,
}

class DriverLocationValidationPolicy {
  const DriverLocationValidationPolicy();

  static const maximumAge = Duration(minutes: 15);
  static const maximumFutureSkew = Duration(minutes: 5);

  DriverLocationRejection? rejectionFor({
    required DriverLocationFix candidate,
    required DateTime now,
    DriverLocationFix? previous,
  }) {
    final accuracy = candidate.point.accuracyMeters;
    if (accuracy == null) return DriverLocationRejection.missingAccuracy;

    final currentTime = now.toUtc();
    if (candidate.recordedAt.isBefore(currentTime.subtract(maximumAge))) {
      return DriverLocationRejection.expired;
    }
    if (candidate.recordedAt.isAfter(currentTime.add(maximumFutureSkew))) {
      return DriverLocationRejection.futureDated;
    }
    if (previous == null) return null;
    if (!candidate.recordedAt.isAfter(previous.recordedAt)) {
      return DriverLocationRejection.outOfOrder;
    }

    final previousAccuracy = previous.point.accuracyMeters;
    if (previousAccuracy != null &&
        accuracy > previousAccuracy &&
        distanceMeters(previous.point, candidate.point) <= accuracy) {
      return DriverLocationRejection.accuracyRegression;
    }
    return null;
  }

  static double distanceMeters(LocationPoint first, LocationPoint second) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(second.latitude - first.latitude);
    final longitudeDelta = _radians(second.longitude - first.longitude);
    final firstLatitude = _radians(first.latitude);
    final secondLatitude = _radians(second.latitude);
    final latitudeSin = math.sin(latitudeDelta / 2);
    final longitudeSin = math.sin(longitudeDelta / 2);
    final haversine = latitudeSin * latitudeSin +
        math.cos(firstLatitude) *
            math.cos(secondLatitude) *
            longitudeSin *
            longitudeSin;
    return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(haversine)));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
