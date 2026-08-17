import 'package:ridex/core/models/app_notification.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/vehicle_type.dart';

class MockData {
  const MockData._();

  static const demoRider = AppUser(
    id: 'rider-1',
    name: 'Ahmed Yaser',
    email: 'ahmed@ridex.demo',
    role: RideRole.rider,
  );

  static const demoDriver = AppUser(
    id: 'driver-1',
    name: 'Omar Salem',
    email: 'omar@ridex.demo',
    role: RideRole.driver,
    driverApprovalStatus: DriverApprovalStatus.approved,
  );

  static const demoAdmin = AppUser(
    id: 'admin-1',
    name: 'RideX Admin',
    email: 'admin@ridex.demo',
    role: RideRole.admin,
  );

  static final locations = [
    RideLocation(
      point: LocationPoint(latitude: 32.1026, longitude: 36.1848),
      label: 'Hashemite University',
      address: 'Hashemite University, Zarqa, Jordan',
      source: LocationSelectionSource.demo,
      providerName: 'demo',
      providerPlaceReference: 'demo-hashemite-university',
    ),
    RideLocation(
      point: LocationPoint(latitude: 31.9632, longitude: 35.9084),
      label: 'Abdali Mall',
      address: 'Abdali Boulevard, Amman, Jordan',
      source: LocationSelectionSource.demo,
      providerName: 'demo',
      providerPlaceReference: 'demo-abdali-mall',
    ),
    RideLocation(
      point: LocationPoint(latitude: 31.7226, longitude: 35.9932),
      label: 'Queen Alia Airport',
      address: 'Queen Alia International Airport, Jordan',
      source: LocationSelectionSource.demo,
      providerName: 'demo',
      providerPlaceReference: 'demo-queen-alia-airport',
    ),
    RideLocation(
      point: LocationPoint(latitude: 31.9592, longitude: 35.8575),
      label: '7th Circle',
      address: '7th Circle, Amman, Jordan',
      source: LocationSelectionSource.demo,
      providerName: 'demo',
      providerPlaceReference: 'demo-7th-circle',
    ),
  ];

  static const vehicleTypes = [
    VehicleType(
      id: 'economy',
      name: 'Economy',
      capacity: 4,
      arrivalMinutes: 3,
      baseFare: 4.20,
      description: 'Smart value for everyday rides.',
    ),
    VehicleType(
      id: 'standard',
      name: 'Standard',
      capacity: 4,
      arrivalMinutes: 5,
      baseFare: 5.80,
      description: 'More comfort and highly rated drivers.',
      isPopular: true,
    ),
    VehicleType(
      id: 'premium',
      name: 'Premium',
      capacity: 4,
      arrivalMinutes: 7,
      baseFare: 8.90,
      description: 'Quiet, spacious executive cars.',
    ),
  ];

  static const driver = DriverSummary(
    name: 'Omar',
    rating: 4.9,
    vehicleName: 'Toyota Camry',
    plate: '652-UKW',
    etaMinutes: 2,
  );

  static const notifications = [
    AppNotification(
      id: '1',
      title: 'Ride matched',
      body: 'Omar is heading to your pickup location.',
      timeLabel: '2 min ago',
    ),
    AppNotification(
      id: '2',
      title: 'Trip completed',
      body: 'Your ride to Abdali Boulevard was completed successfully.',
      timeLabel: 'Today',
      isRead: true,
    ),
  ];

  static BookingDraft initialDraft() => const BookingDraft();

  static BookingDraft sampleBookingDraft() => BookingDraft(
        pickup: locations[0],
        destination: locations[1],
        distanceKm: 5,
        etaMinutes: 12,
      );

  static MockTrip sampleTrip({
    String id = 'trip-1',
    TripStatus status = TripStatus.accepted,
    DateTime? occurredAt,
  }) {
    final booking = sampleBookingDraft().copyWith(
      vehicleType: vehicleTypes.first,
      estimatedFare: 4.20,
    );
    return MockTrip(
      id: id,
      booking: booking,
      status: status,
      driver: driver,
      finalFare: 4.20,
      occurredAt: occurredAt,
    );
  }

  static List<MockTrip> history() => [
        sampleTrip(
          id: 'trip-completed-1',
          status: TripStatus.completed,
          occurredAt: DateTime(2026, 7, 21, 9, 24),
        ),
        sampleTrip(
          id: 'trip-cancelled-1',
          status: TripStatus.cancelledByRider,
          occurredAt: DateTime(2026, 7, 18, 18, 40),
        ).copyWith(finalFare: 0),
      ];
}
