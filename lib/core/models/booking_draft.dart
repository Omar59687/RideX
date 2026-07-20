import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/vehicle_type.dart';

class RideLocation extends Equatable {
  const RideLocation({required this.label, required this.address});

  final String label;
  final String address;

  @override
  List<Object?> get props => [label, address];
}

class BookingDraft extends Equatable {
  const BookingDraft({
    this.pickup,
    this.destination,
    this.stops = const [],
    this.vehicleType,
    this.distanceKm = 5,
    this.etaMinutes = 12,
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
    bool clearVehicleType = false,
  }) {
    return BookingDraft(
      pickup: pickup ?? this.pickup,
      destination: destination ?? this.destination,
      stops: stops ?? this.stops,
      vehicleType: clearVehicleType ? null : vehicleType ?? this.vehicleType,
      distanceKm: distanceKm ?? this.distanceKm,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      estimatedFare: estimatedFare ?? this.estimatedFare,
    );
  }

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
