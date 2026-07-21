import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/repositories/auth_repository.dart';
import 'package:ridex/core/repositories/booking_repository.dart';
import 'package:ridex/core/repositories/profile_repository.dart';
import 'package:ridex/core/repositories/supabase_auth_repository.dart';
import 'package:ridex/core/repositories/supabase_profile_repository.dart';
import 'package:ridex/core/repositories/trips_repository.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/profile_service.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';

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
final tripsRepositoryProvider =
    Provider<TripsRepository>((ref) => MockTripsRepository());
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (!EnvConfig.hasBackendConfig) {
    return MockProfileRepository();
  }
  return SupabaseProfileRepository(
    client: ref.watch(supabaseClientProvider)!,
    profileService: ref.watch(profileServiceProvider)!,
  );
});
