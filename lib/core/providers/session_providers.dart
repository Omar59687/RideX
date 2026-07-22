import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/errors/auth_exception.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/app_notification.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/models/vehicle_type.dart';
import 'package:ridex/core/providers/repositories_providers.dart';

class SessionState {
  const SessionState({
    required this.status,
    this.user,
    this.errorMessage,
  });

  const SessionState.loading()
      : status = SessionStatus.loading,
        user = null,
        errorMessage = null;

  const SessionState.unauthenticated({this.errorMessage})
      : status = SessionStatus.unauthenticated,
        user = null;

  final SessionStatus status;
  final AppUser? user;
  final String? errorMessage;

  bool get isAuthenticated => user != null;
  RideRole? get role => user?.role;

  factory SessionState.fromUser(AppUser user) {
    if (user.isBlocked) {
      return SessionState(status: SessionStatus.blocked, user: user);
    }

    if (user.role == RideRole.driver) {
      return switch (user.driverApprovalStatus) {
        DriverApprovalStatus.rejected =>
          SessionState(status: SessionStatus.driverRejected, user: user),
        DriverApprovalStatus.pending ||
        null =>
          SessionState(status: SessionStatus.driverPending, user: user),
        DriverApprovalStatus.approved =>
          SessionState(status: SessionStatus.authenticated, user: user),
      };
    }

    return SessionState(status: SessionStatus.authenticated, user: user);
  }

  SessionState copyWith({
    SessionStatus? status,
    AppUser? user,
    String? errorMessage,
    bool clearUser = false,
  }) {
    return SessionState(
      status: status ?? this.status,
      user: clearUser ? null : user ?? this.user,
      errorMessage: errorMessage,
    );
  }
}

class SessionController extends Notifier<SessionState> {
  StreamSubscription<void>? _authSubscription;

  @override
  SessionState build() {
    _authSubscription ??=
        ref.read(authRepositoryProvider).authStateChanges().listen((_) {
      unawaited(refreshSession());
    });

    ref.onDispose(() => _authSubscription?.cancel());
    Future<void>.microtask(refreshSession);
    return const SessionState.loading();
  }

  Future<void> refreshSession() async {
    try {
      final user = await ref.read(authRepositoryProvider).restoreSession();
      state = user == null
          ? const SessionState.unauthenticated()
          : SessionState.fromUser(user);
    } on AuthException catch (error) {
      state = SessionState.unauthenticated(errorMessage: error.message);
    } catch (_) {
      state = const SessionState.unauthenticated(
        errorMessage: 'Unable to restore your session.',
      );
    }
  }

  Future<void> continueAsDemo(RideRole role) async {
    final user = await ref.read(authRepositoryProvider).continueAsDemo(role);
    state = SessionState.fromUser(user);
  }

  Future<String?> signIn({
    required String email,
    required String password,
    RideRole? role,
  }) async {
    state = const SessionState.loading();
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password, role: role);
      state = SessionState.fromUser(user);
      return null;
    } on AuthException catch (error) {
      state = SessionState.unauthenticated(errorMessage: error.message);
      return error.message;
    } catch (_) {
      const message = 'Unable to sign in right now.';
      state = const SessionState.unauthenticated(errorMessage: message);
      return message;
    }
  }

  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
    required RideRole role,
  }) async {
    state = const SessionState.loading();
    try {
      final user = await ref.read(authRepositoryProvider).signUp(
            name: name,
            email: email,
            password: password,
            role: role,
          );
      state = SessionState.fromUser(user);
      return null;
    } on AuthException catch (error) {
      state = SessionState.unauthenticated(errorMessage: error.message);
      return error.message;
    } catch (_) {
      const message = 'Unable to create your account right now.';
      state = const SessionState.unauthenticated(errorMessage: message);
      return message;
    }
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    ref.invalidate(notificationPreferencesProvider);
    state = const SessionState.unauthenticated();
  }
}

class BookingController extends Notifier<BookingDraft> {
  @override
  BookingDraft build() => MockData.initialDraft();

  void setPickup(RideLocation location) {
    state = state.copyWith(
      pickup: location,
      clearVehicleType: true,
      estimatedFare: 0,
    );
  }

  void setDestination(RideLocation location) {
    state = state.copyWith(
      destination: location,
      clearVehicleType: true,
      estimatedFare: 0,
    );
  }

  void setVehicleType(VehicleType vehicleType) {
    state = state.copyWith(
      vehicleType: vehicleType,
      estimatedFare: vehicleType.baseFare,
    );
  }

  Future<void> estimateFare() async {
    final fare = await ref.read(bookingRepositoryProvider).estimateFare(state);
    state = state.copyWith(estimatedFare: fare);
  }
}

class ActiveTripController extends Notifier<MockTrip?> {
  Future<void>? _tripCreation;

  @override
  MockTrip? build() => null;

  Future<void> createTrip() {
    return _tripCreation ??= _createTrip().whenComplete(() {
      _tripCreation = null;
    });
  }

  Future<void> _createTrip() async {
    final trip = await ref
        .read(tripsRepositoryProvider)
        .createTrip(ref.read(bookingControllerProvider));
    state = trip;
  }

  void setTrip(MockTrip trip) => state = trip;

  void setStatus(TripStatus status) {
    final trip = state;
    if (trip == null || !canTransition(trip.status, status)) {
      return;
    }
    state = trip.copyWith(status: status);
  }

  void reset() => state = null;
}

class NotificationsController extends Notifier<List<AppNotification>> {
  @override
  List<AppNotification> build() => MockData.notifications;

  void markAllRead() {
    state = [
      for (final notification in state) notification.copyWith(isRead: true),
    ];
  }

  void markRead(String id) {
    state = [
      for (final notification in state)
        notification.id == id
            ? notification.copyWith(isRead: true)
            : notification,
    ];
  }
}

class NotificationPreferences {
  const NotificationPreferences({
    this.push = true,
    this.sms = true,
    this.email = false,
  });

  final bool push;
  final bool sms;
  final bool email;

  NotificationPreferences copyWith({bool? push, bool? sms, bool? email}) {
    return NotificationPreferences(
      push: push ?? this.push,
      sms: sms ?? this.sms,
      email: email ?? this.email,
    );
  }
}

final selectedRoleProvider = StateProvider<RideRole>((ref) => RideRole.rider);
final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
final bookingControllerProvider =
    NotifierProvider<BookingController, BookingDraft>(BookingController.new);
final activeTripControllerProvider =
    NotifierProvider<ActiveTripController, MockTrip?>(
  ActiveTripController.new,
);
final notificationsControllerProvider =
    NotifierProvider<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);
final notificationPreferencesProvider = StateProvider<NotificationPreferences>(
  (ref) => const NotificationPreferences(),
);
final driverOnlineProvider = StateProvider<bool>((ref) => true);
