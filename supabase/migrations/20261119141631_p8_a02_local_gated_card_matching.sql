begin;
-- Default OFF. Only database owners may change this private switch; clients and service role cannot.
create table private.p8_card_matching_gate (singleton boolean primary key default true check (singleton), enabled boolean not null default false);
insert into private.p8_card_matching_gate(singleton, enabled) values (true, false);
alter table private.p8_card_matching_gate enable row level security;
revoke all on private.p8_card_matching_gate from public, anon, authenticated, service_role;
create function private.p8_card_matching_enabled() returns boolean language sql stable security definer set search_path = '' as $$ select coalesce((select enabled from private.p8_card_matching_gate where singleton), false) $$;
create function private.p8_card_matching_gate_locked() returns boolean language plpgsql security definer set search_path = '' as $$ declare result boolean; begin select enabled into result from private.p8_card_matching_gate where singleton for share; return coalesce(result, false); end $$;
revoke all on function private.p8_card_matching_enabled(), private.p8_card_matching_gate_locked() from public, anon, authenticated, service_role;
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
  -- Historical confirmed bookings are recovered unchanged, including Card
  -- bookings created before this temporary policy.
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
  if current_booking.payment_method is distinct from 'cash'::public.payment_method and not (current_booking.payment_method = 'card'::public.payment_method and private.p8_card_matching_gate_locked()) then
    raise exception using errcode = '55000', message = 'Only Cash bookings can be confirmed until Card authorization is available.';
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

