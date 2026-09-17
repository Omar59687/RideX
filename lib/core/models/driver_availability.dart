import 'package:equatable/equatable.dart';

enum DriverAvailabilityState { offline, available, reserved, onTrip }

extension DriverAvailabilityStateX on DriverAvailabilityState {
  static DriverAvailabilityState fromDatabase(String value) {
    return switch (value) {
      'offline' => DriverAvailabilityState.offline,
      'available' => DriverAvailabilityState.available,
      'reserved' => DriverAvailabilityState.reserved,
      'onTrip' => DriverAvailabilityState.onTrip,
      _ => throw ArgumentError.value(value, 'value', 'Unknown availability.'),
    };
  }

  String get databaseValue => switch (this) {
        DriverAvailabilityState.offline => 'offline',
        DriverAvailabilityState.available => 'available',
        DriverAvailabilityState.reserved => 'reserved',
        DriverAvailabilityState.onTrip => 'onTrip',
      };
}

class DriverAvailability extends Equatable {
  const DriverAvailability({required this.state, this.activeTripId})
      : assert(
          state == DriverAvailabilityState.onTrip
              ? activeTripId != null
              : activeTripId == null,
        );

  final DriverAvailabilityState state;
  final String? activeTripId;

  bool get canShareLocation =>
      state == DriverAvailabilityState.available ||
      state == DriverAvailabilityState.reserved ||
      state == DriverAvailabilityState.onTrip;

  @override
  List<Object?> get props => [state, activeTripId];
}
