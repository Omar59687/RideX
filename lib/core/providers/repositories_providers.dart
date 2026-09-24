import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/repositories/auth_repository.dart';
import 'package:ridex/core/repositories/booking_repository.dart';
import 'package:ridex/core/repositories/driver_location_repository.dart';
import 'package:ridex/core/repositories/profile_repository.dart';
import 'package:ridex/core/repositories/mock_driver_location_repository.dart';
import 'package:ridex/core/repositories/google_place_repository.dart';
import 'package:ridex/core/repositories/mock_place_repository.dart';
import 'package:ridex/core/repositories/mock_route_repository.dart';
import 'package:ridex/core/repositories/place_repository.dart';
import 'package:ridex/core/repositories/google_route_repository.dart';
import 'package:ridex/core/repositories/route_repository.dart';
import 'package:ridex/core/repositories/supabase_auth_repository.dart';
import 'package:ridex/core/repositories/supabase_profile_repository.dart';
import 'package:ridex/core/repositories/trips_repository.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/profile_service.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/core/services/driver_location/driver_location_service.dart';
import 'package:ridex/core/services/driver_location/supabase_driver_location_service.dart';
import 'package:ridex/core/services/places/place_service.dart';
import 'package:ridex/core/services/places/supabase_place_service.dart';
import 'package:ridex/core/services/routes/route_service.dart';
import 'package:ridex/core/services/routes/supabase_route_service.dart';

final authServiceProvider = Provider<AuthService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return AuthService(client);
});

final profileServiceProvider = Provider<ProfileService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return ProfileService(client);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (!EnvConfig.hasBackendConfig) {
    return MockAuthRepository();
  }
  return SupabaseAuthRepository(
    authService: ref.watch(authServiceProvider)!,
    profileService: ref.watch(profileServiceProvider)!,
  );
});
final bookingRepositoryProvider =
    Provider<BookingRepository>((ref) => MockBookingRepository());
final placeServiceProvider = Provider<PlaceService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : SupabasePlaceService(
          client,
          ref.watch(appErrorReporterProvider),
        );
});
final placeRepositoryProvider = Provider<PlaceRepository>((ref) {
  if (!EnvConfig.hasBackendConfig) return MockPlaceRepository();
  return GooglePlaceRepository(
    ref.watch(placeServiceProvider)!,
    errorReporter: ref.watch(appErrorReporterProvider),
  );
});
final routeServiceProvider = Provider<RouteService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : SupabaseRouteService(
          client,
          ref.watch(appErrorReporterProvider),
        );
});
final routeRepositoryProvider = Provider<RouteRepository>((ref) {
  if (!EnvConfig.hasBackendConfig) return const MockRouteRepository();
  return GoogleRouteRepository(
    ref.watch(routeServiceProvider)!,
    errorReporter: ref.watch(appErrorReporterProvider),
  );
});
final tripsRepositoryProvider =
    Provider<TripsRepository>((ref) => MockTripsRepository());
final driverLocationServiceProvider = Provider<DriverLocationService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : SupabaseDriverLocationService(
          client,
          ref.watch(appErrorReporterProvider),
        );
});
final driverLocationRepositoryProvider =
    Provider<DriverLocationRepository>((ref) {
  if (!EnvConfig.hasBackendConfig) return MockDriverLocationRepository();
  return ServiceDriverLocationRepository(
    ref.watch(driverLocationServiceProvider)!,
  );
});
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (!EnvConfig.hasBackendConfig) {
    return MockProfileRepository();
  }
  return SupabaseProfileRepository(
    client: ref.watch(supabaseClientProvider)!,
    profileService: ref.watch(profileServiceProvider)!,
  );
});

final currentProfileProvider = FutureProvider.autoDispose<AppUser>((ref) {
  return ref.watch(profileRepositoryProvider).getCurrentProfile();
});
