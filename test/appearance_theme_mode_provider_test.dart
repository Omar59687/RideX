import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('defaults to System when no appearance preference is stored', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(appearanceThemeModeProvider), ThemeMode.system);
    await _waitForMode(container, ThemeMode.system);
    expect(await SharedPreferencesAsync().getString(_preferenceKey), isNull);
  });

  test(
    'Light to Dark to System updates immediately and persists each choice',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(appearanceThemeModeProvider.notifier);

      await controller.setThemeMode(ThemeMode.light);
      expect(container.read(appearanceThemeModeProvider), ThemeMode.light);
      expect(await SharedPreferencesAsync().getString(_preferenceKey), 'light');

      await controller.setThemeMode(ThemeMode.dark);
      expect(container.read(appearanceThemeModeProvider), ThemeMode.dark);
      expect(await SharedPreferencesAsync().getString(_preferenceKey), 'dark');

      await controller.setThemeMode(ThemeMode.system);
      expect(container.read(appearanceThemeModeProvider), ThemeMode.system);
      expect(
        await SharedPreferencesAsync().getString(_preferenceKey),
        'system',
      );
    },
  );

  test(
    'a new provider container restores the saved preference after restart',
    () async {
      await SharedPreferencesAsync().setString(_preferenceKey, 'dark');
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(appearanceThemeModeProvider), ThemeMode.system);
      await _waitForMode(container, ThemeMode.dark);
      expect(container.read(appearanceThemeModeProvider), ThemeMode.dark);
    },
  );

  test('unknown stored values safely restore System Default', () async {
    await SharedPreferencesAsync().setString(_preferenceKey, 'sepia');
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(appearanceThemeModeProvider), ThemeMode.system);
    await _waitForMode(container, ThemeMode.system);
    expect(container.read(appearanceThemeModeProvider), ThemeMode.system);
  });
}

Future<void> _waitForMode(
  ProviderContainer container,
  ThemeMode expected,
) async {
  if (container.read(appearanceThemeModeProvider) == expected) {
    await Future<void>.delayed(Duration.zero);
    return;
  }

  final completed = Completer<void>();
  final subscription = container.listen<ThemeMode>(
    appearanceThemeModeProvider,
    (previous, next) {
      if (next == expected && !completed.isCompleted) completed.complete();
    },
  );
  addTearDown(subscription.close);
  await completed.future.timeout(const Duration(seconds: 2));
}

const _preferenceKey = 'appearance.theme_mode.v1';
