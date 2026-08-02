begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
values
  ('00000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'location-rider@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Location Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'location-other-rider@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Other Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'location-driver@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Location Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000012', 'authenticated', 'authenticated', 'location-other-driver@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Other Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000013', 'authenticated', 'authenticated', 'location-pending@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Pending Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000014', 'authenticated', 'authenticated', 'location-blocked@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Blocked Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000020', 'authenticated', 'authenticated', 'location-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Location Admin"}', now(), now(), '', '', '', '');
update public.users set role = 'driver' where id between 'b1000000-0000-0000-0000-000000000011' and 'b1000000-0000-0000-0000-000000000014';
update public.users set role = 'admin' where id = 'b1000000-0000-0000-0000-000000000020';
update public.users set is_blocked = true where id = 'b1000000-0000-0000-0000-000000000014';
delete from public.rider_profiles where user_id in ('b1000000-0000-0000-0000-000000000011', 'b1000000-0000-0000-0000-000000000012', 'b1000000-0000-0000-0000-000000000013', 'b1000000-0000-0000-0000-000000000014', 'b1000000-0000-0000-0000-000000000020');
insert into public.driver_profiles (user_id, approval_status, is_online, is_available) values
  ('b1000000-0000-0000-0000-000000000011', 'approved', false, false),
  ('b1000000-0000-0000-0000-000000000012', 'approved', false, false),
  ('b1000000-0000-0000-0000-000000000013', 'pending', false, false),
  ('b1000000-0000-0000-0000-000000000014', 'approved', false, false);
insert into public.vehicles (id, driver_id, vehicle_type_code, make, model, color, registration_plate, seat_capacity, is_active) values
  ('b1100000-0000-0000-0000-000000000011', 'b1000000-0000-0000-0000-000000000011', 'economy', 'Toyota', 'Camry', 'White', 'LO 011', 4, true),
  ('b1100000-0000-0000-0000-000000000012', 'b1000000-0000-0000-0000-000000000012', 'economy', 'Toyota', 'Corolla', 'Black', 'LO 012', 4, true);
insert into public.driver_availability (driver_id, state, vehicle_id) values
  ('b1000000-0000-0000-0000-000000000011', 'available', 'b1100000-0000-0000-0000-000000000011'),
  ('b1000000-0000-0000-0000-000000000012', 'available', 'b1100000-0000-0000-0000-000000000012');

select has_table('public', 'driver_locations', 'Driver locations table exists');
select col_is_pk('public', 'driver_locations', 'id', 'locations use UUID primary keys');
select has_fk('public', 'driver_locations', 'locations reference Drivers and Trips');
select ok(exists (select 1 from pg_constraint where conname = 'driver_locations_driver_sequence_unique'), 'per-Driver sequence is unique');
select ok(exists (select 1 from pg_constraint where conname = 'driver_locations_latitude_valid'), 'latitude constraint exists');
select has_index('public', 'driver_locations', 'driver_locations_driver_received_idx', 'latest Driver sample index exists');
select has_index('public', 'driver_locations', 'driver_locations_driver_sequence_idx', 'sequence index exists');
select has_index('public', 'driver_locations', 'driver_locations_trip_received_idx', 'active Trip retrieval index exists');
select has_index('public', 'driver_locations', 'driver_locations_received_at_idx', 'retention index exists');
select ok((select relrowsecurity from pg_class where oid = 'public.driver_locations'::regclass), 'locations have RLS enabled');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000011', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.driver_record_location(null, 1, 31.95, 35.93, 4, null, null, now())$$, 'approved available Driver records own location');
select is((select count(*) from public.driver_locations), 1::bigint, 'Driver reads own sample');
select ok((select received_at >= recorded_at - interval '1 second' from public.driver_locations where sequence = 1), 'server controls received timestamp');
select throws_ok($$insert into public.driver_locations (driver_id, sequence, latitude, longitude, accuracy_meters, recorded_at, received_at) values (auth.uid(), 2, 31.9, 35.9, 1, now(), now() - interval '1 day')$$, '42501', null, 'direct inserts are denied');
select throws_ok($$update public.driver_locations set latitude = 1$$, '42501', null, 'direct updates are denied');
select throws_ok($$delete from public.driver_locations$$, '42501', null, 'direct deletes are denied');
select throws_ok($$select public.driver_record_location(null, 1, 31.95, 35.93, 4, null, null, now())$$, '23505', 'Location sequence must increase for this Driver.', 'duplicate sequence is rejected');
select throws_ok($$select public.driver_record_location(null, 0, 31.95, 35.93, 4, null, null, now())$$, '23505', 'Location sequence must increase for this Driver.', 'out-of-order sequence is rejected');
select throws_ok($$select public.driver_record_location(null, 2, 91, 35.93, 4, null, null, now())$$, '23514', null, 'invalid latitude is rejected');
select throws_ok($$select public.driver_record_location(null, 2, 31.95, 'Infinity'::float8, 4, null, null, now())$$, '23514', null, 'non-finite longitude is rejected');
select throws_ok($$select public.driver_record_location(null, 2, 31.95, 35.93, -1, null, null, now())$$, '23514', null, 'negative accuracy is rejected');
select throws_ok($$select public.driver_record_location(null, 2, 31.95, 35.93, 4, 360, null, now())$$, '23514', null, 'invalid heading is rejected');
select throws_ok($$select public.driver_record_location(null, 2, 31.95, 35.93, 4, null, -1, now())$$, '23514', null, 'negative speed is rejected');
select throws_ok($$select public.driver_record_location(null, 2, 31.95, 35.93, 4, null, null, now() - interval '16 minutes')$$, '22023', 'Location timestamp is outside the accepted time window.', 'stale timestamp is rejected');
select throws_ok($$select public.driver_record_location(null, 2, 31.95, 35.93, 4, null, null, now() + interval '6 minutes')$$, '22023', 'Location timestamp is outside the accepted time window.', 'future timestamp is rejected');
reset role;

insert into public.pricing_configurations (id, vehicle_type_code, pricing_version, base_fare_fils, per_kilometer_fils, per_minute_fils, per_stop_fils, minimum_fare_fils, is_active)
values ('b1200000-0000-0000-0000-000000000001', 'economy', 1, 500, 300, 50, 200, 1000, true);
insert into public.booking_requests (id, rider_id, pickup, destination, vehicle_type_code, payment_method)
values ('b1200000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 'economy', 'cash');
insert into public.fare_quotes (id, booking_request_id, rider_id, status, pickup, destination, route_distance_meters, route_duration_seconds, vehicle_type_code, breakdown, fixed_fare_fils, pricing_configuration_id, pricing_version, quote_version, locked_at)
values ('b1200000-0000-0000-0000-000000000003', 'b1200000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'locked', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 'economy', '{}', 1000, 'b1200000-0000-0000-0000-000000000001', 1, 1, now());
update public.booking_requests set fare_quote_id = 'b1200000-0000-0000-0000-000000000003' where id = 'b1200000-0000-0000-0000-000000000002';
insert into public.trips (id, booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id, payment_method, pickup, destination, route_distance_meters, route_duration_seconds, original_fare_fils, current_fare_fils)
values ('b1200000-0000-0000-0000-000000000004', 'b1200000-0000-0000-0000-000000000002', 'b1200000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000011', 'b1100000-0000-0000-0000-000000000011', 'cash', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 1000, 1000);
update public.driver_availability set state = 'onTrip', active_trip_id = 'b1200000-0000-0000-0000-000000000004' where driver_id = 'b1000000-0000-0000-0000-000000000011';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000011', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.driver_record_location('b1200000-0000-0000-0000-000000000004', 2, 31.96, 35.94, 3, 90, 4, now())$$, 'on-trip Driver records a sample for the assigned active Trip');
select throws_ok($$select public.driver_record_location(null, 3, 31.96, 35.94, 3, null, null, now())$$, '22023', 'On-trip location requires this Driver''s active Trip.', 'on-trip sample requires Trip association');
select throws_ok($$select public.driver_record_location('b1200000-0000-0000-0000-000000000004', 3, 'NaN'::float8, 35.94, 3, null, null, now())$$, '23514', null, 'non-finite latitude is rejected');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.driver_locations), 1::bigint, 'assigned Rider reads only active Trip location samples');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.driver_locations), 0::bigint, 'unrelated Rider cannot read location samples');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000020', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.driver_locations), 2::bigint, 'Admin has restricted operational location visibility');
reset role;
set local role anon;
select throws_ok($$select public.driver_record_location(null, 1, 31.95, 35.93, 4, null, null, now())$$, '42501', null, 'anonymous callers cannot record locations');
select throws_ok($$select count(*) from public.driver_locations$$, '42501', null, 'anonymous callers cannot read locations');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000012', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.driver_record_location(null, 1, 32, 36, 3, 20, 2, now())$$, 'sequences are independent across Drivers');
select is((select count(*) from public.driver_locations), 1::bigint, 'other Driver reads only own sample');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000013', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_record_location(null, 1, 31.95, 35.93, 4, null, null, now())$$, '42501', 'Only an approved, non-blocked Driver can manage vehicles or availability.', 'pending Driver is denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000014', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_record_location(null, 1, 31.95, 35.93, 4, null, null, now())$$, '42501', 'Only an approved, non-blocked Driver can manage vehicles or availability.', 'blocked Driver is denied');
reset role;

