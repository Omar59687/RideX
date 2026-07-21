import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';

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
}
