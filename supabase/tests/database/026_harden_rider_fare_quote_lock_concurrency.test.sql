-- Regression: rider draft mutation and rider quote lock serialize on the
-- booking row instead of deadlocking. Both paths lock the owned booking row
-- first (booking -> quote). The interleave race below reproduces the exact
-- historic deadlock cycle (holder pins the booking row, the real wrapper runs
-- concurrently, the holder then touches the quote row): with quote-first
-- locking Postgres reports 40P01, with booking-first locking the waiter simply
-- blocks and then succeeds once the holder rolls back. The two function-level
-- races document the deterministic version-stale outcomes when each contender
-- fully commits first. No outer transaction wrapper: dblink sessions cannot
-- see uncommitted fixtures.
create extension if not exists dblink with schema extensions;

select no_plan();

create or replace function pg_temp.wait_for_lock(target_pid integer)
returns boolean
language plpgsql
as $$
begin
  for attempt in 1..100 loop
    if exists (
      select 1
      from pg_catalog.pg_stat_activity
      where pid = target_pid
        and wait_event_type = 'Lock'
    ) then
      return true;
    end if;
    perform pg_catalog.pg_sleep(0.05);
  end loop;
  return false;
end;
$$;

create or replace function pg_temp.open_race(
  connection_name text,
  subject_id uuid
)
returns integer
language plpgsql
as $$
declare
  connection_info text;
  remote_pid integer;
begin
  connection_info := format(
    'host=db port=5432 dbname=%s user=%s password=%s',
    current_database(),
    current_user,
    current_user
  );

  perform extensions.dblink_connect(connection_name, connection_info);
  perform extensions.dblink_exec(
    connection_name,
    format('set request.jwt.claim.sub = %L', subject_id::text)
  );
  perform extensions.dblink_exec(
    connection_name,
    'set request.jwt.claim.role = ''authenticated'''
  );
  perform extensions.dblink_exec(connection_name, 'set statement_timeout = ''10s''');
  perform extensions.dblink_exec(connection_name, 'set lock_timeout = ''8s''');
  perform extensions.dblink_exec(
    connection_name,
    $capture$
      create or replace function pg_temp.capture(command text)
      returns table(ok boolean, error_state text, error_message text)
      language plpgsql
      as $body$
      begin
        execute command;
        return query select true, null::text, null::text;
      exception when others then
        return query select false, sqlstate::text, sqlerrm::text;
      end;
      $body$
    $capture$
  );

  select pid into remote_pid
  from extensions.dblink(connection_name, 'select pg_backend_pid()')
    as result(pid integer);
  return remote_pid;
end;
$$;

create or replace function pg_temp.close_race(
  first_connection text,
  second_connection text
)
returns void
language plpgsql
as $$
begin
  perform extensions.dblink_disconnect(first_connection);
  perform extensions.dblink_disconnect(second_connection);
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '26000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-026-concurrency@example.com', '', now(), '{}', '{"display_name":"Concurrency Rider"}', now(), now(), '', '', '', '');

insert into public.booking_requests (
  id, rider_id, pickup, destination, vehicle_type_code, payment_method
) values
  ('26100000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash'),
  ('26100000-0000-0000-0000-000000000002', '26000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash'),
  ('26100000-0000-0000-0000-000000000003', '26000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash');

