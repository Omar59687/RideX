begin;
-- Trusted command creates/reuses an attempt only. It never dispatches or completes it.
-- The invoking service MUST derive actor_rider_id from a verified session; this
-- service-only RPC cannot independently authenticate that end-user assertion.
-- PENDING/UNKNOWN never proves authorization, capture or receipt issuance.
create function public.backend_prepare_card_command(
  actor_rider_id uuid, target_trip_id uuid, target_payment_id uuid,
  expected_trip_version integer, expected_payment_version integer,
  operation text, operation_key text, provider text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  t public.trips%rowtype;
  p public.payments%rowtype;
  a public.payment_attempts%rowtype;
  attempt_type public.payment_attempt_type;
  amount integer;
  reservation_state text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501', message='Backend access required.';
  end if;
  if actor_rider_id is null or target_trip_id is null or target_payment_id is null
    or expected_trip_version is null or expected_trip_version < 1
    or expected_payment_version is null or expected_payment_version < 1
    or operation not in ('authorize','capture') or operation is null
    or operation_key is null or operation_key !~ '^[A-Za-z0-9:_-]{8,128}$'
    or (provider is not null and (provider <> btrim(provider) or length(provider) not between 1 and 64)) then
    raise exception using errcode='22023', message='Invalid command.';
  end if;
  perform 1 from public.users where id=actor_rider_id and role='rider' and not is_blocked for share;
  if not found then raise exception using errcode='42501', message='Command actor unavailable.'; end if;
  select * into t from public.trips where id=target_trip_id for update;
  select * into p from public.payments where id=target_payment_id for update;
  if t.id is null or p.id is null or t.rider_id is distinct from actor_rider_id
    or p.rider_id is distinct from actor_rider_id or p.trip_id is distinct from t.id
    or p.booking_request_id is distinct from t.booking_request_id
    or p.fare_quote_id is distinct from t.fare_quote_id
    or t.driver_id is null or t.vehicle_id is null
    or t.payment_method <> 'card' or p.method <> 'card' or t.currency <> 'JOD' or p.currency <> 'JOD'
    or not exists (select 1 from public.driver_match_offers o
      where o.booking_request_id=t.booking_request_id and o.status='accepted'
        and o.driver_id=t.driver_id and o.vehicle_id=t.vehicle_id and o.fare_quote_id=t.fare_quote_id) then
    raise exception using errcode='42501', message='Canonical command context unavailable.';
  end if;
  if t.version <> expected_trip_version or p.version <> expected_payment_version then
    raise exception using errcode='40001', message='Canonical command version changed.';
  end if;
  if not private.p8_card_matching_gate_locked() then
    raise exception using errcode='55000', message='Card commands disabled.';
  end if;
  if operation='authorize' then
    attempt_type := 'initialAuthorization'; amount := p.authorized_amount_fils;
    if t.status <> 'accepted' or p.card_status <> 'cardPaymentPending'
      or t.original_fare_fils <> amount or t.current_fare_fils <> p.final_amount_fils
      or p.final_amount_fils <> amount then
      raise exception using errcode='55000', message='Authorization unavailable.';
    end if;
  else
    attempt_type := 'capture'; amount := p.final_amount_fils;
    if t.status <> 'completed' or p.card_status <> 'cardPaymentAuthorized'
      or not private.has_current_verified_card_authorization(p.id)
      or t.current_fare_fils <> amount then
      raise exception using errcode='55000', message='Capture unavailable.';
    end if;
  end if;
  a := public.backend_record_payment_attempt(p.id, attempt_type, amount, operation_key, provider);
  select state into reservation_state from private.stripe_test_dispatch_reservations where attempt_id=a.id;
  return jsonb_build_object('trip_id',t.id,'payment_id',p.id,'attempt_id',a.id,
    'trip_version',t.version,'payment_version',p.version,
    'outcome',case when reservation_state is not null or a.status <> 'pending' then 'UNKNOWN' else 'PENDING' end);
end;
$$;
revoke all on function public.backend_prepare_card_command(uuid,uuid,uuid,integer,integer,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.backend_prepare_card_command(uuid,uuid,uuid,integer,integer,text,text,text) to service_role;
commit;
