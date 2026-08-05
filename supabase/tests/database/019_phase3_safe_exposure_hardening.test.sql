begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select is(
  (select count(*) from pg_policies where schemaname = 'public' and tablename in ('payments', 'payment_attempts', 'refunds', 'receipts') and roles @> array['authenticated']::name[] and cmd = 'SELECT'),
  0::bigint, 'authenticated clients have no whole-row finance-table read policies'
);
select ok(has_table_privilege('service_role', 'public.payments', 'select'), 'service role retains backend finance access');
select ok(not has_table_privilege('anon', 'public.payments', 'select'), 'anonymous users cannot read finance tables');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
values
  ('00000000-0000-0000-0000-000000000000', 'f9000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-019@example.com', '', now(), '{}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'f9000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'driver-019@example.com', '', now(), '{}', '{"display_name":"Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'f9000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'admin-019@example.com', '', now(), '{}', '{"display_name":"Admin"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'f9000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'blocked-019@example.com', '', now(), '{}', '{"display_name":"Blocked"}', now(), now(), '', '', '', '');
update public.users set role = 'driver' where id = 'f9000000-0000-0000-0000-000000000002';
update public.users set role = 'admin' where id = 'f9000000-0000-0000-0000-000000000003';
update public.users set is_blocked = true where id = 'f9000000-0000-0000-0000-000000000004';
delete from public.rider_profiles where user_id in ('f9000000-0000-0000-0000-000000000002', 'f9000000-0000-0000-0000-000000000003');
insert into public.driver_profiles (user_id, approval_status, is_online, is_available) values ('f9000000-0000-0000-0000-000000000002', 'approved', false, false);
insert into public.vehicles (id, driver_id, vehicle_type_code, make, model, color, registration_plate, seat_capacity, is_active) values ('f9100000-0000-0000-0000-000000000001', 'f9000000-0000-0000-0000-000000000002', 'comfort', 'Toyota', 'Camry', 'White', 'RDX 019', 4, true);
insert into public.pricing_configurations (id, vehicle_type_code, pricing_version, base_fare_fils, per_kilometer_fils, per_minute_fils, per_stop_fils, minimum_fare_fils, is_active) values ('f9200000-0000-0000-0000-000000000001', 'comfort', 1, 500, 300, 50, 200, 1000, true);
insert into public.booking_requests (id, rider_id, pickup, destination, vehicle_type_code, payment_method, status) values ('f9200000-0000-0000-0000-000000000002', 'f9000000-0000-0000-0000-000000000001', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 'comfort', 'card', 'matched');
insert into public.fare_quotes (id, booking_request_id, rider_id, status, pickup, destination, route_distance_meters, route_duration_seconds, vehicle_type_code, breakdown, fixed_fare_fils, pricing_configuration_id, pricing_version, quote_version, locked_at) values ('f9200000-0000-0000-0000-000000000003', 'f9200000-0000-0000-0000-000000000002', 'f9000000-0000-0000-0000-000000000001', 'locked', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 1000, 300, 'comfort', '{}', 1000, 'f9200000-0000-0000-0000-000000000001', 1, 1, now());
insert into public.trips (id, booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id, status, payment_method, pickup, destination, route_distance_meters, route_duration_seconds, original_fare_fils, current_fare_fils, completed_at) values ('f9200000-0000-0000-0000-000000000004', 'f9200000-0000-0000-0000-000000000002', 'f9200000-0000-0000-0000-000000000003', 'f9000000-0000-0000-0000-000000000001', 'f9000000-0000-0000-0000-000000000002', 'f9100000-0000-0000-0000-000000000001', 'completed', 'card', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 1000, 300, 1000, 1000, now());
insert into public.payments (id, booking_request_id, trip_id, rider_id, method, fare_quote_id, authorized_amount_fils, final_amount_fils, card_status, provider_name, card_brand, card_last_four) values ('f9200000-0000-0000-0000-000000000005', 'f9200000-0000-0000-0000-000000000002', 'f9200000-0000-0000-0000-000000000004', 'f9000000-0000-0000-0000-000000000001', 'card', 'f9200000-0000-0000-0000-000000000003', 1000, 1000, 'cardPaymentSucceeded', 'provider-019', 'visa', '4242');
insert into public.payment_attempts (payment_id, type, status, requested_amount_fils, currency, idempotency_key, provider_name, provider_transaction_reference, completed_at) values ('f9200000-0000-0000-0000-000000000005', 'capture', 'succeeded', 1000, 'JOD', '019-capture', 'provider-019', 'provider-secret-ref', now());

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f9000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select amount_fils from public.user_payment_summary('f9200000-0000-0000-0000-000000000005')), 1000, 'Rider receives the safe Payment summary');
select is((select count(*) from public.user_payment_attempt_summaries('f9200000-0000-0000-0000-000000000005')), 1::bigint, 'Rider receives PaymentAttempt summaries');
select is_empty($$select provider_name from public.payments where id = 'f9200000-0000-0000-0000-000000000005'$$, 'Rider cannot read provider-sensitive Payment columns directly');
select throws_ok($$select public.user_create_help_request('payment', 'Card', 'My card is 4242 4242 4242 4242', 'normal', null, 'f9200000-0000-0000-0000-000000000005', '019-pan')$$, '22023', 'HelpRequest content must not include payment card data.', 'PAN-like HelpRequest content is rejected');
select throws_ok($$select public.user_create_help_request('payment', 'CVV 123', 'Please help', 'normal', null, 'f9200000-0000-0000-0000-000000000005', '019-cvv')$$, '22023', 'HelpRequest content must not include payment card data.', 'CVV HelpRequest content is rejected');
select is((select count(*) from public.help_requests), 0::bigint, 'rejected Card data is not persisted');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f9000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.user_payment_summary('f9200000-0000-0000-0000-000000000005')$$, '42501', 'Finance data does not belong to this user.', 'assigned Driver cannot read Payment summaries');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f9000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.user_payment_summary('f9200000-0000-0000-0000-000000000005')$$, 'Admin receives the restricted Payment summary');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f9000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.user_payment_summary('f9200000-0000-0000-0000-000000000005')$$, '42501', 'A non-blocked finance participant is required.', 'blocked users cannot read safe finance summaries');
reset role;

set local role service_role;
select lives_ok($$select public.backend_create_notification('f9000000-0000-0000-0000-000000000001', 'trip.completed', 'Trip complete', 'Your trip is complete.', '{"destination":"trip","trip_id":"f9200000-0000-0000-0000-000000000004"}', null, '019-trip')$$, 'allowlisted notification destination succeeds');
select throws_ok($$select public.backend_create_notification('f9000000-0000-0000-0000-000000000001', 'trip.completed', 'Trip complete', 'Your trip is complete.', '{"destination":"trip","payment_id":"f9200000-0000-0000-0000-000000000005"}', null, '019-bad-destination')$$, '23514', null, 'notification destination requires its matching identifier');
select throws_ok($$select public.backend_create_notification('f9000000-0000-0000-0000-000000000001', 'trip.completed', 'Trip complete', 'Your trip is complete.', '{"destination":"external","url":"https://example.com"}', null, '019-external')$$, '23514', null, 'notification destination allowlist rejects external navigation');
reset role;

select * from finish();
rollback;
