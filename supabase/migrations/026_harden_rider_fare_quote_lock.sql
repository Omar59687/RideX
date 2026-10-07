begin;

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
  target_quote public.fare_quotes%rowtype;
  current_booking public.booking_requests%rowtype;
begin
  caller_id := private.require_nonblocked_rider();

  if expected_booking_version is null or expected_booking_version < 1
    or expected_quote_version is null or expected_quote_version < 1 then
    raise exception using
      errcode = '22023',
      message = 'Positive expected versions are required.';
  end if;

  select *
  into current_booking
  from public.booking_requests
  where id = target_booking_request_id
    and rider_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'FareQuote was not found for this Rider booking.';
  end if;

  select *
  into target_quote
  from public.fare_quotes
  where id = target_fare_quote_id
    and booking_request_id = target_booking_request_id
    and rider_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'FareQuote was not found for this Rider booking.';
  end if;

  if target_quote.quote_version <> expected_quote_version then
    raise exception using
      errcode = '40001',
      message = 'FareQuote version is stale.';
  end if;

  if target_quote.status = 'locked' then
    if current_booking.fare_quote_id = target_quote.id
      and current_booking.version - 1 = expected_booking_version then
      return target_quote;
    end if;

    raise exception using
      errcode = '40001',
      message = 'Booking version is stale.';
  end if;

  if current_booking.version <> expected_booking_version then
    raise exception using
      errcode = '40001',
      message = 'Booking version is stale.';
  end if;

  select *
  into target_quote
  from public.backend_lock_fare_quote(
    target_fare_quote_id,
    expected_booking_version,
    expected_quote_version
  );

  return target_quote;
end;
$function$;

revoke all on function public.rider_lock_fare_quote(uuid, uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.rider_lock_fare_quote(uuid, uuid, integer, integer)
  to authenticated;

commit;
