create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  declared_role text;
  declared_name text;
begin
  declared_role := lower(trim(coalesce(new.raw_user_meta_data ->> 'role', '')));
  declared_name := trim(coalesce(new.raw_user_meta_data ->> 'display_name', ''));

  if declared_role not in ('rider', 'driver') then
    raise exception 'Invalid signup role.';
  end if;

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
    declared_role,
    declared_name,
    new.email
  );

  if declared_role = 'rider' then
    insert into public.rider_profiles (user_id)
    values (new.id);
  else
    insert into public.driver_profiles (user_id, approval_status)
    values (new.id, 'pending');
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();
