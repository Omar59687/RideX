begin;

create type public.fare_adjustment_status as enum ('pending', 'applied', 'cancelled');

alter table public.vehicles
  add constraint vehicles_id_driver_unique unique (id, driver_id);

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null unique references public.booking_requests (id) on delete restrict,
  fare_quote_id uuid not null references public.fare_quotes (id) on delete restrict,
  rider_id uuid not null references public.rider_profiles (user_id) on delete restrict,
  driver_id uuid not null references public.driver_profiles (user_id) on delete restrict,
  vehicle_id uuid not null references public.vehicles (id) on delete restrict,
  status public.trip_status not null default 'accepted',
  payment_method public.payment_method not null,
  pickup jsonb not null,
  destination jsonb not null,
  route_distance_meters integer not null,
  route_duration_seconds integer not null,
  route_geometry_reference text,
  currency text not null default 'JOD',
  original_fare_fils integer not null,
  current_fare_fils integer not null,
  accepted_at timestamptz not null default now(),
  driver_arriving_at timestamptz,
  driver_arrived_at timestamptz,
  in_progress_at timestamptz,
  completed_at timestamptz,
  terminated_at timestamptz,
  termination_reason_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  constraint trips_locations_valid check (
    private.is_valid_route_location(pickup)
    and private.is_valid_route_location(destination)
    and pickup <> destination
  ),
  constraint trips_route_metrics_nonnegative check (
    route_distance_meters >= 0 and route_duration_seconds >= 0
  ),
  constraint trips_geometry_reference_bounded check (
    route_geometry_reference is null
    or char_length(btrim(route_geometry_reference)) between 1 and 2048
  ),
  constraint trips_money_valid check (
    currency = 'JOD' and original_fare_fils >= 0 and current_fare_fils >= 0
  ),
  constraint trips_card_fare_fixed check (
    payment_method = 'cash' or current_fare_fils = original_fare_fils
  ),
  constraint trips_version_positive check (version > 0),
  constraint trips_termination_reason_bounded check (
    termination_reason_code is null
    or char_length(btrim(termination_reason_code)) between 1 and 100
  ),
  constraint trips_booking_rider_fk
    foreign key (booking_request_id, rider_id)
    references public.booking_requests (id, rider_id) on delete restrict,
  constraint trips_quote_booking_fk
    foreign key (fare_quote_id, booking_request_id)
    references public.fare_quotes (id, booking_request_id) on delete restrict,
  constraint trips_vehicle_driver_fk
    foreign key (vehicle_id, driver_id)
    references public.vehicles (id, driver_id) on delete restrict
);

create index trips_rider_created_at_idx on public.trips (rider_id, created_at desc);
create index trips_driver_created_at_idx on public.trips (driver_id, created_at desc);
create index trips_status_idx on public.trips (status);

create table public.trip_stops (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete restrict,
  sequence smallint not null,
  location jsonb not null,
  label text,
  rider_note text,
  created_at timestamptz not null default now(),
  constraint trip_stops_sequence_bounded check (sequence between 1 and 3),
  constraint trip_stops_location_valid check (private.is_valid_route_location(location)),
  constraint trip_stops_label_bounded check (
    label is null or char_length(btrim(label)) between 1 and 200
  ),
  constraint trip_stops_rider_note_bounded check (
    rider_note is null or char_length(btrim(rider_note)) between 1 and 500
  ),
  constraint trip_stops_trip_sequence_unique unique (trip_id, sequence)
);

create table public.trip_status_events (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete restrict,
  sequence integer not null,
  from_status public.trip_status,
  to_status public.trip_status not null,
  actor_user_id uuid references public.users (id) on delete set null,
  reason_code text,
  occurred_at timestamptz not null default now(),
  constraint trip_status_events_sequence_positive check (sequence > 0),
  constraint trip_status_events_reason_bounded check (
    reason_code is null or char_length(btrim(reason_code)) between 1 and 100
  ),
  constraint trip_status_events_trip_sequence_unique unique (trip_id, sequence)
);

create index trip_status_events_trip_occurred_idx
  on public.trip_status_events (trip_id, occurred_at, sequence);

create table public.trip_change_requests (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete restrict,
  rider_id uuid not null references public.rider_profiles (user_id) on delete restrict,
  status public.trip_change_request_status not null default 'requested',
  requested_destination jsonb not null,
  requested_stops jsonb not null default '[]'::jsonb,
  rider_note text,
  priced_route_distance_meters integer,
  priced_route_duration_seconds integer,
  priced_route_geometry_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  version integer not null default 1,
  constraint trip_change_requests_destination_valid check (
    private.is_valid_route_location(requested_destination)
  ),
  constraint trip_change_requests_stops_valid check (
    private.is_valid_ordered_stops(requested_stops)
  ),
  constraint trip_change_requests_note_bounded check (
    rider_note is null or char_length(btrim(rider_note)) between 1 and 500
  ),
  constraint trip_change_requests_metrics_complete check (
    (priced_route_distance_meters is null and priced_route_duration_seconds is null)
    or (priced_route_distance_meters >= 0 and priced_route_duration_seconds >= 0)
  ),
  constraint trip_change_requests_geometry_bounded check (
    priced_route_geometry_reference is null
    or char_length(btrim(priced_route_geometry_reference)) between 1 and 2048
  ),
  constraint trip_change_requests_version_positive check (version > 0)
);

