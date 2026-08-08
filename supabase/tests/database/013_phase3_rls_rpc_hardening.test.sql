begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

create temporary table phase3_tables (name text primary key, client_select boolean not null);
insert into phase3_tables (name, client_select) values
  ('audit_records', false), ('command_idempotency_keys', false),
  ('vehicles', true), ('driver_availability', true), ('pricing_configurations', true),
  ('booking_requests', true), ('booking_stops', true), ('fare_quotes', true),
  ('driver_match_offers', true), ('trips', true), ('trip_stops', true),
  ('trip_status_events', true), ('trip_change_requests', true), ('fare_adjustments', true),
  ('payments', true), ('payment_attempts', true), ('refunds', true), ('receipts', true),
  ('processed_webhook_events', false), ('driver_locations', true), ('ratings', true),
  ('notifications', true), ('help_requests', true);

select is(
  (select count(*) from phase3_tables), 23::bigint,
  'the complete Phase 3 table inventory is covered'
);
select is(
  (select count(*) from phase3_tables as expected
   join pg_class as tables on tables.oid = ('public.' || expected.name)::regclass
   where tables.relrowsecurity),
  23::bigint, 'every Phase 3 table has RLS enabled'
);
select is(
  (select count(*) from phase3_tables as expected
   where not has_table_privilege('anon', ('public.' || expected.name)::regclass, 'select,insert,update,delete')),
  23::bigint, 'anonymous has no direct access to every Phase 3 table'
);
select is(
  (select count(*) from phase3_tables as expected
   where not has_table_privilege('authenticated', ('public.' || expected.name)::regclass, 'insert,update,delete')),
  23::bigint, 'authenticated clients have no Phase 3 direct write grants'
);
select is(
  (select count(*) from phase3_tables as expected
   where has_table_privilege('authenticated', ('public.' || expected.name)::regclass, 'select') = expected.client_select),
  23::bigint, 'authenticated select grants exactly match the RLS matrix'
);
select is(
  (select count(*) from phase3_tables as expected
   left join pg_policies as policies on policies.schemaname = 'public'
     and policies.tablename = expected.name and policies.cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
   where policies.policyname is null),
  23::bigint, 'no Phase 3 table has a client write policy'
);
select is(
  (select count(*) from pg_policies
   where schemaname = 'public' and tablename in (select name from phase3_tables)
     and roles @> array['authenticated']::name[] and cmd = 'SELECT'),
  16::bigint, 'only non-finance Phase 3 tables have authenticated select policies'
);

