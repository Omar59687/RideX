import 'package:go_router/go_router.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';

String? redirectForSession(GoRouterState state, SessionState session) {
  final location = state.matchedLocation;
  final inAuth = {
    '/',
    '/onboarding',
    '/roles',
    '/sign-in',
    '/sign-up',
    '/forgot-password',
  }.contains(location);

  if (!session.isAuthenticated) {
    return inAuth ? null : '/sign-in';
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
