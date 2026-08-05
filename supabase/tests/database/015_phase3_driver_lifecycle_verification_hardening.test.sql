begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
values
  ('00000000-0000-0000-0000-000000000000', 'a5000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-015@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a5000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'driver-015@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a5000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'other-driver-015@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Other Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a5000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'admin-015@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Admin"}', now(), now(), '', '', '', '');
update public.users set role = 'driver' where id in ('a5000000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-000000000003');
update public.users set role = 'admin' where id = 'a5000000-0000-0000-0000-000000000004';
delete from public.rider_profiles where user_id in ('a5000000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-000000000003', 'a5000000-0000-0000-0000-000000000004');
insert into public.driver_profiles (user_id, approval_status, rejection_reason, is_online, is_available)
values ('a5000000-0000-0000-0000-000000000002', 'approved', null, false, false), ('a5000000-0000-0000-0000-000000000003', 'approved', null, false, false);
delete from public.driver_availability where driver_id = 'a5000000-0000-0000-0000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a5000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.admin_approve_driver('a5000000-0000-0000-0000-000000000002')$$, 'approval recreates a missing availability row');
select is((select state::text from public.driver_availability where driver_id = 'a5000000-0000-0000-0000-000000000002'), 'offline', 'reconciled availability is offline');
reset role;

insert into public.vehicles (id, driver_id, vehicle_type_code, make, model, color, registration_plate, seat_capacity, is_active)
values
  ('a5100000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-000000000002', 'economy', 'Toyota', 'Camry', 'White', 'AR 015', 4, true),
  ('a5100000-0000-0000-0000-000000000003', 'a5000000-0000-0000-0000-000000000002', 'comfort', 'Toyota', 'Crown', 'Black', 'AR 016', 4, false),
  ('a5100000-0000-0000-0000-000000000004', 'a5000000-0000-0000-0000-000000000003', 'economy', 'Honda', 'Accord', 'Blue', 'AR 017', 4, true);
update public.driver_availability set state = 'available', vehicle_id = 'a5100000-0000-0000-0000-000000000002' where driver_id = 'a5000000-0000-0000-0000-000000000002';
insert into public.driver_availability (driver_id, state, vehicle_id) values ('a5000000-0000-0000-0000-000000000003', 'available', 'a5100000-0000-0000-0000-000000000004');
select public.backend_create_pricing_configuration('economy', 500, 300, 50, 200, 1000, 50, true);
insert into public.booking_requests (id, rider_id, pickup, destination, vehicle_type_code, payment_method)
values
  ('a5200000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash'),
  ('a5200000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-000000000001', '{"latitude":31.94,"longitude":35.92}', '{"latitude":31.99,"longitude":35.98}', 'economy', 'cash'),
  ('a5200000-0000-0000-0000-000000000003', 'a5000000-0000-0000-0000-000000000001', '{"latitude":31.93,"longitude":35.91}', '{"latitude":31.97,"longitude":35.96}', 'economy', 'cash'),
  ('a5200000-0000-0000-0000-000000000004', 'a5000000-0000-0000-0000-000000000001', '{"latitude":31.92,"longitude":35.90}', '{"latitude":31.96,"longitude":35.95}', 'economy', 'cash');
insert into public.fare_quotes (id, booking_request_id, rider_id, status, pickup, destination, route_distance_meters, route_duration_seconds, vehicle_type_code, breakdown, fixed_fare_fils, pricing_configuration_id, pricing_version, quote_version, locked_at)
select ('a5300000-0000-0000-0000-00000000000' || n)::uuid, ('a5200000-0000-0000-0000-00000000000' || n)::uuid, 'a5000000-0000-0000-0000-000000000001', 'locked', pickup, destination, 2000, 600, 'economy', '{"fixed_fare_fils":2000}', 2000, (select id from public.pricing_configurations where is_active), 1, 1, now()
from public.booking_requests cross join generate_series(1, 4) as n where id = ('a5200000-0000-0000-0000-00000000000' || n)::uuid;
update public.booking_requests set fare_quote_id = ('a5300000-0000-0000-0000-00000000000' || right(id::text, 1))::uuid;
update public.booking_requests set status = 'confirmed', confirmed_at = now();
update public.booking_requests set status = 'searching', searching_at = now();

select lives_ok($$select public.service_reserve_driver_for_booking('a5000000-0000-0000-0000-000000000002', 'a5200000-0000-0000-0000-000000000001', 'a5100000-0000-0000-0000-000000000002', 2)$$, 'service reserves the available compatible Driver');
select lives_ok($$select public.service_reserve_driver_for_booking('a5000000-0000-0000-0000-000000000002', 'a5200000-0000-0000-0000-000000000001', 'a5100000-0000-0000-0000-000000000002', 3)$$, 'matching service reservation is idempotent');
select is((select count(*) from public.audit_records where action = 'driver.reservation_created' and target_user_id = 'a5000000-0000-0000-0000-000000000002'), 1::bigint, 'idempotent reservation writes one bounded audit record');
select lives_ok($$select public.service_release_driver_reservation('a5000000-0000-0000-0000-000000000002', 'a5200000-0000-0000-0000-000000000001', 3)$$, 'service releases matching reservation');
select lives_ok($$select public.service_release_driver_reservation('a5000000-0000-0000-0000-000000000002', 'a5200000-0000-0000-0000-000000000001', 4)$$, 'matching service release is idempotent');
select is((select count(*) from public.audit_records where action = 'driver.reservation_released' and target_user_id = 'a5000000-0000-0000-0000-000000000002'), 1::bigint, 'idempotent release writes one bounded audit record');
select ok(not exists (select 1 from public.audit_records where action like 'driver.reservation_%' and (previous_data::text ~ 'latitude|destination|pickup' or new_data::text ~ 'latitude|destination|pickup')), 'reservation audit excludes sensitive Booking data');
select throws_ok($$select public.service_reserve_driver_for_booking('a5000000-0000-0000-0000-000000000002', 'a5200000-0000-0000-0000-000000000001', 'a5100000-0000-0000-0000-000000000004', 4)$$, '55000', 'Driver availability or vehicle is not eligible for reservation.', 'wrong vehicle ownership is rejected');
select throws_ok($$select public.service_reserve_driver_for_booking('a5000000-0000-0000-0000-000000000002', 'a5200000-0000-0000-0000-000000000001', 'a5100000-0000-0000-0000-000000000003', 4)$$, '55000', 'Driver availability or vehicle is not eligible for reservation.', 'inactive or incompatible vehicle is rejected');

insert into public.driver_match_offers (id, booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters)
values ('a5400000-0000-0000-0000-000000000001', 'a5200000-0000-0000-0000-000000000001', 'a5300000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000002', 'a5100000-0000-0000-0000-000000000002', 3000);
select is((select state::text from public.driver_availability where driver_id = 'a5000000-0000-0000-0000-000000000002'), 'reserved', 'actual offer reserves Driver');
select throws_ok($$select public.service_reserve_driver_for_booking('a5000000-0000-0000-0000-000000000002', 'a5200000-0000-0000-0000-000000000002', 'a5100000-0000-0000-0000-000000000002', 5)$$, '55000', 'Driver availability or vehicle is not eligible for reservation.', 'concurrent reservation is rejected');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a5000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_set_vehicle_active('a5100000-0000-0000-0000-000000000003', 1, true)$$, '55000', 'The active availability vehicle cannot be switched.', 'reserved vehicle cannot be switched');
reset role;
update public.driver_match_offers set status = 'expired', responded_at = now() where id = 'a5400000-0000-0000-0000-000000000001';
select is((select state::text from public.driver_availability where driver_id = 'a5000000-0000-0000-0000-000000000002'), 'available', 'expired offer releases matching reservation');
insert into public.driver_match_offers (id, booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters)
values ('a5400000-0000-0000-0000-000000000002', 'a5200000-0000-0000-0000-000000000002', 'a5300000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-000000000002', 'a5100000-0000-0000-0000-000000000002', 3000);
update public.driver_match_offers set status = 'cancelled', responded_at = now() where id = 'a5400000-0000-0000-0000-000000000002';
select is((select state::text from public.driver_availability where driver_id = 'a5000000-0000-0000-0000-000000000002'), 'available', 'cancelled offer releases matching reservation');
update public.driver_availability set state = 'reserved', reserved_booking_request_id = 'a5200000-0000-0000-0000-000000000003' where driver_id = 'a5000000-0000-0000-0000-000000000002';
update public.booking_requests set status = 'cancelled', cancelled_at = now(), cancellation_reason_code = 'test' where id = 'a5200000-0000-0000-0000-000000000001';
select is((select reserved_booking_request_id::text from public.driver_availability where driver_id = 'a5000000-0000-0000-0000-000000000002'), 'a5200000-0000-0000-0000-000000000003', 'stale terminal Booking cannot release newer reservation');
update public.booking_requests set status = 'cancelled', cancelled_at = now(), cancellation_reason_code = 'test' where id = 'a5200000-0000-0000-0000-000000000003';
select is((select state::text from public.driver_availability where driver_id = 'a5000000-0000-0000-0000-000000000002'), 'available', 'terminal Booking releases matching reservation');

