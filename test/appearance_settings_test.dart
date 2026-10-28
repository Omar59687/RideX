// RadioListTile.groupValue is deprecated after the project's Flutter 3.27
// baseline; retain the compatible API while asserting selected state.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/app/theme/appearance_theme_mode_provider.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/settings/presentation/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySharedPreferencesAsync preferencesBackend;
  SharedPreferencesAsyncPlatform? previousPlatform;

  setUp(() {
    previousPlatform = SharedPreferencesAsyncPlatform.instance;
    preferencesBackend = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = preferencesBackend;
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = previousPlatform;
  });

  testWidgets('Settings shows and saves Light, Dark, and System choices', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        for (final path in ['/rider/home', '/history', '/rider/profile'])
          GoRoute(path: path, builder: (_, __) => const Scaffold()),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appearancePreferencesProvider.overrideWithValue(
          SharedPreferencesAsync(),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('System default'), findsOneWidget);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    var options = tester
        .widgetList<RadioListTile<ThemeMode>>(
          find.byType(RadioListTile<ThemeMode>),
        )
        .toList();
    expect(options, hasLength(3));
    expect(
      options
          .firstWhere((option) => option.value == ThemeMode.system)
          .groupValue,
      ThemeMode.system,
    );

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceThemeModeProvider), ThemeMode.dark);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    options = tester
        .widgetList<RadioListTile<ThemeMode>>(
          find.byType(RadioListTile<ThemeMode>),
        )
        .toList();
    expect(
      options.firstWhere((option) => option.value == ThemeMode.dark).groupValue,
      ThemeMode.dark,
    );

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceThemeModeProvider), ThemeMode.light);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceThemeModeProvider), ThemeMode.system);

    expect(container.read(sessionControllerProvider).user, isNull);
  });
}
