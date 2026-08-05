begin;

create or replace function private.remaining_route_fare_fils(
  pricing public.pricing_configurations,
  route_distance_meters integer,
  route_duration_seconds integer,
  stop_count integer
)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  subtotal bigint;
  result bigint;
begin
  if route_distance_meters < 0 or route_duration_seconds < 0 or stop_count < 0 then
    raise exception using errcode = '22023', message = 'Cash change pricing requires valid remaining route metrics.';
  end if;

  subtotal := pricing.base_fare_fils::bigint
    + (route_distance_meters::bigint * pricing.per_kilometer_fils + 500) / 1000
    + (route_duration_seconds::bigint * pricing.per_minute_fils + 30) / 60
    + stop_count::bigint * pricing.per_stop_fils;
  result := (greatest(subtotal, pricing.minimum_fare_fils::bigint)
    + pricing.rounding_increment_fils / 2) / pricing.rounding_increment_fils
    * pricing.rounding_increment_fils;
  if result > 2147483647 then
    raise exception using errcode = '22003', message = 'Adjusted fare exceeds supported integer fils.';
  end if;
  return result::integer;
end;
$$;

-- The original RPC remains for established callers. New trusted callers supply
-- both remaining-route snapshots so completed route portions are never priced.
create function private.backend_price_trip_change_request_remaining(
  target_request_id uuid,
  expected_request_version integer,
  new_remaining_distance_meters integer,
  new_remaining_duration_seconds integer,
  original_remaining_distance_meters integer,
  original_remaining_duration_seconds integer,
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
  new_remaining_fare integer;
  original_remaining_fare integer;
  adjustment integer;
  created_adjustment public.fare_adjustments%rowtype;
begin
  if expected_request_version is null or expected_request_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
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
  new_remaining_fare := private.remaining_route_fare_fils(
    pricing, new_remaining_distance_meters, new_remaining_duration_seconds, stop_count
  );
  original_remaining_fare := private.remaining_route_fare_fils(
    pricing, original_remaining_distance_meters, original_remaining_duration_seconds, 0
  );
  adjustment := greatest(0, new_remaining_fare - original_remaining_fare);

  update public.trip_change_requests set status = 'awaitingRiderApproval',
    priced_route_distance_meters = new_remaining_distance_meters,
    priced_route_duration_seconds = new_remaining_duration_seconds,
    priced_route_geometry_reference = nullif(btrim(route_geometry_reference), '')
  where id = current_request.id returning * into current_request;
  insert into public.fare_adjustments (
    trip_id, trip_change_request_id, previous_fare_fils, adjusted_fare_fils,
    adjustment_fils, breakdown, pricing_configuration_id, pricing_version
  ) values (
    current_trip.id, current_request.id, current_trip.current_fare_fils,
    current_trip.current_fare_fils + adjustment, adjustment,
    jsonb_build_object(
      'new_remaining_route_fare_fils', new_remaining_fare,
      'original_remaining_route_fare_fils', original_remaining_fare,
      'adjustment_fils', adjustment,
      'new_remaining_distance_meters', new_remaining_distance_meters,
      'original_remaining_distance_meters', original_remaining_distance_meters
    ), pricing.id, pricing.pricing_version
  ) returning * into created_adjustment;
  return created_adjustment;
end;
$$;

create or replace function public.backend_apply_trip_fare_adjustment(
  target_adjustment_id uuid, expected_adjustment_version integer,
  expected_trip_version integer
)
returns public.trips
language plpgsql security definer set search_path = ''
as $$
declare
  current_adjustment public.fare_adjustments%rowtype;
  current_request public.trip_change_requests%rowtype;
  current_trip public.trips%rowtype;
  current_payment public.payments%rowtype;
begin
  if expected_adjustment_version is null or expected_adjustment_version < 1
    or expected_trip_version is null or expected_trip_version < 1 then
    raise exception using errcode = '22023', message = 'Positive expected versions are required.';
  end if;
  select * into current_adjustment from public.fare_adjustments where id = target_adjustment_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Fare adjustment was not found.'; end if;
  select * into current_trip from public.trips where id = current_adjustment.trip_id for update;
  if current_adjustment.status = 'applied' then return current_trip; end if;
  if current_adjustment.version <> expected_adjustment_version then raise exception using errcode = '40001', message = 'Fare adjustment version is stale.'; end if;
  if current_trip.version <> expected_trip_version then raise exception using errcode = '40001', message = 'Trip version is stale.'; end if;
  select * into current_request from public.trip_change_requests where id = current_adjustment.trip_change_request_id for update;
  select * into current_payment from public.payments where trip_id = current_trip.id for update;
  if current_adjustment.status <> 'pending' or current_request.status <> 'approved'
    or current_trip.payment_method <> 'cash' or current_trip.status <> 'inProgress'
    or current_adjustment.previous_fare_fils <> current_trip.current_fare_fils
    or not found or current_payment.method <> 'cash' or current_payment.cash_status <> 'cashSelected' then
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
  update public.payments set final_amount_fils = current_trip.current_fare_fils
  where id = current_payment.id;
  update public.fare_adjustments set status = 'applied', applied_at = now()
  where id = current_adjustment.id;
  update public.trip_change_requests set status = 'applied', resolved_at = now()
  where id = current_request.id;
  return current_trip;
end;
$$;

create or replace function public.backend_record_payment_attempt(
  target_payment_id uuid, attempt_type public.payment_attempt_type,
  amount_fils integer, attempt_key text, provider text default null
)
returns public.payment_attempts
language plpgsql security definer set search_path = ''
as $$
declare
  payment public.payments%rowtype;
  trip public.trips%rowtype;
  result public.payment_attempts%rowtype;
  attempt_count integer;
  normalized_key text := nullif(btrim(attempt_key), '');
  normalized_provider text := nullif(btrim(provider), '');
begin
  if normalized_key is null or amount_fils is null or amount_fils < 0 then
    raise exception using errcode = '22023', message = 'Payment attempt inputs are invalid.';
  end if;
  select * into payment from public.payments where id = target_payment_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  select * into trip from public.trips where id = payment.trip_id for share;
  if not found then raise exception using errcode = '55000', message = 'Payment must have a canonical Trip.'; end if;
  select * into result from public.payment_attempts
  where payment_id = payment.id and idempotency_key = normalized_key;
  if found then
    if result.type = attempt_type and result.requested_amount_fils = amount_fils
      and result.currency = payment.currency and result.provider_name is not distinct from normalized_provider
      and result.refund_id is null then
      return result;
    end if;
    perform private.write_audit_record(null, 'payment.attempt_idempotency_payload_mismatch', payment.rider_id, null,
      jsonb_build_object('payment_id', payment.id, 'attempt_id', result.id),
      jsonb_build_object('operation', attempt_type, 'amount_fils', amount_fils, 'currency', payment.currency));
    raise exception using errcode = '55000', message = 'Payment attempt idempotency key is already associated with different operation data.';
  end if;
  if attempt_type = 'refund' then
    raise exception using errcode = '55000', message = 'Refund attempts require their canonical Refund operation.';
  end if;
  if attempt_type in ('adjustmentAuthorization', 'providerStatusVerification') then
    raise exception using errcode = '55000', message = 'Payment attempt type is not available through this operation.';
  end if;
  if attempt_type in ('initialAuthorization', 'replacementAuthorization') then
    if payment.method <> 'card' then
      raise exception using errcode = '55000', message = 'Only Card payments can be authorized.';
    end if;
    select count(*) into attempt_count from public.payment_attempts
    where payment_id = payment.id and type in ('initialAuthorization', 'replacementAuthorization');
    if attempt_count >= 2 then raise exception using errcode = '55000', message = 'Card authorization permits at most two attempts.'; end if;
    if payment.card_status not in ('cardPaymentPending', 'cardPaymentFailed')
      or amount_fils <> payment.authorized_amount_fils then
      raise exception using errcode = '55000', message = 'Card authorization attempt is incompatible with Payment and Trip state.';
    end if;
  elsif attempt_type = 'capture' then
    if payment.method <> 'card' or trip.status <> 'completed'
      or payment.card_status <> 'cardPaymentAuthorized' or amount_fils <> payment.final_amount_fils then
      raise exception using errcode = '55000', message = 'Capture requires a completed Trip with an authorized Card Payment.';
    end if;
    if exists (select 1 from public.payment_attempts where payment_id = payment.id and type = 'capture') then
      raise exception using errcode = '55000', message = 'Only one initial Capture attempt is permitted.';
    end if;
  elsif attempt_type = 'captureRetry' then
    if payment.method <> 'card' or trip.status <> 'completed'
      or payment.card_status <> 'cardPaymentFailed' or amount_fils <> payment.final_amount_fils
      or not exists (select 1 from public.payment_attempts where payment_id = payment.id and type = 'capture') then
      raise exception using errcode = '55000', message = 'Capture retry requires a failed initial Capture.';
    end if;
    select count(*) into attempt_count from public.payment_attempts
    where payment_id = payment.id and type = 'captureRetry';
    if attempt_count >= 2 then raise exception using errcode = '55000', message = 'Capture permits at most three attempts.'; end if;
  elsif attempt_type = 'voidAuthorization' then
    if payment.method <> 'card' or trip.status not in ('accepted', 'driverArriving', 'driverArrived')
      or payment.card_status <> 'cardPaymentAuthorized' or amount_fils <> payment.authorized_amount_fils then
      raise exception using errcode = '55000', message = 'Authorization void requires a pre-start authorized Card Payment.';
    end if;
  end if;
  insert into public.payment_attempts (
    payment_id, type, requested_amount_fils, currency, idempotency_key, provider_name
  ) values (
    payment.id, attempt_type, amount_fils, payment.currency, normalized_key, normalized_provider
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.backend_complete_payment_attempt(
  target_attempt_id uuid, final_status public.payment_attempt_status,
  provider_reference text default null, failure_code text default null
)
returns public.payment_attempts
language plpgsql security definer set search_path = ''
as $$
declare
  current_attempt public.payment_attempts%rowtype;
  normalized_reference text := nullif(btrim(provider_reference), '');
  normalized_failure text := nullif(btrim(failure_code), '');
begin
  if final_status is null or final_status = 'pending' then
    raise exception using errcode = '22023', message = 'A payment attempt requires a terminal verified status.';
  end if;
  select * into current_attempt from public.payment_attempts where id = target_attempt_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Payment attempt was not found.'; end if;
  if current_attempt.type = 'refund' then raise exception using errcode = '55000', message = 'Refund attempts require their canonical Refund completion operation.'; end if;
  if current_attempt.status <> 'pending' then
    if current_attempt.status = final_status
      and current_attempt.provider_transaction_reference is not distinct from normalized_reference
      and current_attempt.sanitized_failure_code is not distinct from normalized_failure then
      return current_attempt;
    end if;
    raise exception using errcode = '55000', message = 'A terminal Payment attempt cannot be completed with different data.';
  end if;
  if final_status = 'succeeded' and normalized_reference is null then
    raise exception using errcode = '22023', message = 'A successful Payment attempt requires a provider reference.';
  end if;
  perform set_config('ridex.complete_payment_attempt', 'on', true);
  update public.payment_attempts set status = final_status,
    provider_transaction_reference = normalized_reference,
    sanitized_failure_code = normalized_failure, completed_at = now(), verified_at = now()
  where id = current_attempt.id returning * into current_attempt;
  return current_attempt;
end;
$$;

revoke all on function private.remaining_route_fare_fils(public.pricing_configurations, integer, integer, integer) from public, anon, authenticated, service_role;
revoke all on function private.backend_price_trip_change_request_remaining(uuid, integer, integer, integer, integer, integer, text) from public, anon, authenticated, service_role;
grant execute on function private.backend_price_trip_change_request_remaining(uuid, integer, integer, integer, integer, integer, text) to service_role;

commit;
