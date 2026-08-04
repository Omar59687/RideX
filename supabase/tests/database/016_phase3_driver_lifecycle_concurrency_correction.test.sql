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
    'host=host.docker.internal port=54322 dbname=%s user=%s password=%s',
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
)
values
  ('00000000-0000-0000-0000-000000000000', 'b6000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rider-016@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b6000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'driver-a-016@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver A"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b6000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'driver-b-016@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver B"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b6000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'driver-c-016@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver C"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b6000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'driver-d-016@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver D"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b6000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'driver-audit-016@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Driver Audit"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'b6000000-0000-0000-0000-000000000007', 'authenticated', 'authenticated', 'admin-016@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Admin"}', now(), now(), '', '', '', '');

update public.users
set role = 'driver'
where id between 'b6000000-0000-0000-0000-000000000002'
  and 'b6000000-0000-0000-0000-000000000006';
update public.users set role = 'admin'
where id = 'b6000000-0000-0000-0000-000000000007';
delete from public.rider_profiles
where user_id between 'b6000000-0000-0000-0000-000000000002'
  and 'b6000000-0000-0000-0000-000000000007';
insert into public.driver_profiles (
  user_id, approval_status, rejection_reason, is_online, is_available
)
select id, 'approved', null, false, false
from public.users
where id between 'b6000000-0000-0000-0000-000000000002'
  and 'b6000000-0000-0000-0000-000000000006';
insert into public.driver_availability (driver_id, state)
select user_id, 'offline' from public.driver_profiles
where user_id between 'b6000000-0000-0000-0000-000000000002'
  and 'b6000000-0000-0000-0000-000000000006';
insert into public.vehicles (
  id, driver_id, vehicle_type_code, make, model, color,
  registration_plate, seat_capacity, is_active
)
select
  ('b6100000-0000-0000-0000-00000000000' || suffix)::uuid,
  ('b6000000-0000-0000-0000-00000000000' || suffix)::uuid,
  'economy', 'Toyota', 'Camry', 'White', 'RDX-016-' || suffix, 4, true
from generate_series(2, 6) as suffix;
update public.driver_availability as availability
set state = 'available',
    vehicle_id = ('b6100000-0000-0000-0000-00000000000' ||
      right(availability.driver_id::text, 1))::uuid
where driver_id between 'b6000000-0000-0000-0000-000000000002'
  and 'b6000000-0000-0000-0000-000000000006';

do $$
begin
  perform public.backend_create_pricing_configuration(
    'economy', 500, 300, 50, 200, 1000, 50, true
  );
end;
$$;

insert into public.booking_requests (
  id, rider_id, pickup, destination, vehicle_type_code, payment_method
)
select
  ('b6200000-0000-0000-0000-00000000000' || suffix)::uuid,
  'b6000000-0000-0000-0000-000000000001',
  jsonb_build_object('latitude', 31.90 + suffix / 100.0, 'longitude', 35.90),
  jsonb_build_object('latitude', 31.99, 'longitude', 35.99 - suffix / 100.0),
  'economy', 'cash'
from generate_series(1, 7) as suffix;
insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination,
  route_distance_meters, route_duration_seconds, vehicle_type_code,
  breakdown, fixed_fare_fils, pricing_configuration_id,
  pricing_version, quote_version, locked_at
)
select
  ('b6300000-0000-0000-0000-00000000000' || suffix)::uuid,
  booking.id, booking.rider_id, 'locked', booking.pickup, booking.destination,
  2000, 600, 'economy', '{"fixed_fare_fils":2000}', 2000,
  (select id from public.pricing_configurations where is_active), 1, 1, now()
from generate_series(1, 7) as suffix
join public.booking_requests as booking
  on booking.id = ('b6200000-0000-0000-0000-00000000000' || suffix)::uuid;
update public.booking_requests as booking
set fare_quote_id = ('b6300000-0000-0000-0000-00000000000' ||
      right(booking.id::text, 1))::uuid;
