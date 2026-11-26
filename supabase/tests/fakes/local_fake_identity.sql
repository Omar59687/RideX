-- LOCAL TEST FIXTURE: loaded only by the network-isolated test runner.
-- No production RPC and no path to financial/reconciliation tables.
create schema local_fake_fixture;
revoke all on schema local_fake_fixture from public, anon, authenticated, service_role;
create table local_fake_fixture.gate (enabled boolean not null default false);
insert into local_fake_fixture.gate default values;
revoke all on local_fake_fixture.gate from public, anon, authenticated, service_role;
create table local_fake_fixture.identity (
  operation_id uuid primary key,
  account text not null check (account ~ '^local_fake_[a-z0-9]{1,32}$'),
  provider text not null check (provider = 'local_fake'),
  environment text not null check (environment = 'local_test')
);
alter table local_fake_fixture.identity enable row level security;
revoke all on local_fake_fixture.identity from public, anon, authenticated, service_role;
create function local_fake_fixture.claim(target uuid, fake_account text, outcome text)
returns text language plpgsql security definer set search_path = '' as $$
declare stored local_fake_fixture.identity%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception using errcode='42501'; end if;
  if not exists (select 1 from local_fake_fixture.gate where enabled) then raise exception using errcode='55000'; end if;
  if target is null or fake_account is null or fake_account !~ '^local_fake_[a-z0-9]{1,32}$'
    or outcome is distinct from 'verified_fake' then raise exception using errcode='22023'; end if;
  insert into local_fake_fixture.identity values(target, fake_account, 'local_fake', 'local_test')
    on conflict (operation_id) do nothing;
  if found then return 'claimed'; end if;
  select * into stored from local_fake_fixture.identity where operation_id=target;
  if stored.account is distinct from fake_account then raise exception using errcode='23505'; end if;
  return 'existing';
end;
$$;
revoke all on function local_fake_fixture.claim(uuid,text,text) from public,anon,authenticated,service_role;
grant usage on schema local_fake_fixture to service_role;
grant execute on function local_fake_fixture.claim(uuid,text,text) to service_role;
create function local_fake_fixture.reject_change() returns trigger language plpgsql set search_path='' as $$
begin raise exception using errcode='55000'; end;
$$;
create trigger immutable_identity before update or delete on local_fake_fixture.identity
for each row execute function local_fake_fixture.reject_change();
