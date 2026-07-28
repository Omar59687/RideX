-- Public account creation is always Rider-only. Role changes are available only
-- through the narrowly scoped Admin operations defined below.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  declared_name text;
begin
  declared_name := trim(coalesce(new.raw_user_meta_data ->> 'display_name', ''));

  if declared_name = '' then
    raise exception 'Display name is required.';
  end if;

  if new.email is null or trim(new.email) = '' then
    raise exception 'Email is required.';
  end if;

  insert into public.users (
    id,
    role,
    display_name,
    email
  )
  values (
    new.id,
    'rider',
    declared_name,
    new.email
  );

  insert into public.rider_profiles (user_id)
  values (new.id);

  return new;
end;
$$;

-- Preserve every existing profile and state while repairing only missing rows.
insert into public.rider_profiles (user_id)
select users.id
from public.users as users
where users.role = 'rider'
on conflict (user_id) do nothing;

insert into public.driver_profiles (user_id, approval_status)
select users.id, 'pending'
from public.users as users
where users.role = 'driver'
on conflict (user_id) do nothing;

-- Reassert the client table boundary even if grants drifted after migration 002.
revoke all on table public.users from anon, authenticated;
revoke all on table public.rider_profiles from anon, authenticated;
revoke all on table public.driver_profiles from anon, authenticated;

grant select on table public.users to authenticated;
grant update (display_name, photo_url) on table public.users to authenticated;
grant select on table public.rider_profiles to authenticated;
grant select on table public.driver_profiles to authenticated;

create or replace function public.admin_promote_user_to_driver(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_role text;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.users as caller
    where caller.id = auth.uid()
      and caller.role = 'admin'
      and not caller.is_blocked
  ) then
    raise exception using
      errcode = '42501',
      message = 'Only a non-blocked Admin can manage Drivers.';
  end if;

  select users.role
  into target_role
  from public.users as users
  where users.id = target_user_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Target account was not found.';
  end if;

  if target_role <> 'rider' then
    raise exception using
      errcode = '22023',
      message = 'Only a Rider account can be promoted to Driver.';
  end if;

  update public.users as users
  set role = 'driver'
  where users.id = target_user_id;

  delete from public.rider_profiles as profiles
  where profiles.user_id = target_user_id;

  insert into public.driver_profiles (
    user_id,
    approval_status,
    rejection_reason,
    is_online,
    is_available
  )
  values (target_user_id, 'pending', null, false, false)
  on conflict (user_id) do update
  set approval_status = 'pending',
      rejection_reason = null,
      is_online = false,
      is_available = false;
end;
$$;

create or replace function public.admin_approve_driver(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.users as caller
    where caller.id = auth.uid()
      and caller.role = 'admin'
      and not caller.is_blocked
  ) then
    raise exception using
      errcode = '42501',
      message = 'Only a non-blocked Admin can manage Drivers.';
  end if;

  update public.driver_profiles as profiles
  set approval_status = 'approved',
      rejection_reason = null
  from public.users as users
  where profiles.user_id = target_user_id
    and users.id = profiles.user_id
    and users.role = 'driver';

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Target Driver account was not found.';
  end if;
end;
$$;

create or replace function public.admin_reject_driver(
  target_user_id uuid,
  reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.users as caller
    where caller.id = auth.uid()
      and caller.role = 'admin'
      and not caller.is_blocked
  ) then
    raise exception using
      errcode = '42501',
      message = 'Only a non-blocked Admin can manage Drivers.';
  end if;

  if trim(coalesce(reason, '')) = '' then
    raise exception using
      errcode = '22023',
      message = 'A rejection reason is required.';
  end if;

  update public.driver_profiles as profiles
  set approval_status = 'rejected',
      rejection_reason = trim(reason)
  from public.users as users
  where profiles.user_id = target_user_id
    and users.id = profiles.user_id
    and users.role = 'driver';

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Target Driver account was not found.';
  end if;
end;
$$;

-- Trigger functions are not public RPCs. The Admin functions are callable by
-- authenticated clients but authorize against trusted table state internally.
alter function public.set_updated_at() set search_path = '';
alter function public.protect_users_restricted_columns() set search_path = '';
alter function public.protect_driver_profile_restricted_columns() set search_path = '';

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.protect_users_restricted_columns() from public, anon, authenticated;
revoke all on function public.protect_driver_profile_restricted_columns() from public, anon, authenticated;

revoke all on function public.admin_promote_user_to_driver(uuid) from public, anon, authenticated;
revoke all on function public.admin_approve_driver(uuid) from public, anon, authenticated;
revoke all on function public.admin_reject_driver(uuid, text) from public, anon, authenticated;

grant execute on function public.admin_promote_user_to_driver(uuid) to authenticated;
grant execute on function public.admin_approve_driver(uuid) to authenticated;
grant execute on function public.admin_reject_driver(uuid, text) to authenticated;
