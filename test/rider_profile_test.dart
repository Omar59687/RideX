import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/repositories/auth_repository.dart';
import 'package:ridex/core/repositories/profile_repository.dart';
import 'package:ridex/core/widgets/settings_row.dart';
import 'package:ridex/features/profile/presentation/screens/driver_profile_screen.dart';
import 'package:ridex/features/profile/presentation/screens/rider_profile_screen.dart';

void main() {
  testWidgets('profile shows loading, retryable error, and repository data',
      (tester) async {
    final completer = Completer<AppUser>();
    final repository = _TestProfileRepository(completer.future);

    await tester.pumpWidget(_riderProfileApp(profileRepository: repository));
    expect(find.byKey(const Key('profile-loading')), findsOneWidget);

    completer.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Profile could not be loaded'), findsOneWidget);

    repository.result = Future.value(_repositoryUser);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text(_repositoryUser.name), findsOneWidget);
    expect(find.text(_repositoryUser.email), findsNWidgets(2));
    expect(find.text('RideX rider'), findsOneWidget);
  });

  testWidgets('unsupported profile actions are disabled and clearly labelled',
      (tester) async {
    await _setLargeTestSurface(tester);
    await tester.pumpWidget(
      _riderProfileApp(
        profileRepository: _TestProfileRepository(
          Future.value(_repositoryUser),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved places'), findsOneWidget);
    expect(find.text('Payment methods'), findsOneWidget);
    expect(find.text('RideX Rewards'), findsOneWidget);
    expect(find.text('Coming soon'), findsNWidgets(6));
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('profile-edit')))
          .onPressed,
      isNull,
    );

    final disabledRows = tester
        .widgetList<SettingsRow>(find.byType(SettingsRow))
        .where((row) => !row.enabled);
    expect(disabledRows, hasLength(3));
  });

  testWidgets('profile sign out uses the session controller and opens sign in',
      (tester) async {
    await _setLargeTestSurface(tester);
    final authRepository = _TestAuthRepository(_repositoryUser);
    await tester.pumpWidget(
      _riderProfileApp(
        profileRepository: _TestProfileRepository(
          Future.value(_repositoryUser),
        ),
        authRepository: authRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await tester.pumpAndSettle();

    expect(authRepository.didSignOut, isTrue);
    expect(find.text('Sign in route'), findsOneWidget);
  });

  testWidgets('driver profile remains on the existing driver presentation',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith(
            (ref) => _TestAuthRepository(MockData.demoDriver),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DriverProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver profile'), findsOneWidget);
    expect(find.text('Approved driver · 4.9 rating'), findsOneWidget);
    expect(find.text('Toyota Camry · 652-UKW'), findsOneWidget);
    expect(find.byKey(const Key('profile-content')), findsNothing);
  });
}

const _repositoryUser = AppUser(
  id: 'rider-profile-test',
  name: 'Lina Haddad',
  email: 'lina@example.com',
  role: RideRole.rider,
);

Widget _riderProfileApp({
  required ProfileRepository profileRepository,
  AuthRepository? authRepository,
}) {
  final router = GoRouter(
    initialLocation: '/rider/profile',
    routes: [
      GoRoute(
        path: '/rider/profile',
        builder: (_, __) => const RiderProfileScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (_, __) => const Scaffold(body: Text('Sign in route')),
      ),
      GoRoute(
        path: '/rider/home',
        builder: (_, __) => const Scaffold(body: Text('Home route')),
      ),
      GoRoute(
        path: '/history',
        builder: (_, __) => const Scaffold(body: Text('History route')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const Scaffold(body: Text('Settings route')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      profileRepositoryProvider.overrideWith((ref) => profileRepository),
      if (authRepository != null)
        authRepositoryProvider.overrideWith((ref) => authRepository),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: router,
    ),
  );
}

class _TestProfileRepository implements ProfileRepository {
  _TestProfileRepository(this.result);

  Future<AppUser> result;

  @override
  Future<AppUser> getCurrentProfile() => result;

  @override
  Future<AppUser> getProfile(String userId) => result;
}

class _TestAuthRepository implements AuthRepository {
  _TestAuthRepository(this.user);

  final AppUser user;
  var didSignOut = false;

  @override
  Stream<void> authStateChanges() => const Stream.empty();

  @override
  Future<AppUser?> restoreSession() async => user;

  @override
  Future<AppUser> continueAsDemo() async => user;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async =>
      user;

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async =>
      user;

  @override
  Future<void> signOut() async {
    didSignOut = true;
  }
}

Future<void> _setLargeTestSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
