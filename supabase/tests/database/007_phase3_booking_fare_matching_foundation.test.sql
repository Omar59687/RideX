begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-one@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Rider One"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'rider-two@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Rider Two"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'blocked-rider@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Blocked Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'driver-one-007@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver One"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000012', 'authenticated', 'authenticated', 'driver-two-007@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver Two"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000013', 'authenticated', 'authenticated', 'driver-three-007@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver Three"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000014', 'authenticated', 'authenticated', 'driver-four-007@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver Four"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000020', 'authenticated', 'authenticated', 'admin-007@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Admin"}', now(), now(), '', '', '', '');

update public.users
set role = 'driver'
where id between '40000000-0000-0000-0000-000000000011'
  and '40000000-0000-0000-0000-000000000014';
update public.users set role = 'admin' where id = '40000000-0000-0000-0000-000000000020';
update public.users set is_blocked = true where id = '40000000-0000-0000-0000-000000000003';
delete from public.rider_profiles
where user_id between '40000000-0000-0000-0000-000000000011'
  and '40000000-0000-0000-0000-000000000014'
  or user_id = '40000000-0000-0000-0000-000000000020';
insert into public.driver_profiles (user_id, approval_status, rejection_reason, is_online, is_available)
values
  ('40000000-0000-0000-0000-000000000011', 'approved', null, false, false),
  ('40000000-0000-0000-0000-000000000012', 'approved', null, false, false),
  ('40000000-0000-0000-0000-000000000013', 'approved', null, false, false),
  ('40000000-0000-0000-0000-000000000014', 'approved', null, false, false);
insert into public.vehicles (
  id, driver_id, vehicle_type_code, make, model, color,
  registration_plate, seat_capacity, is_active
) values
  ('41000000-0000-0000-0000-000000000011', '40000000-0000-0000-0000-000000000011', 'economy', 'Toyota', 'Camry', 'White', 'BK 011', 4, true),
  ('41000000-0000-0000-0000-000000000012', '40000000-0000-0000-0000-000000000012', 'economy', 'Toyota', 'Corolla', 'Black', 'BK 012', 4, true),
  ('41000000-0000-0000-0000-000000000013', '40000000-0000-0000-0000-000000000013', 'economy', 'Kia', 'Cerato', 'Blue', 'BK 013', 4, true),
  ('41000000-0000-0000-0000-000000000014', '40000000-0000-0000-0000-000000000014', 'economy', 'Hyundai', 'Elantra', 'Silver', 'BK 014', 4, true);
insert into public.driver_availability (driver_id, state, vehicle_id)
values
  ('40000000-0000-0000-0000-000000000011', 'available', '41000000-0000-0000-0000-000000000011'),
  ('40000000-0000-0000-0000-000000000012', 'available', '41000000-0000-0000-0000-000000000012'),
  ('40000000-0000-0000-0000-000000000013', 'available', '41000000-0000-0000-0000-000000000013'),
  ('40000000-0000-0000-0000-000000000014', 'available', '41000000-0000-0000-0000-000000000014');

