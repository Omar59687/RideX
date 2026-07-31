begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create type public.booking_request_status as enum (
  'draft', 'confirmed', 'searching', 'matched', 'cancelled', 'expired', 'failed'
);
create type public.trip_status as enum (
  'accepted', 'driverArriving', 'driverArrived', 'inProgress', 'completed',
  'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed'
);
create type public.fare_quote_status as enum (
  'calculated', 'locked', 'expired', 'superseded'
);
create type public.trip_change_request_status as enum (
  'requested', 'pricing', 'awaitingRiderApproval', 'authorizationPending',
  'approved', 'rejected', 'cancelled', 'applied', 'failed'
);
create type public.payment_method as enum ('cash', 'card');
create type public.cash_payment_status as enum ('cashSelected', 'paid', 'cancelled');
create type public.card_payment_status as enum (
  'cardPaymentPending', 'cardPaymentAuthorized', 'cardPaymentSucceeded',
  'cardPaymentFailed', 'paymentCancelled', 'refundPending', 'refunded'
);
create type public.payment_attempt_type as enum (
  'initialAuthorization', 'replacementAuthorization', 'adjustmentAuthorization',
  'capture', 'captureRetry', 'voidAuthorization', 'refund',
  'providerStatusVerification'
);
create type public.payment_attempt_status as enum ('pending', 'succeeded', 'failed', 'cancelled');
create type public.driver_availability_state as enum ('offline', 'available', 'reserved', 'onTrip');
create type public.command_idempotency_scope as enum ('booking', 'trip');

alter table public.users
  add column if not exists version integer not null default 1,
  add constraint users_version_positive check (version > 0),
  add constraint users_display_name_bounded check (
    char_length(btrim(display_name)) between 1 and 100
  ),
  add constraint users_email_normalized check (
    email = lower(btrim(email))
    and char_length(email) between 3 and 320
    and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ),
  add constraint users_photo_url_safe check (
    photo_url is null
    or char_length(photo_url) <= 2048
    and photo_url ~ '^https://'
  );

alter table public.rider_profiles
  add column if not exists version integer not null default 1,
  add constraint rider_profiles_version_positive check (version > 0);

alter table public.driver_profiles
  add column if not exists version integer not null default 1,
  add constraint driver_profiles_version_positive check (version > 0),
  add constraint driver_profiles_rejection_reason_valid check (
    (approval_status = 'rejected'
      and char_length(btrim(coalesce(rejection_reason, ''))) between 1 and 500)
    or (approval_status <> 'rejected' and rejection_reason is null)
  );

create or replace function private.bump_optimistic_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.version := old.version + 1;
  return new;
end;
$$;

drop trigger if exists users_bump_optimistic_version on public.users;
create trigger users_bump_optimistic_version
before update on public.users
for each row execute function private.bump_optimistic_version();

drop trigger if exists rider_profiles_bump_optimistic_version on public.rider_profiles;
create trigger rider_profiles_bump_optimistic_version
before update on public.rider_profiles
for each row execute function private.bump_optimistic_version();

drop trigger if exists driver_profiles_bump_optimistic_version on public.driver_profiles;
create trigger driver_profiles_bump_optimistic_version
before update on public.driver_profiles
for each row execute function private.bump_optimistic_version();

create table public.audit_records (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default now(),
  actor_user_id uuid references public.users (id) on delete set null,
  action text not null,
  target_user_id uuid references public.users (id) on delete set null,
  audit_reason text,
  previous_data jsonb not null default '{}'::jsonb,
  new_data jsonb not null default '{}'::jsonb,
  request_context jsonb not null default '{}'::jsonb,
  check (char_length(btrim(action)) between 1 and 128),
  check (audit_reason is null or char_length(btrim(audit_reason)) between 1 and 500),
  check (jsonb_typeof(previous_data) = 'object'),
  check (jsonb_typeof(new_data) = 'object'),
  check (jsonb_typeof(request_context) = 'object')
);

create index audit_records_target_occurred_at_idx
  on public.audit_records (target_user_id, occurred_at desc);
create index audit_records_occurred_at_idx on public.audit_records (occurred_at desc);

create table public.command_idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references public.users (id) on delete cascade,
  command_scope public.command_idempotency_scope not null,
  idempotency_key text not null,
  payload_fingerprint text not null,
  canonical_result jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  check (char_length(btrim(idempotency_key)) between 1 and 128),
  check (payload_fingerprint ~ '^[0-9a-f]{64}$'),
  check (jsonb_typeof(canonical_result) = 'object'),
  check (expires_at = created_at + interval '7 days'),
  unique (actor_user_id, command_scope, idempotency_key)
);

create index command_idempotency_keys_expires_at_idx
  on public.command_idempotency_keys (expires_at);

create or replace function private.reject_audit_record_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'Audit records are immutable.';
end;
$$;

create trigger audit_records_immutable
before update or delete on public.audit_records
for each row execute function private.reject_audit_record_mutation();