select is(
  (select count(*) from pg_proc as functions
   join pg_namespace as schemas on schemas.oid = functions.pronamespace
   where schemas.nspname in ('public', 'private')
     and has_function_privilege('public', functions.oid, 'execute')),
  0::bigint, 'PUBLIC has no execute grant on public or private functions'
);
select is(
  (select count(*) from pg_proc as functions
   join pg_namespace as schemas on schemas.oid = functions.pronamespace
   where schemas.nspname in ('public', 'private')
     and has_function_privilege('anon', functions.oid, 'execute')),
  0::bigint, 'anonymous callers cannot execute public or private functions'
);
select is(
  (select count(*) from pg_proc as functions
   join pg_namespace as schemas on schemas.oid = functions.pronamespace
   where schemas.nspname in ('public', 'private')
     and coalesce(array_to_string(functions.proconfig, ','), '') not in ('search_path=""', 'search_path=')),
  0::bigint, 'public and private functions use an empty search path'
);
select is(
  (select count(*) from pg_proc as functions
   join pg_namespace as schemas on schemas.oid = functions.pronamespace
   where schemas.nspname = 'public' and functions.proname like 'backend_%'
     and not has_function_privilege('authenticated', functions.oid, 'execute')
     and has_function_privilege('service_role', functions.oid, 'execute')),
  17::bigint, 'all backend-only Phase 3 RPCs are isolated to service_role'
);
select ok(not has_schema_privilege('authenticated', 'private', 'USAGE'), 'clients cannot resolve private helpers');
select ok(not has_function_privilege('authenticated', 'private.refresh_driver_rating_aggregate()', 'execute'), 'rating aggregate helper is private');
select ok(not has_function_privilege('authenticated', 'private.is_safe_json_content(jsonb,integer,integer)', 'execute'), 'JSON safety helper is private');
select ok(has_function_privilege('service_role', 'public.backend_price_trip_change_request_remaining(uuid,integer,integer,integer,integer,integer,text)', 'execute'), 'service role can execute remaining-route pricing');
select ok(not has_function_privilege('authenticated', 'public.backend_price_trip_change_request_remaining(uuid,integer,integer,integer,integer,integer,text)', 'execute'), 'authenticated cannot execute remaining-route pricing');
select ok(not has_function_privilege('anon', 'public.backend_price_trip_change_request_remaining(uuid,integer,integer,integer,integer,integer,text)', 'execute'), 'anonymous cannot execute remaining-route pricing');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
values
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'hardening-rider@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Hardening Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'hardening-rider-two@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Hardening Rider Two"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'hardening-driver@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Hardening Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000020', 'authenticated', 'authenticated', 'hardening-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Hardening Admin"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000030', 'authenticated', 'authenticated', 'hardening-blocked@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Hardening Blocked"}', now(), now(), '', '', '', '');
update public.users set role = 'driver' where id = 'd1000000-0000-0000-0000-000000000011';
update public.users set role = 'admin' where id = 'd1000000-0000-0000-0000-000000000020';
update public.users set is_blocked = true where id = 'd1000000-0000-0000-0000-000000000030';
delete from public.rider_profiles where user_id in ('d1000000-0000-0000-0000-000000000011', 'd1000000-0000-0000-0000-000000000020');
insert into public.driver_profiles (user_id, approval_status, is_online, is_available)
values ('d1000000-0000-0000-0000-000000000011', 'approved', false, false);
insert into public.vehicles (id, driver_id, vehicle_type_code, make, model, color, registration_plate, seat_capacity, is_active)
values ('d1100000-0000-0000-0000-000000000011', 'd1000000-0000-0000-0000-000000000011', 'economy', 'Toyota', 'Camry', 'White', 'DH 011', 4, true);
insert into public.pricing_configurations (id, vehicle_type_code, pricing_version, base_fare_fils, per_kilometer_fils, per_minute_fils, per_stop_fils, minimum_fare_fils, is_active)
values ('d1200000-0000-0000-0000-000000000001', 'economy', 1, 500, 300, 50, 200, 1000, true);
insert into public.booking_requests (id, rider_id, pickup, destination, vehicle_type_code, payment_method)
values
  ('d1200000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 'economy', 'cash'),
  ('d1200000-0000-0000-0000-000000000012', 'd1000000-0000-0000-0000-000000000002', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 'economy', 'cash');
insert into public.fare_quotes (id, booking_request_id, rider_id, status, pickup, destination, route_distance_meters, route_duration_seconds, vehicle_type_code, breakdown, fixed_fare_fils, pricing_configuration_id, pricing_version, quote_version, locked_at)
values
  ('d1200000-0000-0000-0000-000000000003', 'd1200000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'locked', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 'economy', '{}', 1000, 'd1200000-0000-0000-0000-000000000001', 1, 1, now()),
  ('d1200000-0000-0000-0000-000000000013', 'd1200000-0000-0000-0000-000000000012', 'd1000000-0000-0000-0000-000000000002', 'locked', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 'economy', '{}', 1000, 'd1200000-0000-0000-0000-000000000001', 1, 1, now());
update public.booking_requests set fare_quote_id = case id when 'd1200000-0000-0000-0000-000000000002' then 'd1200000-0000-0000-0000-000000000003'::uuid else 'd1200000-0000-0000-0000-000000000013'::uuid end;
insert into public.trips (id, booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id, status, payment_method, pickup, destination, route_distance_meters, route_duration_seconds, original_fare_fils, current_fare_fils, completed_at)
values
  ('d1200000-0000-0000-0000-000000000004', 'd1200000-0000-0000-0000-000000000002', 'd1200000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000011', 'd1100000-0000-0000-0000-000000000011', 'completed', 'cash', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 1000, 1000, now()),
  ('d1200000-0000-0000-0000-000000000014', 'd1200000-0000-0000-0000-000000000012', 'd1200000-0000-0000-0000-000000000013', 'd1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000011', 'd1100000-0000-0000-0000-000000000011', 'completed', 'cash', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 1000, 1000, now());
insert into public.payments (id, booking_request_id, trip_id, rider_id, method, fare_quote_id, authorized_amount_fils, final_amount_fils, cash_status)
values ('d1200000-0000-0000-0000-000000000005', 'd1200000-0000-0000-0000-000000000002', 'd1200000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000001', 'cash', 'd1200000-0000-0000-0000-000000000003', 1000, 1000, 'cashSelected');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.rider_create_rating('d1200000-0000-0000-0000-000000000004', 5::smallint, 'Excellent', '["safe_driver"]'::jsonb)$$, 'first Rating succeeds');
reset role;
select is((select rating_average from public.driver_profiles where user_id = 'd1000000-0000-0000-0000-000000000011'), 5.00::numeric, 'first Rating initializes the trusted average');
select is((select rating_count from public.driver_profiles where user_id = 'd1000000-0000-0000-0000-000000000011'), 1, 'first Rating initializes the trusted count');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.rider_create_rating('d1200000-0000-0000-0000-000000000004', 5::smallint, ' Excellent ', '["safe_driver"]'::jsonb)$$, 'identical normalized Rating retry returns the existing row');
select throws_ok($$select public.rider_create_rating('d1200000-0000-0000-0000-000000000004', 4::smallint, 'Excellent', '["safe_driver"]'::jsonb)$$, '55000', 'Rating retry does not match the existing Rating.', 'mismatched Rating retry fails closed');
reset role;
select is((select rating_count from public.driver_profiles where user_id = 'd1000000-0000-0000-0000-000000000011'), 1, 'Rating retries do not double-count');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.rider_create_rating('d1200000-0000-0000-0000-000000000014', 3::smallint, null, '[]'::jsonb)$$, 'second Rating succeeds');
reset role;
select is((select rating_average from public.driver_profiles where user_id = 'd1000000-0000-0000-0000-000000000011'), 4.00::numeric, 'multiple Ratings refresh the trusted average');
select is((select rating_count from public.driver_profiles where user_id = 'd1000000-0000-0000-0000-000000000011'), 2, 'multiple Ratings refresh the trusted count');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.user_create_help_request('trip', 'Late pickup', 'The driver arrived late.', 'normal', 'd1200000-0000-0000-0000-000000000004', 'd1200000-0000-0000-0000-000000000005', 'hardening-help')$$, 'same HelpRequest payload is repeat-safe');
select lives_ok($$select public.user_create_help_request(' trip ', ' Late pickup ', ' The driver arrived late. ', 'normal', 'd1200000-0000-0000-0000-000000000004', 'd1200000-0000-0000-0000-000000000005', ' hardening-help ')$$, 'normalized HelpRequest retry is repeat-safe');
select throws_ok($$select public.user_create_help_request('trip', 'Different subject', 'The driver arrived late.', 'normal', 'd1200000-0000-0000-0000-000000000004', 'd1200000-0000-0000-0000-000000000005', 'hardening-help')$$, '55000', 'HelpRequest retry does not match the existing HelpRequest.', 'mismatched HelpRequest retry fails closed');
select is((select count(*) from public.help_requests), 1::bigint, 'HelpRequest mismatch cannot create or mutate a request');
reset role;

