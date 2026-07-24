import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/router/route_guards.dart';
import 'package:ridex/app/router/route_names.dart';
import 'package:ridex/app/theme/app_motion.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:ridex/features/auth/presentation/screens/account_blocked_screen.dart';
import 'package:ridex/features/auth/presentation/screens/admin_placeholder_screen.dart';
import 'package:ridex/features/auth/presentation/screens/profile_error_screen.dart';
import 'package:ridex/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:ridex/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:ridex/features/auth/presentation/screens/verify_otp_screen.dart';
import 'package:ridex/features/booking/presentation/screens/destination_selection_screen.dart';
import 'package:ridex/features/booking/presentation/screens/fare_estimate_screen.dart';
import 'package:ridex/features/booking/presentation/screens/pickup_selection_screen.dart';
import 'package:ridex/features/booking/presentation/screens/ride_request_searching_screen.dart';
import 'package:ridex/features/booking/presentation/screens/vehicle_type_selection_screen.dart';
import 'package:ridex/features/driver_application/presentation/screens/driver_application_status_screen.dart';
import 'package:ridex/features/driver_home/presentation/screens/driver_home_screen.dart';
import 'package:ridex/features/history/presentation/screens/trip_history_screen.dart';
import 'package:ridex/features/history/presentation/screens/trip_details_screen.dart';
import 'package:ridex/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:ridex/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:ridex/features/profile/presentation/screens/driver_profile_screen.dart';
import 'package:ridex/features/profile/presentation/screens/rider_profile_screen.dart';
import 'package:ridex/features/ratings/presentation/screens/rating_screen.dart';
import 'package:ridex/features/rider_home/presentation/screens/rider_home_screen.dart';
import 'package:ridex/features/settings/presentation/screens/settings_screen.dart';
import 'package:ridex/features/splash/presentation/screens/splash_screen.dart';
import 'package:ridex/features/trips/presentation/screens/driver_active_trip_screen.dart';
import 'package:ridex/features/trips/presentation/screens/driver_arrival_screen.dart';
import 'package:ridex/features/trips/presentation/screens/driver_trip_request_screen.dart';
import 'package:ridex/features/trips/presentation/screens/rider_active_trip_screen.dart';
import 'package:ridex/features/trips/presentation/screens/trip_completion_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: RouterRefresh(ref),
    redirect: (context, state) =>
        redirectForSession(state, ref.read(sessionControllerProvider)),
    routes: [
      GoRoute(
          path: '/',
          name: RouteNames.splash,
          builder: (_, __) => const SplashScreen()),
      GoRoute(
          path: '/onboarding',
          name: RouteNames.onboarding,
          builder: (_, __) => const OnboardingScreen()),
      GoRoute(
          path: '/sign-in',
          name: RouteNames.signIn,
          builder: (_, __) => const SignInScreen()),
      GoRoute(
          path: '/sign-up',
          name: RouteNames.signUp,
          builder: (_, __) => const SignUpScreen()),
      GoRoute(
          path: '/forgot-password',
          name: RouteNames.forgotPassword,
          builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/verify-otp',
        name: RouteNames.verifyOtp,
        builder: (_, state) => VerifyOtpScreen(
          phone: _otpPhoneFromState(state),
        ),
      ),
      GoRoute(
          path: '/account-blocked',
          name: RouteNames.accountBlocked,
          builder: (_, __) => const AccountBlockedScreen()),
      GoRoute(
          path: '/profile-error',
          name: RouteNames.profileError,
          builder: (_, __) => const ProfileErrorScreen()),
      GoRoute(
          path: '/admin',
          name: RouteNames.admin,
          builder: (_, __) => const AdminPlaceholderScreen()),
      GoRoute(
          path: '/rider/home',
          name: RouteNames.riderHome,
          builder: (_, __) => const RiderHomeScreen()),
      GoRoute(
          path: '/rider/pickup',
          name: RouteNames.pickup,
          builder: (_, __) => const PickupSelectionScreen()),
      GoRoute(
          path: '/rider/destination',
          name: RouteNames.destination,
          builder: (_, __) => const DestinationSelectionScreen()),
      GoRoute(
          path: '/rider/vehicle',
          name: RouteNames.vehicleType,
          builder: (_, __) => const VehicleTypeSelectionScreen()),
      GoRoute(
          path: '/rider/fare',
          name: RouteNames.fareEstimate,
          builder: (_, __) => const FareEstimateScreen()),
      GoRoute(
          path: '/rider/searching',
          name: RouteNames.searching,
          builder: (_, __) => const RideRequestSearchingScreen()),
      GoRoute(
          path: '/rider/trip',
          name: RouteNames.riderTrip,
          builder: (_, __) => const RiderActiveTripScreen()),
      GoRoute(
          path: '/rider/completed',
          name: RouteNames.tripCompletion,
          builder: (_, __) => const TripCompletionScreen(isDriverView: false)),
      GoRoute(
          path: '/rider/rating',
          name: RouteNames.rating,
          builder: (_, __) => const RatingScreen()),
      GoRoute(
          path: '/rider/profile',
          name: RouteNames.riderProfile,
          builder: (_, __) => const RiderProfileScreen()),
      GoRoute(
          path: '/driver/profile',
          name: RouteNames.driverProfile,
          builder: (_, __) => const DriverProfileScreen()),
      GoRoute(
          path: '/history',
          name: RouteNames.tripHistory,
          builder: (_, __) => const TripHistoryScreen()),
      GoRoute(
        path: '/history/:tripId',
        name: RouteNames.tripDetails,
        builder: (_, state) => TripDetailsScreen(
          tripId: state.pathParameters['tripId']!,
        ),
      ),
      GoRoute(
          path: '/notifications',
          name: RouteNames.notifications,
          builder: (_, __) => const NotificationsScreen()),
      GoRoute(
          path: '/settings',
          name: RouteNames.settings,
          builder: (_, __) => const SettingsScreen()),
      GoRoute(
          path: '/driver/home',
          name: RouteNames.driverHome,
          builder: (_, __) => const DriverHomeScreen()),
      GoRoute(
          path: '/driver/application',
          name: RouteNames.driverApplication,
          builder: (_, __) => const DriverApplicationStatusScreen()),
      GoRoute(
          path: '/driver/request',
          name: RouteNames.driverTripRequest,
          builder: (_, __) => const DriverTripRequestScreen()),
      GoRoute(
          path: '/driver/arrival',
          name: RouteNames.driverArrival,
          builder: (_, __) => const DriverArrivalScreen()),
      GoRoute(
          path: '/driver/trip',
          name: RouteNames.driverTrip,
          builder: (_, __) => const DriverActiveTripScreen()),
      GoRoute(
          path: '/driver/completed',
          builder: (_, __) => const TripCompletionScreen(isDriverView: true)),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Route error: ${state.error}')),
    ),
  );
});

String? _otpPhoneFromState(GoRouterState state) {
  final extra = state.extra;
  if (extra is VerifyOtpExtra) return extra.phone;
  if (extra is String) return extra;
  if (extra is Map && extra['phone'] is String) {
    return extra['phone'] as String;
  }
  return state.uri.queryParameters['phone'];
}

class RouterRefresh extends ChangeNotifier {
  RouterRefresh(this.ref) {
    ref.listen(sessionControllerProvider, (_, __) => notifyListeners());
  }

  final Ref ref;
}

CustomTransitionPage<void> buildTransitionPage(
    {required LocalKey key, required Widget child}) {
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: AppMotion.standard,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.standardCurve,
        reverseCurve: AppMotion.exitCurve,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}