update public.booking_requests set status = 'confirmed', confirmed_at = now();
update public.booking_requests set status = 'searching', searching_at = now();

insert into public.driver_match_offers (
  id, booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters
)
select
  ('b6400000-0000-0000-0000-00000000000' || suffix)::uuid,
  ('b6200000-0000-0000-0000-00000000000' || suffix)::uuid,
  ('b6300000-0000-0000-0000-00000000000' || suffix)::uuid,
  ('b6000000-0000-0000-0000-00000000000' || (suffix + 1))::uuid,
  ('b6100000-0000-0000-0000-00000000000' || (suffix + 1))::uuid,
  3000
from generate_series(1, 4) as suffix;

select lives_ok(
  $$select private.reconcile_driver_availability('b6000000-0000-0000-0000-000000000006')$$,
  'first reconciliation succeeds'
);
select lives_ok(
  $$select private.reconcile_driver_availability('b6000000-0000-0000-0000-000000000006')$$,
  'repeated reconciliation is idempotent'
);
select is(
  (select count(*) from public.driver_availability
   where driver_id = 'b6000000-0000-0000-0000-000000000006'),
  1::bigint,
  'reconciliation keeps one canonical availability row'
);

insert into public.driver_match_offers (
  id, booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters
)
values (
  'b6400000-0000-0000-0000-000000000005',
  'b6200000-0000-0000-0000-000000000005',
  'b6300000-0000-0000-0000-000000000005',
  'b6000000-0000-0000-0000-000000000006',
  'b6100000-0000-0000-0000-000000000006', 3000
);
update public.driver_match_offers
set status = 'expired', responded_at = now()
where id = 'b6400000-0000-0000-0000-000000000005';
insert into public.driver_match_offers (
  id, booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters
)
values (
  'b6400000-0000-0000-0000-000000000006',
  'b6200000-0000-0000-0000-000000000006',
  'b6300000-0000-0000-0000-000000000006',
  'b6000000-0000-0000-0000-000000000006',
  'b6100000-0000-0000-0000-000000000006', 3000
);
update public.driver_match_offers
set status = 'cancelled', responded_at = now()
where id = 'b6400000-0000-0000-0000-000000000006';
insert into public.driver_match_offers (
  id, booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters
)
values (
  'b6400000-0000-0000-0000-000000000007',
  'b6200000-0000-0000-0000-000000000007',
  'b6300000-0000-0000-0000-000000000007',
  'b6000000-0000-0000-0000-000000000006',
  'b6100000-0000-0000-0000-000000000006', 3000
);
update public.booking_requests
set status = 'cancelled', cancelled_at = now(), cancellation_reason_code = 'test'
where id = 'b6200000-0000-0000-0000-000000000007';
select is(
  (select count(*) from public.audit_records
   where target_user_id = 'b6000000-0000-0000-0000-000000000006'
     and action = 'driver.reservation_created'),
  3::bigint,
  'automatic reservations write three bounded audit records'
);
select is(
  (select count(*) from public.audit_records
   where target_user_id = 'b6000000-0000-0000-0000-000000000006'
     and action = 'driver.reservation_released'),
  3::bigint,
  'offer expiry, offer cancellation, and Booking cancellation are audited'
);
select ok(
  not exists (
    select 1 from public.audit_records
    where target_user_id = 'b6000000-0000-0000-0000-000000000006'
      and action like 'driver.reservation_%'
      and (previous_data::text ~ 'latitude|longitude|pickup|destination'
        or new_data::text ~ 'latitude|longitude|pickup|destination')
  ),
  'automatic reservation audits exclude route and location data'
);

create temporary table race_pids (connection_name text primary key, pid integer);
create temporary table race_results (
  case_name text,
  side text,
  ok boolean,
  error_state text,
  error_message text
);

