-- LOCAL DISPOSABLE DATABASE ONLY: committed fixture rows support real dblink sessions.
-- Run once in a fresh database. Override ridex.test_dblink_conninfo for local
-- clusters whose hostname/socket/auth differs from the existing db:5432 harness.
create extension if not exists pgtap with schema extensions;
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
  connection_info := coalesce(nullif(current_setting('ridex.test_dblink_conninfo', true), ''), format(
    'host=db port=5432 dbname=%s user=%s password=%s',
    current_database(),
    current_user,
    current_user
  ));

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
  perform extensions.dblink_exec(connection_name, 'set role authenticated');
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

\ir ../fixtures/p7_a02_driver_availability.sql
create temporary table results(label text, ok boolean, error_state text, error_message text);
select pg_temp.open_race('a02_first','a7020000-0000-0000-0000-000000000001');
create temporary table waiter as select pg_temp.open_race('a02_second','a7020000-0000-0000-0000-000000000001') pid;
select extensions.dblink_exec('a02_first','begin');
insert into results select 'winner', r.* from extensions.dblink('a02_first', $remote$select * from pg_temp.capture($cmd$select public.driver_set_availability('available','a7021000-0000-0000-0000-000000000001',1)$cmd$)$remote$) as r(ok boolean,error_state text,error_message text);
select extensions.dblink_send_query('a02_second',$remote$select * from pg_temp.capture($cmd$select public.driver_set_availability('offline',null,1)$cmd$)$remote$);
select ok(pg_temp.wait_for_lock((select pid from waiter)), 'conflicting update waits for lifecycle lock');
select extensions.dblink_exec('a02_first','commit');
insert into results select 'loser',r.* from extensions.dblink_get_result('a02_second') as r(ok boolean,error_state text,error_message text);
select ok((select ok from results where label='winner'),'one update succeeds');
select is((select error_state from results where label='loser'),'40001','waiting stale update fails');
select is((select version from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000001'),2,'exactly one version increment');
select is((select state::text from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000001'),'available','loser leaves winning state intact');
select pg_temp.close_race('a02_first','a02_second');
update public.users set is_blocked=false where id='a7020000-0000-0000-0000-000000000001';
update public.driver_profiles set approval_status='approved', rejection_reason=null where user_id='a7020000-0000-0000-0000-000000000001';
select pg_temp.open_race('a02_admin_0','a7020000-0000-0000-0000-000000000003');
truncate waiter;
insert into waiter select pg_temp.open_race('a02_driver_0','a7020000-0000-0000-0000-000000000001');
select extensions.dblink_exec('a02_admin_0','begin');
select * from extensions.dblink('a02_admin_0',$remote$select * from pg_temp.capture($cmd$select public.admin_set_user_blocked('a7020000-0000-0000-0000-000000000001',true,'P7 local race')$cmd$)$remote$) as r(ok boolean,error_state text,error_message text);
select extensions.dblink_send_query('a02_driver_0',$remote$select * from pg_temp.capture($cmd$select public.driver_set_availability('available','a7021000-0000-0000-0000-000000000001',(select version from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000001'))$cmd$)$remote$);
select ok(pg_temp.wait_for_lock((select pid from waiter)),'eligibility race 0 waits');
select extensions.dblink_exec('a02_admin_0','commit');
insert into results select 'revoked0',r.* from extensions.dblink_get_result('a02_driver_0') as r(ok boolean,error_state text,error_message text);
select is((select error_state from results where label='revoked0'),'42501','eligibility revalidated after wait 0');
select is((select state::text from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000001'),'offline','revoked Driver remains offline 0');
select pg_temp.close_race('a02_admin_0','a02_driver_0');
update public.users set is_blocked=false where id='a7020000-0000-0000-0000-000000000001';
update public.driver_profiles set approval_status='approved', rejection_reason=null where user_id='a7020000-0000-0000-0000-000000000001';
select pg_temp.open_race('a02_admin_1','a7020000-0000-0000-0000-000000000003');
truncate waiter;
insert into waiter select pg_temp.open_race('a02_driver_1','a7020000-0000-0000-0000-000000000001');
select extensions.dblink_exec('a02_admin_1','begin');
select * from extensions.dblink('a02_admin_1',$remote$select * from pg_temp.capture($cmd$select public.admin_reject_driver('a7020000-0000-0000-0000-000000000001','P7 local race')$cmd$)$remote$) as r(ok boolean,error_state text,error_message text);
select extensions.dblink_send_query('a02_driver_1',$remote$select * from pg_temp.capture($cmd$select public.driver_set_availability('available','a7021000-0000-0000-0000-000000000001',(select version from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000001'))$cmd$)$remote$);
select ok(pg_temp.wait_for_lock((select pid from waiter)),'eligibility race 1 waits');
select extensions.dblink_exec('a02_admin_1','commit');
insert into results select 'revoked1',r.* from extensions.dblink_get_result('a02_driver_1') as r(ok boolean,error_state text,error_message text);
select is((select error_state from results where label='revoked1'),'42501','eligibility revalidated after wait 1');
select is((select state::text from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000001'),'offline','revoked Driver remains offline 1');
select pg_temp.close_race('a02_admin_1','a02_driver_1');
select * from finish();
