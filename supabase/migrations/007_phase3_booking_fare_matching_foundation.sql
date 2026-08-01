begin;

create type public.driver_match_offer_status as enum (
  'offered', 'accepted', 'declined', 'expired', 'cancelled'
);

create or replace function private.is_valid_route_location(location_value jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_typeof(location_value) = 'object'
    and jsonb_typeof(location_value -> 'latitude') = 'number'
    and jsonb_typeof(location_value -> 'longitude') = 'number'
    and (location_value ->> 'latitude')::numeric between -90 and 90
    and (location_value ->> 'longitude')::numeric between -180 and 180
    and (
      not location_value ? 'label'
      or (
        jsonb_typeof(location_value -> 'label') = 'string'
        and char_length(btrim(location_value ->> 'label')) between 1 and 200
      )
    ),
    false
  );
$$;

create or replace function private.is_valid_ordered_stops(stops_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  stop_value jsonb;
begin
  if jsonb_typeof(stops_value) <> 'array'
    or jsonb_array_length(stops_value) > 3 then
    return false;
  end if;

  for stop_value in select value from jsonb_array_elements(stops_value)
  loop
    if jsonb_typeof(stop_value) <> 'object'
      or not private.is_valid_route_location(stop_value -> 'location')
      or (
        stop_value ? 'label'
        and (
          jsonb_typeof(stop_value -> 'label') <> 'string'
          or char_length(btrim(stop_value ->> 'label')) not between 1 and 200
        )
      )
      or (
        stop_value ? 'rider_note'
        and (
          jsonb_typeof(stop_value -> 'rider_note') <> 'string'
          or char_length(btrim(stop_value ->> 'rider_note')) not between 1 and 500
        )
      ) then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

create table public.pricing_configurations (
  id uuid primary key default gen_random_uuid(),
  vehicle_type_code public.vehicle_type_code not null,
  pricing_version integer not null,
  base_fare_fils integer not null,
  per_kilometer_fils integer not null,
  per_minute_fils integer not null,
  per_stop_fils integer not null,
  minimum_fare_fils integer not null,
  rounding_increment_fils integer not null default 50,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pricing_configurations_version_positive check (pricing_version > 0),
  constraint pricing_configurations_integer_fils_nonnegative check (
    base_fare_fils >= 0
    and per_kilometer_fils >= 0
    and per_minute_fils >= 0
    and per_stop_fils >= 0
    and minimum_fare_fils >= 0
  ),
  constraint pricing_configurations_rounding_positive check (rounding_increment_fils > 0),
  constraint pricing_configurations_vehicle_version_unique unique (vehicle_type_code, pricing_version)
);

create unique index pricing_configurations_one_active_per_vehicle_idx
  on public.pricing_configurations (vehicle_type_code) where is_active;

create table public.booking_requests (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.rider_profiles (user_id) on delete restrict,
  status public.booking_request_status not null default 'draft',
  pickup jsonb not null,
  destination jsonb not null,
  vehicle_type_code public.vehicle_type_code not null,
  payment_method public.payment_method not null,
  fare_quote_id uuid,
  confirmed_at timestamptz,
  searching_at timestamptz,
  matched_at timestamptz,
  cancelled_at timestamptz,
  expired_at timestamptz,
  failed_at timestamptz,
  cancellation_reason_code text,
  failure_reason_code text,
  matched_driver_id uuid references public.driver_profiles (user_id) on delete restrict,
  matched_vehicle_id uuid references public.vehicles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  constraint booking_requests_pickup_valid check (private.is_valid_route_location(pickup)),
  constraint booking_requests_destination_valid check (private.is_valid_route_location(destination)),
  constraint booking_requests_distinct_endpoints check (pickup <> destination),
  constraint booking_requests_version_positive check (version > 0),
  constraint booking_requests_cancellation_reason_bounded check (
    cancellation_reason_code is null
    or char_length(btrim(cancellation_reason_code)) between 1 and 100
  ),
  constraint booking_requests_failure_reason_bounded check (
    failure_reason_code is null
    or char_length(btrim(failure_reason_code)) between 1 and 100
  ),
  constraint booking_requests_match_references_complete check (
    (matched_driver_id is null and matched_vehicle_id is null)
    or (matched_driver_id is not null and matched_vehicle_id is not null)
  ),
  constraint booking_requests_id_rider_unique unique (id, rider_id)
);

create index booking_requests_rider_created_at_idx
  on public.booking_requests (rider_id, created_at desc);
create index booking_requests_status_idx on public.booking_requests (status);

create table public.booking_stops (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null references public.booking_requests (id) on delete cascade,
  sequence smallint not null,
  location jsonb not null,
  label text,
  rider_note text,
  created_at timestamptz not null default now(),
  constraint booking_stops_sequence_bounded check (sequence between 1 and 3),
  constraint booking_stops_location_valid check (private.is_valid_route_location(location)),
  constraint booking_stops_label_bounded check (
    label is null or char_length(btrim(label)) between 1 and 200
  ),
  constraint booking_stops_rider_note_bounded check (
    rider_note is null or char_length(btrim(rider_note)) between 1 and 500
  ),
  constraint booking_stops_booking_sequence_unique unique (booking_request_id, sequence)
);

create index booking_stops_booking_request_id_idx
  on public.booking_stops (booking_request_id);

create table public.fare_quotes (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null,
  rider_id uuid not null,
  status public.fare_quote_status not null default 'calculated',
  pickup jsonb not null,
  destination jsonb not null,
  ordered_stops jsonb not null default '[]'::jsonb,
  route_distance_meters integer not null,
  route_duration_seconds integer not null,
  route_geometry_reference text,
  vehicle_type_code public.vehicle_type_code not null,
  breakdown jsonb not null,
  currency text not null default 'JOD',
  fixed_fare_fils integer not null,
  pricing_configuration_id uuid not null references public.pricing_configurations (id) on delete restrict,
  pricing_version integer not null,
  quote_version integer not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  locked_at timestamptz,
  superseded_at timestamptz,
  supersedes_fare_quote_id uuid references public.fare_quotes (id) on delete restrict,
  constraint fare_quotes_booking_rider_fk
    foreign key (booking_request_id, rider_id)
    references public.booking_requests (id, rider_id) on delete restrict,
  constraint fare_quotes_pickup_valid check (private.is_valid_route_location(pickup)),
  constraint fare_quotes_destination_valid check (private.is_valid_route_location(destination)),
  constraint fare_quotes_ordered_stops_valid check (private.is_valid_ordered_stops(ordered_stops)),
  constraint fare_quotes_route_distance_nonnegative check (route_distance_meters >= 0),
  constraint fare_quotes_route_duration_nonnegative check (route_duration_seconds >= 0),
  constraint fare_quotes_geometry_reference_bounded check (
    route_geometry_reference is null
    or char_length(btrim(route_geometry_reference)) between 1 and 2048
  ),
  constraint fare_quotes_breakdown_object check (jsonb_typeof(breakdown) = 'object'),
  constraint fare_quotes_currency_jod check (currency = 'JOD'),
  constraint fare_quotes_fixed_fare_nonnegative check (fixed_fare_fils >= 0),
  constraint fare_quotes_versions_positive check (pricing_version > 0 and quote_version > 0),
  constraint fare_quotes_calculated_expiry_exact check (expires_at = created_at + interval '10 minutes'),
  constraint fare_quotes_status_timestamps_valid check (
    (status = 'calculated' and locked_at is null and superseded_at is null)
    or (status = 'locked' and locked_at is not null and superseded_at is null)
    or (status = 'expired' and locked_at is null and superseded_at is null)
    or (status = 'superseded' and superseded_at is not null)
  ),
  constraint fare_quotes_booking_quote_version_unique unique (booking_request_id, quote_version),
  constraint fare_quotes_id_booking_unique unique (id, booking_request_id)
);

create unique index fare_quotes_one_active_locked_per_booking_idx
  on public.fare_quotes (booking_request_id) where status = 'locked';
create index fare_quotes_rider_created_at_idx on public.fare_quotes (rider_id, created_at desc);

alter table public.booking_requests
  add constraint booking_requests_current_fare_quote_fk
  foreign key (fare_quote_id, id)
  references public.fare_quotes (id, booking_request_id) on delete restrict;

create table public.driver_match_offers (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null references public.booking_requests (id) on delete restrict,
  fare_quote_id uuid not null references public.fare_quotes (id) on delete restrict,
  driver_id uuid not null references public.driver_profiles (user_id) on delete restrict,
  vehicle_id uuid not null references public.vehicles (id) on delete restrict,
  status public.driver_match_offer_status not null default 'offered',
  radius_meters integer not null,
  offered_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '15 seconds'),
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  version integer not null default 1,
  constraint driver_match_offers_radius_supported check (radius_meters in (3000, 5000, 8000)),
  constraint driver_match_offers_expiry_exact check (expires_at = offered_at + interval '15 seconds'),
  constraint driver_match_offers_version_positive check (version > 0),
  constraint driver_match_offers_response_timestamp_valid check (
    (status = 'offered' and responded_at is null)
    or (status <> 'offered' and responded_at is not null)
  ),
  constraint driver_match_offers_booking_driver_unique unique (booking_request_id, driver_id)
);