create or replace function public.backend_find_nearby_driver_candidates(
  target_booking_request_id uuid,
  expected_booking_version integer,
  requested_radius_meters integer default 3000,
  requested_limit integer default 3
)
returns table (
  driver_id uuid,
  vehicle_id uuid,
  availability_version integer,
  vehicle_version integer,
  location_sequence bigint,
  distance_meters double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  booking public.booking_requests%rowtype;
  observed_at timestamptz := statement_timestamp();
  pickup_latitude double precision;
  pickup_longitude double precision;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Backend access required.';
  end if;
  if target_booking_request_id is null
    or expected_booking_version is null or expected_booking_version < 1
    or requested_radius_meters is null or requested_radius_meters not in (3000, 5000, 8000)
    or requested_limit is null or requested_limit not between 1 and 3 then
    raise exception using errcode = '22023', message = 'Candidate search inputs are invalid.';
  end if;

  -- No FOR UPDATE/SHARE: a STABLE function uses the caller statement snapshot.
  select b.* into booking from public.booking_requests b
  where b.id = target_booking_request_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Booking was not found.';
  end if;
  if booking.version <> expected_booking_version then
    raise exception using errcode = '40001', message = 'Booking version is stale.';
  end if;
  if not exists (select 1 from public.users u where u.id = booking.rider_id
    and u.role = 'rider' and not u.is_blocked) then
    raise exception using errcode = '42501', message = 'Rider cannot enter matching.';
  end if;
  if (booking.payment_method <> 'cash' and not (booking.payment_method = 'card' and private.p8_card_matching_enabled())) or booking.status not in ('confirmed', 'searching')
    or booking.matched_driver_id is not null or booking.matched_vehicle_id is not null
    or (booking.status = 'searching' and (booking.searching_at is null
      or booking.searching_at + interval '90 seconds' <= observed_at))
    or not exists (select 1 from public.fare_quotes q
      where q.id = booking.fare_quote_id and q.booking_request_id = booking.id
        and q.rider_id = booking.rider_id and q.status = 'locked'
        and q.pickup = booking.pickup and q.vehicle_type_code = booking.vehicle_type_code)
    or exists (select 1 from public.trips t where t.booking_request_id = booking.id) then
    raise exception using errcode = '55000', message = 'Candidate search requires an unmatched confirmed Cash booking with its locked FareQuote.';
  end if;
  pickup_latitude := (booking.pickup ->> 'latitude')::double precision;
  pickup_longitude := (booking.pickup ->> 'longitude')::double precision;

  return query
  select a.driver_id, v.id, a.version, v.version, latest.sequence, latest.distance_meters
  from public.driver_availability a
  join public.users u on u.id = a.driver_id and u.role = 'driver' and not u.is_blocked
  join public.driver_profiles p on p.user_id = u.id and p.approval_status = 'approved'
  join public.vehicles v on v.id = a.vehicle_id and v.driver_id = a.driver_id
    and v.is_active and v.vehicle_type_code = booking.vehicle_type_code
  -- Select latest sequence BEFORE quality filters: never resurrect an older fix.
  cross join lateral private.current_matching_gps(a.driver_id, pickup_latitude, pickup_longitude, observed_at) latest
  where a.state = 'available' and a.reserved_booking_request_id is null and a.active_trip_id is null
    and not exists (select 1 from public.trips t where t.driver_id = a.driver_id
      and t.status not in ('completed', 'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed'))
    -- The existing booking/Driver unique constraint permits only one offer ever.
    and not exists (select 1 from public.driver_match_offers o
      where o.booking_request_id = booking.id and o.driver_id = a.driver_id)
    -- Inclusive boundary, with one micrometre solely for float roundoff.
    and latest.distance_meters <= requested_radius_meters::double precision + 0.000001
  order by latest.distance_meters, a.driver_id
  limit requested_limit;
end;
$$;

create or replace function public.backend_create_driver_match_offer(
  target_booking_request_id uuid, target_driver_id uuid, target_vehicle_id uuid,
  requested_radius_meters integer, expected_booking_version integer
) returns public.driver_match_offers
language plpgsql security definer set search_path = '' as $$
declare b public.booking_requests%rowtype; o public.driver_match_offers%rowtype;
  a public.driver_availability%rowtype; gps record; observed_at timestamptz;
begin
  if target_booking_request_id is null or target_driver_id is null or target_vehicle_id is null
    or requested_radius_meters is null or requested_radius_meters not in (3000,5000,8000)
    or expected_booking_version is null or expected_booking_version < 1 then
    raise exception using errcode='22023',message='Matching offer inputs are invalid.';
  end if;
  perform private.lock_matching_driver(target_driver_id);
  perform 1 from public.users where id=(select rider_id from public.booking_requests where id=target_booking_request_id) for no key update;
  select * into b from public.booking_requests where id=target_booking_request_id for update;
  if not found then raise exception using errcode='P0002',message='Booking was not found.'; end if;
  perform 1 from public.driver_match_offers where booking_request_id=b.id order by id for update;
  -- Canonical pair uniqueness is the creation retry/recovery identity. Return
  -- terminal rows too: recovery never resurrects or extends an old offer.
  select * into o from public.driver_match_offers where booking_request_id=b.id and driver_id=target_driver_id;
  if found then
    if o.vehicle_id is distinct from target_vehicle_id or o.radius_meters is distinct from requested_radius_meters then
      raise exception using errcode='23505',message='Matching offer retry conflicts.';
    end if;
    return o;
  end if;
  if b.version <> expected_booking_version then raise exception using errcode='40001',message='Booking version is stale.'; end if;
  if (b.payment_method <> 'cash' and not (b.payment_method = 'card' and private.p8_card_matching_gate_locked())) or b.status not in ('confirmed','searching')
    or not exists(select 1 from public.fare_quotes q where q.id=b.fare_quote_id
      and q.booking_request_id=b.id and q.rider_id=b.rider_id and q.status='locked'
      and q.pickup=b.pickup and q.vehicle_type_code=b.vehicle_type_code)
    or exists(select 1 from public.trips t where t.booking_request_id=b.id) then
    raise exception using errcode='55000',message='Matching requires an unmatched Cash booking with its locked FareQuote.';
  end if;
  if not exists(select 1 from public.users where id=b.rider_id and role='rider' and not is_blocked) then
    raise exception using errcode='42501',message='A blocked Rider cannot enter matching.';
  end if;
  perform private.expire_booking_offers(b.id);
  select * into b from public.booking_requests where id=b.id;
  if b.status not in ('confirmed','searching') then
    raise exception using errcode='55000',message='The matching window has expired.';
  end if;
  if (select count(*) from public.driver_match_offers where booking_request_id=b.id and status='offered') >= 3 then
    raise exception using errcode='54000',message='A booking can have at most three active matching offers.';
  end if;
  select * into a from public.driver_availability where driver_id=target_driver_id for update;
  perform 1 from public.vehicles where id=target_vehicle_id for update;
  if not exists(select 1 from public.users u join public.driver_profiles p on p.user_id=u.id
    join public.vehicles v on v.driver_id=u.id and v.id=target_vehicle_id
    where u.id=target_driver_id and u.role='driver' and not u.is_blocked and p.approval_status='approved'
      and v.is_active and v.vehicle_type_code=b.vehicle_type_code)
    or a.driver_id is null or a.vehicle_id is distinct from target_vehicle_id
    or not (a.state='available' or (a.state='reserved' and a.reserved_booking_request_id=b.id))
    or a.active_trip_id is not null
    or exists(select 1 from public.trips t where t.driver_id=target_driver_id
      and t.status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed')) then
    raise exception using errcode='42501',message='Driver is not eligible for this matching offer.';
  end if;
  -- driver_record_location serializes on availability. After this lock wait,
  -- obtain the newest sequence and recompute, never trust discovery evidence.
  observed_at := clock_timestamp();
  select * into gps from private.current_matching_gps(target_driver_id,
    (b.pickup->>'latitude')::double precision,(b.pickup->>'longitude')::double precision,observed_at);
  if not found or gps.distance_meters > requested_radius_meters + 0.000001 then
    raise exception using errcode='55000',message='Current Driver location is not eligible for this offer.';
  end if;
  if b.searching_at is not null and b.searching_at + interval '90 seconds' <= observed_at then
    raise exception using errcode='55000',message='The matching window has expired.';
  end if;
  if b.status='confirmed' then
    update public.booking_requests set status='searching',searching_at=observed_at where id=b.id;
  end if;
  insert into public.driver_match_offers(booking_request_id,fare_quote_id,driver_id,vehicle_id,radius_meters,offered_at,expires_at)
    values(b.id,b.fare_quote_id,target_driver_id,target_vehicle_id,requested_radius_meters,observed_at,observed_at+interval '15 seconds') returning * into o;
  perform private.write_audit_record(null,'matching.offer_created',target_driver_id,null,
    jsonb_build_object('booking_request_id',b.id),
    jsonb_build_object('offer_id',o.id,'location_sequence',gps.sequence));
  return o;
end;
$$;

create or replace function public.driver_transition_trip(target_id uuid, requested_status public.trip_status, expected_version integer, idempotency_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid(); o public.driver_match_offers%rowtype; b public.booking_requests%rowtype;
  result jsonb;
begin
  if requested_status is distinct from 'accepted' then
    return private.p7_a04_original_driver_transition_trip(target_id,requested_status,expected_version,idempotency_key);
  end if;
  if expected_version is null or expected_version < 1 then
    raise exception using errcode='22023',message='A positive expected version is required.';
  end if;
  perform private.lock_matching_driver(caller);
  caller := private.require_approved_driver();
  select * into o from public.driver_match_offers where id=target_id and driver_id=caller;
  if not found then raise exception using errcode='P0002',message='Matching offer was not found for this Driver.'; end if;
  perform 1 from public.users where id=(select rider_id from public.booking_requests where id=o.booking_request_id) for no key update;
  select * into b from public.booking_requests where id=o.booking_request_id for update;
  perform 1 from public.driver_match_offers where booking_request_id=b.id order by id for update;
  -- Every competing reservation is pinned before the preserved path touches any
  -- offer. Another contender holds no offer/availability while waiting on b.
  -- Already-accepted recovery does not pin availability: Trip cancellation/
  -- completion owns Trip -> availability and must be allowed to finish.
  select * into o from public.driver_match_offers where id=target_id;
  if o.status <> 'accepted' then
    if b.payment_method = 'card' and not private.p8_card_matching_gate_locked() then
      raise exception using errcode='55000', message='Card matching is disabled.';
    end if;
    perform 1 from public.driver_availability where driver_id=caller or reserved_booking_request_id=b.id order by driver_id for update;
    if o.version <> expected_version then raise exception using errcode='40001',message='Matching offer version is stale.'; end if;
    if o.status <> 'offered' or o.expires_at <= clock_timestamp() then
      raise exception using errcode='55000',message='Only a live offered match can create a Trip.';
    end if;
    if b.status <> 'searching' or b.searching_at is null or b.searching_at + interval '90 seconds' <= clock_timestamp() then
      raise exception using errcode='55000',message='The booking is no longer available for assignment.';
    end if;
    if not exists(select 1 from public.users where id=b.rider_id and role='rider' and not is_blocked) then
      raise exception using errcode='42501',message='Rider cannot enter matching.';
    end if;
    if exists(select 1 from public.trips where driver_id=caller
      and status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed')) then
      raise exception using errcode='55000',message='Driver already has an active Trip.';
    end if;
  end if;
  result := private.p7_a04_original_driver_transition_trip(target_id,requested_status,expected_version,idempotency_key);
  return result;
end;
$$;

create or replace function private.reconcile_cancelled_trip_payment(target_trip_id uuid)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_trip public.trips%rowtype;
  current_payment public.payments%rowtype;
  current_authorization public.payment_attempts%rowtype;
begin
  select * into current_trip from public.trips where id = target_trip_id for update;
  if not found or current_trip.status not in (
    'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed'
  ) then
    raise exception using errcode = '55000',
      message = 'Payment cancellation requires a terminal cancelled Trip.';
  end if;

  current_payment := private.ensure_trip_payment(current_trip.id);
  if current_payment.method = 'cash' then
    if current_payment.cash_status = 'cashSelected' then
      update public.payments
      set cash_status = 'cancelled', cancelled_at = now()
      where id = current_payment.id
      returning * into current_payment;
    elsif current_payment.cash_status <> 'cancelled' then
      raise exception using errcode = '55000', message = 'Settled Cash Payment cannot be cancelled.';
    end if;
    return current_payment;
  end if;

  if current_payment.card_status = 'paymentCancelled' then return current_payment; end if;
  if current_payment.card_status not in (
    'cardPaymentPending', 'cardPaymentAuthorized', 'cardPaymentFailed'
  ) then
    raise exception using errcode = '55000',
      message = 'Card Payment is not eligible for cancellation.';
  end if;
  select * into current_authorization
  from public.payment_attempts
  where payment_id = current_payment.id
    and type in ('initialAuthorization', 'replacementAuthorization')
  order by authorization_cycle desc, attempt_sequence desc
  limit 1;
  if exists (select 1 from public.payment_attempts a left join private.stripe_test_dispatch_reservations r on r.attempt_id = a.id where a.payment_id = current_payment.id and a.type in ('initialAuthorization', 'replacementAuthorization') and (a.status = 'pending' or r.state in ('reserved', 'unknown', 'prepared'))) then
    raise exception using errcode = '55000', message = 'Unresolved authorization requires trusted reconciliation before cancellation.';
  end if;
  if found and current_authorization.status = 'succeeded'
    and not private.has_verified_card_void(
      current_payment.id, current_authorization.authorization_cycle
    ) then
    raise exception using errcode = '55000',
      message = 'Card Payment requires a verified current-cycle void before cancellation.';
  end if;
  update public.payments
  set card_status = 'paymentCancelled', cancelled_at = now()
  where id = current_payment.id
  returning * into current_payment;
  return current_payment;
end;
$$;
commit;
