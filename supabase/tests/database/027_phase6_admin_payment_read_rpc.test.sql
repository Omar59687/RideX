begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at,
  updated_at, confirmation_token, email_change, email_change_token_new,
  recovery_token)
values
  ('00000000-0000-0000-0000-000000000000', 'fa000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-027@example.com', '', now(), '{}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'fa000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'driver-027@example.com', '', now(), '{}', '{"display_name":"Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'fa000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'foreign-rider-027@example.com', '', now(), '{}', '{"display_name":"Foreign Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'fa000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'admin-027@example.com', '', now(), '{}', '{"display_name":"Admin"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'fa000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'blocked-admin-027@example.com', '', now(), '{}', '{"display_name":"Blocked Admin"}', now(), now(), '', '', '', '');
update public.users set role = 'driver' where id = 'fa000000-0000-0000-0000-000000000002';
update public.users set role = 'admin' where id in ('fa000000-0000-0000-0000-000000000004', 'fa000000-0000-0000-0000-000000000005');
update public.users set is_blocked = true where id = 'fa000000-0000-0000-0000-000000000005';
delete from public.rider_profiles where user_id in ('fa000000-0000-0000-0000-000000000002', 'fa000000-0000-0000-0000-000000000004', 'fa000000-0000-0000-0000-000000000005');

delete from public.pricing_configurations where vehicle_type_code = 'comfort';
insert into public.pricing_configurations (id, vehicle_type_code, pricing_version,
  base_fare_fils, per_kilometer_fils, per_minute_fils, per_stop_fils,
  minimum_fare_fils, is_active)
values ('fa200000-0000-0000-0000-000000000001', 'comfort', 1, 500, 300, 50, 200, 1000, true);

-- A deterministic 55-row fixture verifies the hard server-side cap. These
-- isolated test records are rolled back below and are not production data.
insert into public.booking_requests (id, rider_id, pickup, destination,
  vehicle_type_code, payment_method)
select ('fa300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       'fa000000-0000-0000-0000-000000000001',
       '{"latitude":31.9,"longitude":35.9}'::jsonb,
       '{"latitude":32.0,"longitude":36.0}'::jsonb,
       'comfort', 'cash'
  from generate_series(1, 55) as n;

insert into public.fare_quotes (id, booking_request_id, rider_id, status,
  pickup, destination, route_distance_meters, route_duration_seconds,
  vehicle_type_code, breakdown, fixed_fare_fils, pricing_configuration_id,
  pricing_version, quote_version)
select ('fa400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       ('fa300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       'fa000000-0000-0000-0000-000000000001', 'calculated',
       '{"latitude":31.9,"longitude":35.9}'::jsonb,
       '{"latitude":32.0,"longitude":36.0}'::jsonb,
       1000, 300, 'comfort', '{}', 1000,
       'fa200000-0000-0000-0000-000000000001', 1, 1
  from generate_series(1, 55) as n;

insert into public.payments (id, booking_request_id, rider_id, method,
  fare_quote_id, authorized_amount_fils, final_amount_fils, cash_status,
  card_status, card_brand, card_last_four, created_at, version, provider_name)
select ('fa500000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       ('fa300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       'fa000000-0000-0000-0000-000000000001',
       case when n = 1 then 'card'::public.payment_method else 'cash'::public.payment_method end,
       ('fa400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       1000, 1000,
       case when n = 1 then null else 'cashSelected'::public.cash_payment_status end,
       case when n = 1 then 'cardPaymentPending'::public.card_payment_status end,
       case when n = 1 then 'visa' end,
       case when n = 1 then '4242' end,
       now() - n * interval '1 minute', 7,
       case when n = 1 then 'provider-private' end
  from generate_series(1, 55) as n;

insert into public.booking_requests (id, rider_id, pickup, destination,
  vehicle_type_code, payment_method)
values ('fa600000-0000-0000-0000-000000000001',
        'fa000000-0000-0000-0000-000000000003',
        '{"latitude":31.9,"longitude":35.9}',
        '{"latitude":32.0,"longitude":36.0}', 'comfort', 'cash');
insert into public.fare_quotes (id, booking_request_id, rider_id, status,
  pickup, destination, route_distance_meters, route_duration_seconds,
  vehicle_type_code, breakdown, fixed_fare_fils, pricing_configuration_id,
  pricing_version, quote_version)
values ('fa600000-0000-0000-0000-000000000002',
        'fa600000-0000-0000-0000-000000000001',
        'fa000000-0000-0000-0000-000000000003', 'calculated',
        '{"latitude":31.9,"longitude":35.9}',
        '{"latitude":32.0,"longitude":36.0}', 1000, 300, 'comfort', '{}',
        1000, 'fa200000-0000-0000-0000-000000000001', 1, 1);
insert into public.payments (id, booking_request_id, rider_id, method,
  fare_quote_id, authorized_amount_fils, final_amount_fils, cash_status)
values ('fa600000-0000-0000-0000-000000000003',
        'fa600000-0000-0000-0000-000000000001',
        'fa000000-0000-0000-0000-000000000003', 'cash',
        'fa600000-0000-0000-0000-000000000002', 1000, 1000, 'cashSelected');

select is((select count(*) from pg_policies where schemaname = 'public'
  and tablename = 'payments' and cmd = 'SELECT'), 0::bigint,
  'migration 019 deny-all Payment SELECT policies remain absent');
select ok(not has_function_privilege('anon',
  'public.user_canonical_payment_record(uuid)', 'EXECUTE'),
  'anon cannot execute canonical Payment RPC');
select ok(not has_function_privilege('anon',
  'public.admin_recent_canonical_payments()', 'EXECUTE'),
  'anon cannot execute Admin listing RPC');
select ok(has_function_privilege('authenticated',
  'public.user_canonical_payment_record(uuid)', 'EXECUTE'),
  'authenticated can invoke the ownership-checked exact RPC');
select ok(has_function_privilege('authenticated',
  'public.admin_recent_canonical_payments()', 'EXECUTE'),
  'authenticated can invoke the Admin-authorized listing RPC');
select ok(not has_function_privilege('authenticated',
  'private.can_read_canonical_payment(uuid)', 'EXECUTE'),
  'private authorization helper is not client executable');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select booking_request_id from public.user_canonical_payment_record(
  'fa500000-0000-0000-0000-000000000001')),
  'fa300000-0000-0000-0000-000000000001'::uuid,
  'Rider receives persisted canonical booking identity');
select is((select version from public.user_canonical_payment_record(
  'fa500000-0000-0000-0000-000000000001')), 7,
  'Rider receives persisted Payment version without fabrication');
select is((select md5(string_agg(to_jsonb(payment_record)::text, ',' order by payment_record.id))
  from public.user_canonical_payment_record('fa500000-0000-0000-0000-000000000001') as payment_record),
  (select md5(string_agg(to_jsonb(payment_record)::text, ',' order by payment_record.id))
  from public.user_canonical_payment_record('fa500000-0000-0000-0000-000000000001') as payment_record),
  'repeated canonical reads return the same persisted record');
select is_empty($$select id from public.user_canonical_payment_record(
  'fa600000-0000-0000-0000-000000000003')$$,
  'another Rider cannot read a foreign payment ID');
select is_empty($$select id from public.user_canonical_payment_record(
  'fa5fffff-ffff-ffff-ffff-ffffffffffff')$$,
  'nonexistent payment ID returns the same empty shape as unauthorized IDs');
select is_empty($$select id from public.payments$$,
  'direct SELECT returns no Payment rows under migration 019 RLS');
select throws_ok($$select * from public.admin_recent_canonical_payments()$$,
  '42501', 'Only a non-blocked Admin can manage Drivers.',
  'Rider is rejected by the Admin listing RPC');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is_empty($$select id from public.user_canonical_payment_record(
  'fa500000-0000-0000-0000-000000000001')$$,
  'Driver cannot read a canonical payment');
select throws_ok($$select * from public.admin_recent_canonical_payments()$$,
  '42501', 'Only a non-blocked Admin can manage Drivers.',
  'Driver is rejected by the Admin listing RPC');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.admin_recent_canonical_payments()), 50::bigint,
  'Admin listing is capped at 50 rows');
