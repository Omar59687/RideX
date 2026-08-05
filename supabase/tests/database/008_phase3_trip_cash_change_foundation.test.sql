begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '50000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'trip-rider@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Trip Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '50000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'other-rider@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Other Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '50000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'blocked-rider-008@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Blocked Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '50000000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'trip-driver-one@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Trip Driver One"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '50000000-0000-0000-0000-000000000012', 'authenticated', 'authenticated', 'trip-driver-two@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Trip Driver Two"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '50000000-0000-0000-0000-000000000020', 'authenticated', 'authenticated', 'trip-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Trip Admin"}', now(), now(), '', '', '', '');

update public.users set role = 'driver'
where id in ('50000000-0000-0000-0000-000000000011', '50000000-0000-0000-0000-000000000012');
update public.users set role = 'admin' where id = '50000000-0000-0000-0000-000000000020';
update public.users set is_blocked = true where id = '50000000-0000-0000-0000-000000000003';
delete from public.rider_profiles where user_id in (
  '50000000-0000-0000-0000-000000000011',
  '50000000-0000-0000-0000-000000000012',
  '50000000-0000-0000-0000-000000000020'
);
insert into public.driver_profiles (user_id, approval_status, rejection_reason, is_online, is_available)
values
  ('50000000-0000-0000-0000-000000000011', 'approved', null, false, false),
  ('50000000-0000-0000-0000-000000000012', 'approved', null, false, false);
insert into public.vehicles (
  id, driver_id, vehicle_type_code, make, model, color,
  registration_plate, seat_capacity, is_active
) values
  ('51000000-0000-0000-0000-000000000011', '50000000-0000-0000-0000-000000000011', 'economy', 'Toyota', 'Camry', 'White', 'TR 011', 4, true),
  ('51000000-0000-0000-0000-000000000012', '50000000-0000-0000-0000-000000000012', 'economy', 'Toyota', 'Corolla', 'Black', 'TR 012', 4, true);
insert into public.driver_availability (driver_id, state, vehicle_id)
values
  ('50000000-0000-0000-0000-000000000011', 'available', '51000000-0000-0000-0000-000000000011'),
  ('50000000-0000-0000-0000-000000000012', 'available', '51000000-0000-0000-0000-000000000012');
select public.backend_create_pricing_configuration('economy', 500, 300, 50, 200, 1000, 50, true);

select has_type('public', 'fare_adjustment_status', 'fare adjustment status enum exists');
select has_table('public', 'trips', 'Trips table exists');
select has_table('public', 'trip_stops', 'Trip stops table exists');
select has_table('public', 'trip_status_events', 'Trip status events table exists');
select has_table('public', 'trip_change_requests', 'Trip change requests table exists');
select has_table('public', 'fare_adjustments', 'Fare adjustments table exists');
select col_is_pk('public', 'trips', 'id', 'Trips use UUID primary keys');
select col_is_pk('public', 'trip_stops', 'id', 'Trip stops use UUID primary keys');
select col_is_pk('public', 'trip_status_events', 'id', 'Trip events use UUID primary keys');
select col_is_pk('public', 'trip_change_requests', 'id', 'Trip changes use UUID primary keys');
select col_is_pk('public', 'fare_adjustments', 'id', 'Fare adjustments use UUID primary keys');
select has_index('public', 'trip_change_requests', 'trip_change_requests_one_unresolved_per_trip_idx', 'only one unresolved change is allowed');
select has_index('public', 'trip_status_events', 'trip_status_events_trip_occurred_idx', 'ordered Trip event index exists');
select ok(exists (select 1 from pg_constraint where conname = 'trip_stops_sequence_bounded'), 'Trip stops are limited to three');
select ok(exists (select 1 from pg_trigger where tgname = 'trip_stops_contiguous' and tgdeferrable), 'Trip stops have deferred contiguity enforcement');
select ok(exists (select 1 from pg_constraint where conname = 'driver_availability_active_trip_fk'), 'availability active Trip reference is constrained');
select ok((select relrowsecurity from pg_class where oid = 'public.trips'::regclass), 'Trips have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.trip_stops'::regclass), 'Trip stops have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.trip_status_events'::regclass), 'Trip events have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.trip_change_requests'::regclass), 'Trip changes have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.fare_adjustments'::regclass), 'Fare adjustments have RLS enabled');

