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
insert into public.payment_attempts (payment_id, type, status, requested_amount_fils, currency, idempotency_key, provider_name, provider_transaction_reference, completed_at)
values ('fa200000-0000-0000-0000-000000000005', 'capture', 'succeeded', 1000, 'JOD', '020-capture', 'provider-020', 'provider-secret-ref', now());
insert into public.refunds (id, payment_id, amount_fils, currency, status, reason_code, requested_by_admin_id, provider_name, provider_refund_reference, completed_at)
values ('fa200000-0000-0000-0000-000000000006', 'fa200000-0000-0000-0000-000000000005', 1000, 'JOD', 'succeeded', 'duplicate_charge', 'fa000000-0000-0000-0000-000000000004', 'provider-020', 'refund-secret-ref', now());
insert into public.receipts (id, receipt_number, trip_id, fare_quote_id, payment_id, rider_snapshot, driver_snapshot, vehicle_snapshot, pickup_snapshot, destination_snapshot, ordered_stops_snapshot, fare_breakdown_snapshot, amount_paid_fils, currency, payment_method, card_brand, card_last_four, source_versions)
values ('fa200000-0000-0000-0000-000000000007', 'RDX-20260805-02000000', 'fa200000-0000-0000-0000-000000000004', 'fa200000-0000-0000-0000-000000000003', 'fa200000-0000-0000-0000-000000000005', '{}', '{}', '{}', '{}', '{}', '[]', '{}', 1000, 'JOD', 'card', 'visa', '4242', '{}');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select amount_fils from public.user_payment_summary('fa200000-0000-0000-0000-000000000005')), 1000, 'Rider reads own Payment summary');
select is((select count(*) from public.user_payment_attempt_summaries('fa200000-0000-0000-0000-000000000005')), 1::bigint, 'Rider reads own PaymentAttempt summaries');
select is((select count(*) from public.user_refund_statuses('fa200000-0000-0000-0000-000000000005')), 1::bigint, 'Rider reads own Refund summaries');
select is((select amount_paid_fils from public.user_receipt_summary('fa200000-0000-0000-0000-000000000007')), 1000, 'Rider reads own Receipt summary');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.user_payment_summary('fa200000-0000-0000-0000-000000000005')$$, 'Admin reads restricted Payment summary');
select lives_ok($$select public.user_payment_attempt_summaries('fa200000-0000-0000-0000-000000000005')$$, 'Admin reads restricted PaymentAttempt summaries');
select lives_ok($$select public.user_refund_statuses('fa200000-0000-0000-0000-000000000005')$$, 'Admin reads restricted Refund summaries');
select lives_ok($$select public.user_receipt_summary('fa200000-0000-0000-0000-000000000007')$$, 'Admin reads restricted Receipt summary');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.user_payment_summary('fa200000-0000-0000-0000-000000000005')$$, '42501', 'Finance data does not belong to this user.', 'assigned Driver cannot read Payment summary');
select throws_ok($$select public.user_payment_attempt_summaries('fa200000-0000-0000-0000-000000000005')$$, '42501', 'Finance data does not belong to this user.', 'assigned Driver cannot read PaymentAttempt summaries');
select throws_ok($$select public.user_refund_statuses('fa200000-0000-0000-0000-000000000005')$$, '42501', 'Finance data does not belong to this user.', 'assigned Driver cannot read Refund summaries');
select is((select amount_paid_fils from public.user_receipt_summary('fa200000-0000-0000-0000-000000000007')), 1000, 'assigned Driver reads only the restricted Receipt summary');
select throws_ok($$select public.user_trip_payment_summary('fa200000-0000-0000-0000-000000000004')$$, '42501', 'Finance data does not belong to this user.', 'Trip Payment wrapper does not bypass Driver denial');
select is((select count(*) from public.user_trip_receipt_summary('fa200000-0000-0000-0000-000000000004')), 1::bigint, 'Trip Receipt wrapper preserves assigned Driver access');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.user_payment_summary('fa200000-0000-0000-0000-000000000005')$$, '42501', 'Finance data does not belong to this user.', 'unrelated Driver cannot read Payment summary');
select throws_ok($$select public.user_payment_attempt_summaries('fa200000-0000-0000-0000-000000000005')$$, '42501', 'Finance data does not belong to this user.', 'unrelated Driver cannot read PaymentAttempt summaries');
select throws_ok($$select public.user_refund_statuses('fa200000-0000-0000-0000-000000000005')$$, '42501', 'Finance data does not belong to this user.', 'unrelated Driver cannot read Refund summaries');
select throws_ok($$select public.user_receipt_summary('fa200000-0000-0000-0000-000000000007')$$, '42501', 'Finance data does not belong to this user.', 'unrelated Driver cannot read Receipt summary');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.user_payment_summary('fa200000-0000-0000-0000-000000000005')$$, '42501', 'A non-blocked finance participant is required.', 'blocked user cannot read Payment summary');
select throws_ok($$select public.user_payment_attempt_summaries('fa200000-0000-0000-0000-000000000005')$$, '42501', 'A non-blocked finance participant is required.', 'blocked user cannot read PaymentAttempt summaries');
select throws_ok($$select public.user_refund_statuses('fa200000-0000-0000-0000-000000000005')$$, '42501', 'A non-blocked finance participant is required.', 'blocked user cannot read Refund summaries');
select throws_ok($$select public.user_receipt_summary('fa200000-0000-0000-0000-000000000007')$$, '42501', 'A non-blocked finance participant is required.', 'blocked user cannot read Receipt summary');
reset role;

