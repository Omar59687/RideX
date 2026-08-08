begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

create temporary table version_gate_cases (
  label text not null,
  command_template text not null
);

insert into version_gate_cases values
  ('Driver Trip transition', $$select public.driver_transition_trip('c7f00000-0000-0000-0000-000000000001', 'accepted', %s, '017-version')$$),
  ('Rider Trip cancellation', $$select public.rider_cancel_trip('c7f00000-0000-0000-0000-000000000001', %s, 'test')$$),
  ('Admin Trip termination', $$select public.admin_terminate_trip('c7f00000-0000-0000-0000-000000000001', %s, 'failed', 'test')$$),
  ('Rider Trip-change creation', $$select public.rider_create_trip_change_request('c7f00000-0000-0000-0000-000000000001', %s, '{"latitude":31.9,"longitude":35.9}', '[]')$$),
  ('Rider Trip-change cancellation', $$select public.rider_cancel_trip_change_request('c7f00000-0000-0000-0000-000000000001', %s)$$),
  ('Rider Trip-change approval', $$select public.rider_approve_trip_change_request('c7f00000-0000-0000-0000-000000000001', %s, 1)$$),
  ('Backend Trip-change pricing', $$select public.backend_price_trip_change_request('c7f00000-0000-0000-0000-000000000001', %s, 1, 1)$$),
  ('Backend Fare application', $$select public.backend_apply_trip_fare_adjustment('c7f00000-0000-0000-0000-000000000001', %s, 1)$$),
  ('Backend Payment transition', $$select public.backend_transition_payment('c7f00000-0000-0000-0000-000000000001', %s, 'cancelled', null)$$),
  ('Admin Refund request', $$select public.admin_request_refund('c7f00000-0000-0000-0000-000000000001', %s, 'test')$$);

select throws_ok(
  format(command_template, invalid_version),
  '22023',
  case when label like '%approval%' or label like '%application%'
    then 'Positive expected versions are required.'
    else 'A positive expected version is required.' end,
  label || ' rejects ' || shape || ' expected version'
)
from version_gate_cases
cross join (values
  ('null', 'null::integer'),
  ('zero', '0'),
  ('negative', '-1')
) as invalid(shape, invalid_version);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
values
  ('00000000-0000-0000-0000-000000000000', 'c7000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-017@example.com', '', now(), '{}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'c7000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'driver-017@example.com', '', now(), '{}', '{"display_name":"Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'c7000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'admin-017@example.com', '', now(), '{}', '{"display_name":"Admin"}', now(), now(), '', '', '', '');

update public.users set role = 'driver'
where id = 'c7000000-0000-0000-0000-000000000002';
update public.users set role = 'admin'
where id = 'c7000000-0000-0000-0000-000000000003';
delete from public.rider_profiles
where user_id in (
  'c7000000-0000-0000-0000-000000000002',
  'c7000000-0000-0000-0000-000000000003'
);
insert into public.driver_profiles (
  user_id, approval_status, is_online, is_available
) values (
  'c7000000-0000-0000-0000-000000000002', 'approved', false, false
);
insert into public.driver_availability (driver_id, state)
values ('c7000000-0000-0000-0000-000000000002', 'offline');
insert into public.vehicles (
  id, driver_id, vehicle_type_code, make, model, color,
  registration_plate, seat_capacity, is_active
) values (
  'c7100000-0000-0000-0000-000000000001',
  'c7000000-0000-0000-0000-000000000002',
  'economy', 'Toyota', 'Camry', 'White', 'RDX 017', 4, true
);
select public.backend_create_pricing_configuration(
  'economy', 500, 300, 50, 200, 1000, 50, true
);

insert into public.booking_requests (
  id, rider_id, pickup, destination, vehicle_type_code, payment_method
)
select
  ('c7200000-0000-0000-0000-' || lpad(sequence_number::text, 12, '0'))::uuid,
  'c7000000-0000-0000-0000-000000000001',
  jsonb_build_object('latitude', 31.90 + sequence_number / 100.0, 'longitude', 35.90),
  jsonb_build_object('latitude', 31.99, 'longitude', 35.99 - sequence_number / 100.0),
  'economy',
  case when sequence_number in (2, 4, 5) then 'card'::public.payment_method
    else 'cash'::public.payment_method end
from generate_series(1, 8) as sequence_number;

insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination,
  route_distance_meters, route_duration_seconds, vehicle_type_code,
  breakdown, fixed_fare_fils, pricing_configuration_id,
  pricing_version, quote_version, locked_at
)
select
  ('c7300000-0000-0000-0000-' || lpad(sequence_number::text, 12, '0'))::uuid,
  booking.id, booking.rider_id, 'locked', booking.pickup, booking.destination,
  2000, 600, 'economy', '{"fixed_fare_fils":2000}', 2000,
  (select id from public.pricing_configurations where is_active),
  1, 1, now()
from generate_series(1, 8) as sequence_number
join public.booking_requests as booking
  on booking.id = ('c7200000-0000-0000-0000-' || lpad(sequence_number::text, 12, '0'))::uuid;

update public.booking_requests as booking
set fare_quote_id = ('c7300000-0000-0000-0000-' || right(booking.id::text, 12))::uuid
where booking.rider_id = 'c7000000-0000-0000-0000-000000000001';
update public.booking_requests set status = 'confirmed', confirmed_at = now()
where rider_id = 'c7000000-0000-0000-0000-000000000001';
update public.booking_requests set status = 'searching', searching_at = now()
where rider_id = 'c7000000-0000-0000-0000-000000000001';

create or replace function pg_temp.as_user(subject_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', subject_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end;
$$;

create or replace function pg_temp.assign_trip(sequence_number integer)
returns uuid language plpgsql as $$
declare
  booking_id uuid := ('c7200000-0000-0000-0000-' || lpad(sequence_number::text, 12, '0'))::uuid;
  quote_id uuid := ('c7300000-0000-0000-0000-' || lpad(sequence_number::text, 12, '0'))::uuid;
  offer_id uuid := ('c7400000-0000-0000-0000-' || lpad(sequence_number::text, 12, '0'))::uuid;
  result jsonb;
begin
  update public.driver_availability
  set state = 'available',
      vehicle_id = 'c7100000-0000-0000-0000-000000000001',
      reserved_booking_request_id = null,
      active_trip_id = null
  where driver_id = 'c7000000-0000-0000-0000-000000000002';
  insert into public.driver_match_offers (
    id, booking_request_id, fare_quote_id, driver_id, vehicle_id,
    radius_meters, expires_at
  ) values (
    offer_id, booking_id, quote_id,
    'c7000000-0000-0000-0000-000000000002',
    'c7100000-0000-0000-0000-000000000001',
    3000, now() + interval '15 seconds'
  );
  perform pg_temp.as_user('c7000000-0000-0000-0000-000000000002');
  result := public.driver_transition_trip(
    offer_id, 'accepted', 1, '017-assign-' || sequence_number
  );
  return (result ->> 'trip_id')::uuid;
end;
$$;

create or replace function pg_temp.driver_transition(
  target_trip_id uuid, next_status public.trip_status,
  expected_version integer, command_key text
)
returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user('c7000000-0000-0000-0000-000000000002');
  return public.driver_transition_trip(
    target_trip_id, next_status, expected_version, command_key
  );
end;
$$;

create temporary table test_trips (
  sequence_number integer primary key,
  trip_id uuid not null unique
);

insert into test_trips values (1, pg_temp.assign_trip(1));
select is(
  (select count(*) from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 1)),
  1::bigint,
  'Trip assignment atomically creates exactly one Payment'
);
select is(
  (select public.backend_create_payment(
    (select trip_id from test_trips where sequence_number = 1)
  )).id,
  (select id from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 1)),
  'Payment creation replay returns the canonical Payment'
);

