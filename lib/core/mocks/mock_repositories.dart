import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/repositories/auth_repository.dart';
import 'package:ridex/core/repositories/booking_repository.dart';
import 'package:ridex/core/repositories/profile_repository.dart';
import 'package:ridex/core/repositories/trips_repository.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/vehicle_type.dart';

class MockAuthRepository implements AuthRepository {
  @override
  Future<AppUser> continueAsDemo(RideRole role) async {
    return role == RideRole.rider ? MockData.demoRider : MockData.demoDriver;
  }

  @override
  Future<AppUser> signIn(
      {required String email,
      required String password,
      required RideRole role}) async {
    return continueAsDemo(role);
  }

  @override
  Future<AppUser> signUp(
      {required String name,
      required String email,
      required String password,
      required RideRole role}) async {
    return AppUser(id: 'demo-$name', name: name, email: email, role: role);
  }

  @override
  Future<void> signOut() async {}
}

class MockBookingRepository implements BookingRepository {
  @override
  Future<double> estimateFare(BookingDraft draft) async {
    final base = draft.vehicleType?.baseFare ?? 2;
    return base + (draft.distanceKm * 0.2) + ((draft.stops.length) * 0.3);
  }

  @override
  Future<List<RideLocation>> getSavedLocations() async => MockData.locations;

  @override
  Future<List<VehicleType>> getVehicleTypes() async => MockData.vehicleTypes;
}

class MockTripsRepository implements TripsRepository {
  @override
  Future<MockTrip> createTrip(BookingDraft draft) async {
    return MockTrip(
      id: 'trip-1',
      booking: draft,
      status: TripStatus.searching,
      driver: MockData.driver,
      finalFare: draft.estimatedFare,
    );
  }

  @override
  Future<List<MockTrip>> getTripHistory() async => MockData.history();
}

class MockProfileRepository implements ProfileRepository {
  @override
  Future<AppUser> getProfile(String userId) async {
    return userId == MockData.demoDriver.id
        ? MockData.demoDriver
        : MockData.demoRider;
  }
}
