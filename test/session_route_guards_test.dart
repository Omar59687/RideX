import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/app/router/route_guards.dart';

void main() {
  test('rider becomes authenticated session', () {
    const rider = AppUser(
      id: '1',
      name: 'Rider',
      email: 'rider@test.com',
      role: RideRole.rider,
    );

    final session = SessionState.fromUser(rider);
    expect(session.status, SessionStatus.authenticated);
  });

  test('pending driver becomes pending session', () {
    const driver = AppUser(
      id: '2',
      name: 'Driver',
      email: 'driver@test.com',
      role: RideRole.driver,
      driverApprovalStatus: DriverApprovalStatus.pending,
    );
    final session = SessionState.fromUser(driver);
    expect(session.status, SessionStatus.driverPending);
  });

  test('blocked user becomes blocked session', () {
    const blocked = AppUser(
      id: '3',
      name: 'Blocked',
      email: 'blocked@test.com',
      role: RideRole.rider,
      isBlocked: true,
    );

    final session = SessionState.fromUser(blocked);
    expect(session.status, SessionStatus.blocked);
  });

  group('route guards', () {
    const rider = AppUser(
      id: 'rider',
      name: 'Rider',
      email: 'rider@test.com',
      role: RideRole.rider,
    );
    const driver = AppUser(
      id: 'driver',
      name: 'Driver',
      email: 'driver@test.com',
      role: RideRole.driver,
      driverApprovalStatus: DriverApprovalStatus.approved,
    );
    const admin = AppUser(
      id: 'admin',
      name: 'Admin',
      email: 'admin@test.com',
      role: RideRole.admin,
    );

    test('unauthenticated users cannot open private routes', () {
      const session = SessionState.unauthenticated();

      for (final location in [
        '/rider/home',
        '/driver/home',
        '/history',
        '/history/trip-1',
        '/notifications',
        '/settings',
        '/admin',
        '/account-blocked',
        '/profile-error',
      ]) {
        expect(
          redirectForLocation(location, session),
          '/sign-in',
          reason: location,
        );
      }
      expect(redirectForLocation('/sign-in', session), isNull);
    });

    test('rider stays in rider routes and cannot open driver routes', () {
      final session = SessionState.fromUser(rider);

      expect(redirectForLocation('/rider/home', session), isNull);
      expect(redirectForLocation('/history', session), isNull);
      expect(redirectForLocation('/driver/trip', session), '/rider/home');
      expect(redirectForLocation('/admin', session), '/rider/home');
      expect(redirectForLocation('/sign-in', session), '/rider/home');
      expect(redirectForLocation('/account-blocked', session), '/rider/home');
      expect(
        redirectForLocation('/driver/application', session),
        '/rider/home',
      );
    });

    test('approved driver stays in driver routes and cannot open rider routes',
        () {
      final session = SessionState.fromUser(driver);

      expect(redirectForLocation('/driver/home', session), isNull);
      expect(redirectForLocation('/history', session), isNull);
      expect(redirectForLocation('/rider/trip', session), '/driver/home');
      expect(redirectForLocation('/admin', session), '/driver/home');
      expect(redirectForLocation('/sign-up', session), '/driver/home');
      expect(redirectForLocation('/account-blocked', session), '/driver/home');
      expect(
        redirectForLocation('/driver/application', session),
        '/driver/home',
      );
    });

    test('pending and rejected drivers stay on application status', () {
      for (final status in [
        DriverApprovalStatus.pending,
        DriverApprovalStatus.rejected,
      ]) {
        final session = SessionState.fromUser(
          AppUser(
            id: status.name,
            name: 'Driver',
            email: '${status.name}@test.com',
            role: RideRole.driver,
            driverApprovalStatus: status,
          ),
        );

        expect(
          redirectForLocation('/rider/home', session),
          '/driver/application',
        );
        expect(
          redirectForLocation('/driver/application', session),
          isNull,
        );
      }
    });

    test('blocked users stay on the blocked account route', () {
      final session = SessionState.fromUser(
        const AppUser(
          id: 'blocked',
          name: 'Blocked',
          email: 'blocked@test.com',
          role: RideRole.rider,
          isBlocked: true,
        ),
      );

      expect(
        redirectForLocation('/rider/home', session),
        '/account-blocked',
      );
      expect(redirectForLocation('/account-blocked', session), isNull);
    });

    test('admins stay in the protected placeholder and cannot open app flows',
        () {
      final session = SessionState.fromUser(admin);

      expect(redirectForLocation('/admin', session), isNull);
      expect(redirectForLocation('/rider/home', session), '/admin');
      expect(redirectForLocation('/driver/home', session), '/admin');
      expect(redirectForLocation('/history/trip-1', session), isNull);
      expect(redirectForLocation('/sign-in', session), '/admin');
    });

    test('profile errors fail closed on the profile-error destination', () {
      const session = SessionState.profileError(
        errorMessage: 'Your account profile is invalid.',
      );

      expect(redirectForLocation('/profile-error', session), isNull);
      expect(redirectForLocation('/sign-in', session), '/profile-error');
      expect(redirectForLocation('/rider/home', session), '/profile-error');
    });
  });
}