create unique index trip_change_requests_one_unresolved_per_trip_idx
  on public.trip_change_requests (trip_id)
  where status in (
    'requested', 'pricing', 'awaitingRiderApproval',
    'authorizationPending', 'approved'
  );
create index trip_change_requests_trip_created_idx
  on public.trip_change_requests (trip_id, created_at desc);

create table public.fare_adjustments (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete restrict,
  trip_change_request_id uuid not null unique references public.trip_change_requests (id) on delete restrict,
  status public.fare_adjustment_status not null default 'pending',
  previous_fare_fils integer not null,
  adjusted_fare_fils integer not null,
  adjustment_fils integer not null,
  breakdown jsonb not null,
  pricing_configuration_id uuid not null references public.pricing_configurations (id) on delete restrict,
  pricing_version integer not null,
  created_at timestamptz not null default now(),
  applied_at timestamptz,
  version integer not null default 1,
  constraint fare_adjustments_money_valid check (
    previous_fare_fils >= 0
    and adjusted_fare_fils >= 0
    and adjustment_fils = adjusted_fare_fils - previous_fare_fils
  ),
  constraint fare_adjustments_breakdown_object check (jsonb_typeof(breakdown) = 'object'),
  constraint fare_adjustments_pricing_version_positive check (pricing_version > 0),
  constraint fare_adjustments_applied_timestamp_valid check (
    (status = 'applied' and applied_at is not null)
    or (status <> 'applied' and applied_at is null)
  ),
  constraint fare_adjustments_version_positive check (version > 0)
);

create index fare_adjustments_trip_created_idx
  on public.fare_adjustments (trip_id, created_at desc);

alter table public.driver_availability
  add constraint driver_availability_reserved_booking_fk
    foreign key (reserved_booking_request_id) references public.booking_requests (id) on delete restrict,
  add constraint driver_availability_active_trip_fk
    foreign key (active_trip_id) references public.trips (id) on delete restrict;

create trigger trips_set_updated_at before update on public.trips
for each row execute function public.set_updated_at();
create trigger trips_bump_optimistic_version before update on public.trips
for each row execute function private.bump_optimistic_version();
create trigger trip_change_requests_set_updated_at before update on public.trip_change_requests
for each row execute function public.set_updated_at();
create trigger trip_change_requests_bump_version before update on public.trip_change_requests
for each row execute function private.bump_optimistic_version();
create trigger fare_adjustments_bump_version before update on public.fare_adjustments
for each row execute function private.bump_optimistic_version();

create or replace function private.enforce_trip_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.booking_request_id is distinct from old.booking_request_id
    or new.fare_quote_id is distinct from old.fare_quote_id
    or new.rider_id is distinct from old.rider_id
    or new.driver_id is distinct from old.driver_id
    or new.vehicle_id is distinct from old.vehicle_id
    or new.payment_method is distinct from old.payment_method
    or new.pickup is distinct from old.pickup
    or new.currency is distinct from old.currency
    or new.original_fare_fils is distinct from old.original_fare_fils
    or new.accepted_at is distinct from old.accepted_at then
    raise exception using errcode = '55000', message = 'Trip assignment and original fare snapshots are immutable.';
  end if;
  if old.status in ('completed', 'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed')
    and new is distinct from old then
    raise exception using errcode = '55000', message = 'Terminal Trips are immutable.';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'accepted' and new.status in ('driverArriving', 'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed'))
    or (old.status = 'driverArriving' and new.status in ('driverArrived', 'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed'))
    or (old.status = 'driverArrived' and new.status in ('inProgress', 'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed'))
    or (old.status = 'inProgress' and new.status in ('completed', 'cancelledByAdmin', 'failed'))
  ) then
    raise exception using errcode = '55000', message = 'Invalid Trip status transition.';
  end if;
  if old.payment_method = 'card' and (
    new.destination is distinct from old.destination
    or new.route_distance_meters is distinct from old.route_distance_meters
    or new.route_duration_seconds is distinct from old.route_duration_seconds
    or new.route_geometry_reference is distinct from old.route_geometry_reference
    or new.current_fare_fils is distinct from old.current_fare_fils
  ) then
    raise exception using errcode = '55000', message = 'Card Trip route and fare snapshots are fixed.';
  end if;
  if (
    new.destination is distinct from old.destination
    or new.route_distance_meters is distinct from old.route_distance_meters
    or new.route_duration_seconds is distinct from old.route_duration_seconds
    or new.route_geometry_reference is distinct from old.route_geometry_reference
    or new.current_fare_fils is distinct from old.current_fare_fils
  ) and (
    old.payment_method <> 'cash'
    or old.status <> 'inProgress'
    or current_setting('ridex.apply_cash_adjustment', true) <> 'on'
  ) then
    raise exception using errcode = '55000', message = 'Trip route and fare changes require an approved Cash adjustment.';
  end if;
  return new;
