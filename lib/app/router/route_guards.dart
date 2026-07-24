import 'package:go_router/go_router.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';

enum _RoutePolicy {
  public,
  rider,
  driver,
  admin,
  shared,
  applicationStatus,
  blocked,
  profileError,
  unknown,
}

String? redirectForSession(GoRouterState state, SessionState session) {
  return redirectForLocation(state.matchedLocation, session);
}

String? redirectForLocation(String location, SessionState session) {
  final policy = _policyForLocation(location);

  if (session.status == SessionStatus.loading) {
    // Keep public auth forms mounted during a submission so errors can render.
    return policy == _RoutePolicy.public ? null : '/';
  }

  if (session.status == SessionStatus.unauthenticated) {
    return policy == _RoutePolicy.public ? null : '/sign-in';
  }

  if (session.status == SessionStatus.profileError) {
    return policy == _RoutePolicy.profileError ? null : '/profile-error';
  }

  if (session.status == SessionStatus.blocked) {
    return policy == _RoutePolicy.blocked ? null : '/account-blocked';
  }

  if (session.status == SessionStatus.driverPending ||
      session.status == SessionStatus.driverRejected) {
    return policy == _RoutePolicy.applicationStatus
        ? null
        : '/driver/application';
  }

  final role = session.role;
  if (role == null) return '/profile-error';
  final home = locationForRole(role);

  return switch (policy) {
    _RoutePolicy.public ||
    _RoutePolicy.applicationStatus ||
    _RoutePolicy.blocked ||
    _RoutePolicy.profileError ||
    _RoutePolicy.unknown =>
      home,
    _RoutePolicy.rider => role == RideRole.rider ? null : home,
    _RoutePolicy.driver => role == RideRole.driver ? null : home,
    _RoutePolicy.admin => role == RideRole.admin ? null : home,
    _RoutePolicy.shared => null,
  };
}

_RoutePolicy _policyForLocation(String location) {
  if (_publicLocations.contains(location)) return _RoutePolicy.public;
  if (_riderLocations.contains(location)) return _RoutePolicy.rider;
  if (_driverLocations.contains(location)) return _RoutePolicy.driver;
  if (_sharedLocations.contains(location) || _isTripDetailsLocation(location)) {
    return _RoutePolicy.shared;
  }

  return switch (location) {
    '/admin' => _RoutePolicy.admin,
    '/driver/application' => _RoutePolicy.applicationStatus,
    '/account-blocked' => _RoutePolicy.blocked,
    '/profile-error' => _RoutePolicy.profileError,
    _ => _RoutePolicy.unknown,
  };
}

bool _isTripDetailsLocation(String location) {
  return location.startsWith('/history/') &&
      location.length > '/history/'.length;
}

const _publicLocations = {
  '/',
  '/onboarding',
  '/sign-in',
  '/sign-up',
  '/forgot-password',
  '/verify-otp',
};

const _riderLocations = {
  '/rider/home',
  '/rider/pickup',
  '/rider/destination',
  '/rider/vehicle',
  '/rider/fare',
  '/rider/searching',
  '/rider/trip',
  '/rider/completed',
  '/rider/rating',
  '/rider/profile',
};

const _driverLocations = {
  '/driver/home',
  '/driver/profile',
  '/driver/request',
  '/driver/arrival',
  '/driver/trip',
  '/driver/completed',
};

const _sharedLocations = {
  '/history',
  '/notifications',
  '/settings',
};

String locationForRole(RideRole role) {
  return switch (role) {
    RideRole.rider => '/rider/home',
    RideRole.driver => '/driver/home',
    RideRole.admin => '/admin',
  };
}

String nextTripRouteForRole(RideRole role) {
  return switch (role) {
    RideRole.rider => '/rider/trip',
    RideRole.driver => '/driver/trip',
    RideRole.admin => '/admin',
  };
}