create index driver_match_offers_driver_status_idx
  on public.driver_match_offers (driver_id, status, expires_at);
create index driver_match_offers_booking_status_idx
  on public.driver_match_offers (booking_request_id, status, expires_at);

create trigger pricing_configurations_set_updated_at
before update on public.pricing_configurations
for each row execute function public.set_updated_at();

create trigger booking_requests_set_updated_at
before update on public.booking_requests
for each row execute function public.set_updated_at();

create trigger booking_requests_bump_optimistic_version
before update on public.booking_requests
for each row execute function private.bump_optimistic_version();

create trigger driver_match_offers_bump_optimistic_version
before update on public.driver_match_offers
for each row execute function private.bump_optimistic_version();

create or replace function private.enforce_pricing_configuration_immutability()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.vehicle_type_code is distinct from old.vehicle_type_code
    or new.pricing_version is distinct from old.pricing_version
    or new.base_fare_fils is distinct from old.base_fare_fils
    or new.per_kilometer_fils is distinct from old.per_kilometer_fils
    or new.per_minute_fils is distinct from old.per_minute_fils
    or new.per_stop_fils is distinct from old.per_stop_fils
    or new.minimum_fare_fils is distinct from old.minimum_fare_fils
    or new.rounding_increment_fils is distinct from old.rounding_increment_fils
    or new.created_at is distinct from old.created_at then
    raise exception using errcode = '55000', message = 'Pricing configuration versions are immutable.';
  end if;
  return new;
