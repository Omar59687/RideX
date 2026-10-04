import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/errors/auth_exception.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/app_notification.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/models/vehicle_type.dart';
import 'package:ridex/core/providers/driver_tracking_providers.dart';
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

  const SessionState.profileError({required this.errorMessage})
      : status = SessionStatus.profileError,
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
    } on ProfileException catch (error) {
      state = SessionState.profileError(errorMessage: error.message);
    } on AuthException catch (error) {
      state = SessionState.unauthenticated(errorMessage: error.message);
    } catch (_) {
      state = const SessionState.unauthenticated(
        errorMessage: 'Unable to restore your session.',
      );
    }
  }

  Future<void> continueAsDemo() async {
    final user = await ref.read(authRepositoryProvider).continueAsDemo();
    state = SessionState.fromUser(user);
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    state = const SessionState.loading();
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password);
      state = SessionState.fromUser(user);
      return null;
    } on ProfileException catch (error) {
      state = SessionState.profileError(errorMessage: error.message);
      return error.message;
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
  }) async {
    state = const SessionState.loading();
    try {
      final user = await ref.read(authRepositoryProvider).signUp(
            name: name,
            email: email,
            password: password,
          );
      state = SessionState.fromUser(user);
      return null;
    } on ProfileException catch (error) {
      state = SessionState.profileError(errorMessage: error.message);
      return error.message;
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
    await ref.read(driverTrackingControllerProvider.notifier).stopForSignOut();
    await ref.read(authRepositoryProvider).signOut();
    ref.invalidate(bookingControllerProvider);
    ref.invalidate(activeTripControllerProvider);
    ref.invalidate(notificationsControllerProvider);
    ref.invalidate(notificationPreferencesProvider);
    ref.invalidate(driverOnlineProvider);
    state = const SessionState.unauthenticated();
  }
}

class BookingController extends Notifier<BookingDraft> {
  /// Maximum number of intermediate stops in a booking draft.
  static const int maxStops = 3;

  @override
  BookingDraft build() => MockData.initialDraft();

  void setPickup(RideLocation location) {
    state = state.copyWith(
      pickup: location,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  void setDestination(RideLocation location) {
    state = state.copyWith(
      destination: location,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  void clearPickup() {
    state = state.copyWith(
      clearPickup: true,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  void clearDestination() {
    state = state.copyWith(
      clearDestination: true,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  void setVehicleType(VehicleType vehicleType) {
    state = state.copyWith(
      vehicleType: vehicleType,
      estimatedFare: vehicleType.baseFare,
    );
  }

  /// Adds an intermediate stop at the end of the ordered stop list.
  ///
  /// Returns `true` when the stop was added and `false` when it was
  /// rejected. A stop is rejected when the draft already holds [maxStops]
  /// stops, when its coordinates are invalid (non-finite or outside the
  /// `LocationPoint` latitude/longitude ranges), or when its coordinates
  /// duplicate the current pickup, the current destination, or an
  /// already-added stop (latitude/longitude equality, matching the
  /// `sameLocation` convention in [BookingDraft.locationValidation]).
  /// A successful add clears the selected vehicle and any fare, distance,
  /// and ETA estimates, consistent with [setPickup]/[setDestination].
  /// Rejected adds leave the state untouched.
  bool addStop(RideLocation stop) {
    if (state.stops.length >= maxStops) return false;
    if (!_hasValidCoordinates(stop.point)) return false;
    if (_isDuplicateStop(stop)) return false;
    state = state.copyWith(
      stops: [...state.stops, stop],
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
    return true;
  }

  /// Removes the stop at [index].
  ///
  /// Out-of-range indexes are a no-op: the state is left untouched
  /// (no estimate reset), so callers can safely forward UI indexes.
  void removeStopAt(int index) {
    if (index < 0 || index >= state.stops.length) return;
    final stops = [...state.stops]..removeAt(index);
    state = state.copyWith(
      stops: stops,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  /// Moves the stop at [from] to position [to], preserving list order
  /// for all other stops.
  ///
  /// Out-of-range indexes (or a [from] equal to [to]) are a no-op: the
  /// state is left untouched, so callers can safely forward UI indexes.
  void moveStop(int from, int to) {
    if (from < 0 ||
        from >= state.stops.length ||
        to < 0 ||
        to >= state.stops.length ||
        from == to) {
      return;
    }
    final stops = [...state.stops];
    final stop = stops.removeAt(from);
    stops.insert(to, stop);
    state = state.copyWith(
      stops: stops,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  /// Removes all intermediate stops.
  ///
  /// Clearing an already-empty stop list is a no-op: the state is left
  /// untouched. A non-empty clear resets the selected vehicle and any
  /// fare, distance, and ETA estimates, consistent with [setPickup].
  void clearStops() {
    if (state.stops.isEmpty) return;
    state = state.copyWith(
      stops: const [],
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  bool _hasValidCoordinates(LocationPoint point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  bool _isDuplicateStop(RideLocation stop) {
    bool samePoint(RideLocation other) =>
        other.point.latitude == stop.point.latitude &&
        other.point.longitude == stop.point.longitude;
    final pickup = state.pickup;
    if (pickup != null && samePoint(pickup)) return true;
    final destination = state.destination;
    if (destination != null && samePoint(destination)) return true;
    return state.stops.any(samePoint);
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