update public.driver_availability set state = 'available', vehicle_id = 'a5100000-0000-0000-0000-000000000002' where driver_id = 'a5000000-0000-0000-0000-000000000002';
insert into public.driver_match_offers (id, booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters)
values ('a5400000-0000-0000-0000-000000000003', 'a5200000-0000-0000-0000-000000000004', 'a5300000-0000-0000-0000-000000000004', 'a5000000-0000-0000-0000-000000000002', 'a5100000-0000-0000-0000-000000000002', 3000);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a5000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.driver_transition_trip('a5400000-0000-0000-0000-000000000003', 'accepted', 1, '015-accept')$$, 'reservation-backed offer assigns a Trip');
select is((select state::text from public.driver_availability where driver_id = 'a5000000-0000-0000-0000-000000000002'), 'onTrip', 'assignment moves the reserved Driver on Trip');
select throws_ok($$select public.driver_set_vehicle_active('a5100000-0000-0000-0000-000000000003', 1, true)$$, '55000', 'The active availability vehicle cannot be switched.', 'on-trip vehicle cannot be switched');
select throws_ok($$select public.driver_set_vehicle_active('a5100000-0000-0000-0000-000000000002', 1, false)$$, '55000', 'An available, reserved, or on-trip vehicle cannot be deactivated.', 'on-trip vehicle cannot be switched off');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a5000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.admin_reject_driver('a5000000-0000-0000-0000-000000000002', 'Safety review')$$, '55000', 'A Driver assigned to a nonterminal Trip must be terminated before rejection.', 'rejection fails closed during active Trip');
select throws_ok($$select public.admin_set_user_blocked('a5000000-0000-0000-0000-000000000002', true, 'Safety review')$$, '55000', 'A Driver assigned to a nonterminal Trip must be terminated before blocking.', 'blocking fails closed during active Trip');
select throws_ok($$update public.driver_availability set state = 'offline'$$, '42501', null, 'direct availability writes remain denied');
reset role;

select is((select count(*) from pg_proc where oid in ('public.service_reserve_driver_for_booking(uuid,uuid,uuid,integer)'::regprocedure, 'public.service_release_driver_reservation(uuid,uuid,integer)'::regprocedure) and prosecdef), 2::bigint, 'reservation RPCs remain SECURITY DEFINER');
select is((select count(*) from information_schema.routine_privileges where specific_schema = 'public' and routine_name in ('service_reserve_driver_for_booking', 'service_release_driver_reservation') and grantee = 'authenticated'), 0::bigint, 'authenticated cannot execute service reservation RPCs');
select * from finish();
rollback;
