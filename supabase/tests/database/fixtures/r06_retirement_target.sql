\ir r06_card_context.sql

insert into public.booking_requests (
  id, rider_id, status, pickup, destination, vehicle_type_code, payment_method
)
select
  '33333333-3333-4333-8333-333333333338', rider_id, 'matched', pickup,
  destination, vehicle_type_code, 'card'
from public.booking_requests
where id = '22200000-0000-0000-0000-000000000002';

insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination, ordered_stops,
  route_distance_meters, route_duration_seconds, route_geometry_reference,
  vehicle_type_code, breakdown, currency, fixed_fare_fils,
  pricing_configuration_id, pricing_version, quote_version, created_at,
  expires_at, locked_at
)
select
  '33333333-3333-4333-8333-333333333339',
  '33333333-3333-4333-8333-333333333338', rider_id, 'locked', pickup,
  destination, ordered_stops, route_distance_meters, route_duration_seconds,
  route_geometry_reference, vehicle_type_code, breakdown, currency,
  fixed_fare_fils, pricing_configuration_id, pricing_version, 1, now(),
  now() + interval '10 minutes', now()
from public.fare_quotes
where id = '22300000-0000-0000-0000-000000000002';

insert into public.trips (
  id, booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id,
  status, payment_method, pickup, destination, route_distance_meters,
  route_duration_seconds, original_fare_fils, current_fare_fils
)
select
  'ceff7eb6-2d1f-4744-9cbc-243d80d550ba',
  '33333333-3333-4333-8333-333333333338',
  '33333333-3333-4333-8333-333333333339', rider_id, driver_id, vehicle_id,
  'accepted', 'card', pickup, destination, route_distance_meters,
  route_duration_seconds, original_fare_fils, current_fare_fils
from public.trips
where id = '22400000-0000-0000-0000-000000000002';

insert into public.payments (
  id, booking_request_id, trip_id, rider_id, method, fare_quote_id,
  authorized_amount_fils, final_amount_fils, currency, card_status
)
select
  '44444444-4444-4444-8444-444444444438', trip.booking_request_id,
  trip.id, trip.rider_id, 'card', trip.fare_quote_id,
  trip.original_fare_fils, trip.current_fare_fils, trip.currency,
  'cardPaymentPending'
from public.trips as trip
where trip.id = 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba';

insert into public.payment_attempts (
  payment_id, type, status, requested_amount_fils, currency, idempotency_key,
  provider_name, authorization_cycle, created_at
)
values (
  '44444444-4444-4444-8444-444444444438', 'initialAuthorization', 'pending',
  2000, 'JOD', 'r06-retirement-original-authorization',
  case
    when pg_catalog.current_setting('ridex.r06_fixture_provider', true) = '__NULL__' then null
    when pg_catalog.current_setting('ridex.r06_fixture_provider', true) is null then 'stripe'
    else pg_catalog.current_setting('ridex.r06_fixture_provider', true)
  end,
  1, now()
);

update public.driver_availability
set state = 'onTrip', vehicle_id = '22100000-0000-0000-0000-000000000001',
  active_trip_id = 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba'
where driver_id = '22000000-0000-0000-0000-000000000002';
