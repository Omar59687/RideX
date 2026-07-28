import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/repositories/supabase_auth_repository.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final hasEnv = EnvConfig.supabaseUrl.isNotEmpty &&
      EnvConfig.supabasePublishableKey.isNotEmpty;

  group('live Supabase role state', () {
    late SupabaseClient client;
    late SupabaseAuthRepository repository;

    setUpAll(() async {
      if (!hasEnv) {
        return;
      }

      SharedPreferences.setMockInitialValues({});

      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        publishableKey: EnvConfig.supabasePublishableKey,
      );

      client = Supabase.instance.client;
      repository = SupabaseAuthRepository(
        authService: AuthService(client),
        profileService: ProfileService(client),
      );
    });

    test('public signup creates only Rider accounts', skip: !hasEnv, () async {
      final suffix = DateTime.now().millisecondsSinceEpoch;
      final email = 'ridex_status_rider_$suffix@example.com';
      const password = 'Ridex123!';

      final rider = await repository.signUp(
        name: 'State Rider $suffix',
        email: email,
        password: password,
      );
      expect(rider.role, RideRole.rider);
      await repository.signOut();
    });
  });
}
