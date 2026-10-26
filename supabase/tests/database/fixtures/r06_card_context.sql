begin;

create extension if not exists pgtap with schema extensions;


insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '22000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-022@example.com', '', now(), '{}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '22000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'driver-022@example.com', '', now(), '{}', '{"display_name":"Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '22000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'admin-022@example.com', '', now(), '{}', '{"display_name":"Admin"}', now(), now(), '', '', '', '');
update public.users set role = 'driver'
where id = '22000000-0000-0000-0000-000000000002';
update public.users set role = 'admin'
where id = '22000000-0000-0000-0000-000000000003';
delete from public.rider_profiles
where user_id in (
  '22000000-0000-0000-0000-000000000002',
  '22000000-0000-0000-0000-000000000003'
);
insert into public.driver_profiles (
  user_id, approval_status, is_online, is_available
) values (
  '22000000-0000-0000-0000-000000000002', 'approved', false, false
);
insert into public.driver_availability (driver_id, state)
values ('22000000-0000-0000-0000-000000000002', 'offline');
insert into public.vehicles (
  id, driver_id, vehicle_type_code, make, model, color,
  registration_plate, seat_capacity, is_active
) values (
  '22100000-0000-0000-0000-000000000001',
  '22000000-0000-0000-0000-000000000002',
  'economy', 'Toyota', 'Camry', 'White', 'RDX 022', 4, true
);
select public.backend_create_pricing_configuration(
  'economy', 500, 300, 50, 200, 1000, 50, true
);

insert into public.booking_requests (
  id, rider_id, pickup, destination, vehicle_type_code, payment_method, status
)
select
  ('22200000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '22000000-0000-0000-0000-000000000001',
  '{"latitude":31.9,"longitude":35.9}',
  '{"latitude":32.0,"longitude":36.0}',
  'economy',
  case when n <= 3 or n = 7 then 'card'::public.payment_method
    else 'cash'::public.payment_method end,
  'matched'
from generate_series(1, 7) as n;

insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination,
  route_distance_meters, route_duration_seconds, vehicle_type_code,
  breakdown, fixed_fare_fils, pricing_configuration_id,
  pricing_version, quote_version, locked_at
)
select
  ('22300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('22200000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '22000000-0000-0000-0000-000000000001', 'locked',
  '{"latitude":31.9,"longitude":35.9}',
  '{"latitude":32.0,"longitude":36.0}',
  4000, 1200, 'economy', '{"fixed_fare_fils":2000}', 2000,
  (select id from public.pricing_configurations where is_active and vehicle_type_code = 'economy'),
  1, 1, now()
from generate_series(1, 7) as n;

insert into public.trips (
  id, booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id,
  status, payment_method, pickup, destination, route_distance_meters,
  route_duration_seconds, original_fare_fils, current_fare_fils
)
select
  ('22400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('22200000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('22300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '22000000-0000-0000-0000-000000000001',
  '22000000-0000-0000-0000-000000000002',
  '22100000-0000-0000-0000-000000000001',
  case when n <= 3 or n = 7 then 'accepted'::public.trip_status
    else 'inProgress'::public.trip_status end,
  case when n <= 3 or n = 7 then 'card'::public.payment_method
    else 'cash'::public.payment_method end,
  '{"latitude":31.9,"longitude":35.9}',
  '{"latitude":32.0,"longitude":36.0}',
  4000, 1200, 2000, 2000
from generate_series(1, 7) as n;

insert into public.payments (
  id, booking_request_id, trip_id, rider_id, method, fare_quote_id,
  authorized_amount_fils, final_amount_fils, currency, cash_status, card_status
)
select
  ('22500000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('22200000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('22400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '22000000-0000-0000-0000-000000000001',
  case when n <= 3 or n = 7 then 'card'::public.payment_method
    else 'cash'::public.payment_method end,
  ('22300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  2000, 2000, 'JOD',
  case when n between 4 and 6 then 'cashSelected'::public.cash_payment_status end,
  case when n <= 3 or n = 7 then 'cardPaymentPending'::public.card_payment_status end
from generate_series(1, 7) as n;

select public.backend_record_payment_attempt('22500000-0000-0000-0000-000000000001','initialAuthorization',2000,'r06-original-authorization','stripe');
insert into public.payment_attempts (payment_id,type,status,requested_amount_fils,currency,
  idempotency_key,provider_name,authorization_cycle,created_at)
values ('22500000-0000-0000-0000-000000000002','initialAuthorization','pending',2000,'JOD',
  'r06-expired-authorization','stripe',1,now()-interval '3 minutes');

insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,
  email_change_token_new,recovery_token)
values ('00000000-0000-0000-0000-000000000000','22000000-0000-0000-0000-000000000004',
  'authenticated','authenticated','foreign-r06@example.invalid','',now(),'{}','{"display_name":"Foreign"}',
  now(),now(),'','','','');