select has_type('public', 'driver_match_offer_status', 'matching offer status enum exists');
select is(enum_range(null::public.driver_match_offer_status)::text, '{offered,accepted,declined,expired,cancelled}', 'matching offer statuses are explicit');
select has_table('public', 'pricing_configurations', 'pricing configurations table exists');
select has_table('public', 'booking_requests', 'booking requests table exists');
select has_table('public', 'booking_stops', 'booking stops table exists');
select has_table('public', 'fare_quotes', 'fare quotes table exists');
select has_table('public', 'driver_match_offers', 'Driver match offers table exists');
select col_is_pk('public', 'pricing_configurations', 'id', 'pricing configurations use UUID primary keys');
select col_is_pk('public', 'booking_requests', 'id', 'bookings use UUID primary keys');
select col_is_pk('public', 'booking_stops', 'id', 'booking stops use UUID primary keys');
select col_is_pk('public', 'fare_quotes', 'id', 'fare quotes use UUID primary keys');
select col_is_pk('public', 'driver_match_offers', 'id', 'matching offers use UUID primary keys');
select has_fk('public', 'booking_requests', 'bookings reference Rider profiles and current FareQuotes');
select has_fk('public', 'booking_stops', 'stops reference bookings');
select has_fk('public', 'fare_quotes', 'quotes reference booking, Rider, pricing, and prior quotes');
select has_fk('public', 'driver_match_offers', 'offers reference booking, quote, Driver, and Vehicle');
select has_index('public', 'pricing_configurations', 'pricing_configurations_one_active_per_vehicle_idx', 'one active pricing configuration is enforced');
select has_index('public', 'fare_quotes', 'fare_quotes_one_active_locked_per_booking_idx', 'one active locked quote is enforced');
select has_index('public', 'driver_match_offers', 'driver_match_offers_booking_status_idx', 'matching offer lifecycle index exists');
select ok(exists (select 1 from pg_constraint where conname = 'booking_stops_sequence_bounded'), 'stop sequence is limited to three');
select ok(exists (select 1 from pg_trigger where tgname = 'booking_stops_contiguous' and tgdeferrable), 'contiguous stops use a deferred aggregate constraint');
select ok(exists (select 1 from pg_constraint where conname = 'fare_quotes_calculated_expiry_exact'), 'calculated quote expiry is constrained');
select ok(exists (select 1 from pg_constraint where conname = 'driver_match_offers_expiry_exact'), 'matching offer expiry is constrained');
select ok((select relrowsecurity from pg_class where oid = 'public.pricing_configurations'::regclass), 'pricing configurations have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.booking_requests'::regclass), 'booking requests have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.booking_stops'::regclass), 'booking stops have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.fare_quotes'::regclass), 'fare quotes have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.driver_match_offers'::regclass), 'matching offers have RLS enabled');
select throws_ok($$select 'premium'::public.vehicle_type_code$$, '22P02', null, 'unsupported vehicle values are rejected');
select throws_ok($$select 'wallet'::public.payment_method$$, '22P02', null, 'unsupported payment values are rejected');

select lives_ok(
  $$select public.backend_create_pricing_configuration('economy', 500, 300, 50, 200, 1000, 50, true)$$,
  'backend creates the approved integer-fils economy pricing configuration'
);
select is((select pricing_version from public.pricing_configurations where is_active), 1, 'first pricing version is one');
select ok((select base_fare_fils = 500 and minimum_fare_fils = 1000 and rounding_increment_fils = 50 from public.pricing_configurations where is_active), 'pricing values are stored in integer JOD fils');
select throws_ok(
  $$update public.pricing_configurations set base_fare_fils = 600 where is_active$$,
  '55000', 'Pricing configuration versions are immutable.',
  'published pricing values cannot be rewritten in place'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_create_booking_draft(
    '{"latitude":31.9500,"longitude":35.9300,"label":"Pickup"}',
    '{"latitude":31.9800,"longitude":35.9700,"label":"Destination"}',
    'economy', 'cash',
    '[{"location":{"latitude":31.951,"longitude":35.931}},{"location":{"latitude":31.952,"longitude":35.932}},{"location":{"latitude":31.953,"longitude":35.933}},{"location":{"latitude":31.954,"longitude":35.934}}]'
  )$$,
  '22023', 'Stops must contain at most three valid ordered locations.',
  'Rider cannot submit more than three stops'
);
select lives_ok(
  $$select public.rider_create_booking_draft(
    '{"latitude":31.9500,"longitude":35.9300,"label":"Pickup"}',
    '{"latitude":31.9800,"longitude":35.9700,"label":"Destination"}',
    'economy', 'cash',
    '[{"location":{"latitude":31.951,"longitude":35.931},"label":"First"},{"location":{"latitude":31.952,"longitude":35.932},"label":"Second"},{"location":{"latitude":31.953,"longitude":35.933},"label":"Third"}]'
  )$$,
  'Rider creates a valid three-stop draft'
);
select is((select count(*) from public.booking_requests), 1::bigint, 'Rider reads their own booking draft');
select is((select count(*) from public.booking_stops), 3::bigint, 'three stops are persisted');
select is((select sum(sequence)::integer from public.booking_stops), 6, 'stop sequence is contiguous from one');
select throws_ok(
  $$insert into public.booking_requests (rider_id, pickup, destination, vehicle_type_code, payment_method)
    values (auth.uid(), '{"latitude":31,"longitude":35}', '{"latitude":32,"longitude":36}', 'economy', 'cash')$$,
  '42501', null, 'direct client booking inserts are denied'
);
select throws_ok($$update public.booking_stops set label = 'Bypass'$$, '42501', null, 'direct client stop updates are denied');
select lives_ok(
  $$select public.rider_update_booking_draft(
    (select id from public.booking_requests), 1,
    '{"latitude":31.9500,"longitude":35.9300,"label":"Pickup"}',
    '{"latitude":31.9900,"longitude":35.9900,"label":"Updated destination"}',
    'economy', 'card',
    '[{"location":{"latitude":31.955,"longitude":35.935},"label":"First"},{"location":{"latitude":31.960,"longitude":35.940},"label":"Second","rider_note":"Gate B"}]'
  )$$,
  'Rider updates a draft through the trusted RPC'
);
select is((select version from public.booking_requests), 2, 'draft update advances the aggregate version once');
select is((select payment_method::text from public.booking_requests), 'card', 'draft update stores a supported payment method');
select is((select count(*) from public.booking_stops), 2::bigint, 'draft update atomically replaces ordered stops');
select throws_ok(
  $$select public.rider_update_booking_draft(
    (select id from public.booking_requests), 1,
    '{"latitude":31.9500,"longitude":35.9300}',
    '{"latitude":31.9900,"longitude":35.9900}',
    'economy', 'cash', '[]'
  )$$,
  '40001', 'Booking version is stale.', 'stale draft updates are rejected'
);
select throws_ok(
  $$select public.backend_calculate_fare_quote((select id from public.booking_requests), 2, 2000, 600, null)$$,
  '42501', null, 'authenticated clients cannot execute backend fare calculation'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.booking_requests), 0::bigint, 'another Rider cannot read the booking');
