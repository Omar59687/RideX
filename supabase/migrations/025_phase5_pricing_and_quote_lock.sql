begin;

-- Phase 5 requires one active, versioned pricing configuration per supported
-- vehicle type. Preserve any owner-managed active configuration; only bootstrap
-- the approved Graduation MVP values when a vehicle type has none.
do $$
declare
  requested_vehicle_type public.vehicle_type_code;
  next_version integer;
begin
  foreach requested_vehicle_type in array array[
    'economy'::public.vehicle_type_code,
    'comfort'::public.vehicle_type_code,
    'xl'::public.vehicle_type_code
  ]
  loop
    perform pg_advisory_xact_lock(
      hashtext('ridex.pricing.' || requested_vehicle_type::text)
    );

    if not exists (
      select 1
      from public.pricing_configurations
      where vehicle_type_code = requested_vehicle_type
        and is_active
    ) then
      select coalesce(max(pricing_version), 0) + 1
      into next_version
      from public.pricing_configurations
      where vehicle_type_code = requested_vehicle_type;

      insert into public.pricing_configurations (
        vehicle_type_code,
        pricing_version,
        base_fare_fils,
        per_kilometer_fils,
        per_minute_fils,
        per_stop_fils,
        minimum_fare_fils,
        rounding_increment_fils,
        is_active
      ) values (
        requested_vehicle_type,
        next_version,
        500,
        300,
        50,
        200,
        1000,
        50,
        true
      );
    end if;
  end loop;
end;
$$;

create or replace function public.rider_lock_fare_quote(
  target_booking_request_id uuid,
  target_fare_quote_id uuid,
  expected_booking_version integer,
  expected_quote_version integer
)
returns public.fare_quotes
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_id uuid;
  locked_quote public.fare_quotes%rowtype;
begin
  caller_id := private.require_nonblocked_rider();

  if not exists (
    select 1
    from public.booking_requests as bookings
    join public.fare_quotes as quotes
      on quotes.booking_request_id = bookings.id
    where bookings.id = target_booking_request_id
      and bookings.rider_id = caller_id
      and quotes.id = target_fare_quote_id
      and quotes.rider_id = caller_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'FareQuote was not found for this Rider booking.';
  end if;

  select *
  into locked_quote
  from public.backend_lock_fare_quote(
    target_fare_quote_id,
    expected_booking_version,
    expected_quote_version
  );

  return locked_quote;
end;
$function$;

revoke all on function public.rider_lock_fare_quote(uuid, uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.rider_lock_fare_quote(uuid, uuid, integer, integer)
  to authenticated;

commit;
