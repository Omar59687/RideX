begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select is(
  (
    select count(*)::integer
    from public.pricing_configurations
    where is_active
  ),
  3,
  'Phase 5 bootstraps one active pricing configuration per vehicle type'
);

select is(
  (
    select count(distinct vehicle_type_code)::integer
    from public.pricing_configurations
    where is_active
  ),
  3,
  'all supported vehicle types have active pricing'
);

select is(
  (
    select count(*)::integer
    from public.pricing_configurations
    where is_active
      and base_fare_fils = 500
      and per_kilometer_fils = 300
      and per_minute_fils = 50
      and per_stop_fils = 200
      and minimum_fare_fils = 1000
      and rounding_increment_fils = 50
  ),
  3,
  'active bootstrap rows use the approved integer-fils formula'
);

select is(
  (
    select count(*)::integer
    from public.pricing_configurations
    where is_active
      and pricing_version > 0
  ),
  3,
  'active pricing rows are versioned'
);

select is(
  (
    select count(*)::integer
    from public.pricing_configurations
    where is_active
      and vehicle_type_code in (
        'economy'::public.vehicle_type_code,
        'comfort'::public.vehicle_type_code,
        'xl'::public.vehicle_type_code
      )
  ),
  3,
  'the active rows cover economy, comfort, and xl'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.rider_lock_fare_quote(uuid,uuid,integer,integer)',
    'EXECUTE'
  ),
  'authenticated callers can execute the Rider quote-lock wrapper'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.rider_lock_fare_quote(uuid,uuid,integer,integer)',
    'EXECUTE'
  ),
  'anonymous callers have no execute privilege on the wrapper'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.rider_lock_fare_quote(uuid,uuid,integer,integer)',
    'EXECUTE'
  ),
  'service role has no execute privilege on the Rider wrapper'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.rider_lock_fare_quote(uuid,uuid,integer,integer)'::regprocedure
  ),
  'the quote-lock wrapper remains SECURITY DEFINER'
);

select ok(
  (
    select array_to_string(proconfig, ',') in ('search_path=""', 'search_path=')
    from pg_proc
    where oid = 'public.rider_lock_fare_quote(uuid,uuid,integer,integer)'::regprocedure
  ),
  'the quote-lock wrapper has an empty search path'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.booking_requests'::regclass),
  'booking request RLS remains enabled'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.fare_quotes'::regclass),
  'FareQuote RLS remains enabled'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'booking_requests'
      and policyname = 'booking_requests_participant_select'
  ),
  'the booking participant policy is preserved'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'fare_quotes'
      and policyname = 'fare_quotes_participant_select'
  ),
  'the FareQuote participant policy is preserved'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '25000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-owner-025@example.com', '', now(), '{}', '{"display_name":"Rider Owner"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '25000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'other-rider-025@example.com', '', now(), '{}', '{"display_name":"Other Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '25000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'blocked-rider-025@example.com', '', now(), '{}', '{"display_name":"Blocked Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '25000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'driver-025@example.com', '', now(), '{}', '{"display_name":"Driver"}', now(), now(), '', '', '', '');

update public.users
set is_blocked = true
where id = '25000000-0000-0000-0000-000000000003';

update public.users
set role = 'driver'
where id = '25000000-0000-0000-0000-000000000004';

delete from public.rider_profiles
where user_id = '25000000-0000-0000-0000-000000000004';