create or replace function private.write_audit_record(
  audit_actor_user_id uuid,
  audit_action text,
  audit_target_user_id uuid,
  audit_reason text,
  audit_previous_data jsonb,
  audit_new_data jsonb,
  audit_request_context jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_records (
    actor_user_id, action, target_user_id, audit_reason,
    previous_data, new_data, request_context
  ) values (
    audit_actor_user_id, audit_action, audit_target_user_id, audit_reason,
    coalesce(audit_previous_data, '{}'::jsonb),
    coalesce(audit_new_data, '{}'::jsonb),
    coalesce(audit_request_context, '{}'::jsonb)
  );
end;
$$;

create or replace function private.audit_user_security_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  audit_action text;
begin
  if new.role is not distinct from old.role
    and new.is_blocked is not distinct from old.is_blocked then
    return new;
  end if;

  audit_action := coalesce(
    nullif(current_setting('ridex.audit_action', true), ''),
    case when new.role is distinct from old.role
      then 'user.role_changed'
      else 'user.blocked_state_changed'
    end
  );

  perform private.write_audit_record(
    nullif(current_setting('ridex.audit_actor_id', true), '')::uuid,
    audit_action,
    new.id,
    nullif(current_setting('ridex.audit_reason', true), ''),
    jsonb_build_object('role', old.role, 'is_blocked', old.is_blocked),
    jsonb_build_object('role', new.role, 'is_blocked', new.is_blocked)
  );
  return new;
end;
$$;

create or replace function private.audit_driver_approval_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.approval_status is not distinct from old.approval_status
    and new.rejection_reason is not distinct from old.rejection_reason then
    return new;
  end if;

  perform private.write_audit_record(
    nullif(current_setting('ridex.audit_actor_id', true), '')::uuid,
    coalesce(nullif(current_setting('ridex.audit_action', true), ''), 'driver.approval_changed'),
    new.user_id,
    nullif(current_setting('ridex.audit_reason', true), ''),
    jsonb_build_object('approval_status', old.approval_status, 'rejection_reason', old.rejection_reason),
    jsonb_build_object('approval_status', new.approval_status, 'rejection_reason', new.rejection_reason)
  );
  return new;
end;
$$;

create trigger users_audit_security_change
after update of role, is_blocked on public.users
for each row execute function private.audit_user_security_change();

create trigger driver_profiles_audit_approval_change
after update of approval_status, rejection_reason on public.driver_profiles
for each row execute function private.audit_driver_approval_change();

create or replace function private.require_nonblocked_admin()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
begin
  if caller_id is null or not exists (
    select 1 from public.users
    where id = caller_id and role = 'admin' and not is_blocked
  ) then
    raise exception using
      errcode = '42501',
      message = 'Only a non-blocked Admin can manage Drivers.';
  end if;
  return caller_id;
end;
$$;

create or replace function private.claim_command_idempotency_key(
  command_actor_user_id uuid,
  command_scope_value public.command_idempotency_scope,
  command_key text,
  command_payload_fingerprint text,
  command_canonical_result jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_fingerprint text;
  existing_result jsonb;
begin
  if command_actor_user_id is null
    or char_length(btrim(coalesce(command_key, ''))) not between 1 and 128
    or coalesce(command_payload_fingerprint, '') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(command_canonical_result) <> 'object' then
    raise exception using errcode = '22023', message = 'Invalid command idempotency input.';
  end if;

  insert into public.command_idempotency_keys (
    actor_user_id, command_scope, idempotency_key, payload_fingerprint, canonical_result
  ) values (
    command_actor_user_id, command_scope_value, btrim(command_key),
    command_payload_fingerprint, command_canonical_result
  ) on conflict (actor_user_id, command_scope, idempotency_key) do nothing;

  select payload_fingerprint, canonical_result
  into existing_fingerprint, existing_result
  from public.command_idempotency_keys
  where actor_user_id = command_actor_user_id
    and command_scope = command_scope_value
    and idempotency_key = btrim(command_key)
  for update;

  if existing_fingerprint <> command_payload_fingerprint then
    perform private.write_audit_record(
      command_actor_user_id,
      'command.idempotency_payload_mismatch',
      command_actor_user_id,
      null,
      jsonb_build_object('command_scope', command_scope_value, 'payload_fingerprint', existing_fingerprint),
      jsonb_build_object('command_scope', command_scope_value, 'payload_fingerprint', command_payload_fingerprint),
      jsonb_build_object('idempotency_key', btrim(command_key))
    );
    return jsonb_build_object('error', 'idempotency_payload_mismatch');
  end if;

  return existing_result;
end;
$$;

create or replace function private.bootstrap_first_admin(target_user_id uuid, audit_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user public.users%rowtype;
begin
  if session_user <> 'postgres' then
    raise exception using errcode = '42501', message = 'Only the database owner can bootstrap the first Admin.';
  end if;
  if char_length(btrim(coalesce(audit_reason, ''))) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'A nonblank audit reason of at most 500 characters is required.';
  end if;

  lock table public.users in share row exclusive mode;
  if exists (select 1 from public.users where role = 'admin') then
    raise exception using errcode = '55000', message = 'An Admin already exists.';
  end if;

  select * into target_user from public.users where id = target_user_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Target account was not found.';
  end if;
  if target_user.is_blocked then
    raise exception using errcode = '22023', message = 'A blocked account cannot become the first Admin.';
  end if;

  perform set_config('ridex.audit_action', 'admin.bootstrap_first', true);
  perform set_config('ridex.audit_reason', btrim(audit_reason), true);
  update public.users set role = 'admin' where id = target_user_id;
  delete from public.rider_profiles where user_id = target_user_id;
  delete from public.driver_profiles where user_id = target_user_id;
end;
$$;

create or replace function public.admin_promote_user_to_driver(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  target_role text;
begin
  caller_id := private.require_nonblocked_admin();
  select role into target_role from public.users where id = target_user_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Target account was not found.';
  end if;
  if target_role <> 'rider' then
    raise exception using errcode = '22023', message = 'Only a Rider account can be promoted to Driver.';
  end if;

  perform set_config('ridex.audit_actor_id', caller_id::text, true);
  perform set_config('ridex.audit_action', 'admin.driver_promoted', true);
  update public.users set role = 'driver' where id = target_user_id;
  delete from public.rider_profiles where user_id = target_user_id;
  insert into public.driver_profiles (user_id, approval_status, rejection_reason, is_online, is_available)
  values (target_user_id, 'pending', null, false, false)
  on conflict (user_id) do update
  set approval_status = 'pending', rejection_reason = null, is_online = false, is_available = false;
end;
$$;

create or replace function public.admin_approve_driver(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
begin
  caller_id := private.require_nonblocked_admin();
  perform set_config('ridex.audit_actor_id', caller_id::text, true);
  perform set_config('ridex.audit_action', 'admin.driver_approved', true);
  update public.driver_profiles as profiles
  set approval_status = 'approved', rejection_reason = null
  from public.users as users
  where profiles.user_id = target_user_id and users.id = profiles.user_id and users.role = 'driver';
  if not found then
    raise exception using errcode = 'P0002', message = 'Target Driver account was not found.';
  end if;
end;
$$;

create or replace function public.admin_reject_driver(target_user_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
begin
  caller_id := private.require_nonblocked_admin();
  if char_length(btrim(coalesce(reason, ''))) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'A rejection reason is required.';
  end if;
  perform set_config('ridex.audit_actor_id', caller_id::text, true);
  perform set_config('ridex.audit_action', 'admin.driver_rejected', true);
  perform set_config('ridex.audit_reason', btrim(reason), true);
  update public.driver_profiles as profiles
  set approval_status = 'rejected', rejection_reason = btrim(reason)
  from public.users as users
  where profiles.user_id = target_user_id and users.id = profiles.user_id and users.role = 'driver';
  if not found then
    raise exception using errcode = 'P0002', message = 'Target Driver account was not found.';
  end if;
end;
$$;

create or replace function public.admin_set_user_blocked(
  target_user_id uuid,
  blocked boolean,
  audit_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
begin
  caller_id := private.require_nonblocked_admin();
  if char_length(btrim(coalesce(audit_reason, ''))) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'A nonblank audit reason is required.';
  end if;
  perform set_config('ridex.audit_actor_id', caller_id::text, true);
  perform set_config('ridex.audit_action', 'admin.user_blocked_state_set', true);
  perform set_config('ridex.audit_reason', btrim(audit_reason), true);
  update public.users set is_blocked = blocked where id = target_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Target account was not found.';
  end if;
end;
$$;

alter table public.audit_records enable row level security;
alter table public.command_idempotency_keys enable row level security;
revoke all on table public.audit_records, public.command_idempotency_keys from public, anon, authenticated;

revoke all on function private.bump_optimistic_version() from public, anon, authenticated;
revoke all on function private.reject_audit_record_mutation() from public, anon, authenticated;
revoke all on function private.write_audit_record(uuid, text, uuid, text, jsonb, jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.audit_user_security_change() from public, anon, authenticated;
revoke all on function private.audit_driver_approval_change() from public, anon, authenticated;
revoke all on function private.require_nonblocked_admin() from public, anon, authenticated;
revoke all on function private.claim_command_idempotency_key(uuid, public.command_idempotency_scope, text, text, jsonb) from public, anon, authenticated;
revoke all on function private.bootstrap_first_admin(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.admin_promote_user_to_driver(uuid) from public, anon, authenticated;
revoke all on function public.admin_approve_driver(uuid) from public, anon, authenticated;
revoke all on function public.admin_reject_driver(uuid, text) from public, anon, authenticated;
revoke all on function public.admin_set_user_blocked(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.admin_promote_user_to_driver(uuid) to authenticated;
grant execute on function public.admin_approve_driver(uuid) to authenticated;
grant execute on function public.admin_reject_driver(uuid, text) to authenticated;
grant execute on function public.admin_set_user_blocked(uuid, boolean, text) to authenticated;

commit;