set local role anon;
select throws_ok($$select public.user_payment_summary('fa200000-0000-0000-0000-000000000005')$$, '42501', null, 'anonymous user cannot read Payment summary');
select throws_ok($$select public.user_payment_attempt_summaries('fa200000-0000-0000-0000-000000000005')$$, '42501', null, 'anonymous user cannot read PaymentAttempt summaries');
select throws_ok($$select public.user_refund_statuses('fa200000-0000-0000-0000-000000000005')$$, '42501', null, 'anonymous user cannot read Refund summaries');
select throws_ok($$select public.user_receipt_summary('fa200000-0000-0000-0000-000000000007')$$, '42501', null, 'anonymous user cannot read Receipt summary');
reset role;

select ok(has_table_privilege('service_role', 'public.payments', 'select'), 'service role retains Payment access');
select ok(has_table_privilege('service_role', 'public.payment_attempts', 'insert'), 'service role retains PaymentAttempt operations');
select ok(has_table_privilege('service_role', 'public.refunds', 'update'), 'service role retains Refund operations');
select ok(has_table_privilege('service_role', 'public.receipts', 'insert'), 'service role retains Receipt operations');
select ok(not has_function_privilege('anon', 'public.user_payment_summary(uuid)', 'execute'), 'anonymous cannot execute Payment summary RPC');
select ok(not has_function_privilege('anon', 'public.user_receipt_summary(uuid)', 'execute'), 'anonymous cannot execute Receipt summary RPC');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$insert into public.payments (booking_request_id, rider_id, method, fare_quote_id, authorized_amount_fils, final_amount_fils, cash_status) values ('fa200000-0000-0000-0000-000000000002', auth.uid(), 'cash', 'fa200000-0000-0000-0000-000000000003', 1, 1, 'paid')$$, '42501', null, 'direct Payment writes remain denied');
select throws_ok($$insert into public.payment_attempts (payment_id, type, requested_amount_fils, currency, idempotency_key) values ('fa200000-0000-0000-0000-000000000005', 'capture', 1, 'JOD', '020-client-attempt')$$, '42501', null, 'direct PaymentAttempt writes remain denied');
select throws_ok($$insert into public.refunds (payment_id, amount_fils, currency, reason_code, requested_by_admin_id) values ('fa200000-0000-0000-0000-000000000005', 1, 'JOD', 'client', auth.uid())$$, '42501', null, 'direct Refund writes remain denied');
select throws_ok($$insert into public.receipts (receipt_number, trip_id, fare_quote_id, payment_id, rider_snapshot, driver_snapshot, vehicle_snapshot, pickup_snapshot, destination_snapshot, ordered_stops_snapshot, fare_breakdown_snapshot, amount_paid_fils, currency, payment_method, source_versions) values ('RDX-20260805-02000001', 'fa200000-0000-0000-0000-000000000004', 'fa200000-0000-0000-0000-000000000003', 'fa200000-0000-0000-0000-000000000005', '{}', '{}', '{}', '{}', '{}', '[]', '{}', 1, 'JOD', 'card', '{}')$$, '42501', null, 'direct Receipt writes remain denied');
reset role;

select * from finish();
rollback;