end;
$$;

create trigger pricing_configurations_enforce_immutability
before update on public.pricing_configurations
for each row execute function private.enforce_pricing_configuration_immutability();

create or replace function private.enforce_booking_request_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status <> 'draft' and (
    new.rider_id is distinct from old.rider_id
    or new.pickup is distinct from old.pickup
    or new.destination is distinct from old.destination
    or new.vehicle_type_code is distinct from old.vehicle_type_code
    or new.payment_method is distinct from old.payment_method
    or new.fare_quote_id is distinct from old.fare_quote_id
  ) then
    raise exception using errcode = '55000', message = 'Confirmed booking inputs are immutable.';
  end if;

  if new.status is distinct from old.status and not (
    (old.status = 'draft' and new.status in ('confirmed', 'cancelled'))
    or (old.status = 'confirmed' and new.status in ('searching', 'cancelled', 'expired', 'failed'))
    or (old.status = 'searching' and new.status in ('matched', 'cancelled', 'expired', 'failed'))
  ) then
    raise exception using errcode = '55000', message = 'Invalid BookingRequest status transition.';
  end if;
  return new;
end;
$$;

create trigger booking_requests_enforce_transition
before update on public.booking_requests
for each row execute function private.enforce_booking_request_transition();

create or replace function private.enforce_draft_booking_stop_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_booking_id uuid := coalesce(new.booking_request_id, old.booking_request_id);
  target_status public.booking_request_status;
begin
  select status into target_status
  from public.booking_requests
  where id = target_booking_id;
  if found and target_status <> 'draft' then
    raise exception using errcode = '55000', message = 'Confirmed booking stops are immutable.';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger booking_stops_require_draft
before insert or update or delete on public.booking_stops
for each row execute function private.enforce_draft_booking_stop_mutation();

create or replace function private.enforce_contiguous_booking_stops()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_booking_id uuid := coalesce(new.booking_request_id, old.booking_request_id);
  stop_count integer;
  minimum_sequence integer;
  maximum_sequence integer;
begin
  if not exists (select 1 from public.booking_requests where id = target_booking_id) then
    return null;
  end if;
  select count(*), min(sequence), max(sequence)
  into stop_count, minimum_sequence, maximum_sequence
  from public.booking_stops
  where booking_request_id = target_booking_id;
  if stop_count > 3
    or (stop_count > 0 and (minimum_sequence <> 1 or maximum_sequence <> stop_count)) then
    raise exception using errcode = '23514', message = 'Booking stops must be contiguous from one with a maximum of three.';
  end if;
  return null;
end;
$$;

create constraint trigger booking_stops_contiguous
after insert or update or delete on public.booking_stops
deferrable initially deferred
for each row execute function private.enforce_contiguous_booking_stops();

create or replace function private.enforce_fare_quote_immutability()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.booking_request_id is distinct from old.booking_request_id
    or new.rider_id is distinct from old.rider_id
    or new.pickup is distinct from old.pickup
    or new.destination is distinct from old.destination
    or new.ordered_stops is distinct from old.ordered_stops
    or new.route_distance_meters is distinct from old.route_distance_meters
    or new.route_duration_seconds is distinct from old.route_duration_seconds
    or new.route_geometry_reference is distinct from old.route_geometry_reference
    or new.vehicle_type_code is distinct from old.vehicle_type_code
    or new.breakdown is distinct from old.breakdown
    or new.currency is distinct from old.currency
    or new.fixed_fare_fils is distinct from old.fixed_fare_fils
    or new.pricing_configuration_id is distinct from old.pricing_configuration_id
    or new.pricing_version is distinct from old.pricing_version
    or new.quote_version is distinct from old.quote_version
    or new.created_at is distinct from old.created_at
    or new.expires_at is distinct from old.expires_at
    or new.supersedes_fare_quote_id is distinct from old.supersedes_fare_quote_id then
    raise exception using errcode = '55000', message = 'FareQuote pricing and route snapshots are immutable.';
  end if;

  if new.status is distinct from old.status and not (
    (old.status = 'calculated' and new.status in ('locked', 'expired', 'superseded'))
    or (old.status = 'locked' and new.status = 'superseded')
  ) then
    raise exception using errcode = '55000', message = 'Invalid FareQuote status transition.';
  end if;
  return new;
