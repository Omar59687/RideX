begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
values
  ('00000000-0000-0000-0000-000000000000', 'a4000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-014@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a4000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'driver-014@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a4000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'admin-014@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Admin"}', now(), now(), '', '', '', '');
update public.users set role = 'admin' where id = 'a4000000-0000-0000-0000-000000000003';
delete from public.rider_profiles where user_id = 'a4000000-0000-0000-0000-000000000003';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a4000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.admin_promote_user_to_driver('a4000000-0000-0000-0000-000000000002')$$, 'promotion creates a Driver');
select is((select state::text from public.driver_availability where driver_id = 'a4000000-0000-0000-0000-000000000002'), 'offline', 'promotion creates canonical offline availability');
select lives_ok($$select public.admin_approve_driver('a4000000-0000-0000-0000-000000000002')$$, 'approval reconciles availability');
reset role;

insert into public.vehicles (id, driver_id, vehicle_type_code, make, model, color, registration_plate, seat_capacity, is_active)
values ('a4100000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000002', 'economy', 'Toyota', 'Camry', 'White', 'AR 014', 4, true),
  ('a4100000-0000-0000-0000-000000000003', 'a4000000-0000-0000-0000-000000000002', 'economy', 'Toyota', 'Corolla', 'Black', 'AR 015', 4, false);
insert into public.booking_requests (id, rider_id, pickup, destination, vehicle_type_code, payment_method, status, searching_at)
values ('a4200000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash', 'searching', now());

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a4000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.driver_set_availability('available', 'a4100000-0000-0000-0000-000000000002', 1)$$, 'approved Driver becomes available');
reset role;

select lives_ok($$select public.service_reserve_driver_for_booking('a4000000-0000-0000-0000-000000000002', 'a4200000-0000-0000-0000-000000000001', 'a4100000-0000-0000-0000-000000000002', 2)$$, 'service operation reserves an eligible Driver');
select is((select state::text from public.driver_availability where driver_id = 'a4000000-0000-0000-0000-000000000002'), 'reserved', 'reservation is canonical');
select throws_ok($$select public.service_reserve_driver_for_booking('a4000000-0000-0000-0000-000000000002', 'a4200000-0000-0000-0000-000000000001', 'a4100000-0000-0000-0000-000000000002', 2)$$, '40001', 'Availability version is stale.', 'stale reservation fails');
select lives_ok($$select public.service_release_driver_reservation('a4000000-0000-0000-0000-000000000002', 'a4200000-0000-0000-0000-000000000001', 3)$$, 'service operation releases the matching reservation');
select is((select state::text from public.driver_availability where driver_id = 'a4000000-0000-0000-0000-000000000002'), 'available', 'release returns Driver to available');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a4000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_set_vehicle_active('a4100000-0000-0000-0000-000000000003', 1, true)$$, '55000', 'The active availability vehicle cannot be switched.', 'available Driver cannot switch the referenced vehicle');
select throws_ok($$update public.driver_availability set state = 'offline'$$, '42501', null, 'direct availability writes remain denied');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a4000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.admin_reject_driver('a4000000-0000-0000-0000-000000000002', 'Documents incomplete')$$, 'rejection succeeds');
select is((select state::text from public.driver_availability where driver_id = 'a4000000-0000-0000-0000-000000000002'), 'offline', 'rejection clears availability references');
select lives_ok($$select public.admin_set_user_blocked('a4000000-0000-0000-0000-000000000002', true, 'Safety review')$$, 'blocking succeeds');
select is((select state::text from public.driver_availability where driver_id = 'a4000000-0000-0000-0000-000000000002'), 'offline', 'blocking retains offline availability');
reset role;

select is((select count(*) from pg_proc where oid in ('public.service_reserve_driver_for_booking(uuid,uuid,uuid,integer)'::regprocedure, 'public.service_release_driver_reservation(uuid,uuid,integer)'::regprocedure) and prosecdef), 2::bigint, 'reservation RPCs are SECURITY DEFINER');
select is((select count(*) from information_schema.routine_privileges where specific_schema = 'public' and routine_name in ('service_reserve_driver_for_booking', 'service_release_driver_reservation') and grantee = 'authenticated'), 0::bigint, 'authenticated cannot execute service reservation RPCs');
select * from finish();
rollback;
