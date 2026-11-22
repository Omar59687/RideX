begin;
-- Locked context read only: no event consumption, provider dispatch, attempt
-- completion, Payment transition, receipt or Driver availability mutation.
create function public.backend_inspect_quarantined_test_event(target_event_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q private.p8_test_webhook_quarantine%rowtype;
  t public.trips%rowtype; p public.payments%rowtype; a public.payment_attempts%rowtype;
  r private.stripe_test_dispatch_reservations%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception using errcode='42501',message='Backend access required.'; end if;
  if target_event_id is null or target_event_id !~ '^evt_[A-Za-z0-9]{1,252}$' then
    raise exception using errcode='22023',message='Invalid event identity.';
  end if;
  select * into q from private.p8_test_webhook_quarantine where provider_event_id=target_event_id;
  if not found then raise exception using errcode='P0002',message='Quarantined event unavailable.'; end if;
  -- Follow the existing financial lock order; then lock/re-read the event.
  select * into t from public.trips where id=q.trip_id for update;
  select * into p from public.payments where id=q.payment_id for update;
  select * into a from public.payment_attempts where id=q.attempt_id for update;
  select * into r from private.stripe_test_dispatch_reservations where attempt_id=q.attempt_id for update;
  select * into q from private.p8_test_webhook_quarantine where provider_event_id=target_event_id for update;
  if q.provider_event_id is null or t.id is null or p.id is null or a.id is null or r.attempt_id is null
    or q.trip_id is distinct from t.id or q.payment_id is distinct from p.id or q.attempt_id is distinct from a.id
    or p.trip_id is distinct from t.id or a.payment_id is distinct from p.id
    or p.booking_request_id is distinct from t.booking_request_id or p.rider_id is distinct from t.rider_id
    or p.method <> 'card' or t.payment_method <> 'card' or a.provider_name is distinct from 'stripe'
    or a.id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416'::uuid
    or r.state <> 'prepared' or r.provider_reference is distinct from q.provider_reference
    or r.trip_id is distinct from t.id or r.payment_id is distinct from p.id or r.rider_id is distinct from p.rider_id
    or r.operation_key is distinct from a.idempotency_key
    or a.requested_amount_fils is distinct from q.amount_fils or q.currency <> 'JOD'
    or a.currency <> 'JOD' or p.currency <> 'JOD' or t.currency <> 'JOD' then
    raise exception using errcode='42501',message='Canonical context unavailable.';
  end if;
  return jsonb_build_object('outcome','UNKNOWN','event_id',q.provider_event_id,'event_type',q.event_type,
    'body_sha256',q.body_sha256,'trip_id',t.id,'trip_version',t.version,'trip_status',t.status,
    'payment_id',p.id,'payment_version',p.version,'card_status',p.card_status,
    'attempt_id',a.id,'attempt_status',a.status,'attempt_type',a.type,'attempt_key',a.idempotency_key,
    'reservation_state',r.state,'provider_reference',r.provider_reference,'amount_fils',a.requested_amount_fils,'currency',a.currency);
end;
$$;
revoke all on function public.backend_inspect_quarantined_test_event(text) from public,anon,authenticated,service_role;
grant execute on function public.backend_inspect_quarantined_test_event(text) to service_role;
commit;
