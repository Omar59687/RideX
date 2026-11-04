begin;

-- Read-only matching discovery. Returned candidates are observations, never
-- reservations: offer/accept commands must revalidate all mutable authority.
create function public.backend_find_nearby_driver_candidates(
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
  select a.driver_id, v.id, a.version, v.version, latest.sequence, distance.meters
  from public.driver_availability a
  join public.users u on u.id = a.driver_id and u.role = 'driver' and not u.is_blocked
  join public.driver_profiles p on p.user_id = u.id and p.approval_status = 'approved'
  join public.vehicles v on v.id = a.vehicle_id and v.driver_id = a.driver_id
    and v.is_active and v.vehicle_type_code = booking.vehicle_type_code
  -- Select latest sequence BEFORE quality filters: never resurrect an older fix.
  cross join lateral (
    select l.* from public.driver_locations l where l.driver_id = a.driver_id
    order by l.sequence desc limit 1
  ) latest
  cross join lateral (
    -- Mean-earth spherical haversine (metres); clamping handles roundoff at
    -- antipodes and works across the antimeridian without a PostGIS dependency.
    select 2.0 * 6371008.8 * asin(sqrt(least(1.0::double precision,
      greatest(0.0::double precision,
        power(sin(radians(latest.latitude - pickup_latitude) / 2.0), 2)
        + cos(radians(pickup_latitude)) * cos(radians(latest.latitude))
          * power(sin(radians(latest.longitude - pickup_longitude) / 2.0), 2)
      )))) as meters
  ) distance
  where a.state = 'available' and a.reserved_booking_request_id is null and a.active_trip_id is null
    and latest.trip_id is null
    and latest.recorded_at >= observed_at - interval '60 seconds'
    and latest.recorded_at <= observed_at + interval '5 seconds'
    and latest.received_at >= observed_at - interval '60 seconds'
    and latest.received_at <= observed_at
    and latest.recorded_at <= latest.received_at + interval '5 seconds'
    and latest.accuracy_meters <= 50
    and not exists (select 1 from public.trips t where t.driver_id = a.driver_id
      and t.status not in ('completed', 'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed'))
    -- The existing booking/Driver unique constraint permits only one offer ever.
    and not exists (select 1 from public.driver_match_offers o
      where o.booking_request_id = booking.id and o.driver_id = a.driver_id)
    -- Inclusive boundary, with one micrometre solely for float roundoff.
    and distance.meters <= requested_radius_meters::double precision + 0.000001
  order by distance.meters, a.driver_id
  limit requested_limit;
end;
$$;

revoke all on function public.backend_find_nearby_driver_candidates(uuid,integer,integer,integer)
  from public, anon, authenticated, service_role;
grant execute on function public.backend_find_nearby_driver_candidates(uuid,integer,integer,integer)
  to service_role;

commit;
