import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appearancePreferencesProvider = Provider<SharedPreferencesAsync>(
  (ref) => SharedPreferencesAsync(),
);

final appearanceThemeModeProvider =
    NotifierProvider<AppearanceThemeModeController, ThemeMode>(
  AppearanceThemeModeController.new,
);

class AppearanceThemeModeController extends Notifier<ThemeMode> {
  static const _preferenceKey = 'appearance.theme_mode.v1';

  late SharedPreferencesAsync _preferences;
  var _hasUserSelection = false;
  var _disposed = false;
  var _revision = 0;
  Future<void> _writeQueue = Future<void>.value();

  @override
  ThemeMode build() {
    _disposed = false;
    _preferences = ref.watch(appearancePreferencesProvider);
    final revision = ++_revision;
    ref.onDispose(() {
      _disposed = true;
      _revision++;
    });
    unawaited(_restore(revision));
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) {
    _hasUserSelection = true;
    _revision++;
    state = mode;

    Future<void> writePreference() async {
      if (_disposed) return;
      await _preferences.setString(_preferenceKey, mode.name);
    }

    final write = _writeQueue.then<void>(
      (_) => writePreference(),
      onError: (Object error, StackTrace stackTrace) => writePreference(),
    );
    _writeQueue = write;
    return write;
  }

  Future<void> _restore(int revision) async {
    try {
      final savedValue = await _preferences.getString(_preferenceKey);
      if (_disposed || revision != _revision || _hasUserSelection) return;
      state = _decodeThemeMode(savedValue);
    } on Object {
      // System mode is the safe default when local storage cannot be read.
    }
  }

  static ThemeMode _decodeThemeMode(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.system,
      };
}
