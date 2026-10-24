begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
values
  ('00000000-0000-0000-0000-000000000000', 'fa000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-020@example.com', '', now(), '{}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'fa000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'assigned-driver-020@example.com', '', now(), '{}', '{"display_name":"Assigned Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'fa000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'other-driver-020@example.com', '', now(), '{}', '{"display_name":"Other Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'fa000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'admin-020@example.com', '', now(), '{}', '{"display_name":"Admin"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'fa000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'blocked-020@example.com', '', now(), '{}', '{"display_name":"Blocked"}', now(), now(), '', '', '', '');
update public.users set role = 'driver' where id in ('fa000000-0000-0000-0000-000000000002', 'fa000000-0000-0000-0000-000000000003');
update public.users set role = 'admin' where id = 'fa000000-0000-0000-0000-000000000004';
update public.users set is_blocked = true where id = 'fa000000-0000-0000-0000-000000000005';
delete from public.rider_profiles where user_id in ('fa000000-0000-0000-0000-000000000002', 'fa000000-0000-0000-0000-000000000003', 'fa000000-0000-0000-0000-000000000004');
insert into public.driver_profiles (user_id, approval_status, is_online, is_available) values
  ('fa000000-0000-0000-0000-000000000002', 'approved', false, false),
  ('fa000000-0000-0000-0000-000000000003', 'approved', false, false);
insert into public.vehicles (id, driver_id, vehicle_type_code, make, model, color, registration_plate, seat_capacity, is_active)
values ('fa100000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000002', 'comfort', 'Toyota', 'Camry', 'White', 'RDX 020', 4, true);
delete from public.pricing_configurations where vehicle_type_code = 'comfort';
insert into public.pricing_configurations (id, vehicle_type_code, pricing_version, base_fare_fils, per_kilometer_fils, per_minute_fils, per_stop_fils, minimum_fare_fils, is_active)
values ('fa200000-0000-0000-0000-000000000001', 'comfort', 1, 500, 300, 50, 200, 1000, true);
insert into public.booking_requests (id, rider_id, pickup, destination, vehicle_type_code, payment_method, status)
values ('fa200000-0000-0000-0000-000000000002', 'fa000000-0000-0000-0000-000000000001', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 'comfort', 'card', 'matched');
insert into public.fare_quotes (id, booking_request_id, rider_id, status, pickup, destination, route_distance_meters, route_duration_seconds, vehicle_type_code, breakdown, fixed_fare_fils, pricing_configuration_id, pricing_version, quote_version, locked_at)
values ('fa200000-0000-0000-0000-000000000003', 'fa200000-0000-0000-0000-000000000002', 'fa000000-0000-0000-0000-000000000001', 'locked', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 1000, 300, 'comfort', '{}', 1000, 'fa200000-0000-0000-0000-000000000001', 1, 1, now());
insert into public.trips (id, booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id, status, payment_method, pickup, destination, route_distance_meters, route_duration_seconds, original_fare_fils, current_fare_fils, completed_at)
values ('fa200000-0000-0000-0000-000000000004', 'fa200000-0000-0000-0000-000000000002', 'fa200000-0000-0000-0000-000000000003', 'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000002', 'fa100000-0000-0000-0000-000000000001', 'completed', 'card', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 1000, 300, 1000, 1000, now());
insert into public.payments (id, booking_request_id, trip_id, rider_id, method, fare_quote_id, authorized_amount_fils, final_amount_fils, card_status, provider_name, card_brand, card_last_four)
values ('fa200000-0000-0000-0000-000000000005', 'fa200000-0000-0000-0000-000000000002', 'fa200000-0000-0000-0000-000000000004', 'fa000000-0000-0000-0000-000000000001', 'card', 'fa200000-0000-0000-0000-000000000003', 1000, 1000, 'cardPaymentSucceeded', 'provider-020', 'visa', '4242');
insert into public.payment_attempts (payment_id, type, status, requested_amount_fils, currency, idempotency_key, provider_name, provider_transaction_reference, completed_at, authorization_cycle)
values ('fa200000-0000-0000-0000-000000000005', 'capture', 'succeeded', 1000, 'JOD', '020-capture', 'provider-020', 'provider-secret-ref', now(), 1);
insert into public.refunds (id, payment_id, amount_fils, currency, status, reason_code, requested_by_admin_id, provider_name, provider_refund_reference, completed_at)
values ('fa200000-0000-0000-0000-000000000006', 'fa200000-0000-0000-0000-000000000005', 1000, 'JOD', 'succeeded', 'duplicate_charge', 'fa000000-0000-0000-0000-000000000004', 'provider-020', 'refund-secret-ref', now());
insert into public.receipts (id, receipt_number, trip_id, fare_quote_id, payment_id, rider_snapshot, driver_snapshot, vehicle_snapshot, pickup_snapshot, destination_snapshot, ordered_stops_snapshot, fare_breakdown_snapshot, amount_paid_fils, currency, payment_method, card_brand, card_last_four, source_versions)
values ('fa200000-0000-0000-0000-000000000007', 'RDX-20260805-02000000', 'fa200000-0000-0000-0000-000000000004', 'fa200000-0000-0000-0000-000000000003', 'fa200000-0000-0000-0000-000000000005', '{}', '{}', '{}', '{}', '{}', '[]', '{}', 1000, 'JOD', 'card', 'visa', '4242', '{}');


