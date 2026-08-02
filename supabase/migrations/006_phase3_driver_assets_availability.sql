begin;

create type public.vehicle_type_code as enum ('economy', 'comfort', 'xl');

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.driver_profiles (user_id) on delete restrict,
  vehicle_type_code public.vehicle_type_code not null,
  make text not null,
  model text not null,
  color text not null,
  registration_plate text not null,
  seat_capacity smallint not null,
  model_year smallint,
  photo_url text,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  constraint vehicles_make_bounded check (char_length(btrim(make)) between 1 and 100),
  constraint vehicles_model_bounded check (char_length(btrim(model)) between 1 and 100),
  constraint vehicles_color_bounded check (char_length(btrim(color)) between 1 and 50),
  constraint vehicles_registration_plate_normalized check (
    registration_plate = upper(btrim(registration_plate))
    and char_length(registration_plate) between 3 and 32
    and registration_plate ~ '^[A-Z0-9][A-Z0-9 -]*[A-Z0-9]$'
  ),
  constraint vehicles_seat_capacity_bounded check (seat_capacity between 1 and 12),
  constraint vehicles_model_year_bounded check (model_year is null or model_year between 1886 and 2100),
  constraint vehicles_photo_url_safe check (photo_url is null or (char_length(photo_url) <= 2048 and photo_url ~ '^https://')),
  constraint vehicles_version_positive check (version > 0),
  constraint vehicles_registration_plate_unique unique (registration_plate)
);

create unique index vehicles_one_active_per_driver_idx
  on public.vehicles (driver_id) where is_active;
create index vehicles_driver_id_idx on public.vehicles (driver_id);

create table public.driver_availability (
  driver_id uuid primary key references public.driver_profiles (user_id) on delete restrict,
  state public.driver_availability_state not null default 'offline',
  vehicle_id uuid references public.vehicles (id) on delete restrict,
  reserved_booking_request_id uuid,
  active_trip_id uuid,
  last_heartbeat_at timestamptz,
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  constraint driver_availability_version_positive check (version > 0),
  constraint driver_availability_state_references_valid check (
    (state = 'offline' and vehicle_id is null and reserved_booking_request_id is null and active_trip_id is null)
    or (state = 'available' and vehicle_id is not null and reserved_booking_request_id is null and active_trip_id is null)
    or (state = 'reserved' and vehicle_id is not null and reserved_booking_request_id is not null and active_trip_id is null)
    or (state = 'onTrip' and vehicle_id is not null and reserved_booking_request_id is null and active_trip_id is not null)
  )
);

create index driver_availability_state_idx on public.driver_availability (state);
create index driver_availability_vehicle_id_idx on public.driver_availability (vehicle_id);

-- Legacy flags remain readable compatibility fields; driver_availability is canonical.
comment on column public.driver_profiles.is_online is 'Deprecated compatibility field; use public.driver_availability.state.';
comment on column public.driver_profiles.is_available is 'Deprecated compatibility field; use public.driver_availability.state.';

insert into public.driver_availability (driver_id, state)
select profiles.user_id, 'offline'
from public.driver_profiles as profiles
on conflict (driver_id) do nothing;

create or replace function private.bump_vehicle_or_availability_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.version := old.version + 1;
  return new;
end;
$$;

create trigger vehicles_set_updated_at
before update on public.vehicles
for each row execute function public.set_updated_at();

create trigger vehicles_bump_optimistic_version
before update on public.vehicles
for each row execute function private.bump_vehicle_or_availability_version();

create trigger driver_availability_set_updated_at
before update on public.driver_availability
for each row execute function public.set_updated_at();

create trigger driver_availability_bump_optimistic_version
before update on public.driver_availability
for each row execute function private.bump_vehicle_or_availability_version();

create or replace function private.require_approved_driver()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
begin
  if caller_id is null or not exists (
    select 1
    from public.users as users
    join public.driver_profiles as profiles on profiles.user_id = users.id
    where users.id = caller_id
      and users.role = 'driver'
      and not users.is_blocked
      and profiles.approval_status = 'approved'
  ) then
    raise exception using errcode = '42501', message = 'Only an approved, non-blocked Driver can manage vehicles or availability.';
  end if;
  return caller_id;
