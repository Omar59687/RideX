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

  group('live Supabase auth', () {
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

    test('sign up, sign in, sign out, and restore session', skip: !hasEnv,
        () async {
      final suffix = DateTime.now().millisecondsSinceEpoch;
      final riderEmail = 'ridex_rider_$suffix@example.com';
      const password = 'Ridex123!';

      final rider = await repository.signUp(
        name: 'RideX Rider $suffix',
        email: riderEmail,
        password: password,
      );
      expect(rider.role, RideRole.rider);
      await repository.signOut();

      final signedIn = await repository.signIn(
        email: riderEmail,
        password: password,
      );
      expect(signedIn.role, RideRole.rider);

      final restored = await repository.restoreSession();
      expect(restored?.email, riderEmail);

      await repository.signOut();
      final afterSignOut = await repository.restoreSession();
      expect(afterSignOut, isNull);
    });
  });
}
