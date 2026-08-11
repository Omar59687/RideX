import 'dart:async';

import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/services/location/location_permission_store.dart';
import 'package:ridex/core/services/location/location_service.dart';

abstract interface class LocationRepository {
  Future<CurrentLocationState> inspectCurrentLocation();

  Future<CurrentLocationState> requestPermissionAndLocate();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

class DeviceLocationRepository implements LocationRepository {
  DeviceLocationRepository({
    required LocationService service,
    required LocationPermissionStore permissionStore,
    this.locationTimeout = const Duration(seconds: 15),
  })  : _service = service,
        _permissionStore = permissionStore;

  final LocationService _service;
  final LocationPermissionStore _permissionStore;
  final Duration locationTimeout;

  @override
  Future<CurrentLocationState> inspectCurrentLocation() async {
    try {
      if (!await _service.isLocationServiceEnabled()) {
        return const CurrentLocationState(
          status: CurrentLocationStatus.serviceDisabled,
          permission: LocationPermissionStatus.notRequested,
          failure: LocationFailure.serviceDisabled,
        );
      }

      final permission = await _service.checkPermission();
      return switch (permission) {
        LocationPermissionStatus.granted => _locate(permission),
        LocationPermissionStatus.permanentlyDenied =>
          Future.value(_permanentlyDenied),
        LocationPermissionStatus.denied => _deniedState(),
        LocationPermissionStatus.notRequested =>
          Future.value(const CurrentLocationState.initial()),
      };
    } on Object {
      return _unavailable(LocationPermissionStatus.notRequested);
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await _service.openAppSettings();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await _service.openLocationSettings();
    } on Object {
      return false;
    }
  }

  @override
  Future<CurrentLocationState> requestPermissionAndLocate() async {
    try {
      if (!await _service.isLocationServiceEnabled()) {
        return const CurrentLocationState(
          status: CurrentLocationStatus.serviceDisabled,
          permission: LocationPermissionStatus.notRequested,
          failure: LocationFailure.serviceDisabled,
        );
      }

      var permission = await _service.checkPermission();
      if (permission == LocationPermissionStatus.denied ||
          permission == LocationPermissionStatus.notRequested) {
        permission = await _service.requestPermission();
        try {
          await _permissionStore.markPermissionRequested();
        } on Object {
          // OS permission remains authoritative if local preference storage fails.
        }
      }

      return switch (permission) {
        LocationPermissionStatus.granted => _locate(permission),
        LocationPermissionStatus.permanentlyDenied =>
          Future.value(_permanentlyDenied),
        LocationPermissionStatus.denied ||
        LocationPermissionStatus.notRequested =>
          Future.value(_denied),
      };
    } on Object {
      return _unavailable(LocationPermissionStatus.notRequested);
    }
  }

  Future<CurrentLocationState> _deniedState() async {
    return await _permissionStore.wasPermissionRequested()
        ? _denied
        : const CurrentLocationState.initial();
  }

  Future<CurrentLocationState> _locate(
    LocationPermissionStatus permission,
  ) async {
    try {
      final point =
          await _service.getCurrentLocation().timeout(locationTimeout);
      return CurrentLocationState(
        status: CurrentLocationStatus.available,
        permission: permission,
        point: point,
      );
    } on TimeoutException {
      return CurrentLocationState(
        status: CurrentLocationStatus.unavailable,
        permission: permission,
        failure: LocationFailure.timeout,
      );
    } on Object {
      return _unavailable(permission);
    }
  }

  CurrentLocationState _unavailable(LocationPermissionStatus permission) {
    return CurrentLocationState(
      status: CurrentLocationStatus.unavailable,
      permission: permission,
      failure: LocationFailure.unavailable,
    );
  }

  static const _denied = CurrentLocationState(
    status: CurrentLocationStatus.unavailable,
    permission: LocationPermissionStatus.denied,
    failure: LocationFailure.permissionDenied,
  );

  static const _permanentlyDenied = CurrentLocationState(
    status: CurrentLocationStatus.unavailable,
    permission: LocationPermissionStatus.permanentlyDenied,
    failure: LocationFailure.permissionPermanentlyDenied,
  );
}
