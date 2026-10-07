import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/repositories/auth_repository.dart';
import 'package:ridex/core/repositories/booking_repository.dart';
import 'package:ridex/core/repositories/driver_location_repository.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
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
import 'package:supabase_flutter/supabase_flutter.dart';

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
final fareRepositoryProvider = Provider<FareRepository>((ref) {
  if (!EnvConfig.hasBackendConfig) {
    // Demo mode: the fare screen keeps the deterministic demo fare path and
    // never calls this repository.
    return const UnavailableFareRepository();
  }
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    return const UnavailableFareRepository();
  }
  return SupabaseFareRepository(
    rpc: ({required String name, required Map<String, dynamic> params}) async {
      try {
        final data = await client.rpc(name, params: params);
        if (data is Map) {
          return data.map((key, value) => MapEntry(key.toString(), value));
        }
        throw const FareException(FareFailure.invalidResponse);
      } on PostgrestException catch (error) {
        throw FareTransportFailure(code: _farePostgrestCode(error));
      } on FareException {
        rethrow;
      }
    },
    quoteEdge: (Map<String, dynamic> body) async {
      try {
        final response = await client.functions.invoke('fare', body: body);
        final envelope = response.data;
        if (envelope is! Map) {
          throw const FareException(FareFailure.invalidResponse);
        }
        return envelope.map((key, value) => MapEntry(key.toString(), value));
      } on FunctionException catch (error) {
        throw FareTransportFailure(
          status: error.status,
          code: _fareEdgeCode(error),
        );
      } on FareException {
        rethrow;
      }
    },
    errorReporter: ref.watch(appErrorReporterProvider),
  );
});
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

/// Maps a PostgREST RPC failure to a provider-neutral fare error code.
///
/// The sanitized backend message is inspected (never surfaced) only to
/// distinguish a missing pricing configuration from other backend errors.
/// Pricing-config seeding is owner-ops: without an active pricing
/// configuration the RPC raises and the UI reports the fare as unavailable.
String? _farePostgrestCode(PostgrestException error) {
  if (error.code == '55000' &&
      error.message.toLowerCase().contains('pricing configuration')) {
    return 'no_pricing_configuration';
  }
  final code = error.code;
  return code == null || code.isEmpty ? null : code;
}

/// Extracts the sanitized Edge `fare` error code from function details.
String? _fareEdgeCode(FunctionException error) {
  final details = error.details;
  if (details is Map) {
    final nested = details['error'];
    if (nested is Map && nested['code'] is String) {
      return nested['code'] as String;
    }
    if (details['code'] is String) {
      return details['code'] as String;
    }
  }
  return null;
}
