import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LocationPermissionStore {
  Future<bool> wasPermissionRequested();

  Future<void> markPermissionRequested();
}

class SharedPreferencesLocationPermissionStore
    implements LocationPermissionStore {
  SharedPreferencesLocationPermissionStore(this._preferences);

  static const _permissionRequestedKey = 'location_permission_requested';

  final SharedPreferencesAsync _preferences;

  @override
  Future<void> markPermissionRequested() {
    return _preferences.setBool(_permissionRequestedKey, true);
  }

  @override
  Future<bool> wasPermissionRequested() async {
    return await _preferences.getBool(_permissionRequestedKey) ?? false;
  }
}
