begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select throws_ok(
  format(
    $$select public.backend_lock_fare_quote('21000000-0000-0000-0000-000000000001', %s, 1)$$,
    invalid_version
  ),
  '22023', 'Positive expected versions are required.',
  'FareQuote lock rejects ' || shape || ' expected Booking version'
)
from (values ('NULL', 'null::integer'), ('zero', '0'), ('negative', '-1'))
  as invalid(shape, invalid_version);

select throws_ok(
  format(
    $$select public.backend_lock_fare_quote('21000000-0000-0000-0000-000000000001', 1, %s)$$,
    invalid_version
  ),
  '22023', 'Positive expected versions are required.',
  'FareQuote lock rejects ' || shape || ' expected FareQuote version'
)
from (values ('NULL', 'null::integer'), ('zero', '0'), ('negative', '-1'))
  as invalid(shape, invalid_version);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '21000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-021@example.com', '', now(), '{}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '21000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'other-rider-021@example.com', '', now(), '{}', '{"display_name":"Other Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '21000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'driver-021@example.com', '', now(), '{}', '{"display_name":"Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '21000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'admin-021@example.com', '', now(), '{}', '{"display_name":"Admin"}', now(), now(), '', '', '', '');
update public.users set role = 'driver' where id = '21000000-0000-0000-0000-000000000003';
update public.users set role = 'admin' where id = '21000000-0000-0000-0000-000000000004';
delete from public.rider_profiles where user_id in (
  '21000000-0000-0000-0000-000000000003',
  '21000000-0000-0000-0000-000000000004'
);
insert into public.driver_profiles (user_id, approval_status, is_online, is_available)
values ('21000000-0000-0000-0000-000000000003', 'approved', false, false);
insert into public.driver_availability (driver_id, state)
values ('21000000-0000-0000-0000-000000000003', 'offline');
insert into public.vehicles (
  id, driver_id, vehicle_type_code, make, model, color,
  registration_plate, seat_capacity, is_active
) values (
  '21100000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000003',
  'economy', 'Toyota', 'Camry', 'White', 'RDX 021', 4, true
);
select public.backend_create_pricing_configuration(
  'economy', 500, 300, 50, 200, 1000, 50, true
);

