begin;
-- Global admission. Leases have no automatic expiry: an uncertain release fails
-- closed and requires an explicitly authorized operator to investigate.
create table private.p8_webhook_admission (
  singleton boolean primary key default true check(singleton),
  window_started_at timestamptz not null default clock_timestamp(),
  accepted integer not null default 0 check(accepted between 0 and 60)
);
insert into private.p8_webhook_admission(singleton) values(true);
create table private.p8_webhook_admission_leases (
  lease_id uuid primary key default gen_random_uuid(),
  admitted_at timestamptz not null default clock_timestamp()
);
alter table private.p8_webhook_admission enable row level security;
alter table private.p8_webhook_admission_leases enable row level security;
revoke all on private.p8_webhook_admission,private.p8_webhook_admission_leases from public,anon,authenticated,service_role;
create function public.backend_acquire_test_webhook_admission()
returns uuid language plpgsql security definer set search_path='' as $$
declare state private.p8_webhook_admission%rowtype; token uuid; observed timestamptz := clock_timestamp();
begin
  if auth.role() is distinct from 'service_role' then raise exception using errcode='42501',message='Backend access required.'; end if;
  select * into state from private.p8_webhook_admission where singleton for update;
  if not found then raise exception using errcode='55000',message='Admission unavailable.'; end if;
  if observed < state.window_started_at then raise exception using errcode='55000',message='Admission clock unavailable.'; end if;
  if observed >= state.window_started_at + interval '60 seconds' then
    update private.p8_webhook_admission set window_started_at=observed,accepted=0 where singleton;
    state.accepted := 0;
  end if;
  if state.accepted >= 60 or (select count(*) from private.p8_webhook_admission_leases) >= 8 then return null; end if;
  insert into private.p8_webhook_admission_leases default values returning lease_id into token;
  update private.p8_webhook_admission set accepted=accepted+1 where singleton;
  return token;
end;
$$;
create function public.backend_release_test_webhook_admission(target_lease uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare removed integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception using errcode='42501',message='Backend access required.'; end if;
  if target_lease is null then return false; end if;
  -- Serialize deletion with admission; a duplicate or unknown release is not success.
  perform 1 from private.p8_webhook_admission where singleton for update;
  if not found then raise exception using errcode='55000',message='Admission unavailable.'; end if;
  delete from private.p8_webhook_admission_leases where lease_id=target_lease;
  get diagnostics removed = row_count;
  return removed=1;
end;
$$;
revoke all on function public.backend_acquire_test_webhook_admission(),public.backend_release_test_webhook_admission(uuid) from public,anon,authenticated,service_role;
grant execute on function public.backend_acquire_test_webhook_admission(),public.backend_release_test_webhook_admission(uuid) to service_role;
commit;
