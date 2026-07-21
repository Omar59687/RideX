import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/repositories/profile_repository.dart';
import 'package:ridex/core/services/supabase/profile_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseProfileRepository implements ProfileRepository {
  const SupabaseProfileRepository({
    required SupabaseClient client,
    required ProfileService profileService,
  })  : _client = client,
        _profileService = profileService;

  final SupabaseClient _client;
  final ProfileService _profileService;

  @override
  Future<AppUser> getCurrentProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No signed-in user.');
    }
    return getProfile(userId);
  }

  @override
  Future<AppUser> getProfile(String userId) {
    return _profileService.fetchAppUser(userId);
  }
}