end;
$$;

create trigger trips_enforce_transition before update on public.trips
for each row execute function private.enforce_trip_transition();

create or replace function private.enforce_trip_stop_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_setting('ridex.trip_stop_mutation', true) <> 'on' then
    raise exception using errcode = '55000', message = 'Trip stops can change only through trusted Trip commands.';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger trip_stops_require_trusted_command
before insert or update or delete on public.trip_stops
for each row execute function private.enforce_trip_stop_mutation();

create or replace function private.enforce_contiguous_trip_stops()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_trip_id uuid := coalesce(new.trip_id, old.trip_id);
  stop_count integer;
  minimum_sequence integer;
  maximum_sequence integer;
begin
  if not exists (select 1 from public.trips where id = target_trip_id) then return null; end if;
  select count(*), min(sequence), max(sequence)
  into stop_count, minimum_sequence, maximum_sequence
  from public.trip_stops where trip_id = target_trip_id;
  if stop_count > 3
    or (stop_count > 0 and (minimum_sequence <> 1 or maximum_sequence <> stop_count)) then
    raise exception using errcode = '23514', message = 'Trip stops must be contiguous from one with a maximum of three.';
  end if;
  return null;
end;
$$;

create constraint trigger trip_stops_contiguous
after insert or update or delete on public.trip_stops
deferrable initially deferred
for each row execute function private.enforce_contiguous_trip_stops();

create or replace function private.reject_trip_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = '55000', message = 'Trip status events are append-only.';
end;
$$;

create trigger trip_status_events_append_only
before update or delete on public.trip_status_events
for each row execute function private.reject_trip_event_mutation();

create or replace function private.append_trip_status_event(
  target_trip_id uuid,
  previous_status public.trip_status,
  next_status public.trip_status,
  event_actor_user_id uuid,
  event_reason_code text default null
)
returns public.trip_status_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_sequence integer;
  created_event public.trip_status_events%rowtype;
begin
  perform 1 from public.trips where id = target_trip_id for update;
  select coalesce(max(sequence), 0) + 1 into next_sequence
  from public.trip_status_events where trip_id = target_trip_id;
  insert into public.trip_status_events (
    trip_id, sequence, from_status, to_status, actor_user_id, reason_code
  ) values (
    target_trip_id, next_sequence, previous_status, next_status,
    event_actor_user_id, nullif(btrim(event_reason_code), '')
  ) returning * into created_event;
  return created_event;
end;
$$;

create or replace function private.can_read_trip(target_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.users as users
    join public.trips as trips on trips.id = target_trip_id
    where users.id = auth.uid() and not users.is_blocked
      and (users.role = 'admin'
        or (users.role = 'rider' and trips.rider_id = users.id)
        or (users.role = 'driver' and trips.driver_id = users.id))
  );
$$;

