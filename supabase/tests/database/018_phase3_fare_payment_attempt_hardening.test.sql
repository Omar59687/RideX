begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', 'e8000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-018@example.com', '', now(), '{}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'e8000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'driver-018@example.com', '', now(), '{}', '{"display_name":"Driver"}', now(), now(), '', '', '', '');
update public.users set role = 'driver' where id = 'e8000000-0000-0000-0000-000000000002';
delete from public.rider_profiles where user_id = 'e8000000-0000-0000-0000-000000000002';
insert into public.driver_profiles (user_id, approval_status, is_online, is_available)
values ('e8000000-0000-0000-0000-000000000002', 'approved', false, false);
insert into public.vehicles (
  id, driver_id, vehicle_type_code, make, model, color, registration_plate, seat_capacity, is_active
) values ('e8100000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000002', 'economy', 'Toyota', 'Camry', 'White', 'RDX 018', 4, true);
select public.backend_create_pricing_configuration('economy', 500, 300, 50, 200, 1000, 50, true);

insert into public.booking_requests (
  id, rider_id, pickup, destination, vehicle_type_code, payment_method, status
) values
  ('e8200000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 'economy', 'cash', 'matched'),
  ('e8200000-0000-0000-0000-000000000002', 'e8000000-0000-0000-0000-000000000001', '{"latitude":31.8,"longitude":35.8}', '{"latitude":32.1,"longitude":36.1}', 'economy', 'card', 'matched');
insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination, route_distance_meters,
  route_duration_seconds, vehicle_type_code, breakdown, fixed_fare_fils,
  pricing_configuration_id, pricing_version, quote_version, locked_at
) values
  ('e8300000-0000-0000-0000-000000000001', 'e8200000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'locked', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 4000, 1200, 'economy', '{}', 2000, (select id from public.pricing_configurations where is_active), 1, 1, now()),
  ('e8300000-0000-0000-0000-000000000002', 'e8200000-0000-0000-0000-000000000002', 'e8000000-0000-0000-0000-000000000001', 'locked', '{"latitude":31.8,"longitude":35.8}', '{"latitude":32.1,"longitude":36.1}', 4000, 1200, 'economy', '{}', 2000, (select id from public.pricing_configurations where is_active), 1, 1, now());
insert into public.trips (
  id, booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id, status,
  payment_method, pickup, destination, route_distance_meters, route_duration_seconds,
  original_fare_fils, current_fare_fils
) values
  ('e8400000-0000-0000-0000-000000000001', 'e8200000-0000-0000-0000-000000000001', 'e8300000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000002', 'e8100000-0000-0000-0000-000000000001', 'inProgress', 'cash', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 4000, 1200, 2000, 2000),
  ('e8400000-0000-0000-0000-000000000002', 'e8200000-0000-0000-0000-000000000002', 'e8300000-0000-0000-0000-000000000002', 'e8000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000002', 'e8100000-0000-0000-0000-000000000001', 'completed', 'card', '{"latitude":31.8,"longitude":35.8}', '{"latitude":32.1,"longitude":36.1}', 4000, 1200, 2000, 2000);
insert into public.payments (
  booking_request_id, trip_id, rider_id, method, fare_quote_id, authorized_amount_fils,
  final_amount_fils, currency, cash_status, card_status
) values
  ('e8200000-0000-0000-0000-000000000001', 'e8400000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'cash', 'e8300000-0000-0000-0000-000000000001', 2000, 2000, 'JOD', 'cashSelected', null),
  ('e8200000-0000-0000-0000-000000000002', 'e8400000-0000-0000-0000-000000000002', 'e8000000-0000-0000-0000-000000000001', 'card', 'e8300000-0000-0000-0000-000000000002', 2000, 2000, 'JOD', null, 'cardPaymentAuthorized');
insert into public.trip_change_requests (
  id, trip_id, rider_id, requested_destination, requested_stops
) values ('e8500000-0000-0000-0000-000000000001', 'e8400000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', '{"latitude":32.2,"longitude":36.2}', '[]');

select lives_ok(
  $$select private.backend_price_trip_change_request_remaining('e8500000-0000-0000-0000-000000000001', 1, 3000, 600, 1000, 300, 'remaining-route')$$,
  'trusted remaining-route pricing succeeds'
);
select is((select adjustment_fils from public.fare_adjustments), 850, 'only the nonnegative remaining-route difference is charged');
select is((select adjusted_fare_fils from public.fare_adjustments), 2850, 'completed route fare is not charged again');
select is((select breakdown ->> 'original_remaining_route_fare_fils' from public.fare_adjustments), '1050', 'adjustment retains trusted original remaining fare evidence');
update public.trip_change_requests set status = 'approved' where id = 'e8500000-0000-0000-0000-000000000001';
select lives_ok(
  $$select public.backend_apply_trip_fare_adjustment((select id from public.fare_adjustments), 1, 1)$$,
  'approved Cash adjustment applies atomically'
);
select is((select current_fare_fils from public.trips where id = 'e8400000-0000-0000-0000-000000000001'), 2850, 'Cash Trip final fare is reconciled');
select is((select final_amount_fils from public.payments where trip_id = 'e8400000-0000-0000-0000-000000000001'), 2850, 'canonical Cash Payment final amount is reconciled');

select lives_ok(
  $$select public.backend_record_payment_attempt((select id from public.payments where method = 'card'), 'capture', 2000, '018-capture', 'provider-a')$$,
  'compatible initial Capture is recorded'
);
select is(
  (select public.backend_record_payment_attempt((select id from public.payments where method = 'card'), 'capture', 2000, '018-capture', 'provider-a')).id,
  (select id from public.payment_attempts where idempotency_key = '018-capture'),
  'identical attempt creation replay returns the canonical attempt'
);
select throws_ok(
  $$select public.backend_record_payment_attempt((select id from public.payments where method = 'card'), 'capture', 1999, '018-capture', 'provider-a')$$,
  '55000', 'Payment attempt idempotency key is already associated with different operation data.',
  'mismatched idempotency-key reuse fails closed'
);
select lives_ok(
  $$select public.backend_complete_payment_attempt((select id from public.payment_attempts where idempotency_key = '018-capture'), 'succeeded', 'capture-018')$$,
  'trusted Capture completion succeeds'
);
select throws_ok(
  $$select public.backend_complete_payment_attempt((select id from public.payment_attempts where idempotency_key = '018-capture'), 'failed', 'capture-018', 'DECLINED')$$,
  '55000', 'A terminal Payment attempt cannot be completed with different data.',
  'terminal completion cannot be rewritten with different terminal data'
);
select throws_ok(
  $$select public.backend_record_payment_attempt((select id from public.payments where trip_id = 'e8400000-0000-0000-0000-000000000001'), 'capture', 2850, '018-cash-capture', 'provider-a')$$,
  '55000', 'Capture requires a completed Trip with an authorized Card Payment.',
  'incompatible Cash Capture is rejected'
);
select * from finish();
rollback;