end;
$$;

create trigger fare_quotes_enforce_immutability
before update on public.fare_quotes
for each row execute function private.enforce_fare_quote_immutability();

create or replace function private.require_nonblocked_rider()
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
    join public.rider_profiles as profiles on profiles.user_id = users.id
    where users.id = caller_id and users.role = 'rider' and not users.is_blocked
  ) then
    raise exception using errcode = '42501', message = 'Only a non-blocked Rider can manage bookings.';
  end if;
  return caller_id;
end;
$$;

create or replace function private.replace_draft_booking_stops(
  target_booking_request_id uuid,
  requested_stops jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_valid_ordered_stops(coalesce(requested_stops, '[]'::jsonb)) then
    raise exception using errcode = '22023', message = 'Stops must contain at most three valid ordered locations.';
  end if;

  delete from public.booking_stops where booking_request_id = target_booking_request_id;
  insert into public.booking_stops (booking_request_id, sequence, location, label, rider_note)
  select
    target_booking_request_id,
    ordinality::smallint,
    value -> 'location',
    nullif(btrim(value ->> 'label'), ''),
    nullif(btrim(value ->> 'rider_note'), '')
  from jsonb_array_elements(coalesce(requested_stops, '[]'::jsonb)) with ordinality;
end;
$$;

create or replace function private.booking_ordered_stops(target_booking_request_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'location', stops.location,
        'label', stops.label,
        'rider_note', stops.rider_note
      )) order by stops.sequence
    ),
    '[]'::jsonb
  )
  from public.booking_stops as stops
  where stops.booking_request_id = target_booking_request_id;
$$;

create or replace function private.can_read_booking(target_booking_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users as users
    where users.id = auth.uid()
      and not users.is_blocked
      and (
        users.role = 'admin'
        or (
          users.role = 'rider'
          and exists (
            select 1 from public.booking_requests as bookings
            where bookings.id = target_booking_request_id and bookings.rider_id = users.id
          )
        )
        or (
          users.role = 'driver'
          and (
            exists (
              select 1 from public.booking_requests as bookings
              where bookings.id = target_booking_request_id and bookings.matched_driver_id = users.id
            )
            or exists (
              select 1 from public.driver_match_offers as offers
              where offers.booking_request_id = target_booking_request_id and offers.driver_id = users.id
            )
          )
        )
      )
  );
$$;

create or replace function private.can_read_match_offer(
  target_booking_request_id uuid,
  target_driver_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users as users
    where users.id = auth.uid()
      and not users.is_blocked
      and (
        users.role = 'admin'
        or (users.role = 'driver' and users.id = target_driver_id)
        or (
          users.role = 'rider'
          and exists (
            select 1 from public.booking_requests as bookings
            where bookings.id = target_booking_request_id and bookings.rider_id = users.id
          )
        )
      )
  );
$$;

create or replace function public.rider_create_booking_draft(
  requested_pickup jsonb,
  requested_destination jsonb,
  requested_vehicle_type public.vehicle_type_code,
  requested_payment_method public.payment_method,
  requested_stops jsonb default '[]'::jsonb
)
returns public.booking_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  created_booking public.booking_requests%rowtype;
begin
  caller_id := private.require_nonblocked_rider();
  if not private.is_valid_route_location(requested_pickup)
    or not private.is_valid_route_location(requested_destination)
    or requested_pickup = requested_destination then
    raise exception using errcode = '22023', message = 'Pickup and destination must be distinct valid locations.';
  end if;
  if not private.is_valid_ordered_stops(coalesce(requested_stops, '[]'::jsonb)) then
    raise exception using errcode = '22023', message = 'Stops must contain at most three valid ordered locations.';
  end if;

  insert into public.booking_requests (
    rider_id, pickup, destination, vehicle_type_code, payment_method
  ) values (
    caller_id, requested_pickup, requested_destination,
    requested_vehicle_type, requested_payment_method
  ) returning * into created_booking;
  perform private.replace_draft_booking_stops(created_booking.id, requested_stops);
  return created_booking;
end;
$$;

