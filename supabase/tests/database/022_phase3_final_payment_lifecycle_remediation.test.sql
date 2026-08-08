begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

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
  (select id from public.pricing_configurations where is_active),
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

select has_column(
  'public', 'payment_attempts', 'authorization_cycle',
  'PaymentAttempt stores its deterministic authorization cycle'
);
select has_index(
  'public', 'payment_attempts',
  'payment_attempts_one_pending_capture_idx',
  'only one Capture-family attempt can remain pending'
);
select has_index(
  'public', 'payment_attempts',
  'payment_attempts_idempotency_key_global_idx',
  'PaymentAttempt idempotency keys are operation-global'
);
select matches(
  (select indexdef from pg_indexes
    where schemaname = 'public'
      and indexname = 'payment_attempts_one_pending_capture_idx'),
  '^CREATE UNIQUE INDEX .* WHERE .*status = ''pending''',
  'pending Capture guard is a partial unique index'
);
select matches(
  (select indexdef from pg_indexes
    where schemaname = 'public'
      and indexname = 'payment_attempts_authorization_cycle_unique_idx'),
  '^CREATE UNIQUE INDEX .*authorization_cycle.*',
  'authorization cycles are unique per Payment'
);

-- Card authorization cycles and cancellation.
select public.backend_record_payment_attempt(
  '22500000-0000-0000-0000-000000000001',
  'initialAuthorization', 2000, '022-auth-initial', 'provider-a'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-auth-initial'),
  'succeeded', '022-auth-initial-reference'
);
select public.backend_transition_payment(
  '22500000-0000-0000-0000-000000000001',
  1, null, 'cardPaymentAuthorized'
);
select throws_ok(
  $$select public.backend_transition_payment(
    '22500000-0000-0000-0000-000000000001',
    2, null, 'cardPaymentPending'
  )$$,
  '55000',
  'A new authorization cycle requires verified release of the current authorization.',
  'new authorization cycle cannot begin before verified release'
);
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000001',
    'replacementAuthorization', 2000, '022-replacement-before-void', 'provider-a'
  )$$,
  '55000',
  'Replacement authorization requires a failed authorization or verified release.',
  'replacement authorization cannot precede verified release'
);
select public.backend_record_payment_attempt(
  '22500000-0000-0000-0000-000000000001',
  'voidAuthorization', 2000, '022-void-cycle-1', 'provider-a'
);
select throws_ok(
  $$select public.backend_transition_payment(
    '22500000-0000-0000-0000-000000000001',
    2, null, 'paymentCancelled'
  )$$,
  '55000', 'Payment cancellation requires a terminal cancelled Trip.',
  'Payment cancellation is blocked while Trip remains active'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_cancel_trip(
    '22400000-0000-0000-0000-000000000001', 1, 'changed_mind'
  )$$,
  '55000',
  'Card Payment requires a verified current-cycle void before cancellation.',
  'requested but unverified void cannot authorize Card cancellation'
);
reset role;
select is(
  (select status::text from public.trips
    where id = '22400000-0000-0000-0000-000000000001'),
  'accepted', 'failed Card cancellation rolls back Trip state'
);

select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-void-cycle-1'),
  'succeeded', '022-void-cycle-1-reference'
);
select public.backend_transition_payment(
  '22500000-0000-0000-0000-000000000001',
  2, null, 'cardPaymentPending'
);
select throws_ok(
  $$select public.backend_transition_payment(
    '22500000-0000-0000-0000-000000000001',
    3, null, 'cardPaymentAuthorized'
  )$$,
  '55000',
  'Card authorization requires the current verified authorization cycle.',
  'old successful authorization cannot authorize a released cycle'
);
select lives_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000001',
    'replacementAuthorization', 2000, '022-auth-replacement', 'provider-a'
  )$$,
  'valid replacement authorization starts the next cycle'
);
select is(
  (select authorization_cycle from public.payment_attempts
    where idempotency_key = '022-auth-replacement'),
  2, 'replacement authorization receives the next deterministic cycle'
);
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000001',
    'replacementAuthorization', 2000, '022-auth-parallel', 'provider-a'
  )$$,
  '55000',
  'Replacement authorization requires one valid preceding initial authorization.',
  'parallel replacement authorization is rejected'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-auth-replacement'),
  'succeeded', '022-auth-replacement-reference'
);
select public.backend_transition_payment(
  '22500000-0000-0000-0000-000000000001',
  3, null, 'cardPaymentAuthorized'
);
update public.trips set status = 'cancelledByAdmin'
where id = '22400000-0000-0000-0000-000000000001';
select throws_ok(
  $$select public.backend_transition_payment(
    '22500000-0000-0000-0000-000000000001',
    4, null, 'paymentCancelled'
  )$$,
  '55000',
  'Card Payment requires a verified current-cycle void before cancellation.',
  'void from prior authorization cycle cannot cancel current cycle'
);

