create table if not exists public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('rider', 'driver', 'admin')),
  display_name text not null,
  email text not null unique,
  photo_url text,
  is_blocked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.rider_profiles (
  user_id uuid primary key references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.driver_profiles (
  user_id uuid primary key references public.users (id) on delete cascade,
  approval_status text not null default 'pending' check (approval_status in ('pending', 'approved', 'rejected')),
  rejection_reason text,
  is_online boolean not null default false,
  is_available boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists users_role_idx on public.users (role);
create index if not exists users_is_blocked_idx on public.users (is_blocked);
create index if not exists driver_profiles_approval_status_idx on public.driver_profiles (approval_status);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists users_set_updated_at on public.users;
create trigger users_set_updated_at
before update on public.users
for each row
execute function public.set_updated_at();

drop trigger if exists rider_profiles_set_updated_at on public.rider_profiles;
create trigger rider_profiles_set_updated_at
before update on public.rider_profiles
for each row
execute function public.set_updated_at();

drop trigger if exists driver_profiles_set_updated_at on public.driver_profiles;
create trigger driver_profiles_set_updated_at
before update on public.driver_profiles
for each row
execute function public.set_updated_at();