-- Build Cash and Card bookings with immutable locked quote snapshots.
insert into public.booking_requests (
  id, rider_id, pickup, destination, vehicle_type_code, payment_method
) values
  ('52000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93,"label":"Cash pickup"}', '{"latitude":31.98,"longitude":35.97,"label":"Cash destination"}', 'economy', 'cash'),
  ('52000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000001', '{"latitude":31.94,"longitude":35.92,"label":"Card pickup"}', '{"latitude":31.99,"longitude":35.98,"label":"Card destination"}', 'economy', 'card');
insert into public.booking_stops (booking_request_id, sequence, location, label)
values ('52000000-0000-0000-0000-000000000001', 1, '{"latitude":31.96,"longitude":35.94}', 'Original stop');
insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination, ordered_stops,
  route_distance_meters, route_duration_seconds, vehicle_type_code, breakdown,
  fixed_fare_fils, pricing_configuration_id, pricing_version, quote_version, locked_at
) values
  ('53000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 'locked', '{"latitude":31.95,"longitude":35.93,"label":"Cash pickup"}', '{"latitude":31.98,"longitude":35.97,"label":"Cash destination"}', '[{"location":{"latitude":31.96,"longitude":35.94},"label":"Original stop"}]', 2000, 600, 'economy', '{"fixed_fare_fils":2000}', 2000, (select id from public.pricing_configurations where is_active), 1, 1, now()),
  ('53000000-0000-0000-0000-000000000002', '52000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000001', 'locked', '{"latitude":31.94,"longitude":35.92,"label":"Card pickup"}', '{"latitude":31.99,"longitude":35.98,"label":"Card destination"}', '[]', 3000, 900, 'economy', '{"fixed_fare_fils":2500}', 2500, (select id from public.pricing_configurations where is_active), 1, 1, now());
update public.booking_requests set fare_quote_id = case id
  when '52000000-0000-0000-0000-000000000001' then '53000000-0000-0000-0000-000000000001'::uuid
  else '53000000-0000-0000-0000-000000000002'::uuid end;
update public.booking_requests set status = 'confirmed', confirmed_at = now();
update public.booking_requests set status = 'searching', searching_at = now();
insert into public.driver_match_offers (
  id, booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters
) values
  ('54000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000011', '51000000-0000-0000-0000-000000000011', 3000),
  ('54000000-0000-0000-0000-000000000002', '52000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000012', '51000000-0000-0000-0000-000000000012', 3000);

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000011', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.driver_transition_trip('54000000-0000-0000-0000-000000000001', 'accepted', 2, 'accept-stale')$$,
  '40001', 'Matching offer version is stale.', 'stale offer acceptance is rejected'
);
select lives_ok(
  $$select public.driver_transition_trip('54000000-0000-0000-0000-000000000001', 'accepted', 1, 'accept-cash')$$,
  'Driver atomically accepts the live offer into a Trip'
);
select is((select count(*) from public.trips), 1::bigint, 'assigned Driver reads the created Trip');
select is((select status::text from public.trips), 'accepted', 'new Trip starts accepted');
select is((select payment_method::text from public.trips), 'cash', 'Trip snapshots booking payment method');
select is((select current_fare_fils from public.trips), 2000, 'Trip snapshots locked fixed fare');
select is((select count(*) from public.trip_stops), 1::bigint, 'Trip snapshots ordered booking stops');
select is((select state::text from public.driver_availability where driver_id = auth.uid()), 'onTrip', 'assignment atomically moves Driver on Trip');
select is((select count(*) from public.trip_status_events), 1::bigint, 'acceptance appends the first event');
select is((select sequence from public.trip_status_events), 1, 'first event sequence is one');
select is(
  (select public.driver_transition_trip('54000000-0000-0000-0000-000000000001', 'accepted', 1, 'accept-cash') ->> 'trip_id'),
  (select id::text from public.trips),
  'acceptance replay returns the canonical Trip'
);
select is((select count(*) from public.trips), 1::bigint, 'acceptance replay cannot duplicate a Trip');
select is(
  (select public.driver_transition_trip('54000000-0000-0000-0000-000000000001', 'accepted', 2, 'accept-cash') ->> 'error'),
  'idempotency_payload_mismatch', 'acceptance key reuse with a different payload fails closed'
);
select throws_ok($$insert into public.trip_status_events (trip_id, sequence, to_status) values ((select id from public.trips), 2, 'driverArriving')$$, '42501', null, 'direct event inserts are denied');
select throws_ok($$update public.trips set status = 'completed'$$, '42501', null, 'direct Trip updates are denied');
select lives_ok($$select public.driver_transition_trip((select id from public.trips), 'driverArriving', 1, 'cash-arriving')$$, 'Driver starts arriving');
select lives_ok($$select public.driver_transition_trip((select id from public.trips), 'driverArrived', 2, 'cash-arrived')$$, 'Driver records arrival');
select throws_ok($$select public.driver_transition_trip((select id from public.trips), 'completed', 2, 'cash-stale')$$, '40001', 'Trip version is stale.', 'stale lifecycle transition is rejected');
select lives_ok($$select public.driver_transition_trip((select id from public.trips), 'inProgress', 3, 'cash-start')$$, 'Driver starts the Cash Trip');
select throws_ok($$select public.driver_transition_trip((select id from public.trips), 'driverArrived', 4, 'cash-backward')$$, '55000', 'Invalid Trip status transition.', 'backward lifecycle transition is rejected');
reset role;