-- Capture ordering and retry limits.
select public.backend_record_payment_attempt(
  '22500000-0000-0000-0000-000000000002',
  'initialAuthorization', 2000, '022-capture-auth', 'provider-a'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-capture-auth'),
  'succeeded', '022-capture-auth-reference'
);
select public.backend_transition_payment(
  '22500000-0000-0000-0000-000000000002',
  1, null, 'cardPaymentAuthorized'
);
update public.trips set status = 'driverArriving'
where id = '22400000-0000-0000-0000-000000000002';
update public.trips set status = 'driverArrived'
where id = '22400000-0000-0000-0000-000000000002';
update public.trips set status = 'inProgress'
where id = '22400000-0000-0000-0000-000000000002';
update public.trips set status = 'completed', completed_at = now()
where id = '22400000-0000-0000-0000-000000000002';
select public.backend_record_payment_attempt(
  '22500000-0000-0000-0000-000000000002',
  'capture', 2000, '022-capture-initial', 'provider-a'
);
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000002',
    'captureRetry', 2000, '022-capture-retry-pending-initial', 'provider-a'
  )$$,
  '55000',
  'Capture retry requires the latest current-cycle Capture attempt to have failed.',
  'Capture retry is rejected while initial Capture is pending'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-capture-initial'),
  'failed', null, 'CAPTURE_DECLINED'
);
select public.backend_transition_payment(
  '22500000-0000-0000-0000-000000000002',
  2, null, 'cardPaymentFailed'
);
select lives_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000002',
    'captureRetry', 2000, '022-capture-retry-1', 'provider-a'
  )$$,
  'Capture retry succeeds after failed Capture within limit'
);
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000002',
    'captureRetry', 2000, '022-capture-retry-parallel', 'provider-a'
  )$$,
  '55000',
  'Capture retry requires the latest current-cycle Capture attempt to have failed.',
  'multiple pending Capture retries are rejected'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-capture-retry-1'),
  'succeeded', '022-capture-retry-reference'
);
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000002',
    'captureRetry', 2000, '022-capture-after-success', 'provider-a'
  )$$,
  '55000',
  'Capture retry requires the latest current-cycle Capture attempt to have failed.',
  'successful Capture is terminal for further Capture retries'
);
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000002',
    'captureRetry', 1999, '022-capture-retry-1', 'provider-a'
  )$$,
  '55000',
  'Payment attempt idempotency key is already associated with different operation data.',
  'Capture retry idempotency mismatch fails closed'
);

