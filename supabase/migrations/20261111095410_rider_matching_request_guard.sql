begin;

create table private.rider_matching_request_budget (
  rider_id uuid primary key references public.users(id) on delete cascade,
  window_started_at timestamptz not null,
  request_count smallint not null check (request_count between 1 and 30)
);
revoke all on private.rider_matching_request_budget from public, anon, authenticated, service_role;

create function public.rider_matching_session_is_active()
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  v_rider_id uuid := auth.uid();
  session_claim text := auth.jwt() ->> 'session_id';
  session_uuid uuid;
  admitted boolean;
begin
  if v_rider_id is null or session_claim is null or session_claim !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  session_uuid := session_claim::uuid;
  if not exists (select 1 from public.users u where u.id=v_rider_id and u.role='rider' and not u.is_blocked) then return false; end if;
  -- auth.sessions schema belongs to GoTrue. Dynamic lookup lets minimal migration harnesses replay
  -- without manufacturing production Auth tables; absent relation/columns fails closed.
  begin
    execute 'select exists(select 1 from auth.sessions s where s.id=$1 and s.user_id=$2 and (to_jsonb(s)->>''not_after'' is null or (to_jsonb(s)->>''not_after'')::timestamptz > now()))'
      into admitted using session_uuid, v_rider_id;
  exception when undefined_table or undefined_column then return false;
  end;
  return coalesce(admitted,false);
end $$;

create function public.rider_matching_request_guard()
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_rider_id uuid := auth.uid(); now_at timestamptz; admitted boolean;
begin
  if v_rider_id is null or not public.rider_matching_session_is_active() then
    raise exception using errcode='42501', message='Active rider session required.';
  end if;
  -- Serialize per rider before sampling time, so lock waiters cannot move a window backward.
  perform pg_advisory_xact_lock(hashtextextended(v_rider_id::text, 732941));
  now_at := clock_timestamp();
  insert into private.rider_matching_request_budget(rider_id,window_started_at,request_count)
  values (v_rider_id, to_timestamp(floor(extract(epoch from now_at)/60)*60), 1)
  on conflict (rider_id) do update set
    window_started_at=case when excluded.window_started_at>private.rider_matching_request_budget.window_started_at
      then excluded.window_started_at else private.rider_matching_request_budget.window_started_at end,
    request_count=case when excluded.window_started_at>private.rider_matching_request_budget.window_started_at
      then 1 else private.rider_matching_request_budget.request_count+1 end
  where excluded.window_started_at>private.rider_matching_request_budget.window_started_at
     or private.rider_matching_request_budget.request_count<30
  returning true into admitted;
  return coalesce(admitted,false);
end $$;
revoke all on function public.rider_matching_session_is_active() from public, anon, service_role;
revoke all on function public.rider_matching_request_guard() from public, anon, service_role;
grant execute on function public.rider_matching_session_is_active() to authenticated;
grant execute on function public.rider_matching_request_guard() to authenticated;
commit;