-- Assignment wins; rejection waits and then fails closed.
insert into race_pids values
  ('reject_assignment_a', pg_temp.open_race('reject_assignment_a', 'b6000000-0000-0000-0000-000000000002')),
  ('reject_assignment_b', pg_temp.open_race('reject_assignment_b', 'b6000000-0000-0000-0000-000000000007'));
select extensions.dblink_exec('reject_assignment_a', 'begin');
select * from extensions.dblink(
  'reject_assignment_a',
  $$select 1 from public.users where id = 'b6000000-0000-0000-0000-000000000002' for update$$
) as locked(value integer);
select extensions.dblink_send_query(
  'reject_assignment_b',
  $remote$select * from pg_temp.capture(
    $command$select public.admin_reject_driver('b6000000-0000-0000-0000-000000000002', 'Race rejection')$command$
  )$remote$
);
select ok(
  pg_temp.wait_for_lock((select pid from race_pids where connection_name = 'reject_assignment_b')),
  'rejection session waits on the assignment lifecycle lock'
);
insert into race_results
select 'reject_assignment', 'assignment', result.*
from extensions.dblink(
  'reject_assignment_a',
  $remote$select * from pg_temp.capture(
    $command$select public.driver_transition_trip('b6400000-0000-0000-0000-000000000001', 'accepted', 1, '016-reject-assignment')$command$
  )$remote$
) as result(ok boolean, error_state text, error_message text);
select extensions.dblink_exec('reject_assignment_a', 'commit');
insert into race_results
select 'reject_assignment', 'rejection', result.*
from extensions.dblink_get_result('reject_assignment_b')
  as result(ok boolean, error_state text, error_message text);
select ok((select ok from race_results where case_name = 'reject_assignment' and side = 'assignment'), 'assignment succeeds before rejection');
select ok(not (select ok from race_results where case_name = 'reject_assignment' and side = 'rejection'), 'rejection fails after assignment');
select is((select error_state from race_results where case_name = 'reject_assignment' and side = 'rejection'), '55000', 'rejection returns lifecycle SQLSTATE');
select is((select status::text from public.trips where driver_id = 'b6000000-0000-0000-0000-000000000002'), 'accepted', 'assignment-first rejection leaves one accepted Trip');
select is((select state::text from public.driver_availability where driver_id = 'b6000000-0000-0000-0000-000000000002'), 'onTrip', 'assignment-first rejection leaves Driver on Trip');
select pg_temp.close_race('reject_assignment_a', 'reject_assignment_b');

-- Rejection wins; assignment waits, revalidates, and fails.
insert into race_pids values
  ('reject_admin_a', pg_temp.open_race('reject_admin_a', 'b6000000-0000-0000-0000-000000000007')),
  ('reject_admin_b', pg_temp.open_race('reject_admin_b', 'b6000000-0000-0000-0000-000000000003'));
select extensions.dblink_exec('reject_admin_a', 'begin');
select * from extensions.dblink(
  'reject_admin_a',
  $$select 1 from public.users where id = 'b6000000-0000-0000-0000-000000000003' for update$$
) as locked(value integer);
select extensions.dblink_send_query(
  'reject_admin_b',
  $remote$select * from pg_temp.capture(
    $command$select public.driver_transition_trip('b6400000-0000-0000-0000-000000000002', 'accepted', 1, '016-reject-admin')$command$
  )$remote$
);
select ok(
  pg_temp.wait_for_lock((select pid from race_pids where connection_name = 'reject_admin_b')),
  'assignment session waits on the rejection lifecycle lock'
);
insert into race_results
select 'reject_admin', 'rejection', result.*
from extensions.dblink(
  'reject_admin_a',
  $remote$select * from pg_temp.capture(
    $command$select public.admin_reject_driver('b6000000-0000-0000-0000-000000000003', 'Race rejection')$command$
  )$remote$
) as result(ok boolean, error_state text, error_message text);
select extensions.dblink_exec('reject_admin_a', 'commit');
insert into race_results
select 'reject_admin', 'assignment', result.*
from extensions.dblink_get_result('reject_admin_b')
  as result(ok boolean, error_state text, error_message text);
