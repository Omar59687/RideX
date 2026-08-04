begin;

-- Keep the canonical availability aggregate present whenever a Driver profile exists.
insert into public.driver_availability (driver_id, state)
select profiles.user_id, 'offline'
from public.driver_profiles as profiles
on conflict (driver_id) do nothing;

create or replace function private.reconcile_driver_availability(target_driver_id uuid)
returns public.driver_availability
language plpgsql
security definer
set search_path = ''
as $$
declare
  availability public.driver_availability%rowtype;
begin
  insert into public.driver_availability (driver_id, state)
  values (target_driver_id, 'offline')
  on conflict (driver_id) do nothing;

  select * into availability
  from public.driver_availability
  where driver_id = target_driver_id
  for update;
  return availability;
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
  if not found then raise exception using errcode = 'P0002', message = 'Target account was not found.'; end if;
  if target_role <> 'rider' then raise exception using errcode = '22023', message = 'Only a Rider account can be promoted to Driver.'; end if;

  perform set_config('ridex.audit_actor_id', caller_id::text, true);
  perform set_config('ridex.audit_action', 'admin.driver_promoted', true);
  update public.users set role = 'driver' where id = target_user_id;
  delete from public.rider_profiles where user_id = target_user_id;
  insert into public.driver_profiles (user_id, approval_status, rejection_reason, is_online, is_available)
  values (target_user_id, 'pending', null, false, false)
  on conflict (user_id) do update
  set approval_status = 'pending', rejection_reason = null, is_online = false, is_available = false;
  perform private.reconcile_driver_availability(target_user_id);
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
  if not found then raise exception using errcode = 'P0002', message = 'Target Driver account was not found.'; end if;
  perform private.reconcile_driver_availability(target_user_id);
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
  perform private.reconcile_driver_availability(target_user_id);
  perform set_config('ridex.audit_actor_id', caller_id::text, true);
  perform set_config('ridex.audit_action', 'admin.driver_rejected', true);
  perform set_config('ridex.audit_reason', btrim(reason), true);
  update public.driver_profiles as profiles
  set approval_status = 'rejected', rejection_reason = btrim(reason)
  from public.users as users
  where profiles.user_id = target_user_id and users.id = profiles.user_id and users.role = 'driver';
  if not found then raise exception using errcode = 'P0002', message = 'Target Driver account was not found.'; end if;
  update public.driver_availability set state = 'offline', vehicle_id = null,
    reserved_booking_request_id = null, active_trip_id = null, last_heartbeat_at = null
  where driver_id = target_user_id;
end;
$$;

create or replace function public.admin_set_user_blocked(target_user_id uuid, blocked boolean, audit_reason text)
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
  if char_length(btrim(coalesce(audit_reason, ''))) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'A nonblank audit reason is required.';
  end if;
  select role into target_role from public.users where id = target_user_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Target account was not found.'; end if;
  if blocked and target_role = 'driver' then
    perform private.reconcile_driver_availability(target_user_id);
    update public.driver_availability set state = 'offline', vehicle_id = null,
      reserved_booking_request_id = null, active_trip_id = null, last_heartbeat_at = null
    where driver_id = target_user_id;
  end if;
  perform set_config('ridex.audit_actor_id', caller_id::text, true);
  perform set_config('ridex.audit_action', 'admin.user_blocked_state_set', true);
  perform set_config('ridex.audit_reason', btrim(audit_reason), true);
  update public.users set is_blocked = blocked where id = target_user_id;
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

create or replace function public.service_reserve_driver_for_booking(
  target_driver_id uuid, target_booking_request_id uuid, target_vehicle_id uuid,
  expected_availability_version integer
)
returns public.driver_availability
language plpgsql
security definer
set search_path = ''
as $$
declare
  availability public.driver_availability%rowtype;
  booking public.booking_requests%rowtype;
begin
  if expected_availability_version is null or expected_availability_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  select * into availability from public.driver_availability where driver_id = target_driver_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Driver availability was not found.'; end if;
  if availability.version <> expected_availability_version then raise exception using errcode = '40001', message = 'Availability version is stale.'; end if;
  select * into booking from public.booking_requests where id = target_booking_request_id for update;
  if not found or booking.status <> 'searching' then raise exception using errcode = '55000', message = 'Booking is not eligible for reservation.'; end if;
  if availability.state <> 'available' or availability.vehicle_id <> target_vehicle_id
    or not exists (
      select 1 from public.users as users join public.driver_profiles as profiles on profiles.user_id = users.id
      join public.vehicles as vehicles on vehicles.id = target_vehicle_id and vehicles.driver_id = users.id
      where users.id = target_driver_id and users.role = 'driver' and not users.is_blocked
        and profiles.approval_status = 'approved' and vehicles.is_active
        and vehicles.vehicle_type_code = booking.vehicle_type_code
    ) then
    raise exception using errcode = '55000', message = 'Driver availability or vehicle is not eligible for reservation.';
  end if;
  update public.driver_availability set state = 'reserved', reserved_booking_request_id = booking.id,
    active_trip_id = null where driver_id = target_driver_id returning * into availability;
  return availability;
