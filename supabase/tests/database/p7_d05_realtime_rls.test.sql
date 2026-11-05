begin;

create extension if not exists pgtap with schema extensions;
select plan(9);

-- Synthetic actors and Trips only. The enclosing transaction is rolled back.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', 'd0500000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'p7-d05-rider-terminal@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"D05 Terminal Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0500000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'p7-d05-rider-blocked@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"D05 Blocked Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0500000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'p7-d05-rider-third@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"D05 Active Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0500000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'p7-d05-driver-assigned@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"D05 Assigned Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0500000-0000-0000-0000-000000000012', 'authenticated', 'authenticated', 'p7-d05-driver-unrelated@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"D05 Unrelated Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0500000-0000-0000-0000-000000000013', 'authenticated', 'authenticated', 'p7-d05-driver-blocked@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"D05 Blocked Driver"}', now(), now(), '', '', '', '');

update public.users set role = 'driver'
where id in (
  'd0500000-0000-0000-0000-000000000011',
  'd0500000-0000-0000-0000-000000000012',
  'd0500000-0000-0000-0000-000000000013'
);
update public.users set is_blocked = true
where id in (
  'd0500000-0000-0000-0000-000000000002',
  'd0500000-0000-0000-0000-000000000013'
);
delete from public.rider_profiles where user_id in (
  'd0500000-0000-0000-0000-000000000011',
  'd0500000-0000-0000-0000-000000000012',
  'd0500000-0000-0000-0000-000000000013'
);
insert into public.driver_profiles (user_id, approval_status)
values
  ('d0500000-0000-0000-0000-000000000011', 'approved'),
  ('d0500000-0000-0000-0000-000000000012', 'approved'),
  ('d0500000-0000-0000-0000-000000000013', 'approved');

insert into public.vehicles (
  id, driver_id, vehicle_type_code, make, model, color,
  registration_plate, seat_capacity, is_active
) values
  ('d0510000-0000-0000-0000-000000000011', 'd0500000-0000-0000-0000-000000000011', 'economy', 'Toyota', 'Camry', 'White', 'D05 011', 4, true),
  ('d0510000-0000-0000-0000-000000000012', 'd0500000-0000-0000-0000-000000000012', 'economy', 'Toyota', 'Corolla', 'Black', 'D05 012', 4, true),
  ('d0510000-0000-0000-0000-000000000013', 'd0500000-0000-0000-0000-000000000013', 'economy', 'Toyota', 'Yaris', 'Blue', 'D05 013', 4, true);

insert into public.pricing_configurations (
  id, vehicle_type_code, pricing_version, base_fare_fils,
  per_kilometer_fils, per_minute_fils, per_stop_fils,
  minimum_fare_fils, is_active
) values (
  'd0520000-0000-0000-0000-000000000001', 'economy', 907, 500,
  300, 50, 200, 1000, false
);

insert into public.booking_requests (
  id, rider_id, pickup, destination, vehicle_type_code, payment_method
) values
  ('d0520000-0000-0000-0000-000000000011', 'd0500000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 'economy', 'cash'),
  ('d0520000-0000-0000-0000-000000000012', 'd0500000-0000-0000-0000-000000000002', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 'economy', 'cash'),
  ('d0520000-0000-0000-0000-000000000013', 'd0500000-0000-0000-0000-000000000003', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 'economy', 'cash');

insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination,
  route_distance_meters, route_duration_seconds, vehicle_type_code,
  breakdown, fixed_fare_fils, pricing_configuration_id,
  pricing_version, quote_version, locked_at
) values
  ('d0530000-0000-0000-0000-000000000011', 'd0520000-0000-0000-0000-000000000011', 'd0500000-0000-0000-0000-000000000001', 'locked', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 'economy', '{}', 1000, 'd0520000-0000-0000-0000-000000000001', 907, 1, now()),
  ('d0530000-0000-0000-0000-000000000012', 'd0520000-0000-0000-0000-000000000012', 'd0500000-0000-0000-0000-000000000002', 'locked', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 'economy', '{}', 1000, 'd0520000-0000-0000-0000-000000000001', 907, 1, now()),
  ('d0530000-0000-0000-0000-000000000013', 'd0520000-0000-0000-0000-000000000013', 'd0500000-0000-0000-0000-000000000003', 'locked', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 'economy', '{}', 1000, 'd0520000-0000-0000-0000-000000000001', 907, 1, now());

update public.booking_requests set fare_quote_id = case id
  when 'd0520000-0000-0000-0000-000000000011' then 'd0530000-0000-0000-0000-000000000011'::uuid
  when 'd0520000-0000-0000-0000-000000000012' then 'd0530000-0000-0000-0000-000000000012'::uuid
  else 'd0530000-0000-0000-0000-000000000013'::uuid
