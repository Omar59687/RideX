-- Separate sessions are required to exercise the confirmation row lock. This
-- fixture is intentionally committed so dblink sessions can observe it.
create extension if not exists dblink with schema extensions;
select no_plan();

create or replace function pg_temp.wait_for_lock(target_pid integer)
returns boolean language plpgsql as $$
begin
  for attempt in 1..100 loop
    if exists (select 1 from pg_catalog.pg_stat_activity where pid = target_pid and wait_event_type = 'Lock') then
      return true;
    end if;
    perform pg_catalog.pg_sleep(0.05);
  end loop;
  return false;
end;
$$;

create or replace function pg_temp.open_confirm_race(connection_name text, subject_id uuid)
returns integer language plpgsql as $$
declare
  connection_info text;
  remote_pid integer;
begin
  connection_info := format('host=db port=5432 dbname=%s user=%s password=%s', current_database(), current_user, current_user);
  perform extensions.dblink_connect(connection_name, connection_info);
  perform extensions.dblink_exec(connection_name, format('set request.jwt.claim.sub = %L', subject_id::text));
  perform extensions.dblink_exec(connection_name, 'set request.jwt.claim.role = ''authenticated''');
  perform extensions.dblink_exec(connection_name, 'set role authenticated');
  perform extensions.dblink_exec(connection_name, 'set statement_timeout = ''10s''');
  perform extensions.dblink_exec(connection_name, 'set lock_timeout = ''8s''');
  perform extensions.dblink_exec(connection_name, $capture$
    create or replace function pg_temp.capture(command text)
    returns table(ok boolean, result jsonb, error_state text, error_message text)
    language plpgsql as $body$
    declare captured jsonb;
    begin
      execute command into captured;
      return query select true, captured, null::text, null::text;
    exception when others then
      return query select false, null::jsonb, sqlstate::text, sqlerrm::text;
    end;
    $body$
  $capture$);
  select pid into remote_pid from extensions.dblink(connection_name, 'select pg_backend_pid()') as result(pid integer);
  return remote_pid;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values ('00000000-0000-0000-0000-000000000000', '29100000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'confirm-race@example.test', '', now(), '{}', '{}', now(), now(), '', '', '', '');

insert into public.booking_requests (id, rider_id, pickup, destination, vehicle_type_code, payment_method)
values ('29200000-0000-0000-0000-000000000001', '29100000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash');

insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination,
  route_distance_meters, route_duration_seconds, vehicle_type_code,
  breakdown, fixed_fare_fils, pricing_configuration_id, pricing_version,
  quote_version, created_at, expires_at, locked_at
) values (
  '29300000-0000-0000-0000-000000000001', '29200000-0000-0000-0000-000000000001',
  '29100000-0000-0000-0000-000000000001', 'locked',
  '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}',
  3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700,
  (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active),
  (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active),
  1, now(), now() + interval '10 minutes', now()
);
alter table public.booking_requests disable trigger booking_requests_bump_optimistic_version;
alter table public.booking_requests disable trigger booking_requests_enforce_transition;
update public.booking_requests set fare_quote_id = '29300000-0000-0000-0000-000000000001' where id = '29200000-0000-0000-0000-000000000001';
alter table public.booking_requests enable trigger booking_requests_enforce_transition;
alter table public.booking_requests enable trigger booking_requests_bump_optimistic_version;

create temporary table confirm_race_results(side text, ok boolean, result jsonb, error_state text, error_message text);
create temporary table confirm_race_pids(connection_name text primary key, pid integer);
insert into confirm_race_pids values
  ('cash_confirm_race_a', pg_temp.open_confirm_race('cash_confirm_race_a', '29100000-0000-0000-0000-000000000001')),
  ('cash_confirm_race_b', pg_temp.open_confirm_race('cash_confirm_race_b', '29100000-0000-0000-0000-000000000001'));

select extensions.dblink_exec('cash_confirm_race_a', 'begin');
select extensions.dblink_send_query('cash_confirm_race_a', $remote$
  select * from pg_temp.capture($command$
    select public.rider_confirm_booking('29200000-0000-0000-0000-000000000001', 1, 'cash-confirm-race-a')
  $command$)
$remote$);
insert into confirm_race_results
select 'first', result.* from extensions.dblink_get_result('cash_confirm_race_a') as result(ok boolean, result jsonb, error_state text, error_message text);
select count(*) from extensions.dblink_get_result('cash_confirm_race_a') as drained(ok boolean, result jsonb, error_state text, error_message text);

select extensions.dblink_send_query('cash_confirm_race_b', $remote$
  select * from pg_temp.capture($command$
    select public.rider_confirm_booking('29200000-0000-0000-0000-000000000001', 1, 'cash-confirm-race-b')
  $command$)
$remote$);
select ok(pg_temp.wait_for_lock((select pid from confirm_race_pids where connection_name = 'cash_confirm_race_b')), 'second confirmation waits on the booking row lock');
select extensions.dblink_exec('cash_confirm_race_a', 'commit');
insert into confirm_race_results
select 'second', result.* from extensions.dblink_get_result('cash_confirm_race_b') as result(ok boolean, result jsonb, error_state text, error_message text);
select count(*) from extensions.dblink_get_result('cash_confirm_race_b') as drained(ok boolean, result jsonb, error_state text, error_message text);

select ok((select ok from confirm_race_results where side = 'first'), 'first concurrent confirmation succeeds');
select ok((select ok from confirm_race_results where side = 'second'), 'second concurrent confirmation recovers successfully');
select is((select count(*)::integer from confirm_race_results where result->>'status' = 'confirmed'), 2, 'both callers receive the canonical confirmed result');
select is((select status::text from public.booking_requests where id = '29200000-0000-0000-0000-000000000001'), 'confirmed', 'race leaves the booking confirmed');
select is((select version from public.booking_requests where id = '29200000-0000-0000-0000-000000000001'), 2, 'race advances booking version once');
select is((select count(*)::integer from public.audit_records where action = 'booking.confirmed' and new_data->>'booking_request_id' = '29200000-0000-0000-0000-000000000001'), 1, 'race writes exactly one confirmation audit');
select extensions.dblink_disconnect('cash_confirm_race_a');
select extensions.dblink_disconnect('cash_confirm_race_b');
select * from finish();