select is((select status::text from public.driver_match_offers where id = '54000000-0000-0000-0000-000000000002'), 'cancelled', 'first valid assignment atomically cancels competing offers');
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000012', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_transition_trip('54000000-0000-0000-0000-000000000002', 'accepted', 1, 'losing-race')$$, '40001', 'Matching offer version is stale.', 'losing assignment observes the winning atomic offer transition');
select is((select count(*) from public.trips), 0::bigint, 'unassigned Driver cannot read another Driver Trip');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.trips), 1::bigint, 'Rider reads own Trip');
select is((select count(*) from public.trip_status_events), 4::bigint, 'Rider reads correctly appended lifecycle events');
select is((select string_agg(sequence::text, ',' order by sequence) from public.trip_status_events), '1,2,3,4', 'event sequences remain contiguous');
select throws_ok(
  $$select public.rider_cancel_trip((select id from public.trips), 4, 'too_late')$$,
  '55000', 'The Rider can cancel only before the Trip starts.',
  'Rider cancellation is rejected after the Trip starts'
);
select throws_ok(
  $$select public.rider_create_trip_change_request((select id from public.trips), 3, '{"latitude":32.01,"longitude":36.01}', '[]', null)$$,
  '40001', 'Trip version is stale.', 'Cash change rejects a stale Trip version'
);
select lives_ok(
  $$select public.rider_create_trip_change_request(
    (select id from public.trips), 4,
    '{"latitude":32.01,"longitude":36.01,"label":"Changed destination"}',
    '[{"location":{"latitude":31.97,"longitude":35.95},"label":"Changed stop"}]',
    'Please add this stop'
  )$$, 'Rider creates an in-progress Cash change'
);
select throws_ok(
  $$select public.rider_create_trip_change_request(
    (select id from public.trips), 4, '{"latitude":32.02,"longitude":36.02}', '[]', null
  )$$, '23505', null, 'only one unresolved Cash change can exist per Trip'
);
select throws_ok(
  $$select public.rider_create_trip_change_request(
    (select id from public.trips), 4, '{"latitude":32.02,"longitude":36.02}',
    '[{"location":{"latitude":31.1,"longitude":35.1}},{"location":{"latitude":31.2,"longitude":35.2}},{"location":{"latitude":31.3,"longitude":35.3}},{"location":{"latitude":31.4,"longitude":35.4}}]', null
  )$$, '22023', 'Trip change route inputs are invalid.', 'Cash change preserves the maximum three stops invariant'
);
select throws_ok($$select public.backend_price_trip_change_request((select id from public.trip_change_requests), 1, 4000, 1200, 'changed-route')$$, '42501', null, 'Rider cannot execute backend Cash pricing');
reset role;