end
where id in (
  'd0520000-0000-0000-0000-000000000011',
  'd0520000-0000-0000-0000-000000000012',
  'd0520000-0000-0000-0000-000000000013'
);

insert into public.trips (
  id, booking_request_id, fare_quote_id, rider_id, driver_id,
  vehicle_id, status, payment_method, pickup, destination,
  route_distance_meters, route_duration_seconds,
  original_fare_fils, current_fare_fils, completed_at
) values
  ('d0540000-0000-0000-0000-000000000011', 'd0520000-0000-0000-0000-000000000011', 'd0530000-0000-0000-0000-000000000011', 'd0500000-0000-0000-0000-000000000001', 'd0500000-0000-0000-0000-000000000011', 'd0510000-0000-0000-0000-000000000011', 'completed', 'cash', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 1000, 1000, now()),
  ('d0540000-0000-0000-0000-000000000012', 'd0520000-0000-0000-0000-000000000012', 'd0530000-0000-0000-0000-000000000012', 'd0500000-0000-0000-0000-000000000002', 'd0500000-0000-0000-0000-000000000012', 'd0510000-0000-0000-0000-000000000012', 'accepted', 'cash', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 1000, 1000, null),
  ('d0540000-0000-0000-0000-000000000013', 'd0520000-0000-0000-0000-000000000013', 'd0530000-0000-0000-0000-000000000013', 'd0500000-0000-0000-0000-000000000003', 'd0500000-0000-0000-0000-000000000013', 'd0510000-0000-0000-0000-000000000013', 'inProgress', 'cash', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 1000, 1000, null);

insert into public.trip_status_events (trip_id, sequence, from_status, to_status, actor_user_id)
values
  ('d0540000-0000-0000-0000-000000000011', 1, 'inProgress', 'completed', 'd0500000-0000-0000-0000-000000000011'),
  ('d0540000-0000-0000-0000-000000000012', 1, null, 'accepted', 'd0500000-0000-0000-0000-000000000012'),
  ('d0540000-0000-0000-0000-000000000013', 1, 'driverArrived', 'inProgress', 'd0500000-0000-0000-0000-000000000013');

insert into public.driver_locations (
  trip_id, driver_id, sequence, latitude, longitude,
  accuracy_meters, recorded_at, received_at
) values
  ('d0540000-0000-0000-0000-000000000011', 'd0500000-0000-0000-0000-000000000011', 1, 31.95, 35.93, 4, now(), now()),
  ('d0540000-0000-0000-0000-000000000012', 'd0500000-0000-0000-0000-000000000012', 1, 31.95, 35.93, 4, now(), now()),
  ('d0540000-0000-0000-0000-000000000013', 'd0500000-0000-0000-0000-000000000013', 1, 31.95, 35.93, 4, now(), now());

-- Positive control: an assigned, non-blocked Driver can read its Trip records.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0500000-0000-0000-0000-000000000011', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*)::integer from public.trip_status_events where trip_id = 'd0540000-0000-0000-0000-000000000011'), 1, 'assigned Driver can read its Trip status event');
select is((select count(*)::integer from public.driver_locations where trip_id = 'd0540000-0000-0000-0000-000000000011'), 1, 'assigned Driver can read its Trip location row');
reset role;

-- Blocked callers cannot read their assigned Trip's event or location rows.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0500000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*)::integer from public.trip_status_events where trip_id = 'd0540000-0000-0000-0000-000000000012'), 0, 'blocked Rider cannot read assigned Trip status events');
select is((select count(*)::integer from public.driver_locations where trip_id = 'd0540000-0000-0000-0000-000000000012'), 0, 'blocked Rider cannot read assigned Trip locations');
reset role;

-- An unrelated Driver cannot read another Driver's Trip events or locations.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0500000-0000-0000-0000-000000000012', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*)::integer from public.trip_status_events where trip_id = 'd0540000-0000-0000-0000-000000000011'), 0, 'unrelated Driver cannot read another Driver Trip events');
select is((select count(*)::integer from public.driver_locations where trip_id = 'd0540000-0000-0000-0000-000000000011'), 0, 'unrelated Driver cannot read another Driver Trip locations');
reset role;

-- A blocked Driver is denied its own otherwise valid Trip event/location rows.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0500000-0000-0000-0000-000000000013', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*)::integer from public.trip_status_events where trip_id = 'd0540000-0000-0000-0000-000000000013'), 0, 'blocked Driver cannot read assigned Trip status events');
select is((select count(*)::integer from public.driver_locations where trip_id = 'd0540000-0000-0000-0000-000000000013'), 0, 'blocked Driver cannot read own location rows');
reset role;

-- Rider location visibility ends when the canonical Trip is terminal.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0500000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*)::integer from public.driver_locations where trip_id = 'd0540000-0000-0000-0000-000000000011'), 0, 'assigned Rider cannot read location after Trip completion');
reset role;

select * from finish();
rollback;