end;
$$;

create or replace function public.driver_create_vehicle(
  vehicle_type public.vehicle_type_code,
  vehicle_make text,
  vehicle_model text,
  vehicle_color text,
  vehicle_registration_plate text,
  vehicle_seat_capacity smallint,
  vehicle_model_year smallint default null,
  vehicle_photo_url text default null
)
returns public.vehicles
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  created_vehicle public.vehicles%rowtype;
begin
  caller_id := private.require_approved_driver();
  insert into public.vehicles (
    driver_id, vehicle_type_code, make, model, color, registration_plate,
    seat_capacity, model_year, photo_url
  ) values (
    caller_id, vehicle_type, btrim(vehicle_make), btrim(vehicle_model), btrim(vehicle_color),
    upper(btrim(vehicle_registration_plate)), vehicle_seat_capacity, vehicle_model_year, btrim(vehicle_photo_url)
  ) returning * into created_vehicle;
  perform private.write_audit_record(caller_id, 'driver.vehicle_created', caller_id, null,
    '{}'::jsonb, jsonb_build_object('vehicle_id', created_vehicle.id, 'plate', created_vehicle.registration_plate, 'type', created_vehicle.vehicle_type_code));
  return created_vehicle;
end;
$$;

create or replace function public.driver_update_vehicle(
  target_vehicle_id uuid,
  expected_version integer,
  vehicle_type public.vehicle_type_code,
  vehicle_make text,
  vehicle_model text,
  vehicle_color text,
  vehicle_registration_plate text,
  vehicle_seat_capacity smallint,
  vehicle_model_year smallint default null,
  vehicle_photo_url text default null
)
returns public.vehicles
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  previous_vehicle public.vehicles%rowtype;
  updated_vehicle public.vehicles%rowtype;
begin
  caller_id := private.require_approved_driver();
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  select * into previous_vehicle from public.vehicles
  where id = target_vehicle_id and driver_id = caller_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Vehicle was not found for this Driver.';
  end if;
  if previous_vehicle.version <> expected_version then
    raise exception using errcode = '40001', message = 'Vehicle version is stale.';
  end if;
  update public.vehicles set
    vehicle_type_code = vehicle_type,
    make = btrim(vehicle_make), model = btrim(vehicle_model), color = btrim(vehicle_color),
    registration_plate = upper(btrim(vehicle_registration_plate)), seat_capacity = vehicle_seat_capacity,
    model_year = vehicle_model_year, photo_url = btrim(vehicle_photo_url)
  where id = target_vehicle_id
  returning * into updated_vehicle;
  perform private.write_audit_record(caller_id, 'driver.vehicle_updated', caller_id, null,
    jsonb_build_object('vehicle_id', previous_vehicle.id, 'plate', previous_vehicle.registration_plate, 'type', previous_vehicle.vehicle_type_code),
    jsonb_build_object('vehicle_id', updated_vehicle.id, 'plate', updated_vehicle.registration_plate, 'type', updated_vehicle.vehicle_type_code));
  return updated_vehicle;
end;
$$;

create or replace function public.driver_set_vehicle_active(
  target_vehicle_id uuid,
  expected_version integer,
  active boolean
)
returns public.vehicles
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  target_vehicle public.vehicles%rowtype;
  prior_active boolean;
begin
  caller_id := private.require_approved_driver();
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  select * into target_vehicle from public.vehicles
  where id = target_vehicle_id and driver_id = caller_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Vehicle was not found for this Driver.';
  end if;
  if target_vehicle.version <> expected_version then
    raise exception using errcode = '40001', message = 'Vehicle version is stale.';
  end if;
  prior_active := target_vehicle.is_active;
  if active then
    update public.vehicles set is_active = false
    where driver_id = caller_id and is_active and id <> target_vehicle_id;
  elsif exists (
    select 1 from public.driver_availability
    where driver_id = caller_id and state <> 'offline' and vehicle_id = target_vehicle_id
  ) then
    raise exception using errcode = '55000', message = 'An available, reserved, or on-trip vehicle cannot be deactivated.';
  end if;
  update public.vehicles set is_active = active where id = target_vehicle_id returning * into target_vehicle;
  perform private.write_audit_record(caller_id, 'driver.vehicle_active_set', caller_id, null,
    jsonb_build_object('vehicle_id', target_vehicle.id, 'is_active', prior_active),
    jsonb_build_object('vehicle_id', target_vehicle.id, 'is_active', active));
  return target_vehicle;