select lives_ok(
  $$select public.backend_price_trip_change_request((select id from public.trip_change_requests), 1, 4000, 1200, 'changed-route')$$,
  'backend prices the Cash route change'
);
select is((select status::text from public.trip_change_requests), 'awaitingRiderApproval', 'priced change awaits Rider approval');
select is((select previous_fare_fils from public.fare_adjustments), 2000, 'adjustment records the prior fare');
select is((select adjusted_fare_fils from public.fare_adjustments), 2900, 'backend uses deterministic integer-fils pricing');
select is((select adjustment_fils from public.fare_adjustments), 900, 'adjustment reconciles old and new fares');
select is((select count(*) from public.fare_adjustments), 1::bigint, 'pricing creates one adjustment');
select lives_ok($$select public.backend_price_trip_change_request((select id from public.trip_change_requests), 1, 4000, 1200, 'changed-route')$$, 'pricing replay is idempotent');
select is((select count(*) from public.fare_adjustments), 1::bigint, 'pricing replay cannot duplicate an adjustment');

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.rider_approve_trip_change_request((select id from public.trip_change_requests), 1, 4)$$, '40001', 'Trip change request version is stale.', 'approval rejects stale request version');
select lives_ok($$select public.rider_approve_trip_change_request((select id from public.trip_change_requests), 2, 4)$$, 'Rider approves the priced Cash change');
select lives_ok($$select public.rider_approve_trip_change_request((select id from public.trip_change_requests), 2, 4)$$, 'approval replay is idempotent');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000011', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.driver_transition_trip((select id from public.trips), 'completed', 4, 'complete-before-adjustment')$$, '55000', 'An approved fare adjustment must be applied before completion.', 'completion blocks an unapplied approved adjustment');
reset role;

select throws_ok($$select public.backend_apply_trip_fare_adjustment((select id from public.fare_adjustments), 1, 3)$$, '40001', 'Trip version is stale.', 'adjustment application rejects stale Trip version');
select lives_ok($$select public.backend_apply_trip_fare_adjustment((select id from public.fare_adjustments), 1, 4)$$, 'backend atomically applies approved Cash adjustment');
select is((select current_fare_fils from public.trips), 2900, 'Cash Trip current fare receives the adjustment');
select is((select destination ->> 'label' from public.trips), 'Changed destination', 'Cash Trip destination receives the approved route');
select is((select count(*) from public.trip_stops), 1::bigint, 'approved stops atomically replace prior stops');
select is((select status::text from public.fare_adjustments), 'applied', 'adjustment becomes applied');
select is((select status::text from public.trip_change_requests), 'applied', 'change request becomes applied');
select lives_ok($$select public.backend_apply_trip_fare_adjustment((select id from public.fare_adjustments), 1, 4)$$, 'applied adjustment replay is idempotent');
select is((select count(*) from public.fare_adjustments where status = 'applied'), 1::bigint, 'applied adjustment cannot be duplicated');

-- An unresolved request is cancelled when the Driver completes the Trip.
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.rider_create_trip_change_request((select id from public.trips), 5, '{"latitude":32.02,"longitude":36.02}', '[]', null)$$, 'Rider creates another unresolved Cash request');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000011', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.driver_transition_trip((select id from public.trips), 'completed', 5, 'cash-complete')$$, 'Driver completes Cash Trip after applied adjustment');
select is((select status::text from public.trips), 'completed', 'Cash Trip becomes completed');
select is((select state::text from public.driver_availability where driver_id = auth.uid()), 'offline', 'completion releases Driver availability');
select throws_ok($$select public.driver_transition_trip((select id from public.trips), 'cancelledByDriver', 6, 'terminal-change')$$, '55000', 'Terminal Trips are immutable.', 'terminal Trip cannot transition again');
select is((select count(*) from public.trip_status_events), 5::bigint, 'completion appends exactly one event');
reset role;
select is((select count(*) from public.trip_change_requests where status = 'cancelled'), 1::bigint, 'completion cancels unresolved Cash requests');
select throws_ok($$update public.trip_status_events set reason_code = 'rewritten' where sequence = 1$$, '55000', 'Trip status events are append-only.', 'trusted writers cannot rewrite events');
select throws_ok($$delete from public.trip_status_events where sequence = 1$$, '55000', 'Trip status events are append-only.', 'trusted writers cannot delete events');
select throws_ok($$update public.trips set destination = '{"latitude":31,"longitude":36}' where status = 'completed'$$, '55000', 'Terminal Trips are immutable.', 'terminal Trip snapshots cannot be changed');

