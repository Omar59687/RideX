begin;

create extension if not exists pgtap with schema extensions;

select plan(57);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'driver-one@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver One"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'driver-two@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver Two"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'pending@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Pending Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'rejected@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Rejected Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'rider@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'admin@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Admin"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000007', 'authenticated', 'authenticated', 'blocked@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Blocked Driver"}', now(), now(), '', '', '', '');

update public.users set role = 'driver' where id between '30000000-0000-0000-0000-000000000001' and '30000000-0000-0000-0000-000000000004' or id = '30000000-0000-0000-0000-000000000007';
update public.users set role = 'admin' where id = '30000000-0000-0000-0000-000000000006';
update public.users set is_blocked = true where id = '30000000-0000-0000-0000-000000000007';
delete from public.rider_profiles where user_id in ('30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000004', '30000000-0000-0000-0000-000000000006', '30000000-0000-0000-0000-000000000007');
insert into public.driver_profiles (user_id, approval_status, rejection_reason, is_online, is_available)
values
  ('30000000-0000-0000-0000-000000000001', 'approved', null, true, true),
  ('30000000-0000-0000-0000-000000000002', 'approved', null, false, false),
  ('30000000-0000-0000-0000-000000000003', 'pending', null, false, false),
  ('30000000-0000-0000-0000-000000000004', 'rejected', 'Incomplete documents', false, false),
  ('30000000-0000-0000-0000-000000000007', 'approved', null, false, false);

-- This is the migration's conflict-safe backfill statement exercised against preexisting Driver rows.
insert into public.driver_availability (driver_id, state)
select user_id, 'offline' from public.driver_profiles
on conflict (driver_id) do nothing;

select has_type('public', 'vehicle_type_code', 'vehicle category enum exists');
select is(enum_range(null::public.driver_availability_state)::text, '{offline,available,reserved,onTrip}', 'canonical availability states are exact');
select has_table('public', 'vehicles', 'vehicles table exists');
select has_table('public', 'driver_availability', 'canonical availability table exists');
select has_column('public', 'vehicles', 'registration_plate', 'vehicle plate column exists');
select has_column('public', 'driver_availability', 'last_heartbeat_at', 'availability heartbeat summary column exists');
select col_is_pk('public', 'vehicles', 'id', 'vehicles have UUID primary keys');
select col_is_pk('public', 'driver_availability', 'driver_id', 'availability has one row per Driver');
select has_fk('public', 'vehicles', 'vehicles belong to Driver profiles');
select has_fk('public', 'driver_availability', 'availability belongs to Driver profiles');
select ok(exists (select 1 from pg_constraint where conname = 'vehicles_seat_capacity_bounded'), 'vehicle seats are bounded');
select ok(exists (select 1 from pg_constraint where conname = 'driver_availability_state_references_valid'), 'availability references match state');
select has_index('public', 'vehicles', 'vehicles_one_active_per_driver_idx', 'one active vehicle index exists');
select has_index('public', 'driver_availability', 'driver_availability_state_idx', 'availability state index exists');
select ok((select relrowsecurity from pg_class where oid = 'public.vehicles'::regclass), 'vehicles have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.driver_availability'::regclass), 'availability has RLS enabled');
select ok((select col_description('public.driver_profiles'::regclass, 4) like '%Deprecated%'), 'legacy is_online field is deprecated');
select ok((select col_description('public.driver_profiles'::regclass, 5) like '%Deprecated%'), 'legacy is_available field is deprecated');
select is((select count(*) from public.driver_availability where driver_id in ('30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000004', '30000000-0000-0000-0000-000000000007')), 5::bigint, 'backfill creates one canonical row per existing Driver');
insert into public.driver_availability (driver_id, state) select user_id, 'offline' from public.driver_profiles on conflict (driver_id) do nothing;
select is((select count(*) from public.driver_availability where driver_id = '30000000-0000-0000-0000-000000000001'), 1::bigint, 'backfill is repeat-safe');
select ok((select is_online and is_available from public.driver_profiles where user_id = '30000000-0000-0000-0000-000000000001'), 'backfill preserves legacy flags');