select ok(has_function_privilege('authenticated', 'public.driver_record_location(uuid,bigint,double precision,double precision,double precision,double precision,double precision,timestamp with time zone)', 'EXECUTE'), 'authenticated can reach guarded location RPC');
select ok(not has_function_privilege('anon', 'public.driver_record_location(uuid,bigint,double precision,double precision,double precision,double precision,double precision,timestamp with time zone)', 'EXECUTE'), 'anonymous callers cannot execute location RPC');
select ok(has_function_privilege('service_role', 'public.backend_purge_expired_driver_locations()', 'EXECUTE'), 'service role can purge expired locations');
select ok(not has_function_privilege('authenticated', 'public.backend_purge_expired_driver_locations()', 'EXECUTE'), 'clients cannot purge locations');
select is((select count(*) from pg_proc where oid in ('public.driver_record_location(uuid,bigint,double precision,double precision,double precision,double precision,double precision,timestamp with time zone)'::regprocedure, 'public.backend_purge_expired_driver_locations()'::regprocedure) and prosecdef), 2::bigint, 'location functions are SECURITY DEFINER');
select is((select count(*) from pg_proc where oid in ('public.driver_record_location(uuid,bigint,double precision,double precision,double precision,double precision,double precision,timestamp with time zone)'::regprocedure, 'public.backend_purge_expired_driver_locations()'::regprocedure) and array_to_string(proconfig, ',') in ('search_path=""', 'search_path=')), 2::bigint, 'location functions have empty search paths');
select is((select count(*) from public.audit_records where action like 'driver.location%'), 0::bigint, 'precise locations are excluded from ordinary audit payloads');

insert into public.driver_locations (driver_id, sequence, latitude, longitude, accuracy_meters, recorded_at, received_at) values
  ('b1000000-0000-0000-0000-000000000011', 99, 31.95, 35.93, 4, now() - interval '8 days', now() - interval '8 days'),
  ('b1000000-0000-0000-0000-000000000011', 100, 31.95, 35.93, 4, now() - interval '7 days', now() - interval '7 days');
set local role service_role;
select is(public.backend_purge_expired_driver_locations(), 1::bigint, 'purge removes only samples older than seven days');
reset role;
select is((select count(*) from public.driver_locations where sequence = 100), 1::bigint, 'seven-day retention boundary is preserved');

select * from finish();
rollback;