select is((select booking_request_id from public.user_canonical_payment_record(
  'fa500000-0000-0000-0000-000000000001')),
  'fa300000-0000-0000-0000-000000000001'::uuid,
  'active Admin can read a canonical payment identity');
select ok((select version > 0 from public.user_canonical_payment_record(
  'fa500000-0000-0000-0000-000000000001')),
  'active Admin receives the stored positive Payment version');
select is_empty($$select provider_name from public.payments$$,
  'Admin cannot read raw provider fields from payments');
select ok(not ((select proargnames from pg_proc where oid =
  'public.admin_recent_canonical_payments()'::regprocedure)
  && array['provider_name', 'provider_transaction_reference',
           'provider_refund_reference', 'sanitized_failure_message']),
  'Admin RPC result contains no provider references or raw failure messages');
select is((select md5(string_agg(to_jsonb(payment_record)::text, ',' order by payment_record.id))
  from public.admin_recent_canonical_payments() as payment_record),
  (select md5(string_agg(to_jsonb(payment_record)::text, ',' order by payment_record.id))
  from public.admin_recent_canonical_payments() as payment_record),
  'repeated Admin listing reads return the same bounded records');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select * from public.admin_recent_canonical_payments()$$,
  '42501', 'Only a non-blocked Admin can manage Drivers.',
  'blocked Admin is rejected by the Admin listing RPC');
select is_empty($$select id from public.user_canonical_payment_record(
  'fa500000-0000-0000-0000-000000000001')$$,
  'blocked Admin exact-ID reads fail closed without existence disclosure');
reset role;

update public.users set is_blocked = false, role = 'rider'
 where id = 'fa000000-0000-0000-0000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select * from public.admin_recent_canonical_payments()$$,
  '42501', 'Only a non-blocked Admin can manage Drivers.',
  'demoted Admin with stale JWT claims is rejected');
select is_empty($$select id from public.user_canonical_payment_record(
  'fa500000-0000-0000-0000-000000000001')$$,
  'demoted Admin cannot use stale claims for exact-ID reads');
reset role;

set local role anon;
select throws_ok($$select * from public.admin_recent_canonical_payments()$$,
  '42501', null, 'anonymous caller has no Admin listing execution privilege');
reset role;

select * from finish();
rollback;
