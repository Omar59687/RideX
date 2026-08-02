begin;

alter table public.trips
  add constraint trips_id_driver_unique unique (id, driver_id);

create table public.driver_locations (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.driver_profiles (user_id) on delete restrict,
  trip_id uuid,
  sequence bigint not null,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_meters double precision not null,
  heading_degrees double precision,
  speed_meters_per_second double precision,
  recorded_at timestamptz not null,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint driver_locations_trip_driver_fk foreign key (trip_id, driver_id)
    references public.trips (id, driver_id) on delete restrict,
  constraint driver_locations_driver_sequence_unique unique (driver_id, sequence),
  constraint driver_locations_sequence_positive check (sequence > 0),
  constraint driver_locations_latitude_valid check (latitude not in ('NaN'::float8, 'Infinity'::float8, '-Infinity'::float8) and latitude between -90 and 90),
  constraint driver_locations_longitude_valid check (longitude not in ('NaN'::float8, 'Infinity'::float8, '-Infinity'::float8) and longitude between -180 and 180),
  constraint driver_locations_accuracy_valid check (accuracy_meters not in ('NaN'::float8, 'Infinity'::float8, '-Infinity'::float8) and accuracy_meters >= 0),
  constraint driver_locations_heading_valid check (
    heading_degrees is null or (heading_degrees not in ('NaN'::float8, 'Infinity'::float8, '-Infinity'::float8) and heading_degrees >= 0 and heading_degrees < 360)
  ),
  constraint driver_locations_speed_valid check (
    speed_meters_per_second is null or (speed_meters_per_second not in ('NaN'::float8, 'Infinity'::float8, '-Infinity'::float8) and speed_meters_per_second >= 0)
  )
);

create index driver_locations_driver_received_idx
  on public.driver_locations (driver_id, received_at desc);
create index driver_locations_driver_sequence_idx
  on public.driver_locations (driver_id, sequence desc);
create index driver_locations_trip_received_idx
  on public.driver_locations (trip_id, received_at desc) where trip_id is not null;
create index driver_locations_received_at_idx on public.driver_locations (received_at);

create or replace function public.driver_record_location(
  requested_trip_id uuid,
  requested_sequence bigint,
  requested_latitude double precision,
  requested_longitude double precision,
  requested_accuracy_meters double precision,
  requested_heading_degrees double precision,
  requested_speed_meters_per_second double precision,
  requested_recorded_at timestamptz
)
returns public.driver_locations
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  availability public.driver_availability%rowtype;
  location public.driver_locations%rowtype;
begin
  caller_id := private.require_approved_driver();

  select * into availability
  from public.driver_availability
  where driver_id = caller_id
  for update;

  if not found or availability.state not in ('available', 'reserved', 'onTrip') then
    raise exception using errcode = '55000', message = 'Driver location requires available, reserved, or on-trip availability.';
  end if;

  if availability.state = 'onTrip' then
    if requested_trip_id is null or requested_trip_id <> availability.active_trip_id
      or not exists (
        select 1 from public.trips
        where id = requested_trip_id
          and driver_id = caller_id
          and status in ('accepted', 'driverArriving', 'driverArrived', 'inProgress')
      ) then
      raise exception using errcode = '22023', message = 'On-trip location requires this Driver''s active Trip.';
    end if;
  elsif requested_trip_id is not null then
    raise exception using errcode = '22023', message = 'Trip location association is allowed only while on a Trip.';
  end if;

  if requested_recorded_at < now() - interval '15 minutes'
    or requested_recorded_at > now() + interval '5 minutes' then
    raise exception using errcode = '22023', message = 'Location timestamp is outside the accepted time window.';
  end if;

  if exists (
    select 1 from public.driver_locations
    where driver_id = caller_id and sequence >= requested_sequence
  ) then
    raise exception using errcode = '23505', message = 'Location sequence must increase for this Driver.';
  end if;

  insert into public.driver_locations (
    driver_id, trip_id, sequence, latitude, longitude, accuracy_meters,
    heading_degrees, speed_meters_per_second, recorded_at
  ) values (
    caller_id, requested_trip_id, requested_sequence, requested_latitude,
    requested_longitude, requested_accuracy_meters, requested_heading_degrees,
    requested_speed_meters_per_second, requested_recorded_at
  ) returning * into location;

  return location;
end;
$$;

create or replace function public.backend_purge_expired_driver_locations()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_count bigint;
begin
  delete from public.driver_locations
  where received_at < now() - interval '7 days';
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

alter table public.driver_locations enable row level security;

create policy driver_locations_participant_select on public.driver_locations for select to authenticated using (
  exists (
    select 1 from public.users
    where id = auth.uid()
      and not is_blocked
      and (
        (role = 'driver' and id = driver_locations.driver_id)
        or (role = 'admin')
        or (role = 'rider' and exists (
          select 1 from public.trips
          where id = driver_locations.trip_id and rider_id = auth.uid()
            and status in ('accepted', 'driverArriving', 'driverArrived', 'inProgress')
        ))
      )
  )
);

revoke all on table public.driver_locations from public, anon, authenticated;
grant select on table public.driver_locations to authenticated;

revoke all on function public.driver_record_location(uuid, bigint, double precision, double precision, double precision, double precision, double precision, timestamptz) from public, anon, authenticated;
revoke all on function public.backend_purge_expired_driver_locations() from public, anon, authenticated;
grant execute on function public.driver_record_location(uuid, bigint, double precision, double precision, double precision, double precision, double precision, timestamptz) to authenticated;
grant execute on function public.backend_purge_expired_driver_locations() to service_role;

commit;
