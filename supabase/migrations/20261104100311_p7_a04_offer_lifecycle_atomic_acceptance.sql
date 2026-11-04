begin;

-- Fail closed on pre-existing conflicting assignments; never repair live data
-- implicitly. The RPC actor locks serialize normal claims; this is defense in
-- depth for every trusted write path as well.
create unique index trips_one_nonterminal_per_driver_idx on public.trips(driver_id)
where status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed');

-- Same A03 policy, shared by discovery and mutation-time revalidation.
create function private.current_matching_gps(
  target_driver_id uuid, pickup_latitude double precision,
  pickup_longitude double precision, observed_at timestamptz
) returns table(sequence bigint, distance_meters double precision)
language sql stable security definer set search_path = '' as $$
  select latest.sequence,
    2.0 * 6371008.8 * asin(sqrt(least(1.0::double precision, greatest(0.0::double precision,
      power(sin(radians(latest.latitude - pickup_latitude) / 2.0), 2)
      + cos(radians(pickup_latitude)) * cos(radians(latest.latitude))
      * power(sin(radians(latest.longitude - pickup_longitude) / 2.0), 2)))))
  from (select l.* from public.driver_locations l where l.driver_id = target_driver_id
    order by l.sequence desc limit 1) latest
  where latest.trip_id is null
    and latest.recorded_at >= observed_at - interval '60 seconds'
    and latest.recorded_at <= observed_at + interval '5 seconds'
    and latest.received_at >= observed_at - interval '60 seconds'
    and latest.received_at <= observed_at
    and latest.recorded_at <= latest.received_at + interval '5 seconds'
    and latest.accuracy_meters <= 50;
$$;
revoke all on function private.current_matching_gps(uuid,double precision,double precision,timestamptz)
  from public,anon,authenticated,service_role;

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
  if booking.payment_method <> 'cash' or booking.status not in ('confirmed', 'searching')
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