-- Existing fixture above creates exactly one payment/receipt, two drivers,
-- one Rider, one Admin and a blocked Rider in this rollback-only transaction.
-- Direct financial table SELECT remains denied by design.
select is((select count(*) from pg_policies where schemaname='public'
           and tablename='payments'), 0::bigint,
          'RLS still has no public.payments SELECT policy');
select ok(not has_function_privilege('anon',
    'public.user_canonical_payment_record(uuid)','EXECUTE'),
          'anon cannot invoke exact-payment RPC');
select ok(not has_function_privilege('anon',
    'public.admin_recent_canonical_payments()','EXECUTE'),
          'anon cannot invoke Admin-list RPC');
select ok(has_function_privilege('authenticated',
    'public.user_canonical_payment_record(uuid)','EXECUTE'),
          'authenticated can invoke exact-payment RPC with DB authorization');
select ok(has_function_privilege('authenticated',
    'public.admin_recent_canonical_payments()','EXECUTE'),
          'authenticated can invoke Admin-list RPC with DB authorization');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select booking_request_id from public.user_canonical_payment_record(
  'fa200000-0000-0000-0000-000000000005')),
  'fa200000-0000-0000-0000-000000000002'::uuid,
  'Rider receives persisted booking identity');
select ok((select version > 0 from public.user_canonical_payment_record(
  'fa200000-0000-0000-0000-000000000005')),
  'Rider receives positive persisted payment version');
select is_empty($$select id from public.payments$$,
  'Authenticated Rider still cannot read raw payments table');
select throws_ok($$select public.admin_recent_canonical_payments()$$,
  '42501', 'Active administrator access is required.',
  'Rider cannot list Admin payments');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.admin_recent_canonical_payments()), 1::bigint,
  'Active Admin can read a bounded sanitized canonical summary list');
select is((select booking_request_id from public.user_canonical_payment_record(
  'fa200000-0000-0000-0000-000000000005')),
  'fa200000-0000-0000-0000-000000000002'::uuid,
  'Active Admin can read complete required identity by exact payment');
select is_empty($$select provider_name from public.payments$$,
  'Admin still cannot directly query provider-sensitive payments columns');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.user_canonical_payment_record(
  'fa200000-0000-0000-0000-000000000005')$$,
  '42501', 'Finance data does not belong to this user.',
  'Assigned Driver cannot read canonical payment record');
select throws_ok($$select public.admin_recent_canonical_payments()$$,
  '42501', 'Active administrator access is required.',
  'Driver cannot enumerate canonical payments');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.user_canonical_payment_record(
  'fa200000-0000-0000-0000-000000000005')$$,
  '42501', 'A non-blocked finance participant is required.',
  'Blocked Rider cannot read payment');
select throws_ok($$select public.admin_recent_canonical_payments()$$,
  '42501', 'Active administrator access is required.',
  'Blocked user cannot list Admin payments');
reset role;

-- Revoke Admin eligibility between requests without changing client JWT claims.
update public.users set role='rider' where id='fa000000-0000-0000-0000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.admin_recent_canonical_payments()$$,
  '42501', 'Active administrator access is required.',
  'Demoted Admin is denied by canonical server role');
reset role;

set local role anon;
select throws_ok($$select public.admin_recent_canonical_payments()$$,
  '42501', null, 'anonymous user has no Admin RPC permission');
select throws_ok($$select public.user_canonical_payment_record(
  'fa200000-0000-0000-0000-000000000005')$$,
  '42501', null, 'anonymous user has no payment RPC permission');
reset role;

select * from finish();
rollback;