insert into public.booking_requests (
  id, rider_id, pickup, destination, vehicle_type_code, payment_method, status
) values
  ('21200000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 'economy', 'cash', 'matched'),
  ('21200000-0000-0000-0000-000000000002', '21000000-0000-0000-0000-000000000001', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 'economy', 'card', 'matched'),
  ('21200000-0000-0000-0000-000000000003', '21000000-0000-0000-0000-000000000001', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 'economy', 'card', 'matched'),
  ('21200000-0000-0000-0000-000000000004', '21000000-0000-0000-0000-000000000001', '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}', 'economy', 'card', 'matched');

insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination,
  route_distance_meters, route_duration_seconds, vehicle_type_code,
  breakdown, fixed_fare_fils, pricing_configuration_id,
  pricing_version, quote_version, locked_at
)
select
  ('21300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('21200000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '21000000-0000-0000-0000-000000000001', 'locked',
  '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}',
  4000, 1200, 'economy', '{"fixed_fare_fils":2000}', 2000,
  (select id from public.pricing_configurations where is_active), 1, 1, now()
from generate_series(1, 4) as n;

insert into public.trips (
  id, booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id,
  status, payment_method, pickup, destination, route_distance_meters,
  route_duration_seconds, original_fare_fils, current_fare_fils
)
select
  ('21400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('21200000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('21300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '21000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000003',
  '21100000-0000-0000-0000-000000000001',
  case when n = 1 then 'inProgress'::public.trip_status
    when n in (2, 3) then 'accepted'::public.trip_status
    else 'completed'::public.trip_status end,
  case when n = 1 then 'cash'::public.payment_method else 'card'::public.payment_method end,
  '{"latitude":31.9,"longitude":35.9}', '{"latitude":32.0,"longitude":36.0}',
  4000, 1200, 2000, 2000
from generate_series(1, 4) as n;

insert into public.payments (
  id, booking_request_id, trip_id, rider_id, method, fare_quote_id,
  authorized_amount_fils, final_amount_fils, currency, cash_status, card_status
)
select
  ('21500000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('21200000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('21400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  '21000000-0000-0000-0000-000000000001',
  case when n = 1 then 'cash'::public.payment_method else 'card'::public.payment_method end,
  ('21300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  2000, 2000, 'JOD',
  case when n = 1 then 'cashSelected'::public.cash_payment_status end,
  case when n = 4 then 'refundPending'::public.card_payment_status
    when n > 1 then 'cardPaymentPending'::public.card_payment_status end
from generate_series(1, 4) as n;

insert into public.trip_change_requests (
  id, trip_id, rider_id, requested_destination, requested_stops
) values (
  '21600000-0000-0000-0000-000000000001',
  '21400000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000001',
  '{"latitude":32.2,"longitude":36.2}', '[]'
);

set local role service_role;
select throws_ok(
  $$select public.backend_price_trip_change_request(
    '21600000-0000-0000-0000-000000000001', 1, 5000, 1500, 'obsolete'
  )$$,
  '0A000',
  'Full-route Cash change pricing is retired; use the remaining-route pricing operation.',
  'legacy full-route Cash pricing fails closed for service role'
);
select is(
  (select count(*) from public.fare_adjustments
    where trip_change_request_id = '21600000-0000-0000-0000-000000000001'),
  0::bigint, 'legacy pricing creates no FareAdjustment'
);
select lives_ok(
  $$select public.backend_price_trip_change_request_remaining(
    '21600000-0000-0000-0000-000000000001', 1,
    3000, 600, 1000, 300, 'remaining-route'
  )$$,
  'approved remaining-route pricing remains callable by service role'
);
select is(
  (select adjustment_fils from public.fare_adjustments
    where trip_change_request_id = '21600000-0000-0000-0000-000000000001'),
  850, 'remaining-route pricing charges only the approved difference'
);
reset role;

select public.backend_record_payment_attempt(
  '21500000-0000-0000-0000-000000000002',
  'initialAuthorization', 2000, '021-auth-old', 'provider-a'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '021-auth-old'),
  'succeeded', 'auth-old-reference'
);
select public.backend_transition_payment(
  '21500000-0000-0000-0000-000000000002', 1, null, 'cardPaymentAuthorized'
);
select public.backend_transition_payment(
  '21500000-0000-0000-0000-000000000002', 2, null, 'cardPaymentPending'
);
select public.backend_record_payment_attempt(
  '21500000-0000-0000-0000-000000000002',
  'replacementAuthorization', 2000, '021-auth-new', 'provider-a'
);
select is(
  (select is_nullable from information_schema.columns
   where table_schema = 'public' and table_name = 'payment_attempts'
     and column_name = 'attempt_sequence'),
  'NO', 'PaymentAttempt sequence is non-null'
);
select is(
  (select identity_generation from information_schema.columns
   where table_schema = 'public' and table_name = 'payment_attempts'
     and column_name = 'attempt_sequence'),
  'ALWAYS', 'PaymentAttempt sequence is database generated'
);
select ok(
  (select count(*) = count(attempt_sequence) from public.payment_attempts),
  'existing PaymentAttempts receive deterministic non-null sequence values'
);
select ok(
  (select attempt_sequence from public.payment_attempts where idempotency_key = '021-auth-old')
    < (select attempt_sequence from public.payment_attempts where idempotency_key = '021-auth-new'),
  'new authorization receives a sequence greater than historical authorization attempts'
);
select throws_ok(
  $$insert into public.payment_attempts (
    payment_id, type, status, requested_amount_fils, currency, idempotency_key,
    attempt_sequence
  ) values (
    '21500000-0000-0000-0000-000000000002', 'capture', 'pending',
    2000, 'JOD', '021-attempt-sequence-override', 1
  )$$,
  '428C9', null, 'callers cannot override generated PaymentAttempt sequence values'
);
select throws_ok(
  $$select public.backend_transition_payment(
    '21500000-0000-0000-0000-000000000002', 3, null, 'cardPaymentAuthorized'
  )$$,
  '55000', 'Card authorization requires a verified two-minute authorization attempt.',
  'pending replacement authorization prevents reuse of prior success'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '021-auth-new'),
  'failed', null, 'DECLINED'
);
update public.payments set card_status = 'cardPaymentAuthorized'
where id = '21500000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '21000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.driver_transition_trip(
    '21400000-0000-0000-0000-000000000002', 'driverArriving', 1, '021-obsolete-progress'
  )$$,
  '55000', 'Card Trip progression requires a verified authorized Payment.',
  'failed latest replacement prevents Driver progression with prior success'
);
reset role;

select public.backend_record_payment_attempt(
  '21500000-0000-0000-0000-000000000003',
  'initialAuthorization', 2000, '021-auth-voided', 'provider-a'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '021-auth-voided'),
  'succeeded', 'auth-voided-reference'
);
select public.backend_transition_payment(
  '21500000-0000-0000-0000-000000000003', 1, null, 'cardPaymentAuthorized'
);
select public.backend_record_payment_attempt(
  '21500000-0000-0000-0000-000000000003',
  'voidAuthorization', 2000, '021-void', 'provider-a'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '021-void'),
  'succeeded', 'void-reference'
);
select public.backend_transition_payment(
  '21500000-0000-0000-0000-000000000003', 2, null, 'cardPaymentPending'
);
select throws_ok(
  $$select public.backend_transition_payment(
    '21500000-0000-0000-0000-000000000003', 3, null, 'cardPaymentAuthorized'
  )$$,
  '55000', 'Card authorization requires a verified two-minute authorization attempt.',
  'successful void prevents reuse of the voided authorization'
);

insert into public.refunds (
  id, payment_id, amount_fils, currency, reason_code, requested_by_admin_id
) values (
  '21700000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000004',
  2000, 'JOD', 'duplicate_charge',
  '21000000-0000-0000-0000-000000000004'
);

select lives_ok(
  $$select public.backend_record_refund_attempt(
    '21700000-0000-0000-0000-000000000001', '021-refund-1', ' provider-a '
  )$$, 'original Refund attempt is recorded'
);
select is(
  (select public.backend_record_refund_attempt(
    '21700000-0000-0000-0000-000000000001', '021-refund-1', 'provider-a')).id,
  (select id from public.payment_attempts where idempotency_key = '021-refund-1'),
  'identical normalized Refund replay returns the canonical attempt'
);
select throws_ok(
  $$select public.backend_record_refund_attempt(
    '21700000-0000-0000-0000-000000000001', '021-refund-1', 'provider-b'
  )$$,
  '55000',
  'Refund attempt idempotency key is already associated with different operation data.',
  'Refund replay with a different provider fails closed'
);
select throws_ok(
  $$select public.backend_record_refund_attempt(
    '21700000-0000-0000-0000-000000000001', '021-refund-2', 'provider-a'
  )$$,
  '55000', 'A Refund retry requires the preceding attempt to complete unsuccessfully.',
  'Refund retry is rejected while the preceding attempt is pending'
);
select public.backend_complete_refund_attempt(
  (select id from public.payment_attempts where idempotency_key = '021-refund-1'),
  'failed', null, 'PROVIDER_UNAVAILABLE'
);
select is(
  (select public.backend_complete_refund_attempt(
    (select id from public.payment_attempts where idempotency_key = '021-refund-1'),
    'failed', null, 'PROVIDER_UNAVAILABLE')).id,
  (select id from public.payment_attempts where idempotency_key = '021-refund-1'),
  'identical terminal Refund completion replay returns the attempt'
);
select throws_ok(
  $$select public.backend_complete_refund_attempt(
    (select id from public.payment_attempts where idempotency_key = '021-refund-1'),
    'cancelled', null, 'PROVIDER_UNAVAILABLE'
  )$$,
  '55000', 'A terminal Refund attempt cannot be completed with different data.',
  'conflicting terminal Refund status fails closed'
);
select throws_ok(
  $$select public.backend_complete_refund_attempt(
    (select id from public.payment_attempts where idempotency_key = '021-refund-1'),
    'failed', 'different-reference', 'PROVIDER_UNAVAILABLE'
  )$$,
  '55000', 'A terminal Refund attempt cannot be completed with different data.',
  'conflicting terminal Refund provider reference fails closed'
);
select lives_ok(
  $$select public.backend_record_refund_attempt(
    '21700000-0000-0000-0000-000000000001', '021-refund-2', 'provider-a'
  )$$, 'first Refund retry is allowed after failure'
);
select ok(
  (select attempt_sequence from public.payment_attempts where idempotency_key = '021-refund-1')
    < (select attempt_sequence from public.payment_attempts where idempotency_key = '021-refund-2'),
  'Refund retry selection preserves newest deterministic sequence ordering'
);
select public.backend_complete_refund_attempt(
  (select id from public.payment_attempts where idempotency_key = '021-refund-2'),
  'cancelled', null, 'PROVIDER_CANCELLED'
);
select lives_ok(
  $$select public.backend_record_refund_attempt(
    '21700000-0000-0000-0000-000000000001', '021-refund-3', 'provider-a'
  )$$, 'second and final Refund retry is allowed after unsuccessful completion'
);
select throws_ok(
  $$select public.backend_record_refund_attempt(
    '21700000-0000-0000-0000-000000000001', '021-refund-4', 'provider-a'
  )$$,
  '55000', 'Refund permits at most three attempts.',
  'fourth total Refund attempt is rejected'
);

insert into public.receipts (
  id, receipt_number, trip_id, fare_quote_id, payment_id,
  rider_snapshot, driver_snapshot, vehicle_snapshot, pickup_snapshot,
  destination_snapshot, ordered_stops_snapshot, fare_breakdown_snapshot,
  amount_paid_fils, currency, payment_method, source_versions
) values (
  '21800000-0000-0000-0000-000000000001', 'RDX-20260808-02100000',
  '21400000-0000-0000-0000-000000000004',
  '21300000-0000-0000-0000-000000000004',
  '21500000-0000-0000-0000-000000000004',
  '{}', '{}', '{}', '{}', '{}', '[]', '{}', 2000, 'JOD', 'card', '{}'
);
insert into public.help_requests (
  id, requester_user_id, category_code, subject, message
) values (
  '21900000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000001',
  'trip', 'Help', 'Please help'
);

set local role service_role;
select throws_ok(
  $$select public.backend_create_notification(
    '21000000-0000-0000-0000-000000000001', 'trip.update', 'Trip', 'Update',
    '{"trip_id":"21400000-0000-0000-0000-000000000002"}', null, '021-id-only'
  )$$,
  '23514', null, 'identifier-only Notification payload is rejected'
);
select lives_ok(
  $$select public.backend_create_notification(
    '21000000-0000-0000-0000-000000000001', 'trip.update', 'Trip', 'Update',
    '{"destination":"trip","trip_id":"21400000-0000-0000-0000-000000000002"}', null, '021-trip-valid'
  )$$, 'recipient-authorized Trip destination succeeds'
);
select lives_ok(
  $$select public.backend_create_notification(
    '21000000-0000-0000-0000-000000000003', 'receipt.ready', 'Receipt', 'Ready',
    '{"destination":"receipt","receipt_id":"21800000-0000-0000-0000-000000000001"}', null, '021-receipt-valid'
  )$$, 'assigned Driver receives an authorized Receipt destination'
);
select lives_ok(
  $$select public.backend_create_notification(
    '21000000-0000-0000-0000-000000000001', 'help.update', 'Help', 'Update',
    '{"destination":"help_request","help_request_id":"21900000-0000-0000-0000-000000000001"}', null, '021-help-valid'
  )$$, 'requester receives an authorized HelpRequest destination'
);
select throws_ok(
  $$select public.backend_create_notification(
    '21000000-0000-0000-0000-000000000002', 'trip.update', 'Trip', 'Update',
    '{"destination":"trip","trip_id":"21400000-0000-0000-0000-000000000002"}', null, '021-trip-cross'
  )$$,
  '42501', 'Notification Trip is not authorized for its recipient.',
  'cross-recipient Trip reference is rejected'
);
select throws_ok(
  $$select public.backend_create_notification(
    '21000000-0000-0000-0000-000000000001', 'payment.update', 'Payment', 'Update',
    '{"destination":"payment","payment_id":"21500000-0000-0000-0000-000000000099"}', null, '021-payment-missing'
  )$$,
  '42501', 'Notification Payment is not authorized for its recipient.',
  'nonexistent Notification reference is rejected'
);
select throws_ok(
  $$select public.backend_create_notification(
    '21000000-0000-0000-0000-000000000001', 'trip.update', 'Trip', 'Update',
    '{"destination":"trip","payment_id":"21500000-0000-0000-0000-000000000002"}', null, '021-wrong-resource'
  )$$,
  '23514', null, 'wrong identifier for destination is rejected'
);
select throws_ok(
  $$select public.backend_create_notification(
    '21000000-0000-0000-0000-000000000001', 'trip.update', 'Trip', 'Update',
    '{"destination":"trip","trip_id":"21400000-0000-0000-0000-000000000002","extra":"no"}', null, '021-extra'
  )$$,
  '23514', null, 'extra Notification payload field is rejected'
);
select throws_ok(
  $$select public.backend_create_notification(
    '21000000-0000-0000-0000-000000000001', 'trip.update', 'Trip', 'Update',
    '{"destination":"trip","trip_id":"21400000-0000-0000-0000-000000000002","nested":{"token":"secret"}}', null, '021-sensitive'
  )$$,
  '23514', null, 'recursive sensitive Notification content remains rejected'
);
reset role;

select * from finish();
rollback;