-- Lock actor rows before booking -> offers -> availability -> vehicle. Actor
-- NO KEY UPDATE remains compatible with GPS INSERT's FK key-share locks.
create function private.lock_matching_driver(target_driver_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.users where id=target_driver_id for no key update;
  perform 1 from public.driver_profiles where user_id=target_driver_id for no key update;
end;
$$;

create function private.expire_booking_offers(target_booking_request_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare b public.booking_requests%rowtype; observed_at timestamptz := clock_timestamp();
begin
  select * into b from public.booking_requests where id=target_booking_request_id for update;
  perform 1 from public.driver_match_offers where booking_request_id=b.id order by id for update;
  if b.status='searching' and b.searching_at + interval '90 seconds' <= observed_at then
    update public.driver_match_offers set status='expired',responded_at=observed_at
      where booking_request_id=b.id and status='offered';
    update public.booking_requests set status='expired',expired_at=observed_at where id=b.id;
    perform private.write_audit_record(null,'matching.search_expired',b.rider_id,null,
      jsonb_build_object('booking_request_id',b.id),jsonb_build_object('status','expired'));
  else
    update public.driver_match_offers set status='expired',responded_at=observed_at
      where booking_request_id=b.id and status='offered' and expires_at <= observed_at;
  end if;
end;
$$;

create or replace function private.release_driver_reservation_on_terminal_offer()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status='offered' and new.status in ('declined','expired','cancelled') then
    perform private.release_matching_driver_reservation(new.driver_id,new.booking_request_id);
  end if;
  return new;
end;
$$;

-- Every terminal offer transition is audited once, including losing offers and
-- Rider cancellation. No location/route payload enters the audit record.
create function private.audit_match_offer_transition()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status is distinct from new.status then
    perform private.write_audit_record(auth.uid(),'matching.offer_'||new.status::text,new.driver_id,null,
      jsonb_build_object('offer_id',new.id,'status',old.status),
      jsonb_build_object('offer_id',new.id,'status',new.status));
  end if;
  return new;
end;
$$;
create trigger driver_match_offers_audit_transition after update of status on public.driver_match_offers
for each row execute function private.audit_match_offer_transition();

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
  if b.payment_method <> 'cash' or b.status not in ('confirmed','searching')
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

create function public.backend_expire_booking_match_offers(target_booking_request_id uuid, expected_booking_version integer)
returns public.booking_requests language plpgsql security definer set search_path = '' as $$
declare b public.booking_requests%rowtype;
begin
  if expected_booking_version is null or expected_booking_version < 1 then
    raise exception using errcode='22023',message='A positive expected version is required.';
  end if;
  select * into b from public.booking_requests where id=target_booking_request_id for update;
  if not found then raise exception using errcode='P0002',message='Booking was not found.'; end if;
  if b.status='expired' then return b; end if;
  if b.version <> expected_booking_version then raise exception using errcode='40001',message='Booking version is stale.'; end if;
  perform private.expire_booking_offers(b.id);
  select * into b from public.booking_requests where id=b.id;
  return b;
end;
$$;

create function public.driver_decline_match_offer(target_offer_id uuid, expected_offer_version integer, idempotency_key text)
returns public.driver_match_offers language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid(); o public.driver_match_offers%rowtype; claimed jsonb;
begin
  perform private.lock_matching_driver(caller);
  caller := private.require_approved_driver();
  if expected_offer_version is null or expected_offer_version < 1 then
    raise exception using errcode='22023',message='A positive expected version is required.';
  end if;
  select * into o from public.driver_match_offers where id=target_offer_id and driver_id=caller;
  if not found then raise exception using errcode='P0002',message='Matching offer was not found for this Driver.'; end if;
  perform 1 from public.booking_requests where id=o.booking_request_id for update;
  perform 1 from public.driver_match_offers where booking_request_id=o.booking_request_id order by id for update;
  select * into o from public.driver_match_offers where id=target_offer_id;
  claimed := private.claim_command_idempotency_key(caller,'trip',idempotency_key,
    encode(extensions.digest(convert_to(concat_ws('|','decline',target_offer_id,expected_offer_version),'UTF8'),'sha256'),'hex'),
    jsonb_build_object('offer_id',o.id,'status','declined'));
  if claimed ? 'error' then raise exception using errcode='23505',message='Offer response retry conflicts.'; end if;
  if o.status in ('declined','expired') then
    update public.command_idempotency_keys set canonical_result=jsonb_build_object('offer_id',o.id,'status',o.status)
      where actor_user_id=caller and command_scope='trip' and command_idempotency_keys.idempotency_key=btrim(driver_decline_match_offer.idempotency_key);
    return o;
  end if;
  if o.version <> expected_offer_version then raise exception using errcode='40001',message='Matching offer version is stale.'; end if;
  if o.status <> 'offered' then raise exception using errcode='55000',message='Offer can no longer be declined.'; end if;
  perform private.expire_booking_offers(o.booking_request_id);
  select * into o from public.driver_match_offers where id=target_offer_id;
  if o.status='expired' then
    update public.command_idempotency_keys set canonical_result=jsonb_build_object('offer_id',o.id,'status',o.status)
      where actor_user_id=caller and command_scope='trip' and command_idempotency_keys.idempotency_key=btrim(driver_decline_match_offer.idempotency_key);
    return o;
  end if;
  update public.driver_match_offers set status='declined',responded_at=clock_timestamp() where id=o.id returning * into o;
  return o;
end;
$$;

-- Keep all Phase 6 Trip/payment compatibility code intact. Only accepted paths
-- get a booking-first lock/revalidation prelude; non-accept transitions delegate.
alter function public.driver_transition_trip(uuid,public.trip_status,integer,text)
  rename to p7_a04_original_driver_transition_trip;
alter function public.p7_a04_original_driver_transition_trip(uuid,public.trip_status,integer,text) set schema private;
create function public.driver_transition_trip(target_id uuid, requested_status public.trip_status, expected_version integer, idempotency_key text)
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

revoke all on function private.lock_matching_driver(uuid), private.expire_booking_offers(uuid),
  private.audit_match_offer_transition(), private.p7_a04_original_driver_transition_trip(uuid,public.trip_status,integer,text)
  from public,anon,authenticated,service_role;
revoke all on function public.driver_decline_match_offer(uuid,integer,text),
  public.backend_expire_booking_match_offers(uuid,integer),
  public.driver_transition_trip(uuid,public.trip_status,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.driver_decline_match_offer(uuid,integer,text),
  public.driver_transition_trip(uuid,public.trip_status,integer,text) to authenticated;
grant execute on function public.backend_expire_booking_match_offers(uuid,integer) to service_role;

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
  perform private.lock_matching_driver(target_driver_id);
  select * into booking from public.booking_requests where id = target_booking_request_id for update;
  select * into availability from public.driver_availability where driver_id = target_driver_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Driver availability was not found.'; end if;
  if availability.version <> expected_availability_version then raise exception using errcode = '40001', message = 'Availability version is stale.'; end if;
  if availability.state = 'reserved' and availability.reserved_booking_request_id = target_booking_request_id
    and availability.vehicle_id = target_vehicle_id then
    return availability;
  end if;
  if booking.id is null or booking.status <> 'searching' then raise exception using errcode = '55000', message = 'Booking is not eligible for reservation.'; end if;
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
  perform 1 from public.booking_requests where id=target_booking_request_id for update;
  perform 1 from public.driver_match_offers where booking_request_id=target_booking_request_id order by id for update;
  select * into availability from public.driver_availability where driver_id = target_driver_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Driver availability was not found.'; end if;
  if availability.version <> expected_availability_version then raise exception using errcode = '40001', message = 'Availability version is stale.'; end if;
  update public.driver_match_offers set status='cancelled',responded_at=clock_timestamp()
    where booking_request_id=target_booking_request_id and driver_id=target_driver_id and status='offered';
  perform private.release_matching_driver_reservation(target_driver_id, target_booking_request_id);
  select * into availability from public.driver_availability where driver_id = target_driver_id;
  return availability;
end;
$$;


-- Non-key eligibility changes must not block audit/location FK key-share reads
-- while waiting for a reservation held by a winning competing Driver.
create or replace function public.admin_reject_driver(target_user_id uuid, reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid; target_user public.users%rowtype; target_profile public.driver_profiles%rowtype;
begin
  caller_id := private.require_nonblocked_admin();
  if char_length(btrim(coalesce(reason, ''))) not between 1 and 500 then raise exception using errcode = '22023', message = 'A rejection reason is required.'; end if;
  select * into target_user from public.users where id = target_user_id for no key update;
  select * into target_profile from public.driver_profiles where user_id = target_user_id for no key update;
  if not found or target_user.role <> 'driver' then raise exception using errcode = 'P0002', message = 'Target Driver account was not found.'; end if;
  caller_id := private.require_nonblocked_admin();
  perform 1 from public.trips where driver_id = target_user_id and status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed') for update;
  if found then raise exception using errcode = '55000', message = 'A Driver assigned to a nonterminal Trip must be terminated before rejection.'; end if;
  perform private.reconcile_driver_availability(target_user_id);
  perform set_config('ridex.audit_actor_id', caller_id::text, true); perform set_config('ridex.audit_action', 'admin.driver_rejected', true); perform set_config('ridex.audit_reason', btrim(reason), true);
  update public.driver_profiles set approval_status = 'rejected', rejection_reason = btrim(reason) where user_id = target_user_id;
  update public.driver_availability set state = 'offline', vehicle_id = null, reserved_booking_request_id = null, active_trip_id = null, last_heartbeat_at = null where driver_id = target_user_id;
end;
$$;

create or replace function public.admin_set_user_blocked(target_user_id uuid, blocked boolean, audit_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid; target_user public.users%rowtype; target_profile public.driver_profiles%rowtype;
begin
  caller_id := private.require_nonblocked_admin();
  if char_length(btrim(coalesce(audit_reason, ''))) not between 1 and 500 then raise exception using errcode = '22023', message = 'A nonblank audit reason is required.'; end if;
  select * into target_user from public.users where id = target_user_id for no key update;
  if not found then raise exception using errcode = 'P0002', message = 'Target account was not found.'; end if;
  if target_user.role = 'driver' then select * into target_profile from public.driver_profiles where user_id = target_user_id for no key update; end if;
  caller_id := private.require_nonblocked_admin();
  if blocked and target_user.role = 'driver' then
    perform 1 from public.trips where driver_id = target_user_id and status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed') for update;
    if found then raise exception using errcode = '55000', message = 'A Driver assigned to a nonterminal Trip must be terminated before blocking.'; end if;
    perform private.reconcile_driver_availability(target_user_id);
    update public.driver_availability set state = 'offline', vehicle_id = null, reserved_booking_request_id = null, active_trip_id = null, last_heartbeat_at = null where driver_id = target_user_id;
  end if;
  perform set_config('ridex.audit_actor_id', caller_id::text, true); perform set_config('ridex.audit_action', 'admin.user_blocked_state_set', true); perform set_config('ridex.audit_reason', btrim(audit_reason), true);
  update public.users set is_blocked = blocked where id = target_user_id;
end;
$$;

commit;
