import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
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

    test('pending, approved, and blocked states are loaded from database',
        skip: !hasEnv, () async {
      final suffix = DateTime.now().millisecondsSinceEpoch;
      final riderEmail = 'ridex_status_rider_$suffix@example.com';
      final driverEmail = 'ridex_status_driver_$suffix@example.com';
      const password = 'Ridex123!';

      await repository.signUp(
        name: 'State Rider $suffix',
        email: riderEmail,
        password: password,
        role: RideRole.rider,
      );
      await repository.signOut();

      final pendingDriver = await repository.signUp(
        name: 'State Driver $suffix',
        email: driverEmail,
        password: password,
        role: RideRole.driver,
      );
      expect(pendingDriver.driverApprovalStatus, DriverApprovalStatus.pending);
      expect(SessionState.fromUser(pendingDriver).status,
          SessionStatus.driverPending);
      await repository.signOut();

      final approveResult = await Process.run(
        'npx',
        [
          'supabase',
          'db',
          'query',
          "update public.driver_profiles set approval_status = 'approved' where user_id = (select id from public.users where email = '$driverEmail');",
        ],
        runInShell: true,
      );
      expect(approveResult.exitCode, 0,
          reason: approveResult.stderr.toString());

      final approvedDriver = await repository.signIn(
        email: driverEmail,
        password: password,
      );
      expect(
          approvedDriver.driverApprovalStatus, DriverApprovalStatus.approved);
      expect(SessionState.fromUser(approvedDriver).status,
          SessionStatus.authenticated);
      await repository.signOut();

      final blockResult = await Process.run(
        'npx',
        [
          'supabase',
          'db',
          'query',
          "update public.users set is_blocked = true where email = '$riderEmail';",
        ],
        runInShell: true,
      );
      expect(blockResult.exitCode, 0, reason: blockResult.stderr.toString());

      final blockedRider = await repository.signIn(
        email: riderEmail,
        password: password,
      );
      expect(blockedRider.isBlocked, isTrue);
      expect(SessionState.fromUser(blockedRider).status, SessionStatus.blocked);
      await repository.signOut();
    });
  });
}