select pg_temp.driver_transition(
  (select trip_id from test_trips where sequence_number = 1),
  'driverArriving', 1, '017-cash-arriving'
);
select pg_temp.driver_transition(
  (select trip_id from test_trips where sequence_number = 1),
  'driverArrived', 2, '017-cash-arrived'
);
select pg_temp.driver_transition(
  (select trip_id from test_trips where sequence_number = 1),
  'inProgress', 3, '017-cash-progress'
);
select pg_temp.as_user('c7000000-0000-0000-0000-000000000001');
select public.rider_create_trip_change_request(
  (select trip_id from test_trips where sequence_number = 1), 4,
  '{"latitude":31.97,"longitude":35.96}', '[]', 'Unresolved test'
);
select pg_temp.driver_transition(
  (select trip_id from test_trips where sequence_number = 1),
  'completed', 4, '017-cash-complete'
);
select is(
  (select cash_status::text from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 1)),
  'paid',
  'Cash completion atomically settles the Payment'
);
select is(
  (select count(*) from public.receipts
   where trip_id = (select trip_id from test_trips where sequence_number = 1)),
  1::bigint,
  'Cash completion atomically issues one Receipt'
);
select is(
  (select status::text from public.trip_change_requests
   where trip_id = (select trip_id from test_trips where sequence_number = 1)),
  'cancelled',
  'Cash completion cancels unresolved unapproved changes'
);
select lives_ok(
  format(
    $$select pg_temp.driver_transition(%L, 'completed', 5, '017-cash-complete-replay')$$,
    (select trip_id from test_trips where sequence_number = 1)
  ),
  'Cash completion replay is idempotent'
);
select is(
  (select count(*) from public.receipts
   where trip_id = (select trip_id from test_trips where sequence_number = 1)),
  1::bigint,
  'Cash completion replay cannot duplicate the Receipt'
);

insert into test_trips values (2, pg_temp.assign_trip(2));
select throws_ok(
  format(
    $$select pg_temp.driver_transition(%L, 'driverArriving', 1, '017-card-denied')$$,
    (select trip_id from test_trips where sequence_number = 2)
  ),
  '55000',
  'Card Trip progression requires a verified authorized Payment.',
  'Card progression is denied before verified authorization'
);

select public.backend_record_payment_attempt(
  (select id from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 2)),
  'initialAuthorization', 2000, '017-card-auth', 'provider'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '017-card-auth'),
  'succeeded', '017-provider-auth'
);
select public.backend_transition_payment(
  (select id from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 2)),
  1, null, 'cardPaymentAuthorized'
);
select lives_ok(
  format(
    $$select pg_temp.driver_transition(%L, 'driverArriving', 1, '017-card-arriving')$$,
    (select trip_id from test_trips where sequence_number = 2)
  ),
  'Card progression succeeds after verified authorization'
);
select pg_temp.driver_transition(
  (select trip_id from test_trips where sequence_number = 2),
  'driverArrived', 2, '017-card-arrived'
);
select pg_temp.driver_transition(
  (select trip_id from test_trips where sequence_number = 2),
  'inProgress', 3, '017-card-progress'
);
select pg_temp.driver_transition(
  (select trip_id from test_trips where sequence_number = 2),
  'completed', 4, '017-card-complete'
);
select is(
  (select card_status::text from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 2)),
  'cardPaymentAuthorized',
  'Card Trip completion does not fabricate Capture settlement'
);
select is(
  (select count(*) from public.receipts
   where trip_id = (select trip_id from test_trips where sequence_number = 2)),
  0::bigint,
  'Card Trip completion does not fabricate a paid Receipt'
);

insert into test_trips values (3, pg_temp.assign_trip(3));
select pg_temp.as_user('c7000000-0000-0000-0000-000000000001');
select public.rider_cancel_trip(
  (select trip_id from test_trips where sequence_number = 3), 1, 'changed_mind'
);
select is(
  (select cash_status::text from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 3)),
  'cancelled',
  'Rider cancellation atomically cancels a Cash Payment'
);

insert into test_trips values (4, pg_temp.assign_trip(4));
select pg_temp.as_user('c7000000-0000-0000-0000-000000000001');
select public.rider_cancel_trip(
  (select trip_id from test_trips where sequence_number = 4), 1, 'changed_mind'
);
select is(
  (select card_status::text from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 4)),
  'paymentCancelled',
  'Rider cancellation atomically cancels an unauthorised Card Payment'
);