create or replace function private.cancel_unresolved_trip_changes(target_trip_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.fare_adjustments set status = 'cancelled'
  where trip_id = target_trip_id and status = 'pending';
  update public.trip_change_requests set status = 'cancelled', resolved_at = now()
  where trip_id = target_trip_id
    and status in ('requested', 'pricing', 'awaitingRiderApproval', 'authorizationPending');
end;
$$;

create or replace function public.driver_transition_trip(
  target_id uuid,
  requested_status public.trip_status,
  expected_version integer,
  idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_offer public.driver_match_offers%rowtype;
  current_booking public.booking_requests%rowtype;
  current_quote public.fare_quotes%rowtype;
  current_availability public.driver_availability%rowtype;
  current_trip public.trips%rowtype;
  created_trip public.trips%rowtype;
  previous_status public.trip_status;
  payload_fingerprint text;
  canonical_result jsonb;
  claimed_result jsonb;
  event_reason text;
begin
  caller_id := private.require_approved_driver();
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  payload_fingerprint := encode(extensions.digest(convert_to(
    concat_ws('|', target_id::text, requested_status::text, expected_version::text), 'UTF8'
  ), 'sha256'), 'hex');
  canonical_result := jsonb_build_object('target_id', target_id, 'status', requested_status);
  claimed_result := private.claim_command_idempotency_key(
    caller_id, 'trip', idempotency_key, payload_fingerprint, canonical_result
  );
  if claimed_result ? 'error' then return claimed_result; end if;

  if requested_status = 'accepted' then
    select * into current_offer from public.driver_match_offers
    where id = target_id and driver_id = caller_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'Matching offer was not found for this Driver.'; end if;
    if current_offer.status = 'accepted' then
      select * into created_trip from public.trips where booking_request_id = current_offer.booking_request_id;
      return jsonb_build_object('trip_id', created_trip.id, 'status', created_trip.status);
    end if;
    if current_offer.version <> expected_version then
      raise exception using errcode = '40001', message = 'Matching offer version is stale.';
    end if;
    if current_offer.status <> 'offered' or current_offer.expires_at <= now() then
      raise exception using errcode = '55000', message = 'Only a live offered match can create a Trip.';
    end if;
    select * into current_booking from public.booking_requests
    where id = current_offer.booking_request_id for update;
    if current_booking.status <> 'searching'
      or current_booking.fare_quote_id <> current_offer.fare_quote_id then
      raise exception using errcode = '55000', message = 'The booking is no longer available for assignment.';
    end if;
    select * into current_quote from public.fare_quotes
    where id = current_offer.fare_quote_id and status = 'locked' for share;
    if not found then raise exception using errcode = '55000', message = 'Trip creation requires the booking locked FareQuote.'; end if;
    select * into current_availability from public.driver_availability
    where driver_id = caller_id for update;
    if current_availability.state <> 'available'
      or current_availability.vehicle_id <> current_offer.vehicle_id
      or not exists (
        select 1 from public.vehicles where id = current_offer.vehicle_id
          and driver_id = caller_id and is_active
          and vehicle_type_code = current_booking.vehicle_type_code
      ) then
      raise exception using errcode = '55000', message = 'Driver availability or vehicle is no longer compatible.';
    end if;
    insert into public.trips (
      booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id,
      payment_method, pickup, destination, route_distance_meters,
      route_duration_seconds, route_geometry_reference,
      original_fare_fils, current_fare_fils
    ) values (
      current_booking.id, current_quote.id, current_booking.rider_id,
      caller_id, current_offer.vehicle_id, current_booking.payment_method,
      current_quote.pickup, current_quote.destination,
      current_quote.route_distance_meters, current_quote.route_duration_seconds,
      current_quote.route_geometry_reference,
      current_quote.fixed_fare_fils, current_quote.fixed_fare_fils
    ) returning * into created_trip;
    perform set_config('ridex.trip_stop_mutation', 'on', true);
    insert into public.trip_stops (trip_id, sequence, location, label, rider_note)
    select created_trip.id, sequence, location, label, rider_note
    from public.booking_stops where booking_request_id = current_booking.id order by sequence;
    update public.driver_match_offers set status = (
      case when id = current_offer.id then 'accepted' else 'cancelled' end
    )::public.driver_match_offer_status,
      responded_at = now()
    where booking_request_id = current_booking.id and status = 'offered';
    update public.booking_requests set status = 'matched', matched_at = now(),
      matched_driver_id = caller_id, matched_vehicle_id = current_offer.vehicle_id
    where id = current_booking.id;
    update public.driver_availability set state = 'onTrip',
      reserved_booking_request_id = null, active_trip_id = created_trip.id
    where driver_id = caller_id;
    perform private.append_trip_status_event(created_trip.id, null, 'accepted', caller_id, null);
    perform private.write_audit_record(caller_id, 'trip.accepted', current_booking.rider_id, null,
      jsonb_build_object('match_offer_id', current_offer.id),
      jsonb_build_object('trip_id', created_trip.id, 'status', created_trip.status));
    update public.command_idempotency_keys set canonical_result = jsonb_build_object(
      'trip_id', created_trip.id, 'status', created_trip.status
    ) where actor_user_id = caller_id and command_scope = 'trip' and command_idempotency_keys.idempotency_key = btrim(driver_transition_trip.idempotency_key);
    return jsonb_build_object('trip_id', created_trip.id, 'status', created_trip.status);
  end if;

  select * into current_trip from public.trips
  where id = target_id and driver_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Trip was not found for this Driver.'; end if;
  if current_trip.status = requested_status then
    return jsonb_build_object('trip_id', current_trip.id, 'status', current_trip.status);
  end if;
  if current_trip.version <> expected_version then
    raise exception using errcode = '40001', message = 'Trip version is stale.';
  end if;
  if requested_status not in ('driverArriving', 'driverArrived', 'inProgress', 'completed', 'cancelledByDriver') then
    raise exception using errcode = '22023', message = 'Drivers cannot request this Trip status.';
  end if;
  if requested_status = 'completed' then
    if exists (select 1 from public.trip_change_requests where trip_id = current_trip.id and status = 'approved') then
      raise exception using errcode = '55000', message = 'An approved fare adjustment must be applied before completion.';
    end if;
    perform private.cancel_unresolved_trip_changes(current_trip.id);
  end if;
  if requested_status = 'cancelledByDriver' then event_reason := 'driver_cancelled'; end if;
  previous_status := current_trip.status;
  update public.trips set status = requested_status,
    driver_arriving_at = case when requested_status = 'driverArriving' then now() else driver_arriving_at end,
    driver_arrived_at = case when requested_status = 'driverArrived' then now() else driver_arrived_at end,
    in_progress_at = case when requested_status = 'inProgress' then now() else in_progress_at end,
    completed_at = case when requested_status = 'completed' then now() else completed_at end,
    terminated_at = case when requested_status = 'cancelledByDriver' then now() else terminated_at end,
    termination_reason_code = case when requested_status = 'cancelledByDriver' then event_reason else termination_reason_code end
  where id = current_trip.id returning * into current_trip;
  if requested_status in ('completed', 'cancelledByDriver') then
    update public.driver_availability set state = 'offline', vehicle_id = null,
      active_trip_id = null, reserved_booking_request_id = null, last_heartbeat_at = null
    where driver_id = caller_id and active_trip_id = current_trip.id;
  end if;
  perform private.append_trip_status_event(current_trip.id, previous_status, requested_status, caller_id, event_reason);
  update public.command_idempotency_keys set canonical_result = jsonb_build_object(
    'trip_id', current_trip.id, 'status', current_trip.status
  ) where actor_user_id = caller_id and command_scope = 'trip' and command_idempotency_keys.idempotency_key = btrim(driver_transition_trip.idempotency_key);
  return jsonb_build_object('trip_id', current_trip.id, 'status', current_trip.status);
end;
$$;

create or replace function public.rider_cancel_trip(
  target_trip_id uuid,
  expected_version integer,
  reason_code text
)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_trip public.trips%rowtype;
  previous_status public.trip_status;
begin
  caller_id := private.require_nonblocked_rider();
  select * into current_trip from public.trips
  where id = target_trip_id and rider_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Trip was not found for this Rider.'; end if;
  if current_trip.status = 'cancelledByRider' then return current_trip; end if;
  if current_trip.version <> expected_version then raise exception using errcode = '40001', message = 'Trip version is stale.'; end if;
  if current_trip.status not in ('accepted', 'driverArriving', 'driverArrived') then
    raise exception using errcode = '55000', message = 'The Rider can cancel only before the Trip starts.';
  end if;
  if char_length(btrim(coalesce(reason_code, ''))) not between 1 and 100 then
    raise exception using errcode = '22023', message = 'A cancellation reason is required.';
  end if;
  previous_status := current_trip.status;
  perform private.cancel_unresolved_trip_changes(current_trip.id);
  update public.trips set status = 'cancelledByRider', terminated_at = now(),
    termination_reason_code = btrim(reason_code)
  where id = current_trip.id returning * into current_trip;
  update public.driver_availability set state = 'offline', vehicle_id = null,
    active_trip_id = null, reserved_booking_request_id = null, last_heartbeat_at = null
  where driver_id = current_trip.driver_id and active_trip_id = current_trip.id;
  perform private.append_trip_status_event(current_trip.id, previous_status, 'cancelledByRider', caller_id, reason_code);
  perform private.write_audit_record(caller_id, 'trip.cancelled_by_rider', caller_id, btrim(reason_code),
    jsonb_build_object('trip_id', current_trip.id, 'status', previous_status),
    jsonb_build_object('status', current_trip.status));
  return current_trip;
end;
$$;

create or replace function public.admin_terminate_trip(
  target_trip_id uuid,
  expected_version integer,
  terminal_status public.trip_status,
  reason_code text
)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_trip public.trips%rowtype;
  previous_status public.trip_status;
begin
  caller_id := private.require_nonblocked_admin();
  if terminal_status not in ('cancelledByAdmin', 'failed') then
    raise exception using errcode = '22023', message = 'Admin termination must cancel or fail the Trip.';
  end if;
  if char_length(btrim(coalesce(reason_code, ''))) not between 1 and 100 then
    raise exception using errcode = '22023', message = 'An exceptional termination reason is required.';
  end if;
  select * into current_trip from public.trips where id = target_trip_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Trip was not found.'; end if;
  if current_trip.status = terminal_status then return current_trip; end if;
  if current_trip.version <> expected_version then raise exception using errcode = '40001', message = 'Trip version is stale.'; end if;
  if current_trip.status in ('completed', 'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed') then
    raise exception using errcode = '55000', message = 'A terminal Trip cannot be terminated again.';
  end if;
  previous_status := current_trip.status;
  perform private.cancel_unresolved_trip_changes(current_trip.id);
  update public.trips set status = terminal_status, terminated_at = now(),
    termination_reason_code = btrim(reason_code)
  where id = current_trip.id returning * into current_trip;
  update public.driver_availability set state = 'offline', vehicle_id = null,
    active_trip_id = null, reserved_booking_request_id = null, last_heartbeat_at = null
  where driver_id = current_trip.driver_id and active_trip_id = current_trip.id;
  perform private.append_trip_status_event(current_trip.id, previous_status, terminal_status, caller_id, reason_code);
  perform private.write_audit_record(caller_id, 'trip.terminated_by_admin', current_trip.rider_id, btrim(reason_code),
    jsonb_build_object('trip_id', current_trip.id, 'status', previous_status),
    jsonb_build_object('status', current_trip.status));
  return current_trip;
end;
$$;

create or replace function public.rider_create_trip_change_request(
  target_trip_id uuid,
  expected_trip_version integer,
  requested_destination jsonb,
  requested_stops jsonb default '[]'::jsonb,
  rider_note text default null
)
returns public.trip_change_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_trip public.trips%rowtype;
  created_request public.trip_change_requests%rowtype;
begin
  caller_id := private.require_nonblocked_rider();
  if not private.is_valid_route_location(requested_destination)
    or not private.is_valid_ordered_stops(coalesce(requested_stops, '[]'::jsonb)) then
    raise exception using errcode = '22023', message = 'Trip change route inputs are invalid.';
  end if;
  select * into current_trip from public.trips
  where id = target_trip_id and rider_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Trip was not found for this Rider.'; end if;
  if current_trip.version <> expected_trip_version then raise exception using errcode = '40001', message = 'Trip version is stale.'; end if;
  if current_trip.payment_method <> 'cash' then
    raise exception using errcode = '55000', message = 'In-progress Trip changes are Cash-only.';
  end if;
  if current_trip.status <> 'inProgress' then
    raise exception using errcode = '55000', message = 'Trip changes require an in-progress Trip.';
  end if;
  if requested_destination = current_trip.pickup then
    raise exception using errcode = '22023', message = 'Pickup and destination must remain distinct.';
  end if;
  insert into public.trip_change_requests (
    trip_id, rider_id, requested_destination, requested_stops, rider_note
  ) values (
    current_trip.id, caller_id, requested_destination,
    coalesce(requested_stops, '[]'::jsonb), nullif(btrim(rider_note), '')
  ) returning * into created_request;
  return created_request;
end;
$$;

create or replace function public.rider_cancel_trip_change_request(
  target_request_id uuid,
  expected_request_version integer
)
returns public.trip_change_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_request public.trip_change_requests%rowtype;
begin
  caller_id := private.require_nonblocked_rider();
  select * into current_request from public.trip_change_requests
  where id = target_request_id and rider_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Trip change request was not found for this Rider.'; end if;
  if current_request.status = 'cancelled' then return current_request; end if;
  if current_request.version <> expected_request_version then raise exception using errcode = '40001', message = 'Trip change request version is stale.'; end if;
  if current_request.status not in ('requested', 'pricing', 'awaitingRiderApproval') then
    raise exception using errcode = '55000', message = 'This Trip change request can no longer be cancelled.';
  end if;
  update public.fare_adjustments set status = 'cancelled'
  where trip_change_request_id = current_request.id and status = 'pending';
  update public.trip_change_requests set status = 'cancelled', resolved_at = now()
  where id = current_request.id returning * into current_request;
  return current_request;
end;
$$;

create or replace function public.rider_approve_trip_change_request(
  target_request_id uuid,
  expected_request_version integer,
  expected_trip_version integer
)
returns public.trip_change_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_request public.trip_change_requests%rowtype;
  current_trip public.trips%rowtype;
begin
  caller_id := private.require_nonblocked_rider();
  select * into current_request from public.trip_change_requests
  where id = target_request_id and rider_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Trip change request was not found for this Rider.'; end if;
  if current_request.status = 'approved' then return current_request; end if;
  if current_request.version <> expected_request_version then raise exception using errcode = '40001', message = 'Trip change request version is stale.'; end if;
  select * into current_trip from public.trips where id = current_request.trip_id for update;
  if current_trip.version <> expected_trip_version then raise exception using errcode = '40001', message = 'Trip version is stale.'; end if;
  if current_trip.payment_method <> 'cash' or current_trip.status <> 'inProgress'
    or current_request.status <> 'awaitingRiderApproval'
    or not exists (select 1 from public.fare_adjustments where trip_change_request_id = current_request.id and status = 'pending') then
    raise exception using errcode = '55000', message = 'Only a priced in-progress Cash change can be approved.';
  end if;
  update public.trip_change_requests set status = 'approved'
  where id = current_request.id returning * into current_request;
  return current_request;
end;
$$;

create or replace function public.backend_price_trip_change_request(
  target_request_id uuid,
  expected_request_version integer,
  route_distance_meters integer,
  route_duration_seconds integer,
  route_geometry_reference text default null
)
returns public.fare_adjustments
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_request public.trip_change_requests%rowtype;
  current_trip public.trips%rowtype;
  pricing public.pricing_configurations%rowtype;
  stop_count integer;
  subtotal bigint;
  final_fare bigint;
  created_adjustment public.fare_adjustments%rowtype;
begin
  if route_distance_meters < 0 or route_duration_seconds < 0 then
    raise exception using errcode = '22023', message = 'Cash change pricing requires valid route metrics.';
  end if;
  select * into current_request from public.trip_change_requests where id = target_request_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Trip change request was not found.'; end if;
  if exists (select 1 from public.fare_adjustments where trip_change_request_id = current_request.id) then
    select * into created_adjustment from public.fare_adjustments where trip_change_request_id = current_request.id;
    return created_adjustment;
  end if;
  if current_request.version <> expected_request_version then raise exception using errcode = '40001', message = 'Trip change request version is stale.'; end if;
  select * into current_trip from public.trips where id = current_request.trip_id for update;
  if current_request.status <> 'requested' or current_trip.payment_method <> 'cash' or current_trip.status <> 'inProgress' then
    raise exception using errcode = '55000', message = 'Only a requested in-progress Cash change can be priced.';
  end if;
  select configurations.* into pricing
  from public.pricing_configurations configurations
  join public.vehicles vehicles on vehicles.id = current_trip.vehicle_id
  where configurations.vehicle_type_code = vehicles.vehicle_type_code and configurations.is_active
  for share of configurations;
  if not found then raise exception using errcode = '55000', message = 'No active pricing configuration supports this Trip.'; end if;
  stop_count := jsonb_array_length(current_request.requested_stops);
  subtotal := pricing.base_fare_fils::bigint
    + (route_distance_meters::bigint * pricing.per_kilometer_fils + 500) / 1000
    + (route_duration_seconds::bigint * pricing.per_minute_fils + 30) / 60
    + stop_count::bigint * pricing.per_stop_fils;
  final_fare := (greatest(subtotal, pricing.minimum_fare_fils::bigint)
    + pricing.rounding_increment_fils / 2) / pricing.rounding_increment_fils
    * pricing.rounding_increment_fils;
  if final_fare > 2147483647 then raise exception using errcode = '22003', message = 'Adjusted fare exceeds supported integer fils.'; end if;
  update public.trip_change_requests set status = 'awaitingRiderApproval',
    priced_route_distance_meters = route_distance_meters,
    priced_route_duration_seconds = route_duration_seconds,
    priced_route_geometry_reference = nullif(btrim(route_geometry_reference), '')
  where id = current_request.id returning * into current_request;
  insert into public.fare_adjustments (
    trip_id, trip_change_request_id, previous_fare_fils, adjusted_fare_fils,
    adjustment_fils, breakdown, pricing_configuration_id, pricing_version
  ) values (
    current_trip.id, current_request.id, current_trip.current_fare_fils,
    final_fare::integer, final_fare::integer - current_trip.current_fare_fils,
    jsonb_build_object('previous_fare_fils', current_trip.current_fare_fils,
      'adjusted_fare_fils', final_fare, 'stop_count', stop_count,
      'route_distance_meters', route_distance_meters,
      'route_duration_seconds', route_duration_seconds),
    pricing.id, pricing.pricing_version
  ) returning * into created_adjustment;
  return created_adjustment;
end;
$$;

create or replace function public.backend_apply_trip_fare_adjustment(
  target_adjustment_id uuid,
  expected_adjustment_version integer,
  expected_trip_version integer
)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_adjustment public.fare_adjustments%rowtype;
  current_request public.trip_change_requests%rowtype;
  current_trip public.trips%rowtype;
begin
  select * into current_adjustment from public.fare_adjustments where id = target_adjustment_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Fare adjustment was not found.'; end if;
  select * into current_trip from public.trips where id = current_adjustment.trip_id for update;
  if current_adjustment.status = 'applied' then return current_trip; end if;
  if current_adjustment.version <> expected_adjustment_version then raise exception using errcode = '40001', message = 'Fare adjustment version is stale.'; end if;
  if current_trip.version <> expected_trip_version then raise exception using errcode = '40001', message = 'Trip version is stale.'; end if;
  select * into current_request from public.trip_change_requests
  where id = current_adjustment.trip_change_request_id for update;
  if current_adjustment.status <> 'pending' or current_request.status <> 'approved'
    or current_trip.payment_method <> 'cash' or current_trip.status <> 'inProgress'
    or current_adjustment.previous_fare_fils <> current_trip.current_fare_fils then
    raise exception using errcode = '55000', message = 'Fare adjustment is not applicable to this Trip state.';
  end if;
  perform set_config('ridex.apply_cash_adjustment', 'on', true);
  perform set_config('ridex.trip_stop_mutation', 'on', true);
  update public.trips set destination = current_request.requested_destination,
    route_distance_meters = current_request.priced_route_distance_meters,
    route_duration_seconds = current_request.priced_route_duration_seconds,
    route_geometry_reference = current_request.priced_route_geometry_reference,
    current_fare_fils = current_adjustment.adjusted_fare_fils
  where id = current_trip.id returning * into current_trip;
  delete from public.trip_stops where trip_id = current_trip.id;
  insert into public.trip_stops (trip_id, sequence, location, label, rider_note)
  select current_trip.id, ordinality::smallint, value -> 'location',
    nullif(btrim(value ->> 'label'), ''), nullif(btrim(value ->> 'rider_note'), '')
  from jsonb_array_elements(current_request.requested_stops) with ordinality;
  update public.fare_adjustments set status = 'applied', applied_at = now()
  where id = current_adjustment.id;
  update public.trip_change_requests set status = 'applied', resolved_at = now()
  where id = current_request.id;
  return current_trip;
end;
$$;

alter table public.trips enable row level security;
alter table public.trip_stops enable row level security;
alter table public.trip_status_events enable row level security;
alter table public.trip_change_requests enable row level security;
alter table public.fare_adjustments enable row level security;

create policy trips_participant_select on public.trips for select to authenticated
using (private.can_read_trip(id));
create policy trip_stops_participant_select on public.trip_stops for select to authenticated
using (private.can_read_trip(trip_id));
create policy trip_status_events_participant_select on public.trip_status_events for select to authenticated
using (private.can_read_trip(trip_id));
create policy trip_change_requests_participant_select on public.trip_change_requests for select to authenticated
using (private.can_read_trip(trip_id));
create policy fare_adjustments_participant_select on public.fare_adjustments for select to authenticated
using (private.can_read_trip(trip_id));

-- A Rider may inspect the assigned vehicle only while participating in its Trip.
drop policy vehicles_driver_or_admin_select on public.vehicles;
create policy vehicles_participant_select on public.vehicles for select to authenticated using (
  exists (select 1 from public.users where id = auth.uid() and not is_blocked and (id = vehicles.driver_id or role = 'admin'))
  or exists (select 1 from public.trips where vehicle_id = vehicles.id and rider_id = auth.uid())
);

revoke all on table public.trips, public.trip_stops, public.trip_status_events,
  public.trip_change_requests, public.fare_adjustments
from public, anon, authenticated, service_role;
grant select on table public.trips, public.trip_stops, public.trip_status_events,
  public.trip_change_requests, public.fare_adjustments to authenticated;
grant select, insert, update, delete on table public.trips, public.trip_stops,
  public.trip_status_events, public.trip_change_requests, public.fare_adjustments to service_role;

revoke all on function private.enforce_trip_transition() from public, anon, authenticated, service_role;
revoke all on function private.enforce_trip_stop_mutation() from public, anon, authenticated, service_role;
revoke all on function private.enforce_contiguous_trip_stops() from public, anon, authenticated, service_role;
revoke all on function private.reject_trip_event_mutation() from public, anon, authenticated, service_role;
revoke all on function private.append_trip_status_event(uuid, public.trip_status, public.trip_status, uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.can_read_trip(uuid) from public, anon, authenticated, service_role;
revoke all on function private.cancel_unresolved_trip_changes(uuid) from public, anon, authenticated, service_role;
grant execute on function private.can_read_trip(uuid) to authenticated;

revoke all on function public.driver_transition_trip(uuid, public.trip_status, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.rider_cancel_trip(uuid, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.admin_terminate_trip(uuid, integer, public.trip_status, text) from public, anon, authenticated, service_role;
revoke all on function public.rider_create_trip_change_request(uuid, integer, jsonb, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.rider_cancel_trip_change_request(uuid, integer) from public, anon, authenticated, service_role;
revoke all on function public.rider_approve_trip_change_request(uuid, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.driver_transition_trip(uuid, public.trip_status, integer, text) to authenticated;
grant execute on function public.rider_cancel_trip(uuid, integer, text) to authenticated;
grant execute on function public.admin_terminate_trip(uuid, integer, public.trip_status, text) to authenticated;
grant execute on function public.rider_create_trip_change_request(uuid, integer, jsonb, jsonb, text) to authenticated;
grant execute on function public.rider_cancel_trip_change_request(uuid, integer) to authenticated;
grant execute on function public.rider_approve_trip_change_request(uuid, integer, integer) to authenticated;

revoke all on function public.backend_price_trip_change_request(uuid, integer, integer, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.backend_apply_trip_fare_adjustment(uuid, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.backend_price_trip_change_request(uuid, integer, integer, integer, text) to service_role;
grant execute on function public.backend_apply_trip_fare_adjustment(uuid, integer, integer) to service_role;

commit;