end;
$$;

create or replace function public.service_release_driver_reservation(
  target_driver_id uuid, target_booking_request_id uuid, expected_availability_version integer
)
returns public.driver_availability
language plpgsql
security definer
set search_path = ''
as $$
declare
  availability public.driver_availability%rowtype;
begin
  if expected_availability_version is null or expected_availability_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  select * into availability from public.driver_availability where driver_id = target_driver_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Driver availability was not found.'; end if;
  if availability.version <> expected_availability_version then raise exception using errcode = '40001', message = 'Availability version is stale.'; end if;
  if availability.state <> 'reserved' or availability.reserved_booking_request_id <> target_booking_request_id then
    raise exception using errcode = '55000', message = 'Driver does not hold this Booking reservation.';
  end if;
  update public.driver_availability set state = 'available', reserved_booking_request_id = null,
    active_trip_id = null where driver_id = target_driver_id returning * into availability;
  return availability;
end;
$$;

create or replace function private.reserve_driver_for_match_offer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  availability public.driver_availability%rowtype;
begin
  select * into availability from public.driver_availability
  where driver_id = new.driver_id for update;
  if not found or availability.state <> 'available' or availability.vehicle_id <> new.vehicle_id then
    raise exception using errcode = '55000', message = 'Matching offers require an available Driver and matching active vehicle.';
  end if;
  update public.driver_availability set state = 'reserved',
    reserved_booking_request_id = new.booking_request_id, active_trip_id = null
  where driver_id = new.driver_id;
  return new;
end;
$$;

create trigger driver_match_offers_reserve_driver
after insert on public.driver_match_offers
for each row execute function private.reserve_driver_for_match_offer();

create or replace function public.backend_create_driver_match_offer(
  target_booking_request_id uuid, target_driver_id uuid, target_vehicle_id uuid,
  requested_radius_meters integer, expected_booking_version integer
)
returns public.driver_match_offers
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_booking public.booking_requests%rowtype;
  created_offer public.driver_match_offers%rowtype;
begin
  if requested_radius_meters not in (3000, 5000, 8000) or expected_booking_version is null or expected_booking_version < 1 then
    raise exception using errcode = '22023', message = 'Matching offer inputs are invalid.';
  end if;
  select * into current_booking from public.booking_requests where id = target_booking_request_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Booking was not found.'; end if;
  if current_booking.version <> expected_booking_version then raise exception using errcode = '40001', message = 'Booking version is stale.'; end if;
  if current_booking.status not in ('confirmed', 'searching') or current_booking.fare_quote_id is null
    or not exists (select 1 from public.fare_quotes where id = current_booking.fare_quote_id and status = 'locked') then
    raise exception using errcode = '55000', message = 'Matching offers require a confirmed or searching booking with a locked FareQuote.';
  end if;
  if not exists (select 1 from public.users where id = current_booking.rider_id and role = 'rider' and not is_blocked) then
    raise exception using errcode = '42501', message = 'A blocked Rider cannot enter matching.';
  end if;
  if current_booking.searching_at is not null and current_booking.searching_at + interval '90 seconds' <= now() then
    raise exception using errcode = '55000', message = 'The matching window has expired.';
  end if;
  if not exists (
    select 1 from public.users as users
    join public.driver_profiles as profiles on profiles.user_id = users.id
    join public.vehicles as vehicles on vehicles.driver_id = profiles.user_id
    join public.driver_availability as availability on availability.driver_id = profiles.user_id
    where users.id = target_driver_id and users.role = 'driver' and not users.is_blocked
      and profiles.approval_status = 'approved' and vehicles.id = target_vehicle_id
      and vehicles.is_active and vehicles.vehicle_type_code = current_booking.vehicle_type_code
      and availability.vehicle_id = vehicles.id
      and (availability.state = 'available' or (availability.state = 'reserved' and availability.reserved_booking_request_id = current_booking.id))
  ) then raise exception using errcode = '42501', message = 'Driver is not eligible for this matching offer.'; end if;
  update public.driver_match_offers set status = 'expired', responded_at = now()
  where booking_request_id = current_booking.id and status = 'offered' and expires_at <= now();
  if (select count(*) from public.driver_match_offers where booking_request_id = current_booking.id and status = 'offered' and expires_at > now()) >= 3 then
    raise exception using errcode = '54000', message = 'A booking can have at most three active matching offers.';
  end if;
  if current_booking.status = 'confirmed' then update public.booking_requests set status = 'searching', searching_at = now() where id = current_booking.id; end if;
  insert into public.driver_match_offers (booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters)
  values (current_booking.id, current_booking.fare_quote_id, target_driver_id, target_vehicle_id, requested_radius_meters)
  returning * into created_offer;
  return created_offer;
