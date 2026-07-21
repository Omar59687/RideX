import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/app.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/providers/repositories_providers.dart';

Widget buildTestApp({List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
      bookingRepositoryProvider.overrideWith((ref) => MockBookingRepository()),
      tripsRepositoryProvider.overrideWith((ref) => MockTripsRepository()),
      profileRepositoryProvider.overrideWith((ref) => MockProfileRepository()),
      ...overrides,
    ],
    child: const RideXApp(),
  );
}
