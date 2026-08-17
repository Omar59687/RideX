import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/vehicle_type.dart';

enum LocationSelectionSource { search, map, gps, saved, recent, demo }

class RideLocation extends Equatable {
  const RideLocation({
    required this.point,
    required this.label,
    required this.address,
    required this.source,
    this.providerName,
    this.providerPlaceReference,
  });

  final LocationPoint point;
  final String label;
  final String address;
  final LocationSelectionSource source;
  final String? providerName;
  final String? providerPlaceReference;

  @override
  List<Object?> get props => [
        point,
        label,
        address,
        source,
        providerName,
        providerPlaceReference,
      ];
}

enum BookingLocationValidation {
  valid,
  missingPickup,
  missingDestination,
  sameLocation,
}

class BookingDraft extends Equatable {
  const BookingDraft({
    this.pickup,
    this.destination,
    this.stops = const [],
    this.vehicleType,
    this.distanceKm = 0,
    this.etaMinutes = 0,
    this.estimatedFare = 0,
  });

  final RideLocation? pickup;
  final RideLocation? destination;
  final List<RideLocation> stops;
  final VehicleType? vehicleType;
  final double distanceKm;
  final int etaMinutes;
  final double estimatedFare;

  BookingDraft copyWith({
    RideLocation? pickup,
    RideLocation? destination,
    List<RideLocation>? stops,
    VehicleType? vehicleType,
    double? distanceKm,
    int? etaMinutes,
    double? estimatedFare,
    bool clearPickup = false,
    bool clearDestination = false,
    bool clearVehicleType = false,
  }) {
    return BookingDraft(
      pickup: clearPickup ? null : pickup ?? this.pickup,
      destination: clearDestination ? null : destination ?? this.destination,
      stops: stops ?? this.stops,
      vehicleType: clearVehicleType ? null : vehicleType ?? this.vehicleType,
      distanceKm: distanceKm ?? this.distanceKm,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      estimatedFare: estimatedFare ?? this.estimatedFare,
    );
  }

  BookingLocationValidation get locationValidation {
    final pickupPoint = pickup?.point;
    if (pickupPoint == null) return BookingLocationValidation.missingPickup;
    final destinationPoint = destination?.point;
    if (destinationPoint == null) {
      return BookingLocationValidation.missingDestination;
    }
    if (pickupPoint.latitude == destinationPoint.latitude &&
        pickupPoint.longitude == destinationPoint.longitude) {
      return BookingLocationValidation.sameLocation;
    }
    return BookingLocationValidation.valid;
  }

  bool get isRoutingReady =>
      locationValidation == BookingLocationValidation.valid;

  @override
  List<Object?> get props => [
        pickup,
        destination,
        stops,
        vehicleType,
        distanceKm,
        etaMinutes,
        estimatedFare
      ];
}