insert into public.fare_quotes (
  id, booking_request_id, rider_id, pickup, destination,
  route_distance_meters, route_duration_seconds, vehicle_type_code,
  breakdown, fixed_fare_fils, pricing_configuration_id,
  pricing_version, quote_version, created_at, expires_at
) values
  ('26200000-0000-0000-0000-000000000001', '26100000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700, (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), 1, now(), now() + interval '10 minutes'),
  ('26200000-0000-0000-0000-000000000002', '26100000-0000-0000-0000-000000000002', '26000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700, (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), 1, now(), now() + interval '10 minutes'),
  ('26200000-0000-0000-0000-000000000003', '26100000-0000-0000-0000-000000000003', '26000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700, (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active), 1, now(), now() + interval '10 minutes');

create temporary table race_pids (connection_name text primary key, pid integer);
create temporary table race_results (
  case_name text,
  side text,
  ok boolean,
  error_state text,
  error_message text
);

-- True interleaving: a booking-first holder pins the booking row exactly as
-- rider_update_booking_draft does, the real rider_lock_fare_quote runs
-- concurrently, and the holder then invalidates the calculated quote exactly
-- as the draft does. Quote-first locking deadlocks here (40P01); booking-first
-- locking lets the holder reach the quote row while the wrapper only waits.
insert into race_pids values
  ('quote_lock_race_hold_a', pg_temp.open_race('quote_lock_race_hold_a', '26000000-0000-0000-0000-000000000001')),
  ('quote_lock_race_hold_b', pg_temp.open_race('quote_lock_race_hold_b', '26000000-0000-0000-0000-000000000001'));
select extensions.dblink_exec('quote_lock_race_hold_a', 'begin');
insert into race_results
select 'hold_interleave', 'booking_holder', result.*
from extensions.dblink(
  'quote_lock_race_hold_a',
  $remote$select * from pg_temp.capture(
    $command$select 1 from public.booking_requests where id = '26100000-0000-0000-0000-000000000003' and rider_id = '26000000-0000-0000-0000-000000000001' for update$command$
  )$remote$
) as result(ok boolean, error_state text, error_message text);
select extensions.dblink_send_query(
  'quote_lock_race_hold_b',
  $remote$select * from pg_temp.capture(
    $command$select public.rider_lock_fare_quote('26100000-0000-0000-0000-000000000003', '26200000-0000-0000-0000-000000000003', 1, 1)$command$
  )$remote$
);
select ok(
  pg_temp.wait_for_lock((select pid from race_pids where connection_name = 'quote_lock_race_hold_b')),
  'quote-lock session waits while the holder pins the booking row'
);
insert into race_results
select 'hold_interleave', 'quote_touch', result.*
from extensions.dblink(
  'quote_lock_race_hold_a',
  $remote$select * from pg_temp.capture(
    $command$update public.fare_quotes set status = 'superseded', superseded_at = now() where booking_request_id = '26100000-0000-0000-0000-000000000003' and status = 'calculated'$command$
  )$remote$
) as result(ok boolean, error_state text, error_message text);
select extensions.dblink_exec('quote_lock_race_hold_a', 'rollback');
insert into race_results
select 'hold_interleave', 'quote_lock', result.*
from extensions.dblink_get_result('quote_lock_race_hold_b')
  as result(ok boolean, error_state text, error_message text);
select ok((select ok from race_results where case_name = 'hold_interleave' and side = 'booking_holder'), 'holder pins the owned booking row');
select ok((select ok from race_results where case_name = 'hold_interleave' and side = 'quote_touch'), 'holder reaches the quote row without deadlocking the wrapper');
select ok((select ok from race_results where case_name = 'hold_interleave' and side = 'quote_lock'), 'quote lock succeeds after the holder rolls back');
select is((select status::text from public.fare_quotes where id = '26200000-0000-0000-0000-000000000003'), 'locked', 'interleaved race leaves the quote locked');
select is((select version from public.booking_requests where id = '26100000-0000-0000-0000-000000000003'), 2, 'interleaved race advances the booking version once');
select is((select fare_quote_id from public.booking_requests where id = '26100000-0000-0000-0000-000000000003'), '26200000-0000-0000-0000-000000000003'::uuid, 'interleaved race links the booking to the locked quote');
select pg_temp.close_race('quote_lock_race_hold_a', 'quote_lock_race_hold_b');

-- Draft mutation commits first while holding the booking row; the quote lock
-- waits, then fails deterministically version-stale. Documents the
-- serialization outcome for this order.
insert into race_pids values
  ('quote_lock_race_draft_a', pg_temp.open_race('quote_lock_race_draft_a', '26000000-0000-0000-0000-000000000001')),
  ('quote_lock_race_draft_b', pg_temp.open_race('quote_lock_race_draft_b', '26000000-0000-0000-0000-000000000001'));
select extensions.dblink_exec('quote_lock_race_draft_a', 'begin');
insert into race_results
select 'draft_first', 'draft_update', result.*
from extensions.dblink(
  'quote_lock_race_draft_a',
  $remote$select * from pg_temp.capture(
    $command$select public.rider_update_booking_draft('26100000-0000-0000-0000-000000000001', 1, '{"latitude":31.91,"longitude":35.91}'::jsonb, '{"latitude":31.99,"longitude":35.99}'::jsonb, 'economy'::public.vehicle_type_code, 'cash'::public.payment_method, '[]'::jsonb)$command$
  )$remote$
) as result(ok boolean, error_state text, error_message text);
select extensions.dblink_send_query(
  'quote_lock_race_draft_b',
  $remote$select * from pg_temp.capture(
    $command$select public.rider_lock_fare_quote('26100000-0000-0000-0000-000000000001', '26200000-0000-0000-0000-000000000001', 1, 1)$command$
  )$remote$
);
select ok(
  pg_temp.wait_for_lock((select pid from race_pids where connection_name = 'quote_lock_race_draft_b')),
  'quote-lock session waits on the draft booking lock'
);
select extensions.dblink_exec('quote_lock_race_draft_a', 'commit');
insert into race_results
select 'draft_first', 'quote_lock', result.*
from extensions.dblink_get_result('quote_lock_race_draft_b')
  as result(ok boolean, error_state text, error_message text);
select ok((select ok from race_results where case_name = 'draft_first' and side = 'draft_update'), 'draft mutation succeeds while holding the booking lock');
select ok(not (select ok from race_results where case_name = 'draft_first' and side = 'quote_lock'), 'waiting quote lock fails after the draft commit');
select is((select error_state from race_results where case_name = 'draft_first' and side = 'quote_lock'), '40001', 'waiting quote lock returns version-stale SQLSTATE');
select is((select error_message from race_results where case_name = 'draft_first' and side = 'quote_lock'), 'Booking version is stale.', 'waiting quote lock reports a stale booking version');
select is((select version from public.booking_requests where id = '26100000-0000-0000-0000-000000000001'), 2, 'draft-first race advances the booking version once');
select is((select status::text from public.fare_quotes where id = '26200000-0000-0000-0000-000000000001'), 'superseded', 'draft-first race supersedes the calculated quote');
select is((select count(*) from public.fare_quotes where booking_request_id = '26100000-0000-0000-0000-000000000001' and status = 'locked'), 0::bigint, 'draft-first race leaves no locked quote');
select pg_temp.close_race('quote_lock_race_draft_a', 'quote_lock_race_draft_b');

-- Quote lock holds the booking row; the draft mutation waits, then fails
-- version-stale once the lock commits.
insert into race_pids values
  ('quote_lock_race_lock_a', pg_temp.open_race('quote_lock_race_lock_a', '26000000-0000-0000-0000-000000000001')),
  ('quote_lock_race_lock_b', pg_temp.open_race('quote_lock_race_lock_b', '26000000-0000-0000-0000-000000000001'));
select extensions.dblink_exec('quote_lock_race_lock_a', 'begin');
insert into race_results
select 'lock_first', 'quote_lock', result.*
from extensions.dblink(
  'quote_lock_race_lock_a',
  $remote$select * from pg_temp.capture(
    $command$select public.rider_lock_fare_quote('26100000-0000-0000-0000-000000000002', '26200000-0000-0000-0000-000000000002', 1, 1)$command$
  )$remote$
) as result(ok boolean, error_state text, error_message text);
select extensions.dblink_send_query(
  'quote_lock_race_lock_b',
  $remote$select * from pg_temp.capture(
    $command$select public.rider_update_booking_draft('26100000-0000-0000-0000-000000000002', 1, '{"latitude":31.91,"longitude":35.91}'::jsonb, '{"latitude":31.99,"longitude":35.99}'::jsonb, 'economy'::public.vehicle_type_code, 'cash'::public.payment_method, '[]'::jsonb)$command$
  )$remote$
);
select ok(
  pg_temp.wait_for_lock((select pid from race_pids where connection_name = 'quote_lock_race_lock_b')),
  'draft session waits on the quote-lock booking lock'
);
select extensions.dblink_exec('quote_lock_race_lock_a', 'commit');
insert into race_results
select 'lock_first', 'draft_update', result.*
from extensions.dblink_get_result('quote_lock_race_lock_b')
  as result(ok boolean, error_state text, error_message text);
select ok((select ok from race_results where case_name = 'lock_first' and side = 'quote_lock'), 'quote lock succeeds while holding the booking lock');
select ok(not (select ok from race_results where case_name = 'lock_first' and side = 'draft_update'), 'waiting draft mutation fails after the lock commit');
select is((select error_state from race_results where case_name = 'lock_first' and side = 'draft_update'), '40001', 'waiting draft mutation returns version-stale SQLSTATE');
select is((select error_message from race_results where case_name = 'lock_first' and side = 'draft_update'), 'Booking version is stale.', 'waiting draft mutation reports a stale booking version');
select is((select version from public.booking_requests where id = '26100000-0000-0000-0000-000000000002'), 2, 'lock-first race advances the booking version once');
select is((select status::text from public.fare_quotes where id = '26200000-0000-0000-0000-000000000002'), 'locked', 'lock-first race leaves the quote locked');
select is((select fare_quote_id from public.booking_requests where id = '26100000-0000-0000-0000-000000000002'), '26200000-0000-0000-0000-000000000002'::uuid, 'lock-first race links the booking to the locked quote');
select pg_temp.close_race('quote_lock_race_lock_a', 'quote_lock_race_lock_b');

select ok(
  not exists (select 1 from race_results where error_state = '40P01'),
  'no session deadlocked; both races serialized on the booking lock'
);

-- Self-cleaning: leave no committed fixtures behind so later test files stay
-- isolated without an intermediate reset. Narrow to this file's UUIDs only;
-- shared pricing configurations are untouched.
update public.booking_requests
set fare_quote_id = null
where id in (
  '26100000-0000-0000-0000-000000000001',
  '26100000-0000-0000-0000-000000000002',
  '26100000-0000-0000-0000-000000000003'
);

delete from public.fare_quotes
where id in (
  '26200000-0000-0000-0000-000000000001',
  '26200000-0000-0000-0000-000000000002',
  '26200000-0000-0000-0000-000000000003'
);

delete from public.booking_requests
where id in (
  '26100000-0000-0000-0000-000000000001',
  '26100000-0000-0000-0000-000000000002',
  '26100000-0000-0000-0000-000000000003'
);

delete from auth.users
where id = '26000000-0000-0000-0000-000000000001';

select is(
  (select count(*) from public.fare_quotes where booking_request_id in (
    '26100000-0000-0000-0000-000000000001',
    '26100000-0000-0000-0000-000000000002',
    '26100000-0000-0000-0000-000000000003'
  )),
  0::bigint,
  'cleanup removes the concurrency fare quotes'
);

select is(
  (select count(*) from public.booking_requests where id in (
    '26100000-0000-0000-0000-000000000001',
    '26100000-0000-0000-0000-000000000002',
    '26100000-0000-0000-0000-000000000003'
  )),
  0::bigint,
  'cleanup removes the concurrency bookings'
);

select is(
  (select count(*) from auth.users where id = '26000000-0000-0000-0000-000000000001'),
  0::bigint,
  'cleanup removes the concurrency rider'
);

select * from finish();