create or replace function public.rider_update_booking_draft(
  target_booking_request_id uuid,
  expected_version integer,
  requested_pickup jsonb,
  requested_destination jsonb,
  requested_vehicle_type public.vehicle_type_code,
  requested_payment_method public.payment_method,
  requested_stops jsonb default '[]'::jsonb
)
returns public.booking_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_booking public.booking_requests%rowtype;
begin
  caller_id := private.require_nonblocked_rider();
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  if not private.is_valid_route_location(requested_pickup)
    or not private.is_valid_route_location(requested_destination)
    or requested_pickup = requested_destination then
    raise exception using errcode = '22023', message = 'Pickup and destination must be distinct valid locations.';
  end if;
  if not private.is_valid_ordered_stops(coalesce(requested_stops, '[]'::jsonb)) then
    raise exception using errcode = '22023', message = 'Stops must contain at most three valid ordered locations.';
  end if;

  select * into current_booking
  from public.booking_requests
  where id = target_booking_request_id and rider_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Booking draft was not found for this Rider.';
  end if;
  if current_booking.status <> 'draft' then
    raise exception using errcode = '55000', message = 'Only a draft booking can be updated.';
  end if;
  if current_booking.version <> expected_version then
    raise exception using errcode = '40001', message = 'Booking version is stale.';
  end if;

  update public.fare_quotes
  set status = 'superseded', superseded_at = now()
  where booking_request_id = current_booking.id and status = 'calculated';

  update public.booking_requests
  set pickup = requested_pickup,
      destination = requested_destination,
      vehicle_type_code = requested_vehicle_type,
      payment_method = requested_payment_method,
      fare_quote_id = null
  where id = current_booking.id
  returning * into current_booking;
  perform private.replace_draft_booking_stops(current_booking.id, requested_stops);
  return current_booking;
end;
$$;

