begin;

create or replace function private.release_matching_driver_reservation(
  target_driver_id uuid,
  target_booking_request_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  availability public.driver_availability%rowtype;
begin
  select * into availability
  from public.driver_availability
  where driver_id = target_driver_id
  for update;

  if not found
    or availability.state <> 'reserved'
    or availability.reserved_booking_request_id <> target_booking_request_id then
    return false;
  end if;

  update public.driver_availability
  set state = 'available', reserved_booking_request_id = null, active_trip_id = null
  where driver_id = target_driver_id;
  perform private.write_audit_record(
    null, 'driver.reservation_released', target_driver_id, null,
    jsonb_build_object('booking_request_id', target_booking_request_id, 'state', availability.state),
    jsonb_build_object('booking_request_id', target_booking_request_id, 'state', 'available')
  );
  return true;
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
  if availability.state = 'reserved' and availability.reserved_booking_request_id = target_booking_request_id
    and availability.vehicle_id = target_vehicle_id then
    return availability;
  end if;
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
  perform private.write_audit_record(
    null, 'driver.reservation_created', target_driver_id, null,
    jsonb_build_object('booking_request_id', booking.id, 'state', 'available'),
    jsonb_build_object('booking_request_id', booking.id, 'state', 'reserved')
  );
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
  perform private.release_matching_driver_reservation(target_driver_id, target_booking_request_id);
  select * into availability from public.driver_availability where driver_id = target_driver_id;
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
  if availability.state = 'reserved' and availability.reserved_booking_request_id = new.booking_request_id
    and availability.vehicle_id = new.vehicle_id then
    return new;
  end if;
  if not found or availability.state <> 'available' or availability.vehicle_id <> new.vehicle_id then
    raise exception using errcode = '55000', message = 'Matching offers require an available Driver and matching active vehicle.';
  end if;
  update public.driver_availability set state = 'reserved',
    reserved_booking_request_id = new.booking_request_id, active_trip_id = null
  where driver_id = new.driver_id;
  perform private.write_audit_record(
    null, 'driver.reservation_created', new.driver_id, null,
    jsonb_build_object('booking_request_id', new.booking_request_id, 'state', 'available'),
    jsonb_build_object('booking_request_id', new.booking_request_id, 'state', 'reserved')
  );
  return new;
end;
$$;

create or replace function private.release_driver_reservation_on_terminal_offer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'offered' and new.status in ('expired', 'cancelled') then
    perform private.release_matching_driver_reservation(new.driver_id, new.booking_request_id);
  end if;
  return new;
end;
$$;

create trigger driver_match_offers_release_driver_on_terminal_status
after update of status on public.driver_match_offers
for each row execute function private.release_driver_reservation_on_terminal_offer();

create or replace function private.release_driver_reservations_on_terminal_booking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  reserved_driver_id uuid;
begin
  if old.status is distinct from new.status
    and new.status in ('cancelled', 'expired', 'failed')
    and not exists (select 1 from public.trips where booking_request_id = new.id) then
    for reserved_driver_id in
      select driver_id from public.driver_availability
      where state = 'reserved' and reserved_booking_request_id = new.id
    loop
      perform private.release_matching_driver_reservation(reserved_driver_id, new.id);
    end loop;
  end if;
  return new;
end;
$$;

create trigger booking_requests_release_drivers_on_terminal_status
after update of status on public.booking_requests
for each row execute function private.release_driver_reservations_on_terminal_booking();

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
  perform 1 from public.trips
  where driver_id = target_user_id
    and status not in ('completed', 'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed')
  for update;
  if found then raise exception using errcode = '55000', message = 'A Driver assigned to a nonterminal Trip must be terminated before rejection.'; end if;
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
    perform 1 from public.trips
    where driver_id = target_user_id
      and status not in ('completed', 'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed')
    for update;
    if found then raise exception using errcode = '55000', message = 'A Driver assigned to a nonterminal Trip must be terminated before blocking.'; end if;
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

revoke all on function private.release_matching_driver_reservation(uuid, uuid),
  private.release_driver_reservation_on_terminal_offer(),
  private.release_driver_reservations_on_terminal_booking() from public, anon, authenticated, service_role;

commit;