-- Reuse Driver Two to prove Card route/fare immutability and Admin termination.
insert into public.driver_match_offers (
  id, booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters
) values (
  '54000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000002',
  '53000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000012',
  '51000000-0000-0000-0000-000000000012', 3000
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000012', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.driver_transition_trip('54000000-0000-0000-0000-000000000003', 'accepted', 1, 'accept-card')$$, 'Driver accepts Card Trip');
select throws_ok(
  $$select public.driver_transition_trip((select id from public.trips where payment_method = 'card'), 'driverArriving', 1, 'card-arriving-before-auth')$$,
  '55000', 'Card Trip progression requires a verified authorized Payment.',
  'Card Driver cannot start arriving before verified authorization'
);
reset role;
select public.backend_record_payment_attempt(
  (select id from public.payments where trip_id = (select id from public.trips where payment_method = 'card')),
  'initialAuthorization', 2500, '008-card-auth', 'provider'
);
select public.backend_complete_payment_attempt(
  (select id from public.payment_attempts where idempotency_key = '008-card-auth'),
  'succeeded', '008-card-provider-auth'
);
select public.backend_transition_payment(
  (select id from public.payments where trip_id = (select id from public.trips where payment_method = 'card')),
  1, null, 'cardPaymentAuthorized'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000012', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.driver_transition_trip((select id from public.trips where payment_method = 'card'), 'driverArriving', 1, 'card-arriving')$$, 'Card Driver starts arriving');
select lives_ok($$select public.driver_transition_trip((select id from public.trips where payment_method = 'card'), 'driverArrived', 2, 'card-arrived')$$, 'Card Driver arrives');
select lives_ok($$select public.driver_transition_trip((select id from public.trips where payment_method = 'card'), 'inProgress', 3, 'card-start')$$, 'Card Trip starts');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_create_trip_change_request(
    (select id from public.trips where payment_method = 'card'), 4,
    '{"latitude":32.03,"longitude":36.03}', '[]', null
  )$$, '55000', 'In-progress Trip changes are Cash-only.', 'Card Trips reject in-progress route changes'
);
reset role;
select throws_ok(
  $$update public.trips set current_fare_fils = current_fare_fils + 50 where payment_method = 'card'$$,
  '55000', 'Card Trip route and fare snapshots are fixed.', 'Card fare cannot be adjusted even by a trusted table writer'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000020', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.trips), 2::bigint, 'non-blocked Admin has restricted Trip read access');
select throws_ok(
  $$select public.admin_terminate_trip(
    (select id from public.trips where payment_method = 'card'), 4,
    'cancelledByAdmin', 'safety_exception'
  )$$,
  '55000',
  'Card Payment requires trusted provider reconciliation before cancellation.',
  'Admin Card termination fails closed before provider reconciliation'
);
select is(
  (select status::text from public.trips where payment_method = 'card'),
  'inProgress',
  'failed Admin Card termination leaves the Trip unchanged'
);
reset role;
select public.backend_transition_payment(
  (select id from public.payments where trip_id = (select id from public.trips where payment_method = 'card')),
  2, null, 'paymentCancelled'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000020', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok(
  $$select public.admin_terminate_trip(
    (select id from public.trips where payment_method = 'card'), 4,
    'cancelledByAdmin', 'safety_exception'
  )$$, 'Admin exceptionally terminates a nonterminal Trip without a partial charge'
);
select throws_ok(
  $$select public.admin_terminate_trip(
    (select id from public.trips where payment_method = 'card'), 5,
    'failed', 'again'
  )$$, '55000', 'A terminal Trip cannot be terminated again.', 'Admin cannot terminate an already terminal Trip'
);
reset role;
select is((select current_fare_fils from public.trips where payment_method = 'card'), 2500, 'Admin termination does not create a partial Card charge');
select is((select status::text from public.trips where payment_method = 'card'), 'cancelledByAdmin', 'Admin termination records the approved terminal state');

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.trips), 0::bigint, 'unrelated Rider cannot read Trips');
select is((select count(*) from public.trip_status_events), 0::bigint, 'unrelated Rider cannot read Trip events');
select is((select count(*) from public.fare_adjustments), 0::bigint, 'unrelated Rider cannot read fare adjustments');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.trips), 0::bigint, 'blocked Rider cannot read Trips');
select throws_ok($$select public.rider_cancel_trip('00000000-0000-0000-0000-000000000000', 1, 'blocked')$$, '42501', 'Only a non-blocked Rider can manage bookings.', 'blocked Rider cannot execute Trip commands');
reset role;