create or replace function public.rider_confirm_booking(
  target_booking_request_id uuid,
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
  current_booking public.booking_requests%rowtype;
  payload_fingerprint text;
  canonical_result jsonb;
  claimed_result jsonb;
begin
  caller_id := private.require_nonblocked_rider();
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  canonical_result := jsonb_build_object(
    'booking_request_id', target_booking_request_id,
    'status', 'confirmed'
  );
  payload_fingerprint := encode(
    extensions.digest(
      convert_to(concat_ws('|', target_booking_request_id::text, expected_version::text), 'UTF8'),
      'sha256'
    ),
    'hex'
  );
  claimed_result := private.claim_command_idempotency_key(
    caller_id, 'booking', idempotency_key, payload_fingerprint, canonical_result
  );
  if claimed_result ? 'error' then
    return claimed_result;
  end if;

  select * into current_booking
  from public.booking_requests
  where id = target_booking_request_id and rider_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Booking was not found for this Rider.';
  end if;
  if current_booking.status = 'confirmed' then
    return claimed_result;
  end if;
  if current_booking.status <> 'draft' then
    raise exception using errcode = '55000', message = 'Only a draft booking can be confirmed.';
  end if;
  if current_booking.version <> expected_version then
    raise exception using errcode = '40001', message = 'Booking version is stale.';
  end if;
  if current_booking.fare_quote_id is null or not exists (
    select 1 from public.fare_quotes
    where id = current_booking.fare_quote_id
      and booking_request_id = current_booking.id
      and status = 'locked'
  ) then
    raise exception using errcode = '55000', message = 'Booking confirmation requires its active locked FareQuote.';
  end if;

  update public.booking_requests
  set status = 'confirmed', confirmed_at = now()
  where id = current_booking.id;
  perform private.write_audit_record(
    caller_id, 'booking.confirmed', caller_id, null,
    jsonb_build_object('booking_request_id', current_booking.id, 'status', current_booking.status),
    canonical_result
  );
  return canonical_result;
end;
$$;

create or replace function public.rider_cancel_booking(
  target_booking_request_id uuid,
  expected_version integer,
  reason_code text default null
)
returns public.booking_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_booking public.booking_requests%rowtype;
begin
  caller_id := private.require_nonblocked_rider();
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  select * into current_booking
  from public.booking_requests
  where id = target_booking_request_id and rider_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Booking was not found for this Rider.';
  end if;
  if current_booking.status = 'cancelled' then
    return current_booking;
  end if;
  if current_booking.status not in ('draft', 'confirmed', 'searching') then
    raise exception using errcode = '55000', message = 'This booking can no longer be cancelled by its Rider.';
  end if;
  if current_booking.version <> expected_version then
    raise exception using errcode = '40001', message = 'Booking version is stale.';
  end if;
  if current_booking.status <> 'draft'
    and char_length(btrim(coalesce(reason_code, ''))) not between 1 and 100 then
    raise exception using errcode = '22023', message = 'A cancellation reason is required after confirmation.';
  end if;

  update public.driver_match_offers
  set status = 'cancelled', responded_at = now()
  where booking_request_id = current_booking.id and status = 'offered';
  update public.booking_requests
  set status = 'cancelled',
      cancelled_at = now(),
      cancellation_reason_code = nullif(btrim(reason_code), '')
  where id = current_booking.id
  returning * into current_booking;
  perform private.write_audit_record(
    caller_id, 'booking.cancelled', caller_id, current_booking.cancellation_reason_code,
    jsonb_build_object('booking_request_id', current_booking.id),
    jsonb_build_object('status', current_booking.status)
  );
  return current_booking;
end;
$$;

create or replace function public.backend_create_pricing_configuration(
  requested_vehicle_type public.vehicle_type_code,
  requested_base_fare_fils integer,
  requested_per_kilometer_fils integer,
  requested_per_minute_fils integer,
  requested_per_stop_fils integer,
  requested_minimum_fare_fils integer,
  requested_rounding_increment_fils integer default 50,
  activate boolean default true
)
returns public.pricing_configurations
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_version integer;
  created_configuration public.pricing_configurations%rowtype;
begin
  perform pg_advisory_xact_lock(hashtext('ridex.pricing.' || requested_vehicle_type::text));
  select coalesce(max(pricing_version), 0) + 1 into next_version
  from public.pricing_configurations
  where vehicle_type_code = requested_vehicle_type;
  if activate then
    update public.pricing_configurations
    set is_active = false
    where vehicle_type_code = requested_vehicle_type and is_active;
  end if;
  insert into public.pricing_configurations (
    vehicle_type_code, pricing_version, base_fare_fils,
    per_kilometer_fils, per_minute_fils, per_stop_fils,
    minimum_fare_fils, rounding_increment_fils, is_active
  ) values (
    requested_vehicle_type, next_version, requested_base_fare_fils,
    requested_per_kilometer_fils, requested_per_minute_fils, requested_per_stop_fils,
    requested_minimum_fare_fils, requested_rounding_increment_fils, activate
  ) returning * into created_configuration;
  return created_configuration;
end;
$$;

create or replace function public.backend_calculate_fare_quote(
  target_booking_request_id uuid,
  expected_booking_version integer,
  requested_route_distance_meters integer,
  requested_route_duration_seconds integer,
  requested_route_geometry_reference text default null
)
returns public.fare_quotes
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_booking public.booking_requests%rowtype;
  pricing public.pricing_configurations%rowtype;
  ordered_stops jsonb;
  stop_count integer;
  distance_fils bigint;
  duration_fils bigint;
  stops_fils bigint;
  subtotal_fils bigint;
  fare_before_rounding bigint;
  final_fare bigint;
  next_quote_version integer;
  created_quote public.fare_quotes%rowtype;
begin
  if expected_booking_version is null or expected_booking_version < 1
    or requested_route_distance_meters < 0
    or requested_route_duration_seconds < 0 then
    raise exception using errcode = '22023', message = 'Fare calculation requires valid metrics and a positive expected version.';
  end if;
  select * into current_booking
  from public.booking_requests
  where id = target_booking_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Booking was not found.';
  end if;
  if current_booking.status <> 'draft' then
    raise exception using errcode = '55000', message = 'Fare can be calculated only for a draft booking.';
  end if;
  if current_booking.version <> expected_booking_version then
    raise exception using errcode = '40001', message = 'Booking version is stale.';
  end if;
  if not exists (select 1 from public.users where id = current_booking.rider_id and not is_blocked) then
    raise exception using errcode = '42501', message = 'A blocked Rider cannot receive a FareQuote.';
  end if;
  select * into pricing
  from public.pricing_configurations
  where vehicle_type_code = current_booking.vehicle_type_code and is_active
  for share;
  if not found then
    raise exception using errcode = '55000', message = 'No active pricing configuration supports this vehicle type.';
  end if;

  ordered_stops := private.booking_ordered_stops(current_booking.id);
  stop_count := jsonb_array_length(ordered_stops);
  distance_fils := (
    requested_route_distance_meters::bigint * pricing.per_kilometer_fils + 500
  ) / 1000;
  duration_fils := (
    requested_route_duration_seconds::bigint * pricing.per_minute_fils + 30
  ) / 60;
  stops_fils := stop_count::bigint * pricing.per_stop_fils;
  subtotal_fils := pricing.base_fare_fils::bigint + distance_fils + duration_fils + stops_fils;
  fare_before_rounding := greatest(subtotal_fils, pricing.minimum_fare_fils::bigint);
  final_fare := (
    fare_before_rounding + pricing.rounding_increment_fils / 2
  ) / pricing.rounding_increment_fils * pricing.rounding_increment_fils;
  if final_fare > 2147483647 then
    raise exception using errcode = '22003', message = 'Calculated fare exceeds supported integer fils.';
  end if;

  update public.fare_quotes
  set status = (
        case when expires_at <= now() then 'expired' else 'superseded' end
      )::public.fare_quote_status,
      superseded_at = case when expires_at > now() then now() else null end
  where booking_request_id = current_booking.id and status = 'calculated';
  select coalesce(max(quote_version), 0) + 1 into next_quote_version
  from public.fare_quotes
  where booking_request_id = current_booking.id;

  insert into public.fare_quotes (
    booking_request_id, rider_id, pickup, destination, ordered_stops,
    route_distance_meters, route_duration_seconds, route_geometry_reference,
    vehicle_type_code, breakdown, fixed_fare_fils,
    pricing_configuration_id, pricing_version, quote_version
  ) values (
    current_booking.id, current_booking.rider_id, current_booking.pickup,
    current_booking.destination, ordered_stops, requested_route_distance_meters,
    requested_route_duration_seconds, nullif(btrim(requested_route_geometry_reference), ''),
    current_booking.vehicle_type_code,
    jsonb_build_object(
      'base_fare_fils', pricing.base_fare_fils,
      'distance_fils', distance_fils,
      'duration_fils', duration_fils,
      'stops_fils', stops_fils,
      'subtotal_fils', subtotal_fils,
      'minimum_fare_fils', pricing.minimum_fare_fils,
      'rounding_increment_fils', pricing.rounding_increment_fils,
      'fixed_fare_fils', final_fare
    ),
    final_fare::integer, pricing.id, pricing.pricing_version, next_quote_version
  ) returning * into created_quote;
  return created_quote;
end;
$$;

create or replace function public.backend_lock_fare_quote(
  target_fare_quote_id uuid,
  expected_booking_version integer,
  expected_quote_version integer
)
returns public.fare_quotes
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_quote public.fare_quotes%rowtype;
  current_booking public.booking_requests%rowtype;
  ordered_stops jsonb;
begin
  select * into target_quote
  from public.fare_quotes
  where id = target_fare_quote_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'FareQuote was not found.';
  end if;
  select * into current_booking
  from public.booking_requests
  where id = target_quote.booking_request_id
  for update;
  if current_booking.status <> 'draft' then
    raise exception using errcode = '55000', message = 'A FareQuote can be locked only for a draft booking.';
  end if;
  if current_booking.version <> expected_booking_version then
    raise exception using errcode = '40001', message = 'Booking version is stale.';
  end if;
  if target_quote.quote_version <> expected_quote_version then
    raise exception using errcode = '40001', message = 'FareQuote version is stale.';
  end if;
  if target_quote.status <> 'calculated' or target_quote.expires_at <= now() then
    raise exception using errcode = '55000', message = 'Only an unexpired calculated FareQuote can be locked.';
  end if;
  ordered_stops := private.booking_ordered_stops(current_booking.id);
  if target_quote.pickup <> current_booking.pickup
    or target_quote.destination <> current_booking.destination
    or target_quote.ordered_stops <> ordered_stops
    or target_quote.vehicle_type_code <> current_booking.vehicle_type_code then
    raise exception using errcode = '40001', message = 'FareQuote inputs are stale.';
  end if;

  update public.fare_quotes
  set status = 'superseded', superseded_at = now()
  where booking_request_id = current_booking.id and status = 'locked';
  update public.fare_quotes
  set status = 'locked', locked_at = now()
  where id = target_quote.id
  returning * into target_quote;
  update public.booking_requests
  set fare_quote_id = target_quote.id
  where id = current_booking.id;
  return target_quote;
end;
$$;

create or replace function public.backend_create_driver_match_offer(
  target_booking_request_id uuid,
  target_driver_id uuid,
  target_vehicle_id uuid,
  requested_radius_meters integer,
  expected_booking_version integer
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
  if requested_radius_meters not in (3000, 5000, 8000)
    or expected_booking_version is null or expected_booking_version < 1 then
    raise exception using errcode = '22023', message = 'Matching offer inputs are invalid.';
  end if;
  select * into current_booking
  from public.booking_requests
  where id = target_booking_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Booking was not found.';
  end if;
  if current_booking.version <> expected_booking_version then
    raise exception using errcode = '40001', message = 'Booking version is stale.';
  end if;
  if current_booking.status not in ('confirmed', 'searching')
    or current_booking.fare_quote_id is null
    or not exists (
      select 1 from public.fare_quotes
      where id = current_booking.fare_quote_id and status = 'locked'
    ) then
    raise exception using errcode = '55000', message = 'Matching offers require a confirmed or searching booking with a locked FareQuote.';
  end if;
  if not exists (
    select 1 from public.users
    where id = current_booking.rider_id and role = 'rider' and not is_blocked
  ) then
    raise exception using errcode = '42501', message = 'A blocked Rider cannot enter matching.';
  end if;
  if current_booking.searching_at is not null
    and current_booking.searching_at + interval '90 seconds' <= now() then
    raise exception using errcode = '55000', message = 'The matching window has expired.';
  end if;
  if not exists (
    select 1
    from public.users as users
    join public.driver_profiles as profiles on profiles.user_id = users.id
    join public.vehicles as vehicles on vehicles.driver_id = profiles.user_id
    join public.driver_availability as availability on availability.driver_id = profiles.user_id
    where users.id = target_driver_id
      and users.role = 'driver'
      and not users.is_blocked
      and profiles.approval_status = 'approved'
      and vehicles.id = target_vehicle_id
      and vehicles.is_active
      and vehicles.vehicle_type_code = current_booking.vehicle_type_code
      and availability.state = 'available'
      and availability.vehicle_id = vehicles.id
  ) then
    raise exception using errcode = '42501', message = 'Driver is not eligible for this matching offer.';
  end if;

  update public.driver_match_offers
  set status = 'expired', responded_at = now()
  where booking_request_id = current_booking.id
    and status = 'offered'
    and expires_at <= now();
  if (
    select count(*) from public.driver_match_offers
    where booking_request_id = current_booking.id
      and status = 'offered'
      and expires_at > now()
  ) >= 3 then
    raise exception using errcode = '54000', message = 'A booking can have at most three active matching offers.';
  end if;

  if current_booking.status = 'confirmed' then
    update public.booking_requests
    set status = 'searching', searching_at = now()
    where id = current_booking.id;
  end if;
  insert into public.driver_match_offers (
    booking_request_id, fare_quote_id, driver_id, vehicle_id, radius_meters
  ) values (
    current_booking.id, current_booking.fare_quote_id,
    target_driver_id, target_vehicle_id, requested_radius_meters
  ) returning * into created_offer;
  return created_offer;
end;
$$;

alter table public.pricing_configurations enable row level security;
alter table public.booking_requests enable row level security;
alter table public.booking_stops enable row level security;
alter table public.fare_quotes enable row level security;
alter table public.driver_match_offers enable row level security;

create policy pricing_configurations_authenticated_select
on public.pricing_configurations for select to authenticated
using (
  exists (
    select 1 from public.users as users
    where users.id = auth.uid()
      and not users.is_blocked
      and (pricing_configurations.is_active or users.role = 'admin')
  )
);

create policy booking_requests_participant_select
on public.booking_requests for select to authenticated
using (private.can_read_booking(id));

create policy booking_stops_participant_select
on public.booking_stops for select to authenticated
using (private.can_read_booking(booking_request_id));

create policy fare_quotes_participant_select
on public.fare_quotes for select to authenticated
using (private.can_read_booking(booking_request_id));

create policy driver_match_offers_participant_select
on public.driver_match_offers for select to authenticated
using (private.can_read_match_offer(booking_request_id, driver_id));

revoke all on table
  public.pricing_configurations,
  public.booking_requests,
  public.booking_stops,
  public.fare_quotes,
  public.driver_match_offers
from public, anon, authenticated, service_role;
grant select on table
  public.pricing_configurations,
  public.booking_requests,
  public.booking_stops,
  public.fare_quotes,
  public.driver_match_offers
to authenticated;
grant select, insert, update, delete on table
  public.pricing_configurations,
  public.booking_requests,
  public.booking_stops,
  public.fare_quotes,
  public.driver_match_offers
to service_role;

revoke all on function private.is_valid_route_location(jsonb) from public, anon, authenticated, service_role;
revoke all on function private.is_valid_ordered_stops(jsonb) from public, anon, authenticated, service_role;
revoke all on function private.enforce_pricing_configuration_immutability() from public, anon, authenticated, service_role;
revoke all on function private.enforce_booking_request_transition() from public, anon, authenticated, service_role;
revoke all on function private.enforce_draft_booking_stop_mutation() from public, anon, authenticated, service_role;
revoke all on function private.enforce_contiguous_booking_stops() from public, anon, authenticated, service_role;
revoke all on function private.enforce_fare_quote_immutability() from public, anon, authenticated, service_role;
revoke all on function private.require_nonblocked_rider() from public, anon, authenticated, service_role;
revoke all on function private.replace_draft_booking_stops(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.booking_ordered_stops(uuid) from public, anon, authenticated, service_role;
revoke all on function private.can_read_booking(uuid) from public, anon, authenticated, service_role;
revoke all on function private.can_read_match_offer(uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function private.can_read_booking(uuid) to authenticated;
grant execute on function private.can_read_match_offer(uuid, uuid) to authenticated;

revoke all on function public.rider_create_booking_draft(jsonb, jsonb, public.vehicle_type_code, public.payment_method, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.rider_update_booking_draft(uuid, integer, jsonb, jsonb, public.vehicle_type_code, public.payment_method, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.rider_confirm_booking(uuid, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.rider_cancel_booking(uuid, integer, text) from public, anon, authenticated, service_role;
grant execute on function public.rider_create_booking_draft(jsonb, jsonb, public.vehicle_type_code, public.payment_method, jsonb) to authenticated;
grant execute on function public.rider_update_booking_draft(uuid, integer, jsonb, jsonb, public.vehicle_type_code, public.payment_method, jsonb) to authenticated;
grant execute on function public.rider_confirm_booking(uuid, integer, text) to authenticated;
grant execute on function public.rider_cancel_booking(uuid, integer, text) to authenticated;

revoke all on function public.backend_create_pricing_configuration(public.vehicle_type_code, integer, integer, integer, integer, integer, integer, boolean) from public, anon, authenticated, service_role;
revoke all on function public.backend_calculate_fare_quote(uuid, integer, integer, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.backend_lock_fare_quote(uuid, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.backend_create_driver_match_offer(uuid, uuid, uuid, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.backend_create_pricing_configuration(public.vehicle_type_code, integer, integer, integer, integer, integer, integer, boolean) to service_role;
grant execute on function public.backend_calculate_fare_quote(uuid, integer, integer, integer, text) to service_role;
grant execute on function public.backend_lock_fare_quote(uuid, integer, integer) to service_role;
grant execute on function public.backend_create_driver_match_offer(uuid, uuid, uuid, integer, integer) to service_role;

commit;
