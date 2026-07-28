import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/errors/auth_exception.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';

void main() {
  group('three-role domain', () {
    test('parses only exact trusted role values', () {
      expect(RideRoleX.fromDatabase('rider'), RideRole.rider);
      expect(RideRoleX.fromDatabase('driver'), RideRole.driver);
      expect(RideRoleX.fromDatabase('admin'), RideRole.admin);
      expect(
        () => RideRoleX.fromDatabase('Admin'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => RideRoleX.fromDatabase('unknown'),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses only exact Driver approval values', () {
      expect(
        DriverApprovalStatusX.fromDatabase('pending'),
        DriverApprovalStatus.pending,
      );
      expect(
        () => DriverApprovalStatusX.fromDatabase('unknown'),
        throwsA(isA<FormatException>()),
      );
    });

    test('Admin and blocked Admin session states are explicit', () {
      expect(
        SessionState.fromUser(MockData.demoAdmin).status,
        SessionStatus.authenticated,
      );
      expect(
        SessionState.fromUser(
          const AppUser(
            id: 'blocked-admin',
            name: 'Blocked Admin',
            email: 'blocked-admin@ridex.demo',
            role: RideRole.admin,
            isBlocked: true,
          ),
        ).status,
        SessionStatus.blocked,
      );
    });
  });

  group('mock authorization isolation', () {
    late MockAuthRepository repository;

    setUp(() => repository = MockAuthRepository());

    test('exact credentials resolve Rider, Driver, and Admin', () async {
      expect(
        await repository.signIn(
          email: 'demo@ridex.app',
          password: '123456',
        ),
        MockData.demoRider,
      );
      expect(
        await repository.signIn(
          email: 'driver@ridex.app',
          password: '123456',
        ),
        MockData.demoDriver,
      );
      expect(
        await repository.signIn(
          email: 'admin@ridex.app',
          password: '123456',
        ),
        MockData.demoAdmin,
      );
    });

    test('email patterns never grant a role', () async {
      await expectLater(
        repository.signIn(
          email: 'another-admin@ridex.app',
          password: '123456',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('public demo and signup are Rider-only', () async {
      expect(await repository.continueAsDemo(), MockData.demoRider);
      final user = await repository.signUp(
        name: 'Public User',
        email: 'public@example.com',
        password: '123456',
      );
      expect(user.role, RideRole.rider);
    });
  });

  test('missing and malformed profile restoration errors fail closed',
      () async {
    for (final message in [
      'Your account profile is missing.',
      'Your account profile is invalid.',
    ]) {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith(
            (ref) => _InvalidProfileAuthRepository(message),
          ),
        ],
      );

      await container.read(sessionControllerProvider.notifier).refreshSession();

      final session = container.read(sessionControllerProvider);
      expect(session.status, SessionStatus.profileError);
      expect(session.user, isNull);
      expect(session.isAuthenticated, isFalse);
      expect(session.errorMessage, message);
      container.dispose();
    }
  });
}

class _InvalidProfileAuthRepository extends MockAuthRepository {
  _InvalidProfileAuthRepository(this.message);

  final String message;

  @override
  Future<AppUser?> restoreSession() {
    throw ProfileException(message);
  }
}
