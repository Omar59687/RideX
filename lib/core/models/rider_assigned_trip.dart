import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/payment_method.dart';

class RiderTripPlace extends Equatable {
  RiderTripPlace({required this.point, String? label})
      : label = _optionalText(label, 'label', 200);

  final LocationPoint point;
  final String? label;

  @override
  List<Object?> get props => [point, label];
}

class RiderDriverSummary extends Equatable {
  RiderDriverSummary({
    required String driverId,
    String? displayName,
    this.ratingAverage,
    this.ratingCount,
  })  : driverId = _canonicalId(driverId, 'driverId'),
        displayName = _optionalText(displayName, 'displayName', 200) {
    if (ratingAverage != null &&
        (!ratingAverage!.isFinite ||
            ratingAverage! < 0 ||
            ratingAverage! > 5)) {
      throw ArgumentError.value(
        ratingAverage,
        'ratingAverage',
        'Must be finite and from 0 to 5.',
      );
    }
    if (ratingCount != null && ratingCount! < 0) {
      throw ArgumentError.value(
        ratingCount,
        'ratingCount',
        'Must be nonnegative.',
      );
    }
    if ((ratingAverage == null) != (ratingCount == null)) {
      throw ArgumentError(
        'ratingAverage and ratingCount must be provided together.',
      );
    }
  }

  final String driverId;
  final String? displayName;
  final double? ratingAverage;
  final int? ratingCount;

  @override
  List<Object?> get props => [
        driverId,
        displayName,
        ratingAverage,
        ratingCount,
      ];
}

class RiderVehicleSummary extends Equatable {
  RiderVehicleSummary({
    required String vehicleId,
    String? make,
    String? model,
    String? color,
    String? registrationPlate,
    this.seatCapacity,
  })  : vehicleId = _canonicalId(vehicleId, 'vehicleId'),
        make = _optionalText(make, 'make', 100),
        model = _optionalText(model, 'model', 100),
        color = _optionalText(color, 'color', 50),
        registrationPlate = _optionalText(
          registrationPlate,
          'registrationPlate',
          32,
          minimumLength: 3,
        ) {
    if (seatCapacity != null && (seatCapacity! < 1 || seatCapacity! > 12)) {
      throw ArgumentError.value(
        seatCapacity,
        'seatCapacity',
        'Must be from 1 to 12.',
      );
    }
  }

  final String vehicleId;
  final String? make;
  final String? model;
  final String? color;
  final String? registrationPlate;
  final int? seatCapacity;

  @override
  List<Object?> get props => [
        vehicleId,
        make,
        model,
        color,
        registrationPlate,
        seatCapacity,
      ];
}

class RiderAssignedTrip extends Equatable {
  RiderAssignedTrip({
    required String tripId,
    required String bookingRequestId,
    required String riderId,
    required this.version,
    required this.status,
    required this.paymentMethod,
    required this.pickup,
    required this.destination,
    List<RiderTripPlace> stops = const [],
    required this.routeDistanceMeters,
    required this.routeDurationSeconds,
    String? routeGeometryReference,
    required this.originalFareFils,
    required this.currentFareFils,
    required String currency,
    required this.driver,
    required this.vehicle,
    required DateTime acceptedAt,
    required DateTime updatedAt,
  })  : tripId = _canonicalId(tripId, 'tripId'),
        bookingRequestId = _canonicalId(bookingRequestId, 'bookingRequestId'),
        riderId = _canonicalId(riderId, 'riderId'),
        stops = List.unmodifiable(stops),
        routeGeometryReference = _optionalText(
          routeGeometryReference,
          'routeGeometryReference',
          2048,
        ),
        currency = _currency(currency),
        acceptedAt = acceptedAt.toUtc(),
        updatedAt = updatedAt.toUtc() {
    if (version <= 0) {
      throw ArgumentError.value(version, 'version', 'Must be positive.');
    }
    if (paymentMethod != PaymentMethod.cash) {
      throw ArgumentError.value(
        paymentMethod,
        'paymentMethod',
        'Phase 7 Rider trips must use Cash.',
      );
    }
    if (this.stops.length > 3) {
      throw ArgumentError.value(
        stops,
        'stops',
        'Must contain at most three entries.',
      );
    }
    if (pickup.point.latitude == destination.point.latitude &&
        pickup.point.longitude == destination.point.longitude) {
      throw ArgumentError.value(
        destination,
        'destination',
        'Must differ from pickup.',
      );
    }
    if (routeDistanceMeters < 0) {
      throw ArgumentError.value(
        routeDistanceMeters,
        'routeDistanceMeters',
        'Must be nonnegative.',
      );
    }
    if (routeDurationSeconds < 0) {
      throw ArgumentError.value(
        routeDurationSeconds,
        'routeDurationSeconds',
        'Must be nonnegative.',
      );
    }
    if (originalFareFils < 0 || currentFareFils < 0) {
      throw ArgumentError.value(
        originalFareFils < 0 ? originalFareFils : currentFareFils,
        originalFareFils < 0 ? 'originalFareFils' : 'currentFareFils',
        'Must be nonnegative.',
      );
    }
  }

  final String tripId;
  final String bookingRequestId;
  final String riderId;
  final int version;
  final DriverTripLifecycleStatus status;
  final PaymentMethod paymentMethod;
  final RiderTripPlace pickup;
  final RiderTripPlace destination;
  final List<RiderTripPlace> stops;
  final int routeDistanceMeters;
  final int routeDurationSeconds;
  final String? routeGeometryReference;
  final int originalFareFils;
  final int currentFareFils;
  final String currency;
  final RiderDriverSummary driver;
  final RiderVehicleSummary vehicle;
  final DateTime acceptedAt;
  final DateTime updatedAt;

  bool get isTerminal => switch (status) {
        DriverTripLifecycleStatus.completed ||
        DriverTripLifecycleStatus.cancelledByRider ||
        DriverTripLifecycleStatus.cancelledByDriver ||
        DriverTripLifecycleStatus.cancelledByAdmin ||
        DriverTripLifecycleStatus.failed =>
          true,
        DriverTripLifecycleStatus.accepted ||
        DriverTripLifecycleStatus.driverArriving ||
        DriverTripLifecycleStatus.driverArrived ||
        DriverTripLifecycleStatus.inProgress =>
          false,
      };

  @override
  List<Object?> get props => [
        tripId,
        bookingRequestId,
        riderId,
        version,
        status,
        paymentMethod,
        pickup,
        destination,
        stops,
        routeDistanceMeters,
        routeDurationSeconds,
        routeGeometryReference,
        originalFareFils,
        currentFareFils,
        currency,
        driver,
        vehicle,
        acceptedAt,
        updatedAt,
      ];
}

String _canonicalId(String value, String name) {
  if (!isCanonicalTripId(value)) {
    throw ArgumentError.value(value, name, 'Must be a canonical UUID.');
  }
  return value;
}

String? _optionalText(
  String? value,
  String name,
  int maximumLength, {
  int minimumLength = 1,
}) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length < minimumLength ||
      trimmed.length > maximumLength) {
    throw ArgumentError.value(
      value,
      name,
      'Must be $minimumLength..$maximumLength characters after trimming.',
    );
  }
  return trimmed;
}

String _currency(String value) {
  if (value != 'JOD') {
    throw ArgumentError.value(value, 'currency', 'Must be JOD.');
  }
  return value;
}
