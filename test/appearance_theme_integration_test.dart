import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/app.dart';
import 'package:ridex/app/router/app_router.dart';
import 'package:ridex/app/theme/appearance_theme_mode_provider.dart';
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

  testWidgets(
    'default System reacts to brightness and switching modes is live',
    (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );

      final router = GoRouter(
        initialLocation: '/theme-test',
        routes: [
          GoRoute(
            path: '/theme-test',
            builder: (_, __) =>
                const Scaffold(body: Center(child: _ThemeProbe())),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          appRouterProvider.overrideWithValue(router),
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
          child: const RideXApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(appearanceThemeModeProvider), ThemeMode.system);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      expect(find.byKey(const ValueKey('light')), findsOneWidget);

      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dark')), findsOneWidget);

      await container
          .read(appearanceThemeModeProvider.notifier)
          .setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(find.byKey(const ValueKey('light')), findsOneWidget);

      await container
          .read(appearanceThemeModeProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(find.byKey(const ValueKey('dark')), findsOneWidget);

      await container
          .read(appearanceThemeModeProvider.notifier)
          .setThemeMode(ThemeMode.system);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      expect(find.byKey(const ValueKey('dark')), findsOneWidget);
      expect(container.read(appRouterProvider), same(router));
      expect(find.text('Theme probe'), findsOneWidget);
    },
  );
}

class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe();

  @override
  Widget build(BuildContext context) =>
      Text('Theme probe', key: ValueKey(Theme.of(context).brightness.name));
}
