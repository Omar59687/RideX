import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/models/location_point.dart';

abstract interface class LocationService {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermissionStatus> checkPermission();

  Future<LocationPermissionStatus> requestPermission();

  Future<LocationPoint> getCurrentLocation();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}
