import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/booking_draft.dart';

enum TripStatus {
  requested,
  searching,
  accepted,
  driverArriving,
  driverArrived,
  inProgress,
  completed,
  cancelledByRider,
  cancelledByDriver,
  noDriverFound,
}

extension TripStatusX on TripStatus {
  String get label => switch (this) {
        TripStatus.requested => 'Requested',
        TripStatus.searching => 'Searching',
        TripStatus.accepted => 'Accepted',
        TripStatus.driverArriving => 'Driver arriving',
        TripStatus.driverArrived => 'Driver arrived',
        TripStatus.inProgress => 'In progress',
        TripStatus.completed => 'Completed',
        TripStatus.cancelledByRider => 'Cancelled by rider',
        TripStatus.cancelledByDriver => 'Cancelled by driver',
        TripStatus.noDriverFound => 'No driver found',
      };
}

class DriverSummary extends Equatable {
  const DriverSummary({
    required this.name,
    required this.rating,
    required this.vehicleName,
    required this.plate,
    required this.etaMinutes,
  });

  final String name;
  final double rating;
  final String vehicleName;
  final String plate;
  final int etaMinutes;

  @override
  List<Object?> get props => [name, rating, vehicleName, plate, etaMinutes];
}

class MockTrip extends Equatable {
  const MockTrip({
    required this.id,
    required this.booking,
    required this.status,
    required this.driver,
    required this.finalFare,
    this.occurredAt,
  });

  final String id;
  final BookingDraft booking;
  final TripStatus status;
  final DriverSummary driver;
  final double finalFare;
  final DateTime? occurredAt;

  MockTrip copyWith({
    TripStatus? status,
    double? finalFare,
    DateTime? occurredAt,
  }) {
    return MockTrip(
      id: id,
      booking: booking,
      status: status ?? this.status,
      driver: driver,
      finalFare: finalFare ?? this.finalFare,
      occurredAt: occurredAt ?? this.occurredAt,
    );
  }

  @override
  List<Object?> get props =>
      [id, booking, status, driver, finalFare, occurredAt];
}

bool canTransition(TripStatus from, TripStatus to) {
  return switch (from) {
    TripStatus.requested =>
      {TripStatus.searching, TripStatus.cancelledByRider}.contains(to),
    TripStatus.searching => {
        TripStatus.accepted,
        TripStatus.cancelledByRider,
        TripStatus.noDriverFound
      }.contains(to),
    TripStatus.accepted => {
        TripStatus.driverArriving,
        TripStatus.cancelledByRider,
        TripStatus.cancelledByDriver
      }.contains(to),
    TripStatus.driverArriving => {
        TripStatus.driverArrived,
        TripStatus.cancelledByRider,
        TripStatus.cancelledByDriver
      }.contains(to),
    TripStatus.driverArrived => {
        TripStatus.inProgress,
        TripStatus.cancelledByRider,
        TripStatus.cancelledByDriver
      }.contains(to),
    TripStatus.inProgress => to == TripStatus.completed,
    TripStatus.completed ||
    TripStatus.cancelledByRider ||
    TripStatus.cancelledByDriver ||
    TripStatus.noDriverFound =>
      false,
  };
}
