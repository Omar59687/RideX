import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/app.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/services/maps/ride_map_service.dart';
import 'package:ridex/core/repositories/mock_place_repository.dart';
import 'package:ridex/core/repositories/mock_route_repository.dart';
import 'package:ridex/core/repositories/location_repository.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';

Widget buildTestApp({List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
      bookingRepositoryProvider.overrideWith((ref) => MockBookingRepository()),
      tripsRepositoryProvider.overrideWith((ref) => MockTripsRepository()),
      profileRepositoryProvider.overrideWith((ref) => MockProfileRepository()),
      placeRepositoryProvider.overrideWith((ref) => MockPlaceRepository()),
      routeRepositoryProvider.overrideWithValue(const MockRouteRepository()),
      rideMapServiceProvider.overrideWithValue(const MockRideMapService()),
      // Offline tests never touch real preferences: no pending command can
      // exist here, and restores resolve to null without platform channels.
      pendingFareLockStoreProvider
          .overrideWithValue(const _NullPendingFareLockStore()),
      locationRepositoryProvider.overrideWithValue(
        const _UnavailableLocationRepository(),
      ),
      ...overrides,
    ],
    child: const RideXApp(),
  );
}

class _UnavailableLocationRepository implements LocationRepository {
  const _UnavailableLocationRepository();

  @override
  Future<CurrentLocationState> inspectCurrentLocation() async =>
      const CurrentLocationState.initial();

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;

  @override
  Future<CurrentLocationState> requestPermissionAndLocate() async =>
      const CurrentLocationState.initial();
}

/// Offline pending-lock store: nothing is ever staged here, so restores
/// always resolve to null without touching platform channels. Staging
/// throws: a live lock dispatch has no business running inside offline
/// full-app flows.
class _NullPendingFareLockStore implements PendingFareLockStore {
  const _NullPendingFareLockStore();

  @override
  Future<void> save(PendingFareLock command) {
    throw UnimplementedError(
      'Live fare locks are unavailable in offline full-app tests.',
    );
  }

  @override
  Future<PendingFareLock?> loadForRider(String riderId) async => null;

  @override
  Future<PendingFareLockSlot> inspectForRider(String riderId) async =>
      const PendingFareLockSlot.absent();

  @override
  Future<void> clearForRider(String riderId) async {}
}