set local role anon;
select throws_ok($$select public.rider_cancel_trip('00000000-0000-0000-0000-000000000000', 1, 'anonymous')$$, '42501', null, 'anonymous callers cannot execute Rider Trip RPCs');
select throws_ok($$select public.driver_transition_trip('00000000-0000-0000-0000-000000000000', 'accepted', 1, 'anonymous')$$, '42501', null, 'anonymous callers cannot execute Driver Trip RPCs');
reset role;

select ok(has_function_privilege('authenticated', 'public.driver_transition_trip(uuid,public.trip_status,integer,text)', 'EXECUTE'), 'authenticated can reach guarded Driver Trip RPC');
select ok(not has_function_privilege('anon', 'public.driver_transition_trip(uuid,public.trip_status,integer,text)', 'EXECUTE'), 'anonymous cannot execute Driver Trip RPC');
select ok(not has_function_privilege('authenticated', 'public.backend_price_trip_change_request(uuid,integer,integer,integer,text)', 'EXECUTE'), 'authenticated cannot execute backend pricing');
select ok(has_function_privilege('service_role', 'public.backend_price_trip_change_request(uuid,integer,integer,integer,text)', 'EXECUTE'), 'service role can execute backend pricing');
select ok(not has_table_privilege('authenticated', 'public.trips', 'INSERT'), 'authenticated has no direct Trip insert privilege');
select ok(not has_table_privilege('authenticated', 'public.trip_change_requests', 'UPDATE'), 'authenticated has no direct change update privilege');
select ok(not has_table_privilege('authenticated', 'public.fare_adjustments', 'INSERT'), 'authenticated has no direct adjustment insert privilege');
select ok(has_table_privilege('authenticated', 'public.trips', 'SELECT'), 'participant Trip reads are explicitly granted');
select is(
  (select count(*) from pg_proc where oid in (
    'public.driver_transition_trip(uuid,public.trip_status,integer,text)'::regprocedure,
    'public.rider_cancel_trip(uuid,integer,text)'::regprocedure,
    'public.admin_terminate_trip(uuid,integer,public.trip_status,text)'::regprocedure,
    'public.rider_create_trip_change_request(uuid,integer,jsonb,jsonb,text)'::regprocedure,
    'public.rider_cancel_trip_change_request(uuid,integer)'::regprocedure,
    'public.rider_approve_trip_change_request(uuid,integer,integer)'::regprocedure,
    'public.backend_price_trip_change_request(uuid,integer,integer,integer,text)'::regprocedure,
    'public.backend_apply_trip_fare_adjustment(uuid,integer,integer)'::regprocedure
  ) and prosecdef),
  8::bigint, 'all public Checkpoint 3.4 command functions are SECURITY DEFINER'
);
select is(
  (select count(*) from pg_proc where oid in (
    'public.driver_transition_trip(uuid,public.trip_status,integer,text)'::regprocedure,
    'public.rider_cancel_trip(uuid,integer,text)'::regprocedure,
    'public.admin_terminate_trip(uuid,integer,public.trip_status,text)'::regprocedure,
    'public.rider_create_trip_change_request(uuid,integer,jsonb,jsonb,text)'::regprocedure,
    'public.rider_cancel_trip_change_request(uuid,integer)'::regprocedure,
    'public.rider_approve_trip_change_request(uuid,integer,integer)'::regprocedure,
    'public.backend_price_trip_change_request(uuid,integer,integer,integer,text)'::regprocedure,
    'public.backend_apply_trip_fare_adjustment(uuid,integer,integer)'::regprocedure
  ) and array_to_string(proconfig, ',') in ('search_path=""', 'search_path=')),
  8::bigint, 'all public Checkpoint 3.4 command functions have empty search paths'
);
select is((select count(*) from public.audit_records where action = 'trip.accepted'), 2::bigint, 'Trip acceptance is audited once per Trip despite replay');
select is((select count(*) from public.audit_records where action = 'trip.terminated_by_admin'), 1::bigint, 'Admin exceptional termination is audited');

select * from finish();
rollback;
