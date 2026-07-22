import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/auth_repository.dart';
import 'package:ridex/core/widgets/mock_bottom_nav_bar.dart';
import 'package:ridex/core/widgets/ride_x_bottom_navigation.dart';
import 'package:ridex/core/widgets/settings_row.dart';
import 'package:ridex/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:ridex/features/settings/presentation/screens/settings_screen.dart';

void main() {
  testWidgets('rider notifications expose unread state and mark all read',
      (tester) async {
    final app = _buildApp(
      initialLocation: '/notifications',
      user: MockData.demoRider,
    );
    addTearDown(app.dispose);

    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    expect(find.text('1 new update'), findsOneWidget);
    expect(find.byType(RideXBottomNavigation), findsOneWidget);
    expect(find.text('Tap to mark as read'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifications-mark-all-read')));
    await tester.pump();

    expect(
      app.container
          .read(notificationsControllerProvider)
          .every((notification) => notification.isRead),
      isTrue,
    );
    expect(find.text('You are all caught up'), findsOneWidget);
    expect(find.text('Tap to mark as read'), findsNothing);
  });

  testWidgets('tapping an unread notification marks that item read',
      (tester) async {
    final app = _buildApp(
      initialLocation: '/notifications',
      user: MockData.demoRider,
    );
    addTearDown(app.dispose);

    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-1')));
    await tester.pump();

    expect(
      app.container
          .read(notificationsControllerProvider)
          .firstWhere((notification) => notification.id == '1')
          .isRead,
      isTrue,
    );
  });

  testWidgets('rider settings keep preferences in Riverpod session state',
      (tester) async {
    await _setLargeTestSurface(tester);
    final app = _buildApp(
      initialLocation: '/settings',
      user: MockData.demoRider,
    );
    addTearDown(app.dispose);

    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rider-settings-content')), findsOneWidget);
    expect(find.text('Coming soon'), findsNWidgets(3));
    expect(
      tester
          .widgetList<SettingsRow>(find.byType(SettingsRow))
          .where((row) => !row.enabled),
      hasLength(3),
    );

    await tester.tap(find.byKey(const Key('settings-email')));
    await tester.pump();

    expect(app.container.read(notificationPreferencesProvider).email, isTrue);
    expect(
      app.container.read(notificationPreferencesProvider).push,
      isTrue,
    );
  });

  testWidgets('settings sign out uses session controller and opens sign in',
      (tester) async {
    await _setLargeTestSurface(tester);
    final authRepository = _TestAuthRepository(MockData.demoRider);
    final app = _buildApp(
      initialLocation: '/settings',
      user: MockData.demoRider,
      authRepository: authRepository,
    );
    addTearDown(app.dispose);

    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-email')));
    await tester.pump();
    expect(app.container.read(notificationPreferencesProvider).email, isTrue);

    await tester.tap(find.byKey(const Key('settings-sign-out')));
    await tester.pumpAndSettle();

    expect(authRepository.didSignOut, isTrue);
    expect(app.container.read(notificationPreferencesProvider).email, isFalse);
    expect(find.text('Sign in route'), findsOneWidget);
  });

  testWidgets('driver notifications and settings retain legacy presentation',
      (tester) async {
    await _setLargeTestSurface(tester);
    final app = _buildApp(
      initialLocation: '/notifications',
      user: MockData.demoDriver,
    );
    addTearDown(app.dispose);

    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    expect(find.byType(MockBottomNavBar), findsOneWidget);
    expect(find.byType(RideXBottomNavigation), findsNothing);
    expect(find.text('1 new update'), findsNothing);

    app.router.go('/settings');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('driver-settings-content')), findsOneWidget);
    expect(find.byKey(const Key('rider-settings-content')), findsNothing);
    expect(find.text('Mock notification preferences'), findsOneWidget);
    expect(find.byType(MockBottomNavBar), findsOneWidget);
  });
}

_TestApp _buildApp({
  required String initialLocation,
  required AppUser user,
  AuthRepository? authRepository,
}) {
  final repository = authRepository ?? _TestAuthRepository(user);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((ref) => repository),
    ],
  );
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (_, __) => const Scaffold(body: Text('Sign in route')),
      ),
      for (final path in [
        '/rider/home',
        '/driver/home',
        '/history',
        '/rider/profile',
        '/driver/profile',
      ])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text('$path route')),
        ),
    ],
  );
  return _TestApp(
    container: container,
    router: router,
    widget: UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
}

class _TestApp {
  const _TestApp({
    required this.container,
    required this.router,
    required this.widget,
  });

  final ProviderContainer container;
  final GoRouter router;
  final Widget widget;

  void dispose() {
    router.dispose();
    container.dispose();
  }
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
  Future<AppUser> continueAsDemo(RideRole role) async => user;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
    RideRole? role,
  }) async =>
      user;

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    required RideRole role,
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
