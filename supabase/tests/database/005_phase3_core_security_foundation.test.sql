begin;

create extension if not exists pgtap with schema extensions;

select plan(55);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'bootstrap@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Bootstrap Target"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'blocked@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Blocked Target"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'driver@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver Target"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'blocked-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Blocked Admin"}', now(), now(), '', '', '', '');

update public.users set is_blocked = true where id = '20000000-0000-0000-0000-000000000002';

select has_schema('private', 'private schema exists');
select has_type('public', 'booking_request_status', 'booking status enum exists');
select has_type('public', 'trip_status', 'trip status enum exists');
select has_type('public', 'fare_quote_status', 'fare quote status enum exists');
select has_type('public', 'trip_change_request_status', 'trip change status enum exists');
select has_type('public', 'payment_method', 'payment method enum exists');
select has_type('public', 'cash_payment_status', 'cash status enum exists');
select has_type('public', 'card_payment_status', 'card status enum exists');
select has_type('public', 'payment_attempt_type', 'attempt type enum exists');
select has_type('public', 'payment_attempt_status', 'attempt status enum exists');
select has_type('public', 'driver_availability_state', 'availability enum exists');
select has_table('public', 'audit_records', 'audit table exists');
select has_table('public', 'command_idempotency_keys', 'idempotency table exists');
select has_column('public', 'users', 'version', 'users have optimistic versions');
select has_column('public', 'rider_profiles', 'version', 'rider profiles have optimistic versions');
select has_column('public', 'driver_profiles', 'version', 'driver profiles have optimistic versions');
select col_is_pk('public', 'audit_records', 'id', 'audit records have UUID primary keys');
select has_index('public', 'command_idempotency_keys', 'command_idempotency_keys_expires_at_idx', 'idempotency retention index exists');
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.command_idempotency_keys'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%expires_at%created_at%7 days%'
  ),
  'seven-day retention check exists'
);

select throws_ok(
  $$select private.bootstrap_first_admin('20000000-0000-0000-0000-000000000002', 'blocked')$$,
  '22023', 'A blocked account cannot become the first Admin.', 'blocked bootstrap target is rejected'
);
select throws_ok(
  $$select private.bootstrap_first_admin('20000000-0000-0000-0000-000000000099', 'missing')$$,
  'P0002', 'Target account was not found.', 'missing bootstrap target is rejected'
);
select throws_ok(
  $$select private.bootstrap_first_admin('20000000-0000-0000-0000-000000000001', ' ')$$,
  '22023', 'A nonblank audit reason of at most 500 characters is required.', 'blank bootstrap reason is rejected'
);
select lives_ok(
  $$select private.bootstrap_first_admin('20000000-0000-0000-0000-000000000001', 'Initial trusted operator bootstrap')$$,
  'database owner can bootstrap the first Admin'
);
select is((select role from public.users where id = '20000000-0000-0000-0000-000000000001'), 'admin', 'bootstrap promotes the target');
select ok(not exists (select 1 from public.rider_profiles where user_id = '20000000-0000-0000-0000-000000000001'), 'bootstrap preserves Admin profile consistency');
select is((select count(*) from public.audit_records where action = 'admin.bootstrap_first'), 1::bigint, 'bootstrap creates one audit record');
select throws_ok(
  $$select private.bootstrap_first_admin('20000000-0000-0000-0000-000000000003', 'second bootstrap')$$,
  '55000', 'An Admin already exists.', 'second/concurrent bootstrap fails closed'
);
select throws_ok(
  $$update public.audit_records set action = 'changed'$$,
  '55000', 'Audit records are immutable.', 'audit updates are immutable'
);
select throws_ok(
  $$delete from public.audit_records$$,
  '55000', 'Audit records are immutable.', 'audit deletes are immutable'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select private.bootstrap_first_admin('20000000-0000-0000-0000-000000000003', 'unauthorized')$$,
  '42501', null, 'authenticated callers cannot execute bootstrap'
);
select throws_ok($$insert into public.audit_records (action) values ('forbidden')$$, '42501', null, 'direct audit writes are denied');
select throws_ok(
  $$insert into public.command_idempotency_keys (actor_user_id, command_scope, idempotency_key, payload_fingerprint, canonical_result) values ('20000000-0000-0000-0000-000000000003', 'booking', 'forbidden', repeat('a', 64), '{}'::jsonb)$$,
  '42501', null, 'direct idempotency writes are denied'
);
reset role;

