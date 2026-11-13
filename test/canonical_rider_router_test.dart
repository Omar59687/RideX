import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/router/app_router.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/app/theme/appearance_theme_mode_provider.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/repositories/location_repository.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/features/booking/application/rider_booking_integration_gate.dart';
import 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart';
import 'package:ridex/features/trips/presentation/screens/canonical_rider_trip_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/in_memory_appearance_preferences.dart';

class _Session extends SessionController {
  @override
  SessionState build() => _session(RideRole.rider);
  void publish(SessionState next) => state = next;
}

class _NoLocation implements LocationRepository {
  @override
  Future<CurrentLocationState> inspectCurrentLocation() async =>
      const CurrentLocationState.initial();
  @override
  Future<CurrentLocationState> requestPermissionAndLocate() =>
      inspectCurrentLocation();
  @override
  Future<bool> openAppSettings() async => false;
  @override
  Future<bool> openLocationSettings() async => false;
}

SessionState _session(RideRole role) => SessionState.fromUser(AppUser(
      id: 'route-test-${role.name}',
      name: 'Route test',
      email: '${role.name}@example.com',
      role: role,
      driverApprovalStatus: DriverApprovalStatus.approved,
    ));

void main() {
  for (final path in ['/rider/cash-searching', '/rider/canonical-trip']) {
    testWidgets('production GoRouter protects and refreshes $path',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(overrides: [
        sessionControllerProvider.overrideWith(_Session.new),
        locationRepositoryProvider.overrideWithValue(_NoLocation()),
        appearancePreferencesProvider
            .overrideWithValue(InMemoryAppearancePreferences()),
      ]);
      final router = container.read(appRouterProvider);
      final session =
          container.read(sessionControllerProvider.notifier) as _Session;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ));
      Future<void> settleRoute() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      // Invalid locators deliberately exercise the real screen's fail-closed
      // state without constructing booking/Trip authority or hosted clients.
      final uri = '$path?booking=route-probe&trip=route-probe';
      router.go(uri);
      await settleRoute();
      expect(router.routeInformationProvider.value.uri.toString(), uri);
      if (path.endsWith('cash-searching')) {
        expect(find.byType(CanonicalRideSearchingScreen), findsOneWidget);
      } else {
        expect(find.byType(CanonicalRiderTripScreen), findsOneWidget);
      }

      for (final role in [RideRole.driver, RideRole.admin]) {
        // RouterRefresh must evict an already-mounted Rider page on a session
        // replacement, and reject a subsequent direct navigation as well.
        session.publish(_session(role));
        await settleRoute();
        final home = role == RideRole.driver ? '/driver/home' : '/admin';
        expect(router.routeInformationProvider.value.uri.path, home);
        router.go(uri);
        await settleRoute();
        expect(router.routeInformationProvider.value.uri.path, home);
        session.publish(_session(RideRole.rider));
        router.go(uri);
        await settleRoute();
        expect(router.routeInformationProvider.value.uri.path, path);
      }

      session.publish(const SessionState.unauthenticated());
      await settleRoute();
      expect(router.routeInformationProvider.value.uri.path, '/sign-in');
      router.go(uri);
      await settleRoute();
      expect(router.routeInformationProvider.value.uri.path, '/sign-in');

      session.publish(_session(RideRole.rider));
      for (final existing in ['/rider/destination', '/history', '/settings']) {
        router.go(existing);
        await settleRoute();
        expect(router.routeInformationProvider.value.uri.path, existing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      container.dispose();
    }, skip: !riderCashMatchingIntegrationEnabled);
  }
}