end;
$$;

-- Assignment can only consume the backend's reservation, not an arbitrary available Driver.
create or replace function public.driver_transition_trip(target_id uuid, requested_status public.trip_status, expected_version integer, idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid; current_offer public.driver_match_offers%rowtype; current_booking public.booking_requests%rowtype;
  current_quote public.fare_quotes%rowtype; current_availability public.driver_availability%rowtype;
  current_trip public.trips%rowtype; created_trip public.trips%rowtype; previous_status public.trip_status;
  payload_fingerprint text; canonical_result jsonb; claimed_result jsonb; event_reason text;
begin
  caller_id := private.require_approved_driver();
  if expected_version is null or expected_version < 1 then raise exception using errcode = '22023', message = 'A positive expected version is required.'; end if;
  payload_fingerprint := encode(extensions.digest(convert_to(concat_ws('|', target_id::text, requested_status::text, expected_version::text), 'UTF8'), 'sha256'), 'hex');
  canonical_result := jsonb_build_object('target_id', target_id, 'status', requested_status);
  claimed_result := private.claim_command_idempotency_key(caller_id, 'trip', idempotency_key, payload_fingerprint, canonical_result);
  if claimed_result ? 'error' then return claimed_result; end if;
  if requested_status = 'accepted' then
    select * into current_offer from public.driver_match_offers where id = target_id and driver_id = caller_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'Matching offer was not found for this Driver.'; end if;
    if current_offer.status = 'accepted' then select * into created_trip from public.trips where booking_request_id = current_offer.booking_request_id; return jsonb_build_object('trip_id', created_trip.id, 'status', created_trip.status); end if;
    if current_offer.version <> expected_version then raise exception using errcode = '40001', message = 'Matching offer version is stale.'; end if;
    if current_offer.status <> 'offered' or current_offer.expires_at <= now() then raise exception using errcode = '55000', message = 'Only a live offered match can create a Trip.'; end if;
    select * into current_booking from public.booking_requests where id = current_offer.booking_request_id for update;
    if current_booking.status <> 'searching' or current_booking.fare_quote_id <> current_offer.fare_quote_id then raise exception using errcode = '55000', message = 'The booking is no longer available for assignment.'; end if;
    select * into current_quote from public.fare_quotes where id = current_offer.fare_quote_id and status = 'locked' for share;
    if not found then raise exception using errcode = '55000', message = 'Trip creation requires the booking locked FareQuote.'; end if;
    select * into current_availability from public.driver_availability where driver_id = caller_id for update;
    if current_availability.state <> 'reserved' or current_availability.vehicle_id <> current_offer.vehicle_id
      or current_availability.reserved_booking_request_id <> current_booking.id
      or not exists (select 1 from public.vehicles where id = current_offer.vehicle_id and driver_id = caller_id and is_active and vehicle_type_code = current_booking.vehicle_type_code) then
      raise exception using errcode = '55000', message = 'Driver reservation or vehicle is no longer compatible.';
    end if;
    insert into public.trips (booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id, payment_method, pickup, destination, route_distance_meters, route_duration_seconds, route_geometry_reference, original_fare_fils, current_fare_fils)
    values (current_booking.id, current_quote.id, current_booking.rider_id, caller_id, current_offer.vehicle_id, current_booking.payment_method, current_quote.pickup, current_quote.destination, current_quote.route_distance_meters, current_quote.route_duration_seconds, current_quote.route_geometry_reference, current_quote.fixed_fare_fils, current_quote.fixed_fare_fils) returning * into created_trip;
    perform set_config('ridex.trip_stop_mutation', 'on', true);
    insert into public.trip_stops (trip_id, sequence, location, label, rider_note) select created_trip.id, sequence, location, label, rider_note from public.booking_stops where booking_request_id = current_booking.id order by sequence;
    update public.driver_match_offers set status = (case when id = current_offer.id then 'accepted' else 'cancelled' end)::public.driver_match_offer_status, responded_at = now() where booking_request_id = current_booking.id and status = 'offered';
    update public.driver_availability set state = 'available', reserved_booking_request_id = null,
      active_trip_id = null
    where reserved_booking_request_id = current_booking.id and driver_id <> caller_id and state = 'reserved';
    update public.booking_requests set status = 'matched', matched_at = now(), matched_driver_id = caller_id, matched_vehicle_id = current_offer.vehicle_id where id = current_booking.id;
    update public.driver_availability set state = 'onTrip', reserved_booking_request_id = null, active_trip_id = created_trip.id where driver_id = caller_id;
    perform private.append_trip_status_event(created_trip.id, null, 'accepted', caller_id, null);
    perform private.write_audit_record(caller_id, 'trip.accepted', current_booking.rider_id, null, jsonb_build_object('match_offer_id', current_offer.id), jsonb_build_object('trip_id', created_trip.id, 'status', created_trip.status));
    update public.command_idempotency_keys set canonical_result = jsonb_build_object('trip_id', created_trip.id, 'status', created_trip.status) where actor_user_id = caller_id and command_scope = 'trip' and command_idempotency_keys.idempotency_key = btrim(driver_transition_trip.idempotency_key);
    return jsonb_build_object('trip_id', created_trip.id, 'status', created_trip.status);
  end if;
  select * into current_trip from public.trips where id = target_id and driver_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Trip was not found for this Driver.'; end if;
  if current_trip.status = requested_status then return jsonb_build_object('trip_id', current_trip.id, 'status', current_trip.status); end if;
  if current_trip.version <> expected_version then raise exception using errcode = '40001', message = 'Trip version is stale.'; end if;
  if requested_status not in ('driverArriving', 'driverArrived', 'inProgress', 'completed', 'cancelledByDriver') then raise exception using errcode = '22023', message = 'Drivers cannot request this Trip status.'; end if;
  if requested_status = 'completed' then if exists (select 1 from public.trip_change_requests where trip_id = current_trip.id and status = 'approved') then raise exception using errcode = '55000', message = 'An approved fare adjustment must be applied before completion.'; end if; perform private.cancel_unresolved_trip_changes(current_trip.id); end if;
  if requested_status = 'cancelledByDriver' then event_reason := 'driver_cancelled'; end if;
  previous_status := current_trip.status;
  update public.trips set status = requested_status, driver_arriving_at = case when requested_status = 'driverArriving' then now() else driver_arriving_at end, driver_arrived_at = case when requested_status = 'driverArrived' then now() else driver_arrived_at end, in_progress_at = case when requested_status = 'inProgress' then now() else in_progress_at end, completed_at = case when requested_status = 'completed' then now() else completed_at end, terminated_at = case when requested_status = 'cancelledByDriver' then now() else terminated_at end, termination_reason_code = case when requested_status = 'cancelledByDriver' then event_reason else termination_reason_code end where id = current_trip.id returning * into current_trip;
  if requested_status in ('completed', 'cancelledByDriver') then update public.driver_availability set state = 'offline', vehicle_id = null, active_trip_id = null, reserved_booking_request_id = null, last_heartbeat_at = null where driver_id = caller_id and active_trip_id = current_trip.id; end if;
  perform private.append_trip_status_event(current_trip.id, previous_status, requested_status, caller_id, event_reason);
  update public.command_idempotency_keys set canonical_result = jsonb_build_object('trip_id', current_trip.id, 'status', current_trip.status) where actor_user_id = caller_id and command_scope = 'trip' and command_idempotency_keys.idempotency_key = btrim(driver_transition_trip.idempotency_key);
  return jsonb_build_object('trip_id', current_trip.id, 'status', current_trip.status);
end;
$$;

revoke all on function private.reconcile_driver_availability(uuid), private.reserve_driver_for_match_offer() from public, anon, authenticated, service_role;
revoke all on function public.service_reserve_driver_for_booking(uuid, uuid, uuid, integer), public.service_release_driver_reservation(uuid, uuid, integer) from public, anon, authenticated, service_role;
grant execute on function public.service_reserve_driver_for_booking(uuid, uuid, uuid, integer), public.service_release_driver_reservation(uuid, uuid, integer) to service_role;

commit;
