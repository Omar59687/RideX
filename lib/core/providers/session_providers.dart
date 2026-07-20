import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/app_notification.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/vehicle_type.dart';
import 'package:ridex/core/providers/repositories_providers.dart';

class SessionState {
  const SessionState({this.user});

  final AppUser? user;
  bool get isAuthenticated => user != null;
  RideRole? get role => user?.role;
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState();

  Future<void> continueAsDemo(RideRole role) async {
    final user = await ref.read(authRepositoryProvider).continueAsDemo(role);
    state = SessionState(user: user);
  }

  Future<void> signIn(
      {required String email,
      required String password,
      required RideRole role}) async {
    final user = await ref
        .read(authRepositoryProvider)
        .signIn(email: email, password: password, role: role);
    state = SessionState(user: user);
  }

  Future<void> signUp(
      {required String name,
      required String email,
      required String password,
      required RideRole role}) async {
    final user = await ref
        .read(authRepositoryProvider)
        .signUp(name: name, email: email, password: password, role: role);
    state = SessionState(user: user);
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const SessionState();
  }
}

class BookingController extends Notifier<BookingDraft> {
  @override
  BookingDraft build() => MockData.initialDraft();

  void setPickup(RideLocation location) {
    state = state.copyWith(
        pickup: location, clearVehicleType: true, estimatedFare: 0);
  }

  void setDestination(RideLocation location) {
    state = state.copyWith(
        destination: location, clearVehicleType: true, estimatedFare: 0);
  }

  void setVehicleType(VehicleType vehicleType) {
    state = state.copyWith(
        vehicleType: vehicleType, estimatedFare: vehicleType.baseFare);
  }

  Future<void> estimateFare() async {
    final fare = await ref.read(bookingRepositoryProvider).estimateFare(state);
    state = state.copyWith(estimatedFare: fare);
  }
}

class ActiveTripController extends Notifier<MockTrip?> {
  @override
  MockTrip? build() => null;

  Future<void> createTrip() async {
    final trip = await ref
        .read(tripsRepositoryProvider)
        .createTrip(ref.read(bookingControllerProvider));
    state = trip;
  }

  void setTrip(MockTrip trip) => state = trip;

  void setStatus(TripStatus status) {
    final trip = state;
    if (trip == null || !canTransition(trip.status, status)) return;
    state = trip.copyWith(status: status);
  }

  void reset() => state = null;
}

class NotificationsController extends Notifier<List<AppNotification>> {
  @override
  List<AppNotification> build() => MockData.notifications;

  void markAllRead() {
    state = [
      for (final notification in state) notification.copyWith(isRead: true)
    ];
  }
}

final selectedRoleProvider = StateProvider<RideRole>((ref) => RideRole.rider);
final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
final bookingControllerProvider =
    NotifierProvider<BookingController, BookingDraft>(BookingController.new);
final activeTripControllerProvider =
    NotifierProvider<ActiveTripController, MockTrip?>(ActiveTripController.new);
final notificationsControllerProvider =
    NotifierProvider<NotificationsController, List<AppNotification>>(
        NotificationsController.new);
final driverOnlineProvider = StateProvider<bool>((ref) => true);
