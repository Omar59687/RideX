import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/repositories/location_repository.dart';

import 'helpers/fake_location.dart';

void main() {
  late FakeLocationService service;
  late MemoryLocationPermissionStore permissionStore;
  late DeviceLocationRepository repository;

  setUp(() {
    service = FakeLocationService();
    permissionStore = MemoryLocationPermissionStore();
    repository = DeviceLocationRepository(
      service: service,
      permissionStore: permissionStore,
      locationTimeout: const Duration(milliseconds: 10),
    );
  });

  test('distinguishes permission not requested from a previous denial',
      () async {
    service.permission = LocationPermissionStatus.denied;

    final initial = await repository.inspectCurrentLocation();
    permissionStore.requested = true;
    final denied = await repository.inspectCurrentLocation();

    expect(initial, const CurrentLocationState.initial());
    expect(denied.permission, LocationPermissionStatus.denied);
    expect(denied.failure, LocationFailure.permissionDenied);
  });

  test('requests permission once and returns the actual device point',
      () async {
    service.permission = LocationPermissionStatus.denied;
    service.requestedPermission = LocationPermissionStatus.granted;

    final state = await repository.requestPermissionAndLocate();

    expect(state.status, CurrentLocationStatus.available);
    expect(state.permission, LocationPermissionStatus.granted);
    expect(state.point, service.point);
    expect(service.permissionRequestCount, 1);
    expect(service.locationRequestCount, 1);
    expect(permissionStore.requested, isTrue);
  });

  test('does not request again when permission is already granted', () async {
    service.permission = LocationPermissionStatus.granted;

    final state = await repository.requestPermissionAndLocate();

    expect(state.status, CurrentLocationStatus.available);
    expect(service.permissionRequestCount, 0);
    expect(service.locationRequestCount, 1);
  });

  test('reports permanent denial without requesting GPS', () async {
    service.permission = LocationPermissionStatus.permanentlyDenied;

    final state = await repository.inspectCurrentLocation();

    expect(state.permission, LocationPermissionStatus.permanentlyDenied);
    expect(state.failure, LocationFailure.permissionPermanentlyDenied);
    expect(service.locationRequestCount, 0);
  });

  test('distinguishes a disabled location service', () async {
    service.serviceEnabled = false;

    final state = await repository.inspectCurrentLocation();

    expect(state.status, CurrentLocationStatus.serviceDisabled);
    expect(state.failure, LocationFailure.serviceDisabled);
    expect(service.permissionRequestCount, 0);
    expect(service.locationRequestCount, 0);
  });

  test('maps a location timeout to a safe failure', () async {
    service.permission = LocationPermissionStatus.granted;
    service.locationResult = Completer<Never>().future;

    final state = await repository.inspectCurrentLocation();

    expect(state.status, CurrentLocationStatus.unavailable);
    expect(state.failure, LocationFailure.timeout);
  });

  test('sanitizes provider errors', () async {
    service.permission = LocationPermissionStatus.granted;
    service.locationError = StateError('raw provider failure');

    final state = await repository.inspectCurrentLocation();

    expect(state.status, CurrentLocationStatus.unavailable);
    expect(state.failure, LocationFailure.unavailable);
  });

  test('sanitizes settings launch errors', () async {
    service.settingsError = StateError('raw settings failure');

    expect(await repository.openAppSettings(), isFalse);
    expect(await repository.openLocationSettings(), isFalse);
  });
}