select ok((select ok from race_results where case_name = 'reject_admin' and side = 'rejection'), 'rejection succeeds before assignment');
select ok(not (select ok from race_results where case_name = 'reject_admin' and side = 'assignment'), 'assignment fails after rejection');
select is((select error_state from race_results where case_name = 'reject_admin' and side = 'assignment'), '42501', 'assignment revalidation returns authorization SQLSTATE');
select is((select count(*) from public.trips where driver_id = 'b6000000-0000-0000-0000-000000000003'), 0::bigint, 'rejection-first race creates no Trip');
select is((select approval_status::text from public.driver_profiles where user_id = 'b6000000-0000-0000-0000-000000000003'), 'rejected', 'rejection-first race leaves Driver rejected');
select is((select state::text from public.driver_availability where driver_id = 'b6000000-0000-0000-0000-000000000003'), 'offline', 'rejection-first race leaves availability offline');
select pg_temp.close_race('reject_admin_a', 'reject_admin_b');

-- Assignment wins; blocking waits and then fails closed.
insert into race_pids values
  ('block_assignment_a', pg_temp.open_race('block_assignment_a', 'b6000000-0000-0000-0000-000000000004')),
  ('block_assignment_b', pg_temp.open_race('block_assignment_b', 'b6000000-0000-0000-0000-000000000007'));
select extensions.dblink_exec('block_assignment_a', 'begin');
select * from extensions.dblink(
  'block_assignment_a',
  $$select 1 from public.users where id = 'b6000000-0000-0000-0000-000000000004' for update$$
) as locked(value integer);
select extensions.dblink_send_query(
  'block_assignment_b',
  $remote$select * from pg_temp.capture(
    $command$select public.admin_set_user_blocked('b6000000-0000-0000-0000-000000000004', true, 'Race blocking')$command$
  )$remote$
);
select ok(
  pg_temp.wait_for_lock((select pid from race_pids where connection_name = 'block_assignment_b')),
  'blocking session waits on the assignment lifecycle lock'
);
insert into race_results
select 'block_assignment', 'assignment', result.*
from extensions.dblink(
  'block_assignment_a',
  $remote$select * from pg_temp.capture(
    $command$select public.driver_transition_trip('b6400000-0000-0000-0000-000000000003', 'accepted', 1, '016-block-assignment')$command$
  )$remote$
) as result(ok boolean, error_state text, error_message text);
select extensions.dblink_exec('block_assignment_a', 'commit');
insert into race_results
select 'block_assignment', 'blocking', result.*
from extensions.dblink_get_result('block_assignment_b')
  as result(ok boolean, error_state text, error_message text);
select ok((select ok from race_results where case_name = 'block_assignment' and side = 'assignment'), 'assignment succeeds before blocking');
select ok(not (select ok from race_results where case_name = 'block_assignment' and side = 'blocking'), 'blocking fails after assignment');
select is((select error_state from race_results where case_name = 'block_assignment' and side = 'blocking'), '55000', 'blocking returns lifecycle SQLSTATE');
select is((select is_blocked from public.users where id = 'b6000000-0000-0000-0000-000000000004'), false, 'assignment-first race leaves Driver unblocked');
select is((select state::text from public.driver_availability where driver_id = 'b6000000-0000-0000-0000-000000000004'), 'onTrip', 'assignment-first blocking leaves Driver on Trip');
select pg_temp.close_race('block_assignment_a', 'block_assignment_b');

-- Blocking wins; assignment waits, revalidates, and fails.
insert into race_pids values
  ('block_admin_a', pg_temp.open_race('block_admin_a', 'b6000000-0000-0000-0000-000000000007')),
  ('block_admin_b', pg_temp.open_race('block_admin_b', 'b6000000-0000-0000-0000-000000000005'));
