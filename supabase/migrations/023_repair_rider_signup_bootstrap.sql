begin;

-- Dashboard-created users do not necessarily include raw user metadata. Keep
-- public signup Rider-only while deriving a safe display name when the trusted
-- Auth Admin API omits display_name.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  declared_name text;
begin
  if new.email is null or btrim(new.email) = '' then
    raise exception using
      errcode = '22023',
      message = 'Email is required.';
  end if;

  declared_name := btrim(coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  if declared_name = '' then
    declared_name := btrim(split_part(new.email, '@', 1));
  end if;
  if declared_name = '' then
    declared_name := 'RideX Rider';
  end if;
  declared_name := left(declared_name, 100);

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

revoke all on function public.handle_new_user() from public, anon, authenticated;

commit;