set local role service_role;
select lives_ok($$select public.backend_create_notification('d1000000-0000-0000-0000-000000000001', 'trip.completed', 'Trip complete', 'Your trip is complete.', '{"destination":"notifications"}', null, 'hardening-notification')$$, 'backend notification creation succeeds');
select lives_ok($$select public.backend_create_notification('d1000000-0000-0000-0000-000000000001', 'trip.completed', ' Trip complete ', ' Your trip is complete. ', '{"destination":"notifications"}', null, ' hardening-notification ')$$, 'identical normalized notification retry returns the original');
select throws_ok($$select public.backend_create_notification('d1000000-0000-0000-0000-000000000001', 'trip.completed', 'Changed', 'Your trip is complete.', '{"destination":"notifications"}', null, 'hardening-notification')$$, '55000', 'Notification retry does not match the existing Notification.', 'notification mismatch fails closed');
select lives_ok($$select public.backend_create_notification('d1000000-0000-0000-0000-000000000002', 'trip.completed', 'Trip complete', 'Your trip is complete.', '{"destination":"notifications"}', null, 'hardening-notification')$$, 'notification deduplication remains recipient-isolated');
select is((select count(*) from public.notifications), 2::bigint, 'notification retries never duplicate records');
select throws_ok($$select public.backend_create_notification('d1000000-0000-0000-0000-000000000001', 'security.notice', 'Notice', 'Body', '{"destination":"notifications","safe":{"access_token":"not-stored"}}', null, 'nested-token')$$, '23514', null, 'nested access tokens are rejected');
select throws_ok($$select public.backend_create_notification('d1000000-0000-0000-0000-000000000001', 'security.notice', 'Notice', 'Body', '{"destination":"notifications","items":[{"card_number":"not-stored"}]}', null, 'nested-pan')$$, '23514', null, 'nested card data is rejected');
reset role;

select throws_ok($$select private.write_audit_record(null, 'unsafe.audit', null, null, '{"latitude":31.95}'::jsonb, '{}'::jsonb)$$, '22023', 'Audit data must contain only bounded safe metadata.', 'audit records reject precise Driver coordinates');
select throws_ok($$select private.write_audit_record(null, 'unsafe.audit', null, null, '{}'::jsonb, '{"authorization":"not-stored"}'::jsonb)$$, '22023', 'Audit data must contain only bounded safe metadata.', 'audit records reject credentials');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000030', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.ratings), 0::bigint, 'blocked users receive no Rating rows');
select is((select count(*) from public.notifications), 0::bigint, 'blocked users receive no Notification rows');
select throws_ok($$select public.user_create_help_request('other', 'Blocked', 'No access.', 'normal')$$, '42501', 'Only a non-blocked Rider or Driver can create help requests.', 'blocked users cannot execute guarded commands');
reset role;
set local role anon;
select throws_ok($$select count(*) from public.trips$$, '42501', null, 'anonymous users cannot read Phase 3 participant data');
select throws_ok($$select public.rider_create_rating('d1200000-0000-0000-0000-000000000004', 5::smallint, null, '[]'::jsonb)$$, '42501', null, 'anonymous users cannot execute guarded RPCs');
reset role;

select * from finish();
rollback;
