import 'package:equatable/equatable.dart';

class VehicleType extends Equatable {
  const VehicleType({
    required this.id,
    required this.name,
    required this.capacity,
    required this.arrivalMinutes,
    required this.baseFare,
    required this.description,
    this.isPopular = false,
  });

  final String id;
  final String name;
  final int capacity;
  final int arrivalMinutes;
  final double baseFare;
  final String description;
  final bool isPopular;

  @override
  List<Object?> get props =>
      [id, name, capacity, arrivalMinutes, baseFare, description, isPopular];
}
