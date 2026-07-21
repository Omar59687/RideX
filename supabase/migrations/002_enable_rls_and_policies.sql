revoke all on table public.users from anon, authenticated;
revoke all on table public.rider_profiles from anon, authenticated;
revoke all on table public.driver_profiles from anon, authenticated;

grant select on table public.users to authenticated;
grant update (display_name, photo_url) on table public.users to authenticated;

grant select on table public.rider_profiles to authenticated;
grant select on table public.driver_profiles to authenticated;

alter table public.users enable row level security;
alter table public.rider_profiles enable row level security;
alter table public.driver_profiles enable row level security;

drop policy if exists users_select_own on public.users;
create policy users_select_own
on public.users
for select
to authenticated
using (auth.uid() = id);

drop policy if exists users_update_own_safe_fields on public.users;
create policy users_update_own_safe_fields
on public.users
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists rider_profiles_select_own on public.rider_profiles;
create policy rider_profiles_select_own
on public.rider_profiles
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists driver_profiles_select_own on public.driver_profiles;
create policy driver_profiles_select_own
on public.driver_profiles
for select
to authenticated
using (auth.uid() = user_id);

create or replace function public.protect_users_restricted_columns()
returns trigger
language plpgsql
as $$
begin
  if current_user not in ('postgres', 'service_role') then
    if new.id <> old.id
      or new.email is distinct from old.email
      or new.role is distinct from old.role
      or new.is_blocked is distinct from old.is_blocked then
      raise exception 'Restricted user columns cannot be updated directly.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists users_protect_restricted_columns on public.users;
create trigger users_protect_restricted_columns
before update on public.users
for each row
execute function public.protect_users_restricted_columns();

create or replace function public.protect_driver_profile_restricted_columns()
returns trigger
language plpgsql
as $$
begin
  if current_user not in ('postgres', 'service_role') then
    if new.user_id <> old.user_id
      or new.approval_status is distinct from old.approval_status
      or new.rejection_reason is distinct from old.rejection_reason then
      raise exception 'Restricted driver profile columns cannot be updated directly.';
    end if;

    if new.is_online is distinct from old.is_online
      or new.is_available is distinct from old.is_available then
      raise exception 'Driver availability fields are not client-editable in Phase 2.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists driver_profiles_protect_restricted_columns on public.driver_profiles;
create trigger driver_profiles_protect_restricted_columns
before update on public.driver_profiles
for each row
execute function public.protect_driver_profile_restricted_columns();