set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.driver_create_vehicle('economy'::public.vehicle_type_code, ' Toyota ', ' Camry ', ' White ', ' ab 123 ', 4::smallint, 2022::smallint, 'https://example.com/car.jpg')$$, 'approved Driver creates a vehicle');
select is((select registration_plate from public.vehicles where driver_id = auth.uid()), 'AB 123', 'vehicle plates are normalized');
select throws_ok($$select public.driver_create_vehicle('economy'::public.vehicle_type_code, repeat('a', 101), 'Model', 'Blue', 'CD 456', 4::smallint, null, null)$$, '23514', null, 'unbounded vehicle make is rejected');
select throws_ok($$select public.driver_create_vehicle('economy'::public.vehicle_type_code, 'Make', 'Model', 'Blue', 'EF 789', 13::smallint, null, null)$$, '23514', null, 'invalid seat capacity is rejected');
select throws_ok($$select public.driver_create_vehicle('economy'::public.vehicle_type_code, 'Make', 'Model', 'Blue', 'AB 123', 4::smallint, null, null)$$, '23505', null, 'normalized plates are globally unique');
select lives_ok($$select public.driver_update_vehicle((select id from public.vehicles where driver_id = auth.uid()), 1, 'comfort'::public.vehicle_type_code, 'Toyota', 'Corolla', 'Black', 'GH 001', 4::smallint, 2023::smallint, null)$$, 'Driver updates own vehicle with version');
select is((select vehicle_type_code::text from public.vehicles where driver_id = auth.uid()), 'comfort', 'vehicle update stores valid category');
select throws_ok($$select public.driver_update_vehicle((select id from public.vehicles where driver_id = auth.uid()), 1, 'comfort'::public.vehicle_type_code, 'Toyota', 'Corolla', 'Black', 'GH 001', 4::smallint, 2023::smallint, null)$$, '40001', 'Vehicle version is stale.', 'stale vehicle update is rejected');
select lives_ok($$select public.driver_set_vehicle_active((select id from public.vehicles where driver_id = auth.uid()), 2, true)$$, 'Driver activates own vehicle');
select ok((select is_active from public.vehicles where driver_id = auth.uid()), 'active vehicle is recorded');
select lives_ok($$select public.driver_set_availability('available', (select id from public.vehicles where driver_id = auth.uid()), 1)$$, 'approved Driver becomes available with active vehicle');
select is((select state::text from public.driver_availability where driver_id = auth.uid()), 'available', 'canonical availability becomes available');
select throws_ok($$select public.driver_set_vehicle_active((select id from public.vehicles where driver_id = auth.uid()), 3, false)$$, '55000', 'An available, reserved, or on-trip vehicle cannot be deactivated.', 'available vehicle cannot be deactivated');
select lives_ok($$select public.driver_set_availability('offline', null, 2)$$, 'Driver becomes offline');
select is((select state::text from public.driver_availability where driver_id = auth.uid()), 'offline', 'offline clears canonical vehicle reference');
select throws_ok($$select public.driver_set_availability('reserved', null, 3)$$, '22023', 'Drivers can request only offline or available availability states.', 'Driver cannot self-reserve');
select throws_ok($$select public.driver_set_availability('available', (select id from public.vehicles where driver_id = auth.uid()), 2)$$, '40001', 'Availability version is stale.', 'stale availability update is rejected');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_set_vehicle_active((select id from public.vehicles where driver_id = '30000000-0000-0000-0000-000000000001'), 3, true)$$, 'P0002', 'Vehicle was not found for this Driver.', 'Driver cannot activate another Driver vehicle');
select throws_ok($$select public.driver_set_availability('available', (select id from public.vehicles where driver_id = '30000000-0000-0000-0000-000000000001'), 1)$$, '22023', 'Available state requires this Driver''s active vehicle.', 'Driver cannot use another Driver vehicle');
select is((select count(*) from public.vehicles), 0::bigint, 'Driver owns only their vehicle rows under RLS');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_create_vehicle('economy'::public.vehicle_type_code, 'Make', 'Model', 'Blue', 'IJ 001', 4::smallint, null, null)$$, '42501', 'Only an approved, non-blocked Driver can manage vehicles or availability.', 'pending Driver is denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_create_vehicle('economy'::public.vehicle_type_code, 'Make', 'Model', 'Blue', 'IJ 002', 4::smallint, null, null)$$, '42501', 'Only an approved, non-blocked Driver can manage vehicles or availability.', 'rejected Driver is denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000007', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_create_vehicle('economy'::public.vehicle_type_code, 'Make', 'Model', 'Blue', 'IJ 003', 4::smallint, null, null)$$, '42501', 'Only an approved, non-blocked Driver can manage vehicles or availability.', 'blocked Driver is denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_create_vehicle('economy'::public.vehicle_type_code, 'Make', 'Model', 'Blue', 'IJ 004', 4::smallint, null, null)$$, '42501', 'Only an approved, non-blocked Driver can manage vehicles or availability.', 'Rider is denied');
select throws_ok($$insert into public.vehicles (driver_id, vehicle_type_code, make, model, color, registration_plate, seat_capacity) values (auth.uid(), 'economy', 'Make', 'Model', 'Blue', 'ZZ 999', 4)$$, '42501', null, 'direct vehicle inserts are denied');
select throws_ok($$update public.driver_availability set state = 'offline'$$, '42501', null, 'direct availability updates are denied');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.vehicles), 1::bigint, 'Driver can read own vehicles');
select is((select count(*) from public.driver_availability), 1::bigint, 'Driver can read own availability row');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000006', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.vehicles), 1::bigint, 'Admin has restricted vehicle read access');
select is((select count(*) from public.driver_availability), 5::bigint, 'Admin has restricted availability read access');
reset role;

