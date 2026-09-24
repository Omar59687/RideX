begin;

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
    where driver_id = caller_id and recorded_at >= requested_recorded_at
  ) then
    raise exception using errcode = '23505', message = 'Location timestamp must increase for this Driver.';
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

commit;