-- Initial/replacement ordering and cross-Payment idempotency binding.
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000003',
    'replacementAuthorization', 2000, '022-invalid-first-replacement', 'provider-a'
  )$$,
  '55000',
  'Replacement authorization requires one valid preceding initial authorization.',
  'replacement authorization cannot be the first authorization attempt'
);
select public.backend_record_payment_attempt(
  '22500000-0000-0000-0000-000000000003',
  'initialAuthorization', 2000, '022-order-initial', 'provider-a'
);
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000003',
    'initialAuthorization', 2000, '022-order-second-initial', 'provider-a'
  )$$,
  '55000', 'Initial authorization must be the first authorization attempt.',
  'second initial authorization is rejected'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-order-initial'),
  'failed', null, 'AUTH_DECLINED'
);
select lives_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000003',
    'replacementAuthorization', 2000, '022-order-replacement', 'provider-a'
  )$$,
  'replacement authorization follows failed initial authorization'
);
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000003',
    'replacementAuthorization', 2000, '022-order-replacement', 'provider-b'
  )$$,
  '55000',
  'Payment attempt idempotency key is already associated with different operation data.',
  'authorization idempotency mismatch rejects changed provider semantics'
);
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000003',
    'replacementAuthorization', 2000, '022-auth-replacement', 'provider-a'
  )$$,
  '55000',
  'Payment attempt idempotency key is already associated with different operation data.',
  'idempotency key cannot be reused for another Payment'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-order-replacement'),
  'succeeded', '022-order-replacement-reference'
);
select public.backend_transition_payment(
  '22500000-0000-0000-0000-000000000003',
  1, null, 'cardPaymentAuthorized'
);
select public.backend_record_payment_attempt(
  '22500000-0000-0000-0000-000000000003',
  'voidAuthorization', 2000, '022-valid-cancel-void', 'provider-a'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-valid-cancel-void'),
  'succeeded', '022-valid-cancel-void-reference'
);
update public.trips set status = 'cancelledByAdmin'
where id = '22400000-0000-0000-0000-000000000003';
select lives_ok(
  $$select public.backend_transition_payment(
    '22500000-0000-0000-0000-000000000003',
    2, null, 'paymentCancelled'
  )$$,
  'terminal Card cancellation succeeds after verified current-cycle release'
);
select is(
  (select card_status::text from public.payments
    where id = '22500000-0000-0000-0000-000000000003'),
  'paymentCancelled', 'verified release produces canonical Card cancellation'
);

-- Capture retry count remains bounded at three total attempts.
select public.backend_record_payment_attempt(
  '22500000-0000-0000-0000-000000000007',
  'initialAuthorization', 2000, '022-limit-auth', 'provider-a'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-limit-auth'),
  'succeeded', '022-limit-auth-reference'
);
select public.backend_transition_payment(
  '22500000-0000-0000-0000-000000000007',
  1, null, 'cardPaymentAuthorized'
);
update public.trips set status = 'driverArriving'
where id = '22400000-0000-0000-0000-000000000007';
update public.trips set status = 'driverArrived'
where id = '22400000-0000-0000-0000-000000000007';
update public.trips set status = 'inProgress'
where id = '22400000-0000-0000-0000-000000000007';
update public.trips set status = 'completed', completed_at = now()
where id = '22400000-0000-0000-0000-000000000007';
select public.backend_record_payment_attempt(
  '22500000-0000-0000-0000-000000000007',
  'capture', 2000, '022-limit-capture', 'provider-a'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-limit-capture'),
  'failed', null, 'CAPTURE_DECLINED'
);
select public.backend_transition_payment(
  '22500000-0000-0000-0000-000000000007',
  2, null, 'cardPaymentFailed'
);
select public.backend_record_payment_attempt(
  '22500000-0000-0000-0000-000000000007',
  'captureRetry', 2000, '022-limit-retry-1', 'provider-a'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-limit-retry-1'),
  'failed', null, 'CAPTURE_DECLINED'
);
select public.backend_record_payment_attempt(
  '22500000-0000-0000-0000-000000000007',
  'captureRetry', 2000, '022-limit-retry-2', 'provider-a'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '022-limit-retry-2'),
  'failed', null, 'CAPTURE_DECLINED'
);
select throws_ok(
  $$select public.backend_record_payment_attempt(
    '22500000-0000-0000-0000-000000000007',
    'captureRetry', 2000, '022-limit-retry-3', 'provider-a'
  )$$,
  '55000', 'Capture permits at most three attempts.',
  'Capture rejects a fourth total attempt'
);

-- Cash can settle only through atomic trusted Trip completion.
select throws_ok(
  $$select public.backend_transition_payment(
    '22500000-0000-0000-0000-000000000004',
    1, 'paid', null
  )$$,
  '55000',
  'Cash Payment can be paid only by atomic trusted Trip completion.',
  'generic Payment RPC cannot mark Cash paid'
);
update public.driver_availability
set state = 'onTrip',
    vehicle_id = '22100000-0000-0000-0000-000000000001',
    active_trip_id = '22400000-0000-0000-0000-000000000004'
