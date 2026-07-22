import 'package:go_router/go_router.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';

String? redirectForSession(GoRouterState state, SessionState session) {
  final location = state.matchedLocation;
  const publicLocations = {
    '/',
    '/onboarding',
    '/roles',
    '/sign-in',
    '/sign-up',
    '/forgot-password',
    '/verify-otp',
  };
  final inAuth = publicLocations.contains(location);

  if (session.status == SessionStatus.loading) {
    // Keep auth forms mounted while a submit is in flight so they can render
    // repository errors. Private deep links still wait on the splash route.
    return location == '/' || inAuth ? null : '/';
  }

  if (session.status == SessionStatus.unauthenticated) {
    return inAuth ? null : '/sign-in';
  }

  if (session.status == SessionStatus.blocked) {
    return location == '/account-blocked' ? null : '/account-blocked';
  }

  if (session.status == SessionStatus.driverPending ||
      session.status == SessionStatus.driverRejected) {
    return location == '/driver/application' ? null : '/driver/application';
  }

  if (session.role == RideRole.rider && inAuth) {
    return '/rider/home';
  }

  if (session.role == RideRole.driver && inAuth) {
    return '/driver/home';
  }

  if (session.role == RideRole.rider && location.startsWith('/driver')) {
    return '/rider/home';
  }

  if (session.role == RideRole.driver && location.startsWith('/rider')) {
    return '/driver/home';
  }

  return null;
}

String locationForRole(RideRole role) {
  return switch (role) {
    RideRole.rider => '/rider/home',
    RideRole.driver => '/driver/home',
  };
}

String nextTripRouteForRole(RideRole role) {
  return switch (role) {
    RideRole.rider => '/rider/trip',
    RideRole.driver => '/driver/trip',
  };
}