select extensions.dblink_exec('block_admin_a', 'begin');
select * from extensions.dblink(
  'block_admin_a',
  $$select 1 from public.users where id = 'b6000000-0000-0000-0000-000000000005' for update$$
) as locked(value integer);
select extensions.dblink_send_query(
  'block_admin_b',
  $remote$select * from pg_temp.capture(
    $command$select public.driver_transition_trip('b6400000-0000-0000-0000-000000000004', 'accepted', 1, '016-block-admin')$command$
  )$remote$
);
select ok(
  pg_temp.wait_for_lock((select pid from race_pids where connection_name = 'block_admin_b')),
  'assignment session waits on the blocking lifecycle lock'
);
insert into race_results
select 'block_admin', 'blocking', result.*
from extensions.dblink(
  'block_admin_a',
  $remote$select * from pg_temp.capture(
    $command$select public.admin_set_user_blocked('b6000000-0000-0000-0000-000000000005', true, 'Race blocking')$command$
  )$remote$
) as result(ok boolean, error_state text, error_message text);
select extensions.dblink_exec('block_admin_a', 'commit');
insert into race_results
select 'block_admin', 'assignment', result.*
from extensions.dblink_get_result('block_admin_b')
  as result(ok boolean, error_state text, error_message text);
select ok((select ok from race_results where case_name = 'block_admin' and side = 'blocking'), 'blocking succeeds before assignment');
select ok(not (select ok from race_results where case_name = 'block_admin' and side = 'assignment'), 'assignment fails after blocking');
select is((select error_state from race_results where case_name = 'block_admin' and side = 'assignment'), '42501', 'assignment revalidation returns authorization SQLSTATE');
select is((select is_blocked from public.users where id = 'b6000000-0000-0000-0000-000000000005'), true, 'blocking-first race leaves Driver blocked');
select is((select count(*) from public.trips where driver_id = 'b6000000-0000-0000-0000-000000000005'), 0::bigint, 'blocking-first race creates no Trip');
select is((select state::text from public.driver_availability where driver_id = 'b6000000-0000-0000-0000-000000000005'), 'offline', 'blocking-first race leaves availability offline');
select pg_temp.close_race('block_admin_a', 'block_admin_b');

-- The public wrapper still delegates non-accepted transitions to the preserved function.
insert into race_pids values
  ('transition_check_a', pg_temp.open_race('transition_check_a', 'b6000000-0000-0000-0000-000000000002'));
insert into race_results
select 'transition_check', 'driver_arriving', result.*
from extensions.dblink(
  'transition_check_a',
  $remote$select * from pg_temp.capture(
    $command$select public.driver_transition_trip(
      (select id from public.trips where driver_id = 'b6000000-0000-0000-0000-000000000002'),
      'driverArriving', 1, '016-nonaccepted-transition'
    )$command$
  )$remote$
) as result(ok boolean, error_state text, error_message text);
select ok((select ok from race_results where case_name = 'transition_check'), 'non-accepted public transition delegates successfully');
select is((select status::text from public.trips where driver_id = 'b6000000-0000-0000-0000-000000000002'), 'driverArriving', 'delegated transition updates Trip status');
select extensions.dblink_disconnect('transition_check_a');

select ok(
  has_function_privilege(
    'authenticated',
    'public.driver_transition_trip(uuid,public.trip_status,integer,text)',
    'EXECUTE'
  ),
  'authenticated can execute the public Trip transition wrapper'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'private.driver_transition_trip(uuid,public.trip_status,integer,text)',
    'EXECUTE'
  ),
  'authenticated cannot execute the private preserved transition'
);
select is(
  (select count(*) from pg_proc
   where oid in (
     'public.driver_transition_trip(uuid,public.trip_status,integer,text)'::regprocedure,
     'private.driver_transition_trip(uuid,public.trip_status,integer,text)'::regprocedure
   ) and prosecdef),
  2::bigint,
  'public and private Trip transition functions remain SECURITY DEFINER'
);

select * from finish();
