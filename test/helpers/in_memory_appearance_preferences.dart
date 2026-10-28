import 'package:shared_preferences/shared_preferences.dart';

class InMemoryAppearancePreferences implements SharedPreferencesAsync {
  final Map<String, Object> _values = {};

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
