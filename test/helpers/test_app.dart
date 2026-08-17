import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/app.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/services/maps/ride_map_service.dart';
import 'package:ridex/core/repositories/mock_place_repository.dart';
import 'package:ridex/core/repositories/location_repository.dart';
import 'package:ridex/core/models/current_location_state.dart';

Widget buildTestApp({List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
      bookingRepositoryProvider.overrideWith((ref) => MockBookingRepository()),
      tripsRepositoryProvider.overrideWith((ref) => MockTripsRepository()),
      profileRepositoryProvider.overrideWith((ref) => MockProfileRepository()),
      placeRepositoryProvider.overrideWith((ref) => MockPlaceRepository()),
      rideMapServiceProvider.overrideWithValue(const MockRideMapService()),
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