where driver_id = '22000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok(
  $$select public.driver_transition_trip(
    '22400000-0000-0000-0000-000000000004',
    'completed', 1, '022-cash-complete'
  )$$,
  'trusted Cash Trip completion succeeds'
);
reset role;
select is(
  (select status::text from public.trips
    where id = '22400000-0000-0000-0000-000000000004'),
  'completed', 'trusted Cash completion completes Trip'
);
select is(
  (select cash_status::text from public.payments
    where id = '22500000-0000-0000-0000-000000000004'),
  'paid', 'trusted Cash completion settles Payment'
);
select is(
  (select count(*) from public.receipts
    where trip_id = '22400000-0000-0000-0000-000000000004'),
  1::bigint, 'trusted Cash completion issues one Receipt'
);

update public.driver_availability
set state = 'onTrip',
    vehicle_id = '22100000-0000-0000-0000-000000000001',
    active_trip_id = '22400000-0000-0000-0000-000000000005'
where driver_id = '22000000-0000-0000-0000-000000000002';
create or replace function pg_temp.reject_022_receipt()
returns trigger
language plpgsql
as $$
begin
  raise exception using errcode = 'XX000', message = 'Forced 022 Receipt failure.';
end;
$$;
create trigger reject_022_receipt
before insert on public.receipts
for each row execute function pg_temp.reject_022_receipt();
set local role authenticated;
select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.driver_transition_trip(
    '22400000-0000-0000-0000-000000000005',
    'completed', 1, '022-cash-rollback'
  )$$,
  'XX000', 'Forced 022 Receipt failure.',
  'Receipt failure aborts atomic Cash completion'
);
reset role;
select is(
  (select status::text from public.trips
    where id = '22400000-0000-0000-0000-000000000005'),
  'inProgress', 'Receipt failure rolls back Trip completion'
);
select is(
  (select cash_status::text from public.payments
    where id = '22500000-0000-0000-0000-000000000005'),
  'cashSelected', 'Receipt failure rolls back Cash Payment settlement'
);
select is(
  (select count(*) from public.receipts
    where trip_id = '22400000-0000-0000-0000-000000000005'),
  0::bigint, 'Receipt failure leaves no partial Receipt'
);
drop trigger reject_022_receipt on public.receipts;

-- Zero remaining-route differences are valid and nonnegative.
insert into public.trip_change_requests (
  id, trip_id, rider_id, requested_destination, requested_stops
) values (
  '22600000-0000-0000-0000-000000000001',
  '22400000-0000-0000-0000-000000000006',
  '22000000-0000-0000-0000-000000000001',
  '{"latitude":32.1,"longitude":36.1}', '[]'
);
select lives_ok(
  $$select public.backend_price_trip_change_request_remaining(
    '22600000-0000-0000-0000-000000000001', 1,
    1000, 300, 5000, 1500, '022-zero-adjustment'
  )$$,
  'remaining-route pricing accepts a zero adjustment'
);
select is(
  (select adjustment_fils from public.fare_adjustments
    where trip_change_request_id = '22600000-0000-0000-0000-000000000001'),
  0, 'cheaper remaining route clamps FareAdjustment to zero'
);
select ok(
  (select adjustment_fils >= 0 from public.fare_adjustments
    where trip_change_request_id = '22600000-0000-0000-0000-000000000001'),
  'remaining-route FareAdjustment remains nonnegative'
);

-- Admin HelpRequest resolution rejects prohibited card data.
insert into public.help_requests (
  id, requester_user_id, category_code, subject, message
) values (
  '22700000-0000-0000-0000-000000000001',
  '22000000-0000-0000-0000-000000000001',
  'payment', 'Payment support', 'Please review my payment issue.'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.admin_assign_help_request(
  '22700000-0000-0000-0000-000000000001', 1,
  '22000000-0000-0000-0000-000000000003'
);
select throws_ok(
  $$select public.admin_resolve_help_request(
    '22700000-0000-0000-0000-000000000001', 2,
    'Customer supplied CVV 123 during review.'
  )$$,
  '22023', 'HelpRequest resolution must not include payment card data.',
  'Admin HelpRequest resolution rejects prohibited card data'
);
reset role;
select is(
  (select status::text from public.help_requests
    where id = '22700000-0000-0000-0000-000000000001'),
  'assigned', 'rejected Admin card data is not persisted'
);

select * from finish();
rollback;