set local role anon;
select throws_ok($$select public.driver_create_vehicle('economy'::public.vehicle_type_code, 'Make', 'Model', 'Blue', 'IJ 005', 4::smallint, null, null)$$, '42501', null, 'anonymous callers cannot execute Driver RPCs');
reset role;
select ok(has_function_privilege('authenticated', 'public.driver_create_vehicle(public.vehicle_type_code,text,text,text,text,smallint,smallint,text)', 'EXECUTE'), 'authenticated can reach guarded create RPC');
select ok(not has_function_privilege('anon', 'public.driver_create_vehicle(public.vehicle_type_code,text,text,text,text,smallint,smallint,text)', 'EXECUTE'), 'anon cannot execute create RPC');
select is((select count(*) from pg_proc where oid in ('public.driver_create_vehicle(public.vehicle_type_code,text,text,text,text,smallint,smallint,text)'::regprocedure, 'public.driver_update_vehicle(uuid,integer,public.vehicle_type_code,text,text,text,text,smallint,smallint,text)'::regprocedure, 'public.driver_set_vehicle_active(uuid,integer,boolean)'::regprocedure, 'public.driver_set_availability(public.driver_availability_state,uuid,integer)'::regprocedure) and prosecdef), 4::bigint, 'Driver RPCs are SECURITY DEFINER');
select is((select count(*) from pg_proc where oid in ('public.driver_create_vehicle(public.vehicle_type_code,text,text,text,text,smallint,smallint,text)'::regprocedure, 'public.driver_update_vehicle(uuid,integer,public.vehicle_type_code,text,text,text,text,smallint,smallint,text)'::regprocedure, 'public.driver_set_vehicle_active(uuid,integer,boolean)'::regprocedure, 'public.driver_set_availability(public.driver_availability_state,uuid,integer)'::regprocedure) and array_to_string(proconfig, ',') in ('search_path=""', 'search_path=')), 4::bigint, 'Driver RPCs have empty search paths');
select is((select count(*) from public.audit_records where action in ('driver.vehicle_created', 'driver.vehicle_updated', 'driver.vehicle_active_set', 'driver.availability_set')), 5::bigint, 'important vehicle and availability changes are audited');

select * from finish();
rollback;
