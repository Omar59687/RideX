import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/004_enforce_role_authorization_boundary.sql',
    ).readAsStringSync();
  });

  test('public signup is Rider-only and ignores role metadata', () {
    final signupFunction = _between(
      migration,
      'create or replace function public.handle_new_user()',
      '-- Preserve every existing profile',
    );

    expect(signupFunction, contains("'rider'"));
    expect(signupFunction, contains('insert into public.rider_profiles'));
    expect(signupFunction, isNot(contains("->> 'role'")));
    expect(signupFunction, isNot(contains('public.driver_profiles')));
  });

  test('compatibility backfill preserves rows and defaults Drivers pending',
      () {
    final backfill = _between(
      migration,
      '-- Preserve every existing profile',
      '-- Reassert the client table boundary',
    );

    expect(backfill, contains("where users.role = 'rider'"));
    expect(backfill, contains("where users.role = 'driver'"));
    expect(backfill, contains("select users.id, 'pending'"));
    expect(
        'on conflict (user_id) do nothing'.allMatches(backfill), hasLength(2));
    expect(backfill, isNot(contains('update public.driver_profiles')));
  });

  test('Admin operations fail closed and have locked execution grants', () {
    const functions = <String>[
      'admin_promote_user_to_driver',
      'admin_approve_driver',
      'admin_reject_driver',
    ];

    for (final function in functions) {
      final start = migration.indexOf('function public.$function(');
      expect(start, greaterThanOrEqualTo(0), reason: '$function is missing');
      final bodyEnd = migration.indexOf(r'$$;', start);
      final body = migration.substring(start, bodyEnd);

      expect(body, contains('security definer'));
      expect(body, contains("set search_path = ''"));
      expect(body, contains('caller.role = \'admin\''));
      expect(body, contains('and not caller.is_blocked'));
      expect(body, contains('caller.id = auth.uid()'));
    }

    expect(
      RegExp(
        r'grant execute on function public\.admin_[^;]+ to authenticated;',
      ).allMatches(migration),
      hasLength(3),
    );
    expect(
      RegExp(
        r'revoke all on function public\.admin_[^;]+ from public, anon, authenticated;',
      ).allMatches(migration),
      hasLength(3),
    );
  });

  test('authenticated table grants expose no authorization columns', () {
    final grants = _between(
      migration,
      '-- Reassert the client table boundary',
      'create or replace function public.admin_promote_user_to_driver',
    );

    expect(grants, contains('revoke all on table public.users'));
    expect(
      grants,
      contains(
        'grant update (display_name, photo_url) on table public.users '
        'to authenticated;',
      ),
    );
    expect(grants, isNot(contains('grant update (role')));
    expect(grants, isNot(contains('grant update (approval_status')));
  });
}

String _between(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start);

  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startMarker');
  expect(end, greaterThan(start), reason: 'Missing $endMarker');
  return source.substring(start, end);
}