end;
$$;

create or replace function public.driver_set_availability(
  requested_state public.driver_availability_state,
  requested_vehicle_id uuid default null,
  expected_version integer default null
)
returns public.driver_availability
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_availability public.driver_availability%rowtype;
  selected_vehicle public.vehicles%rowtype;
  prior_state public.driver_availability_state;
  prior_vehicle_id uuid;
begin
  caller_id := private.require_approved_driver();
  if requested_state not in ('offline', 'available') then
    raise exception using errcode = '22023', message = 'Drivers can request only offline or available availability states.';
  end if;
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  select * into current_availability from public.driver_availability where driver_id = caller_id for update;
  if not found or current_availability.version <> expected_version then
    raise exception using errcode = '40001', message = 'Availability version is stale.';
  end if;
  if current_availability.state in ('reserved', 'onTrip') then
    raise exception using errcode = '55000', message = 'Matching or Trip services own the current availability state.';
  end if;
  prior_state := current_availability.state;
  prior_vehicle_id := current_availability.vehicle_id;
  if requested_state = 'available' then
    select * into selected_vehicle from public.vehicles
    where id = requested_vehicle_id and driver_id = caller_id and is_active for update;
    if not found then
      raise exception using errcode = '22023', message = 'Available state requires this Driver''s active vehicle.';
    end if;
    update public.driver_availability set state = 'available', vehicle_id = selected_vehicle.id,
      reserved_booking_request_id = null, active_trip_id = null
    where driver_id = caller_id returning * into current_availability;
  else
    update public.driver_availability set state = 'offline', vehicle_id = null,
      reserved_booking_request_id = null, active_trip_id = null, last_heartbeat_at = null
    where driver_id = caller_id returning * into current_availability;
  end if;
  perform private.write_audit_record(caller_id, 'driver.availability_set', caller_id, null,
    jsonb_build_object('state', prior_state, 'vehicle_id', prior_vehicle_id),
    jsonb_build_object('state', requested_state, 'vehicle_id', current_availability.vehicle_id));
  return current_availability;
end;
$$;

alter table public.vehicles enable row level security;
alter table public.driver_availability enable row level security;

create policy vehicles_driver_or_admin_select on public.vehicles for select to authenticated using (
  exists (select 1 from public.users where id = auth.uid() and not is_blocked and (id = vehicles.driver_id or role = 'admin'))
);
create policy driver_availability_driver_or_admin_select on public.driver_availability for select to authenticated using (
  exists (select 1 from public.users where id = auth.uid() and not is_blocked and (id = driver_availability.driver_id or role = 'admin'))
);

revoke all on table public.vehicles, public.driver_availability from public, anon, authenticated;
grant select on table public.vehicles, public.driver_availability to authenticated;

revoke all on function private.bump_vehicle_or_availability_version() from public, anon, authenticated;
revoke all on function private.require_approved_driver() from public, anon, authenticated;
revoke all on function public.driver_create_vehicle(public.vehicle_type_code, text, text, text, text, smallint, smallint, text) from public, anon, authenticated;
revoke all on function public.driver_update_vehicle(uuid, integer, public.vehicle_type_code, text, text, text, text, smallint, smallint, text) from public, anon, authenticated;
revoke all on function public.driver_set_vehicle_active(uuid, integer, boolean) from public, anon, authenticated;
revoke all on function public.driver_set_availability(public.driver_availability_state, uuid, integer) from public, anon, authenticated;
grant execute on function public.driver_create_vehicle(public.vehicle_type_code, text, text, text, text, smallint, smallint, text) to authenticated;
grant execute on function public.driver_update_vehicle(uuid, integer, public.vehicle_type_code, text, text, text, text, smallint, smallint, text) to authenticated;
grant execute on function public.driver_set_vehicle_active(uuid, integer, boolean) to authenticated;
grant execute on function public.driver_set_availability(public.driver_availability_state, uuid, integer) to authenticated;

commit;
