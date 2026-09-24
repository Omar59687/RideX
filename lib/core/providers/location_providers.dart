import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/repositories/location_repository.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/services/location/location_permission_store.dart';
import 'package:ridex/core/services/location/location_service.dart';
import 'package:ridex/core/services/maps/ride_map_service.dart';
import 'package:ridex/core/widgets/google_current_location_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef CurrentLocationMapBuilder = Widget Function(
  BuildContext context,
  LocationPoint? point,
);

final locationServiceProvider = Provider<LocationService>((ref) {
  return const GeolocatorLocationService();
});

final locationPermissionStoreProvider =
    Provider<LocationPermissionStore>((ref) {
  return SharedPreferencesLocationPermissionStore(SharedPreferencesAsync());
});

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return DeviceLocationRepository(
    service: ref.watch(locationServiceProvider),
    permissionStore: ref.watch(locationPermissionStoreProvider),
    errorReporter: ref.watch(appErrorReporterProvider),
  );
});

final rideMapServiceProvider = Provider<RideMapService>((ref) {
  return GoogleRideMapService(
    enabled: EnvConfig.hasMapsConfig,
    errorReporter: ref.watch(appErrorReporterProvider),
  );
});

final mapConfigurationProvider = FutureProvider<bool>((ref) {
  return ref.watch(rideMapServiceProvider).isConfigured();
});

final mapPlatformSupportedProvider = Provider<bool>((ref) {
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
});

final currentLocationMapBuilderProvider = Provider<CurrentLocationMapBuilder>(
  (ref) {
    final errorReporter = ref.watch(appErrorReporterProvider);
    return (context, point) => GoogleCurrentLocationMap(
          point: point,
          errorReporter: errorReporter,
        );
  },
);

class CurrentLocationController
    extends AutoDisposeNotifier<CurrentLocationState> {
  bool _operationRunning = false;
  int _generation = 0;
  late final AppErrorReporter _errorReporter;

  @override
  CurrentLocationState build() {
    _errorReporter = ref.read(appErrorReporterProvider);
    ref.onDispose(() => _generation++);
    Future<void>.microtask(refresh);
    return const CurrentLocationState.initial();
  }

  Future<void> refresh() {
    return _run(
      loadingStatus: CurrentLocationStatus.checking,
      operation: ref.read(locationRepositoryProvider).inspectCurrentLocation,
    );
  }

  Future<void> requestPermission() {
    return _run(
      loadingStatus: CurrentLocationStatus.requestingPermission,
      operation:
          ref.read(locationRepositoryProvider).requestPermissionAndLocate,
    );
  }

  Future<void> openAppSettings() async {
    await ref.read(locationRepositoryProvider).openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await ref.read(locationRepositoryProvider).openLocationSettings();
  }

  Future<void> _run({
    required CurrentLocationStatus loadingStatus,
    required Future<CurrentLocationState> Function() operation,
  }) async {
    if (_operationRunning) return;

    _operationRunning = true;
    final operationGeneration = ++_generation;
    final previousPoint = state.point;
    final previousPermission = state.permission;
    state = state.copyWith(
      status: loadingStatus,
      clearFailure: true,
    );

    late final CurrentLocationState nextState;
    try {
      nextState = await operation();
    } on Object catch (error, stackTrace) {
      _errorReporter.report(
        operation: 'loading current location state',
        error: error,
        stackTrace: stackTrace,
      );
      nextState = CurrentLocationState(
        status: CurrentLocationStatus.unavailable,
        permission: previousPermission,
        failure: LocationFailure.gpsUnavailable,
      );
    }
    if (operationGeneration == _generation) {
      final preservePoint = previousPoint != null &&
          nextState.point == null &&
          nextState.permission == LocationPermissionStatus.granted &&
          (nextState.failure == LocationFailure.locationNotFound ||
              nextState.failure == LocationFailure.gpsUnavailable);
      state =
          preservePoint ? nextState.copyWith(point: previousPoint) : nextState;
      _operationRunning = false;
    }
  }
}

final currentLocationControllerProvider = NotifierProvider.autoDispose<
    CurrentLocationController, CurrentLocationState>(
  CurrentLocationController.new,
);
