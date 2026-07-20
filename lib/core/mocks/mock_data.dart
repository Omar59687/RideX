import 'package:ridex/core/models/app_notification.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/booking_draft.dart';
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
  );

  static const locations = [
    RideLocation(label: 'My current location', address: 'Hashemite University'),
    RideLocation(label: 'Abdali Mall', address: 'Abdali Boulevard'),
    RideLocation(label: 'Airport Center', address: 'Queen Alia Airport'),
    RideLocation(label: '7th Circle', address: 'Amman, Jordan'),
  ];

  static const vehicleTypes = [
    VehicleType(
      id: 'taxi',
      name: 'Taxi',
      capacity: 2,
      arrivalMinutes: 2,
      baseFare: 1.99,
      description: 'Fast pickup for short city rides.',
      isPopular: true,
    ),
    VehicleType(
      id: 'economy',
      name: 'Economy',
      capacity: 5,
      arrivalMinutes: 4,
      baseFare: 5.0,
      description: 'Comfortable daily rides with extra room.',
    ),
    VehicleType(
      id: 'economy_plus',
      name: 'Economy+',
      capacity: 6,
      arrivalMinutes: 5,
      baseFare: 8.99,
      description: 'Best for groups, bags, and longer distances.',
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

  static BookingDraft initialDraft() => const BookingDraft(
        pickup: RideLocation(label: 'Pickup', address: 'Hashemite University'),
        destination:
            RideLocation(label: 'Drop-off', address: 'Abdali Boulevard'),
        distanceKm: 5,
        etaMinutes: 12,
      );

  static MockTrip sampleTrip({TripStatus status = TripStatus.accepted}) {
    final booking = initialDraft().copyWith(
      vehicleType: vehicleTypes.first,
      estimatedFare: 1.99,
    );
    return MockTrip(
      id: 'trip-1',
      booking: booking,
      status: status,
      driver: driver,
      finalFare: 1.99,
    );
  }

  static List<MockTrip> history() => [
        sampleTrip(status: TripStatus.completed),
        sampleTrip(status: TripStatus.cancelledByRider).copyWith(finalFare: 0),
      ];
}