select throws_ok(
  $$select public.rider_update_booking_draft(
    (select id from public.booking_requests where true), 2,
    '{"latitude":31,"longitude":35}', '{"latitude":32,"longitude":36}',
    'economy', 'cash', '[]'
  )$$,
  'P0002', 'Booking draft was not found for this Rider.', 'another Rider cannot mutate the booking'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_create_booking_draft(
    '{"latitude":31,"longitude":35}', '{"latitude":32,"longitude":36}',
    'economy', 'cash', '[]'
  )$$,
  '42501', 'Only a non-blocked Rider can manage bookings.', 'blocked Rider cannot create a booking'
);
reset role;

select lives_ok(
  $$select public.backend_calculate_fare_quote(
    (select id from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'),
    2, 2000, 600, 'route-v1'
  )$$,
  'backend calculates a FareQuote from the booking snapshot'
);
select is((select fixed_fare_fils from public.fare_quotes where quote_version = 1), 2000, 'approved deterministic formula produces 2000 fils');
select is((select currency from public.fare_quotes where quote_version = 1), 'JOD', 'FareQuote currency is JOD');
select is((select expires_at - created_at from public.fare_quotes where quote_version = 1), interval '10 minutes', 'calculated quote expires in exactly ten minutes');
select is((select jsonb_array_length(ordered_stops) from public.fare_quotes where quote_version = 1), 2, 'FareQuote snapshots ordered stops');
select ok((select (breakdown ->> 'fixed_fare_fils')::integer = fixed_fare_fils from public.fare_quotes where quote_version = 1), 'FareQuote breakdown reconciles to fixed fare');
select lives_ok(
  $$select public.backend_calculate_fare_quote(
    (select id from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'),
    2, 1000, 60, 'route-v2'
  )$$,
  'backend creates a monotonically versioned replacement quote'
);
select is((select status::text from public.fare_quotes where quote_version = 1), 'superseded', 'prior calculated quote becomes superseded');
select is((select max(quote_version) from public.fare_quotes), 2, 'quote versions are monotonic per booking');
select throws_ok(
  $$select public.backend_lock_fare_quote((select id from public.fare_quotes where quote_version = 1), 2, 1)$$,
  '55000', 'Only an unexpired calculated FareQuote can be locked.', 'superseded quotes cannot be locked'
);
select throws_ok(
  $$select public.backend_lock_fare_quote((select id from public.fare_quotes where quote_version = 2), 1, 2)$$,
  '40001', 'Booking version is stale.', 'quote locking rejects stale booking versions'
);
select throws_ok(
  $$select public.backend_lock_fare_quote((select id from public.fare_quotes where quote_version = 2), 2, 1)$$,
  '40001', 'FareQuote version is stale.', 'quote locking rejects stale quote versions'
);
select lives_ok(
  $$select public.backend_lock_fare_quote((select id from public.fare_quotes where quote_version = 2), 2, 2)$$,
  'backend locks the current unexpired quote'
);
select is((select status::text from public.fare_quotes where quote_version = 2), 'locked', 'current FareQuote is locked');
select is((select version from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'), 3, 'locking the quote advances the booking aggregate version');
select ok((select fare_quote_id = (select id from public.fare_quotes where quote_version = 2) from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'), 'booking references its locked FareQuote');
select throws_ok($$update public.fare_quotes set fixed_fare_fils = fixed_fare_fils + 50 where quote_version = 2$$, '55000', 'FareQuote pricing and route snapshots are immutable.', 'FareQuote amount is immutable');

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_confirm_booking((select id from public.booking_requests), 2, 'confirm-stale')$$,
  '40001', 'Booking version is stale.', 'confirmation rejects a stale booking aggregate version'
);
select lives_ok(
  $$select public.rider_confirm_booking((select id from public.booking_requests), 3, 'confirm-main')$$,
  'Rider confirms a booking with its locked quote'
);
select is((select status::text from public.booking_requests), 'confirmed', 'booking becomes confirmed');
select is((select version from public.booking_requests), 4, 'confirmation advances the aggregate version');
select is(
  (select public.rider_confirm_booking((select id from public.booking_requests), 3, 'confirm-main')),
  jsonb_build_object('booking_request_id', (select id from public.booking_requests), 'status', 'confirmed'),
  'matching confirmation replay returns the canonical result despite the stale original version'
);
select is(
  (select public.rider_confirm_booking((select id from public.booking_requests), 4, 'confirm-main') ->> 'error'),
  'idempotency_payload_mismatch',
  'confirmation key reuse with a different payload fails closed'
);
select throws_ok(
  $$select public.rider_update_booking_draft(
    (select id from public.booking_requests), 4,
    '{"latitude":31,"longitude":35}', '{"latitude":32,"longitude":36}',
    'economy', 'cash', '[]'
  )$$,
  '55000', 'Only a draft booking can be updated.', 'confirmed booking inputs cannot be changed through the Rider RPC'
);
select throws_ok($$update public.booking_stops set label = 'Changed'$$, '42501', null, 'confirmed stops cannot be directly changed by clients');
reset role;
select throws_ok(
  $$update public.booking_requests
    set destination = '{"latitude":32,"longitude":36}'
    where rider_id = '40000000-0000-0000-0000-000000000001'$$,
  '55000', 'Confirmed booking inputs are immutable.', 'confirmed inputs remain immutable for trusted table writers'
);
select throws_ok(
  $$delete from public.booking_stops
    where booking_request_id = (select id from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001')$$,
  '55000', 'Confirmed booking stops are immutable.', 'confirmed stop snapshots remain immutable for trusted writers'
);

select lives_ok(
  $$select public.backend_create_driver_match_offer(
    (select id from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'),
    '40000000-0000-0000-0000-000000000011', '41000000-0000-0000-0000-000000000011', 3000, 4
  )$$,
  'backend creates the first matching record without executing a match'
);
select is((select status::text from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'), 'searching', 'first offer starts the matching window');
select is((select version from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'), 5, 'starting matching advances the booking aggregate version');
select is((select expires_at - offered_at from public.driver_match_offers where driver_id = '40000000-0000-0000-0000-000000000011'), interval '15 seconds', 'matching offer expires in exactly fifteen seconds');
select throws_ok(
  $$select public.backend_create_driver_match_offer(
    (select id from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'),
    '40000000-0000-0000-0000-000000000011', '41000000-0000-0000-0000-000000000011', 3000, 5
  )$$,
  '23505', null, 'a Driver receives at most one offer per booking'
);
select lives_ok(
  $$select public.backend_create_driver_match_offer(
    (select id from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'),
    '40000000-0000-0000-0000-000000000012', '41000000-0000-0000-0000-000000000012', 5000, 5
  )$$,
  'backend creates a second active offer'
);
select lives_ok(
  $$select public.backend_create_driver_match_offer(
    (select id from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'),
    '40000000-0000-0000-0000-000000000013', '41000000-0000-0000-0000-000000000013', 8000, 5
  )$$,
  'backend creates a third active offer'
);
select throws_ok(
  $$select public.backend_create_driver_match_offer(
    (select id from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'),
    '40000000-0000-0000-0000-000000000014', '41000000-0000-0000-0000-000000000014', 8000, 5
  )$$,
  '54000', 'A booking can have at most three active matching offers.', 'matching foundation limits active offers to three'
);
select throws_ok(
  $$select public.backend_create_driver_match_offer(
    (select id from public.booking_requests where rider_id = '40000000-0000-0000-0000-000000000001'),
    '40000000-0000-0000-0000-000000000014', '41000000-0000-0000-0000-000000000014', 4000, 5
  )$$,
  '22023', 'Matching offer inputs are invalid.', 'unsupported matching radii are rejected'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000011', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.booking_requests), 1::bigint, 'offered Driver can read the authorized booking');
select is((select count(*) from public.booking_stops), 2::bigint, 'offered Driver can read the authorized stops');
select is((select count(*) from public.fare_quotes), 2::bigint, 'offered Driver can read the authorized FareQuotes');
select is((select count(*) from public.driver_match_offers), 1::bigint, 'Driver reads only their own offer');
select throws_ok($$update public.driver_match_offers set status = 'accepted', responded_at = now()$$, '42501', null, 'Driver cannot directly accept or mutate an offer');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000014', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.booking_requests), 0::bigint, 'unoffered Driver cannot read the booking');
select is((select count(*) from public.driver_match_offers), 0::bigint, 'unoffered Driver cannot read matching offers');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.driver_match_offers), 3::bigint, 'Rider reads matching status records for their booking');
select lives_ok(
  $$select public.rider_cancel_booking((select id from public.booking_requests), 5, 'rider_changed_mind')$$,
  'Rider cancels a searching booking with a reason'
);
select is((select status::text from public.booking_requests), 'cancelled', 'searching booking becomes cancelled');
select is((select version from public.booking_requests), 6, 'cancellation advances the booking aggregate version');
select is((select count(*) from public.driver_match_offers where status = 'cancelled'), 3::bigint, 'cancellation closes active matching offers');
select lives_ok(
  $$select public.rider_cancel_booking((select id from public.booking_requests), 5, 'rider_changed_mind')$$,
  'repeated booking cancellation is idempotent'
);
reset role;

update public.users set is_blocked = true where id = '40000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.booking_requests), 0::bigint, 'blocked Rider loses booking read access');
select is((select count(*) from public.fare_quotes), 0::bigint, 'blocked Rider loses FareQuote read access');
select throws_ok(
  $$select public.rider_cancel_booking('00000000-0000-0000-0000-000000000000', 1, null)$$,
  '42501', 'Only a non-blocked Rider can manage bookings.', 'blocked Rider is denied by command RPCs'
);
reset role;
update public.users set is_blocked = false where id = '40000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000020', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.booking_requests), 1::bigint, 'non-blocked Admin has restricted booking read access');
select is((select count(*) from public.driver_match_offers), 3::bigint, 'non-blocked Admin has restricted matching-offer read access');
reset role;

set local role anon;
select throws_ok(
  $$select public.rider_create_booking_draft(
    '{"latitude":31,"longitude":35}', '{"latitude":32,"longitude":36}',
    'economy', 'cash', '[]'
  )$$,
  '42501', null, 'anonymous callers cannot execute Rider booking RPCs'
);
reset role;

select ok(has_function_privilege('authenticated', 'public.rider_create_booking_draft(jsonb,jsonb,public.vehicle_type_code,public.payment_method,jsonb)', 'EXECUTE'), 'authenticated can reach the guarded Rider create RPC');
select ok(not has_function_privilege('anon', 'public.rider_create_booking_draft(jsonb,jsonb,public.vehicle_type_code,public.payment_method,jsonb)', 'EXECUTE'), 'anonymous cannot execute Rider booking RPCs');
select ok(not has_function_privilege('authenticated', 'public.backend_calculate_fare_quote(uuid,integer,integer,integer,text)', 'EXECUTE'), 'authenticated cannot execute backend fare RPCs');
select ok(has_function_privilege('service_role', 'public.backend_calculate_fare_quote(uuid,integer,integer,integer,text)', 'EXECUTE'), 'service role can execute backend fare RPCs');
select ok(not has_table_privilege('authenticated', 'public.booking_requests', 'INSERT'), 'authenticated has no direct booking insert privilege');
select ok(not has_table_privilege('authenticated', 'public.fare_quotes', 'UPDATE'), 'authenticated has no direct FareQuote update privilege');
select ok(not has_table_privilege('authenticated', 'public.driver_match_offers', 'INSERT'), 'authenticated has no direct offer insert privilege');
select ok(has_table_privilege('authenticated', 'public.booking_requests', 'SELECT'), 'authenticated participant reads are explicitly granted');
select ok(not has_schema_privilege('authenticated', 'private', 'USAGE'), 'authenticated cannot use private authorization helpers');
select is(
  (
    select count(*)
    from pg_proc
    where oid in (
      'public.rider_create_booking_draft(jsonb,jsonb,public.vehicle_type_code,public.payment_method,jsonb)'::regprocedure,
      'public.rider_update_booking_draft(uuid,integer,jsonb,jsonb,public.vehicle_type_code,public.payment_method,jsonb)'::regprocedure,
      'public.rider_confirm_booking(uuid,integer,text)'::regprocedure,
      'public.rider_cancel_booking(uuid,integer,text)'::regprocedure,
      'public.backend_create_pricing_configuration(public.vehicle_type_code,integer,integer,integer,integer,integer,integer,boolean)'::regprocedure,
      'public.backend_calculate_fare_quote(uuid,integer,integer,integer,text)'::regprocedure,
      'public.backend_lock_fare_quote(uuid,integer,integer)'::regprocedure,
      'public.backend_create_driver_match_offer(uuid,uuid,uuid,integer,integer)'::regprocedure
    ) and prosecdef
  ),
  8::bigint,
  'all public Checkpoint 3.3 command functions are SECURITY DEFINER'
);
select is(
  (
    select count(*)
    from pg_proc
    where oid in (
      'public.rider_create_booking_draft(jsonb,jsonb,public.vehicle_type_code,public.payment_method,jsonb)'::regprocedure,
      'public.rider_update_booking_draft(uuid,integer,jsonb,jsonb,public.vehicle_type_code,public.payment_method,jsonb)'::regprocedure,
      'public.rider_confirm_booking(uuid,integer,text)'::regprocedure,
      'public.rider_cancel_booking(uuid,integer,text)'::regprocedure,
      'public.backend_create_pricing_configuration(public.vehicle_type_code,integer,integer,integer,integer,integer,integer,boolean)'::regprocedure,
      'public.backend_calculate_fare_quote(uuid,integer,integer,integer,text)'::regprocedure,
      'public.backend_lock_fare_quote(uuid,integer,integer)'::regprocedure,
      'public.backend_create_driver_match_offer(uuid,uuid,uuid,integer,integer)'::regprocedure
    ) and array_to_string(proconfig, ',') in ('search_path=""', 'search_path=')
  ),
  8::bigint,
  'all public Checkpoint 3.3 command functions have empty search paths'
);
select is((select count(*) from public.audit_records where action = 'booking.confirmed'), 1::bigint, 'booking confirmation is audited once despite replay');
select is((select count(*) from public.audit_records where action = 'booking.cancelled'), 1::bigint, 'booking cancellation is audited once despite replay');
select is((select count(*) from public.audit_records where action = 'command.idempotency_payload_mismatch' and actor_user_id = '40000000-0000-0000-0000-000000000001'), 1::bigint, 'confirmation idempotency mismatch is audited');

select * from finish();
rollback;