select ok(not has_function_privilege('public', 'private.bootstrap_first_admin(uuid,text)', 'EXECUTE'), 'public cannot execute bootstrap');
select ok(not has_function_privilege('anon', 'private.bootstrap_first_admin(uuid,text)', 'EXECUTE'), 'anon cannot execute bootstrap');
select ok(not has_function_privilege('authenticated', 'private.bootstrap_first_admin(uuid,text)', 'EXECUTE'), 'authenticated cannot execute bootstrap');
select ok(not has_function_privilege('service_role', 'private.bootstrap_first_admin(uuid,text)', 'EXECUTE'), 'service role cannot execute bootstrap');
select ok(not has_schema_privilege('authenticated', 'private', 'USAGE'), 'authenticated cannot use private schema');

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.admin_promote_user_to_driver('20000000-0000-0000-0000-000000000003')$$, 'Admin promotes Rider to Driver');
select lives_ok($$select public.admin_approve_driver('20000000-0000-0000-0000-000000000003')$$, 'Admin approves Driver');
select lives_ok($$select public.admin_reject_driver('20000000-0000-0000-0000-000000000003', 'Documents need review')$$, 'Admin rejects Driver');
select lives_ok($$select public.admin_set_user_blocked('20000000-0000-0000-0000-000000000003', true, 'Safety review')$$, 'Admin can block a user');
select lives_ok($$select public.admin_set_user_blocked('20000000-0000-0000-0000-000000000003', false, 'Review complete')$$, 'Admin can unblock a user');
reset role;
select is((select count(*) from public.audit_records where action in ('admin.driver_promoted', 'admin.driver_approved', 'admin.driver_rejected')), 3::bigint, 'Driver promotion and approval decisions are audited');
select is((select count(*) from public.audit_records where action = 'admin.user_blocked_state_set'), 2::bigint, 'block and unblock are audited');

update public.users set role = 'admin', is_blocked = true where id = '20000000-0000-0000-0000-000000000004';
delete from public.rider_profiles where user_id = '20000000-0000-0000-0000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.admin_approve_driver('20000000-0000-0000-0000-000000000003')$$, '42501', 'Only a non-blocked Admin can manage Drivers.', 'blocked Admin is rejected');
reset role;

select is(
  private.claim_command_idempotency_key('20000000-0000-0000-0000-000000000003', 'booking', 'confirm-1', repeat('a', 64), '{"booking_id":"canonical"}'::jsonb),
  '{"booking_id":"canonical"}'::jsonb, 'initial idempotency command returns its canonical result'
);
select is(
  private.claim_command_idempotency_key('20000000-0000-0000-0000-000000000003', 'booking', 'confirm-1', repeat('a', 64), '{"booking_id":"ignored"}'::jsonb),
  '{"booking_id":"canonical"}'::jsonb, 'matching key and payload replay returns the existing canonical result'
);
select is(
  private.claim_command_idempotency_key('20000000-0000-0000-0000-000000000003', 'booking', 'confirm-1', repeat('b', 64), '{}'::jsonb),
  '{"error":"idempotency_payload_mismatch"}'::jsonb,
  'different payload key reuse fails closed'
);
select is((select count(*) from public.audit_records where action = 'command.idempotency_payload_mismatch'), 1::bigint, 'idempotency mismatch is audited');
select is((select expires_at - created_at from public.command_idempotency_keys where idempotency_key = 'confirm-1'), interval '7 days', 'idempotency metadata retains commands for seven days');
select is((select version from public.users where id = '20000000-0000-0000-0000-000000000003'), 4, 'identity mutations advance optimistic versions');
select ok((select relrowsecurity from pg_class where oid = 'public.audit_records'::regclass), 'audit records have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.command_idempotency_keys'::regclass), 'idempotency records have RLS enabled');
select is((select count(*) from pg_proc where oid in ('private.bootstrap_first_admin(uuid,text)'::regprocedure, 'private.claim_command_idempotency_key(uuid,public.command_idempotency_scope,text,text,jsonb)'::regprocedure, 'public.admin_set_user_blocked(uuid,boolean,text)'::regprocedure) and prosecdef), 3::bigint, 'trusted functions are SECURITY DEFINER');
select is((select count(*) from pg_proc where oid in ('private.bootstrap_first_admin(uuid,text)'::regprocedure, 'private.claim_command_idempotency_key(uuid,public.command_idempotency_scope,text,text,jsonb)'::regprocedure, 'public.admin_set_user_blocked(uuid,boolean,text)'::regprocedure) and array_to_string(proconfig, ',') in ('search_path=""', 'search_path=')), 3::bigint, 'trusted functions have empty search paths');

select * from finish();
rollback;