insert into test_trips values (5, pg_temp.assign_trip(5));
select public.backend_record_payment_attempt(
  (select id from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 5)),
  'initialAuthorization', 2000, '017-cancel-auth', 'provider'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '017-cancel-auth'),
  'succeeded', '017-cancel-provider-auth'
);
select public.backend_transition_payment(
  (select id from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 5)),
  1, null, 'cardPaymentAuthorized'
);
select pg_temp.as_user('c7000000-0000-0000-0000-000000000001');
select throws_ok(
  format(
    $$select public.rider_cancel_trip(%L, 1, 'changed_mind')$$,
    (select trip_id from test_trips where sequence_number = 5)
  ),
  '55000',
  'Card Payment requires a verified current-cycle void before cancellation.',
  'Authorized Card cancellation fails closed pending provider reconciliation'
);
select is(
  (select status::text from public.trips
   where id = (select trip_id from test_trips where sequence_number = 5)),
  'accepted',
  'Failed Card cancellation rolls back the Trip transition'
);
select public.backend_record_payment_attempt(
  (select id from public.payments
    where trip_id = (select trip_id from test_trips where sequence_number = 5)),
  'voidAuthorization', 2000, '017-cancel-void', 'provider'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '017-cancel-void'),
  'succeeded', '017-cancel-provider-void'
);
select pg_temp.as_user('c7000000-0000-0000-0000-000000000001');
select lives_ok(
  format(
    $$select public.rider_cancel_trip(%L, 1, 'changed_mind')$$,
    (select trip_id from test_trips where sequence_number = 5)
  ),
  'Card Trip cancellation succeeds after verified provider release'
);

insert into test_trips values (6, pg_temp.assign_trip(6));
select pg_temp.as_user('c7000000-0000-0000-0000-000000000003');
select public.admin_terminate_trip(
  (select trip_id from test_trips where sequence_number = 6),
  1, 'cancelledByAdmin', 'safety_review'
);
select is(
  (select cash_status::text from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 6)),
  'cancelled',
  'Admin termination atomically reconciles the Cash Payment'
);

insert into public.payments (
  booking_request_id, trip_id, rider_id, method, fare_quote_id,
  authorized_amount_fils, final_amount_fils, currency, cash_status
) values (
  'c7200000-0000-0000-0000-000000000007', null,
  'c7000000-0000-0000-0000-000000000001', 'cash',
  'c7300000-0000-0000-0000-000000000007', 2000, 2000, 'JOD',
  'cashSelected'
);
select throws_ok(
  $$select pg_temp.assign_trip(7)$$,
  '55000',
  'Payment must reconcile with its locked FareQuote and Trip.',
  'Assignment fails closed when the canonical Payment conflicts'
);
select is(
  (select count(*) from public.trips
   where booking_request_id = 'c7200000-0000-0000-0000-000000000007'),
  0::bigint,
  'Payment creation failure rolls back Trip assignment'
);

insert into test_trips values (8, pg_temp.assign_trip(8));
select pg_temp.driver_transition(
  (select trip_id from test_trips where sequence_number = 8),
  'driverArriving', 1, '017-rollback-arriving'
);
select pg_temp.driver_transition(
  (select trip_id from test_trips where sequence_number = 8),
  'driverArrived', 2, '017-rollback-arrived'
);
select pg_temp.driver_transition(
  (select trip_id from test_trips where sequence_number = 8),
  'inProgress', 3, '017-rollback-progress'
);
create or replace function pg_temp.reject_receipt_insert()
returns trigger language plpgsql as $$
begin
  raise exception using errcode = 'XX000', message = 'Forced Receipt failure.';
end;
$$;
create trigger test_reject_receipt_insert
before insert on public.receipts
for each row execute function pg_temp.reject_receipt_insert();
select throws_ok(
  format(
    $$select pg_temp.driver_transition(%L, 'completed', 4, '017-rollback-complete')$$,
    (select trip_id from test_trips where sequence_number = 8)
  ),
  'XX000',
  'Forced Receipt failure.',
  'Receipt failure aborts the entire Cash completion command'
);
select is(
  (select status::text from public.trips
   where id = (select trip_id from test_trips where sequence_number = 8)),
  'inProgress',
  'Receipt failure rolls back Trip completion'
);
select is(
  (select cash_status::text from public.payments
   where trip_id = (select trip_id from test_trips where sequence_number = 8)),
  'cashSelected',
  'Receipt failure rolls back Cash settlement'
);
select is(
  (select count(*) from public.receipts
   where trip_id = (select trip_id from test_trips where sequence_number = 8)),
  0::bigint,
  'Receipt failure leaves no partial Receipt'
);
drop trigger test_reject_receipt_insert on public.receipts;

select ok(
  not has_function_privilege(
    'authenticated',
    'private.ensure_trip_payment(uuid)',
    'EXECUTE'
  ),
  'authenticated cannot execute private Payment reconciliation helpers'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.backend_transition_payment(uuid,integer,public.cash_payment_status,public.card_payment_status)',
    'EXECUTE'
  ),
  'service role retains trusted Payment transition access'
);

select * from finish();
rollback;
