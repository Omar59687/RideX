begin;

-- P7-A02: preserve canonical tables, state values, signatures and result shapes.
-- Eligibility means approved/nonblocked Driver + owned active vehicle; there is
-- no separate vehicle approval workflow. Reservation/release RPCs are unchanged.
-- last_heartbeat_at has no canonical writer today. Do not impose a freshness
-- cutoff or synthesize heartbeats from availability updates/GPS in this phase.

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
  -- Match migration 016's lifecycle lock order before availability/vehicle locks.
  -- NO KEY UPDATE serializes eligibility changes without blocking FK key-share reads.
  -- Revalidate after waiting: an earlier approval snapshot is not authority.
  perform 1 from public.users where id = auth.uid() for no key update;
  perform 1 from public.driver_profiles where user_id = auth.uid() for no key update;
  caller_id := private.require_approved_driver();
  if requested_state is null or requested_state not in ('offline', 'available') then
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
  availability public.driver_availability%rowtype;
begin
  -- Match migration 016's lifecycle lock order before availability/vehicle locks.
  -- NO KEY UPDATE serializes eligibility changes without blocking FK key-share reads.
  -- Revalidate after waiting: an earlier approval snapshot is not authority.
  perform 1 from public.users where id = auth.uid() for no key update;
  perform 1 from public.driver_profiles where user_id = auth.uid() for no key update;
  caller_id := private.require_approved_driver();
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  select * into availability from public.driver_availability
  where driver_id = caller_id for update;
  select * into previous_vehicle from public.vehicles
  where id = target_vehicle_id and driver_id = caller_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Vehicle was not found for this Driver.';
  end if;
  if previous_vehicle.version <> expected_version then
    raise exception using errcode = '40001', message = 'Vehicle version is stale.';
  end if;
  -- The selected category is part of matching eligibility and must stay stable
  -- until the Driver goes offline. Cosmetic updates remain compatible.
  if availability.state <> 'offline' and availability.vehicle_id = previous_vehicle.id
    and vehicle_type is distinct from previous_vehicle.vehicle_type_code then
    raise exception using errcode = '55000', message = 'An in-use vehicle type cannot be changed.';
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

create or replace function public.driver_set_vehicle_active(target_vehicle_id uuid, expected_version integer, active boolean)
returns public.vehicles
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  target_vehicle public.vehicles%rowtype;
  availability public.driver_availability%rowtype;
  prior_active boolean;
begin
  -- Match migration 016's lifecycle lock order before availability/vehicle locks.
  -- NO KEY UPDATE serializes eligibility changes without blocking FK key-share reads.
  -- Revalidate after waiting: an earlier approval snapshot is not authority.
  perform 1 from public.users where id = auth.uid() for no key update;
  perform 1 from public.driver_profiles where user_id = auth.uid() for no key update;
  caller_id := private.require_approved_driver();
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  select * into availability from public.driver_availability where driver_id = caller_id for update;
  select * into target_vehicle from public.vehicles where id = target_vehicle_id and driver_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Vehicle was not found for this Driver.'; end if;
  if target_vehicle.version <> expected_version then raise exception using errcode = '40001', message = 'Vehicle version is stale.'; end if;
  prior_active := target_vehicle.is_active;
  if active and availability.state <> 'offline' and availability.vehicle_id <> target_vehicle_id then
    raise exception using errcode = '55000', message = 'The active availability vehicle cannot be switched.';
  end if;
  if not active and availability.state <> 'offline' and availability.vehicle_id = target_vehicle_id then
    raise exception using errcode = '55000', message = 'An available, reserved, or on-trip vehicle cannot be deactivated.';
  end if;
  if active then
    update public.vehicles set is_active = false where driver_id = caller_id and is_active and id <> target_vehicle_id;
  end if;
  update public.vehicles set is_active = active where id = target_vehicle_id returning * into target_vehicle;
  perform private.write_audit_record(caller_id, 'driver.vehicle_active_set', caller_id, null,
    jsonb_build_object('vehicle_id', target_vehicle.id, 'is_active', prior_active),
    jsonb_build_object('vehicle_id', target_vehicle.id, 'is_active', active));
  return target_vehicle;
end;
$$;

revoke all on function public.driver_set_availability(public.driver_availability_state, uuid, integer) from public, anon, authenticated, service_role;
grant execute on function public.driver_set_availability(public.driver_availability_state, uuid, integer) to authenticated;
revoke all on function public.driver_update_vehicle(uuid, integer, public.vehicle_type_code, text, text, text, text, smallint, smallint, text) from public, anon, authenticated, service_role;
grant execute on function public.driver_update_vehicle(uuid, integer, public.vehicle_type_code, text, text, text, text, smallint, smallint, text) to authenticated;
revoke all on function public.driver_set_vehicle_active(uuid, integer, boolean) from public, anon, authenticated, service_role;
grant execute on function public.driver_set_vehicle_active(uuid, integer, boolean) to authenticated;

commit;