insert into public.booking_requests (
  id, rider_id, pickup, destination, vehicle_type_code, payment_method
) values
  ('25100000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash'),
  ('25100000-0000-0000-0000-000000000002', '25000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash'),
  ('25100000-0000-0000-0000-000000000003', '25000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash'),
  ('25100000-0000-0000-0000-000000000004', '25000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash'),
  ('25100000-0000-0000-0000-000000000005', '25000000-0000-0000-0000-000000000002', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash');

insert into public.fare_quotes (
  id, booking_request_id, rider_id, pickup, destination,
  route_distance_meters, route_duration_seconds, vehicle_type_code,
  breakdown, fixed_fare_fils, pricing_configuration_id,
  pricing_version, quote_version, created_at, expires_at
) values
  ('25200000-0000-0000-0000-000000000001', '25100000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700, (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), 1, now(), now() + interval '10 minutes'),
  ('25200000-0000-0000-0000-000000000002', '25100000-0000-0000-0000-000000000002', '25000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700, (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), 1, now() - interval '11 minutes', now() - interval '1 minute'),
  ('25200000-0000-0000-0000-000000000003', '25100000-0000-0000-0000-000000000003', '25000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700, (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), 1, now(), now() + interval '10 minutes'),
  ('25200000-0000-0000-0000-000000000004', '25100000-0000-0000-0000-000000000004', '25000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700, (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), 1, now(), now() + interval '10 minutes'),
  ('25200000-0000-0000-0000-000000000005', '25100000-0000-0000-0000-000000000005', '25000000-0000-0000-0000-000000000002', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700, (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), 1, now(), now() + interval '10 minutes');

set local role anon;
select throws_ok(
  $$select public.rider_lock_fare_quote('25100000-0000-0000-0000-000000000001', '25200000-0000-0000-0000-000000000001', 1, 1)$$,
  '42501', null,
  'unauthenticated callers cannot execute the quote-lock wrapper'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '25000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_lock_fare_quote('25100000-0000-0000-0000-000000000001', '25200000-0000-0000-0000-000000000001', 1, 1)$$,
  '42501', 'Only a non-blocked Rider can manage bookings.',
  'non-Rider callers are rejected'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '25000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_lock_fare_quote('25100000-0000-0000-0000-000000000001', '25200000-0000-0000-0000-000000000001', 1, 1)$$,
  '42501', 'Only a non-blocked Rider can manage bookings.',
  'blocked Riders are rejected'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '25000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_lock_fare_quote('25100000-0000-0000-0000-000000000001', '25200000-0000-0000-0000-000000000001', 1, 1)$$,
  'P0002', 'FareQuote was not found for this Rider booking.',
  'a Rider cannot lock another Rider booking and quote'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '25000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select throws_ok(
  $$select public.rider_lock_fare_quote('25100000-0000-0000-0000-000000000002', '25200000-0000-0000-0000-000000000002', 1, 1)$$,
  '55000', 'Only an unexpired calculated FareQuote can be locked.',
  'an expired FareQuote cannot be locked'
);

select throws_ok(
  $$select public.rider_lock_fare_quote('25100000-0000-0000-0000-000000000003', '25200000-0000-0000-0000-000000000003', 2, 1)$$,
  '40001', 'Booking version is stale.',
  'a stale expected Booking version is rejected'
);

select throws_ok(
  $$select public.rider_lock_fare_quote('25100000-0000-0000-0000-000000000004', '25200000-0000-0000-0000-000000000004', 1, 2)$$,
  '40001', 'FareQuote version is stale.',
  'a stale expected FareQuote version is rejected'
);

select throws_ok(
  $$select public.rider_lock_fare_quote('25100000-0000-0000-0000-000000000001', '25200000-0000-0000-0000-000000000004', 1, 1)$$,
  'P0002', 'FareQuote was not found for this Rider booking.',
  'a quote from another owned booking cannot be substituted'
);

select is(
  (public.rider_lock_fare_quote(
    '25100000-0000-0000-0000-000000000001',
    '25200000-0000-0000-0000-000000000001',
    1,
    1
  )).id,
  '25200000-0000-0000-0000-000000000001'::uuid,
  'an eligible fresh FareQuote locks successfully'
);

select is(
  (select status::text from public.fare_quotes where id = '25200000-0000-0000-0000-000000000001'),
  'locked',
  'the fresh lock transitions the FareQuote exactly once'
);

select is(
  (select version from public.booking_requests where id = '25100000-0000-0000-0000-000000000001'),
  2,
  'the fresh lock advances the Booking version once'
);

select is(
  (select fare_quote_id from public.booking_requests where id = '25100000-0000-0000-0000-000000000001'),
  '25200000-0000-0000-0000-000000000001'::uuid,
  'the Booking references the locked FareQuote'
);

reset role;

select set_config(
  'ridex.test.quote_locked_at',
  (select locked_at::text from public.fare_quotes where id = '25200000-0000-0000-0000-000000000001'),
  true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '25000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (public.rider_lock_fare_quote(
    '25100000-0000-0000-0000-000000000001',
    '25200000-0000-0000-0000-000000000001',
    1,
    1
  )).id,
  '25200000-0000-0000-0000-000000000001'::uuid,
  'an exact retry with pre-lock versions returns the locked FareQuote'
);

select is(
  (select count(*) from public.fare_quotes where booking_request_id = '25100000-0000-0000-0000-000000000001' and status = 'locked'),
  1::bigint,
  'an exact retry leaves one locked FareQuote'
);

select is(
  (select version from public.booking_requests where id = '25100000-0000-0000-0000-000000000001'),
  2,
  'an exact retry does not rerun the Booking transition'
);

select is(
  (select locked_at from public.fare_quotes where id = '25200000-0000-0000-0000-000000000001'),
  current_setting('ridex.test.quote_locked_at')::timestamptz,
  'an exact retry preserves the original lock timestamp'
);

select throws_ok(
  $$select public.rider_lock_fare_quote('25100000-0000-0000-0000-000000000001', '25200000-0000-0000-0000-000000000001', 2, 1)$$,
  '40001', 'Booking version is stale.',
  'a retry with the current rather than pre-lock Booking version is rejected'
);

select throws_ok(
  $$select public.rider_lock_fare_quote('25100000-0000-0000-0000-000000000001', '25200000-0000-0000-0000-000000000001', 1, 2)$$,
  '40001', 'FareQuote version is stale.',
  'a retry with a conflicting FareQuote version is rejected'
);

reset role;

update public.booking_requests
set updated_at = updated_at
where id = '25100000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '25000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select throws_ok(
  $$select public.rider_lock_fare_quote(
    '25100000-0000-0000-0000-000000000001',
    '25200000-0000-0000-0000-000000000001',
    1,
    1
  )$$,
  '40001', 'Booking version is stale.',
  'a later Booking update invalidates the prior lock retry contract'
);

select is(
  (select version from public.booking_requests where id = '25100000-0000-0000-0000-000000000001'),
  3,
  'a rejected delayed retry does not mutate the Booking again'
);

reset role;

select * from finish();
rollback;
