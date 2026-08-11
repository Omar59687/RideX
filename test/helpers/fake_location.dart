import 'dart:async';

import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/repositories/location_repository.dart';
import 'package:ridex/core/services/location/location_permission_store.dart';
import 'package:ridex/core/services/location/location_service.dart';

class FakeLocationService implements LocationService {
  bool serviceEnabled = true;
  LocationPermissionStatus permission = LocationPermissionStatus.notRequested;
  LocationPermissionStatus requestedPermission =
      LocationPermissionStatus.granted;
  LocationPoint point = LocationPoint(
    latitude: 31.963158,
    longitude: 35.930359,
    accuracyMeters: 8,
  );
  Future<LocationPoint>? locationResult;
  Object? locationError;
  int permissionRequestCount = 0;
  int locationRequestCount = 0;
  int appSettingsCount = 0;
  int locationSettingsCount = 0;
  Object? settingsError;

  @override
  Future<LocationPermissionStatus> checkPermission() async => permission;

  @override
  Future<LocationPoint> getCurrentLocation() {
    locationRequestCount++;
    if (locationError != null) return Future.error(locationError!);
    return locationResult ?? Future.value(point);
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<bool> openAppSettings() async {
    appSettingsCount++;
    if (settingsError != null) throw settingsError!;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCount++;
    if (settingsError != null) throw settingsError!;
    return true;
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    permissionRequestCount++;
    permission = requestedPermission;
    return requestedPermission;
  }
}

class MemoryLocationPermissionStore implements LocationPermissionStore {
  MemoryLocationPermissionStore({this.requested = false});

  bool requested;

  @override
  Future<void> markPermissionRequested() async {
    requested = true;
  }

  @override
  Future<bool> wasPermissionRequested() async => requested;
}

class FakeLocationRepository implements LocationRepository {
  FakeLocationRepository({
    this.inspectedState = const CurrentLocationState.initial(),
    this.requestedState = const CurrentLocationState.initial(),
  });

  CurrentLocationState inspectedState;
  CurrentLocationState requestedState;
  Future<CurrentLocationState>? inspectResult;
  Future<CurrentLocationState>? requestResult;
  int inspectCount = 0;
  int requestCount = 0;
  int appSettingsCount = 0;
  int locationSettingsCount = 0;

  @override
  Future<CurrentLocationState> inspectCurrentLocation() {
    inspectCount++;
    return inspectResult ?? Future.value(inspectedState);
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsCount++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCount++;
    return true;
  }

  @override
  Future<CurrentLocationState> requestPermissionAndLocate() {
    requestCount++;
    return requestResult ?? Future.value(requestedState);
  }
}

Future<void> flushLocationTasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
