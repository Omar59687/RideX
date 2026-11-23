begin;
-- Quarantine is evidence storage only; no payment, attempt or Trip transition.
-- A verified signature MUST be checked by a trusted server before invoking this
-- service-only function. This function cannot independently verify signatures.
create table private.p8_test_webhook_quarantine (
  provider_event_id text primary key,
  event_type text not null,
  body_sha256 text not null,
  provider_reference text not null,
  trip_id uuid not null references public.trips(id),
  payment_id uuid not null references public.payments(id),
  attempt_id uuid not null references public.payment_attempts(id),
  amount_fils integer not null,
  currency text not null,
  recorded_at timestamptz not null default now()
);
alter table private.p8_test_webhook_quarantine enable row level security;
revoke all on private.p8_test_webhook_quarantine from public,anon,authenticated,service_role;
create function public.backend_quarantine_test_webhook(
  event_id text, event_kind text, body_hash text, provider_ref text,
  target_trip_id uuid, target_payment_id uuid, target_attempt_id uuid,
  amount_fils integer, currency text
) returns text language plpgsql security definer set search_path='' as $$
declare t public.trips%rowtype; p public.payments%rowtype; a public.payment_attempts%rowtype;
  evidence private.stripe_test_dispatch_reservations%rowtype;
  stored private.p8_test_webhook_quarantine%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception using errcode='42501',message='Backend access required.'; end if;
  if event_id is null or event_id !~ '^evt_[A-Za-z0-9]{1,252}$'
    or event_kind is null or event_kind !~ '^[a-z0-9_.]{1,128}$'
    or body_hash is null or body_hash !~ '^[0-9a-f]{64}$'
    or provider_ref is null or provider_ref !~ '^pi_[A-Za-z0-9]{1,253}$'
    or target_trip_id is null or target_payment_id is null or target_attempt_id is null
    or amount_fils is null or amount_fils < 0 or currency is distinct from 'JOD' then
    raise exception using errcode='22023',message='Invalid evidence.';
  end if;
  -- Follow financial lock order and do not treat reservation as a financial outcome.
  select * into t from public.trips where id=target_trip_id for update;
  select * into p from public.payments where id=target_payment_id for update;
  select * into a from public.payment_attempts where id=target_attempt_id for update;
  select * into evidence from private.stripe_test_dispatch_reservations where attempt_id=target_attempt_id for update;
  if t.id is null or p.id is null or a.id is null or evidence.attempt_id is null
    or p.trip_id is distinct from t.id or a.payment_id is distinct from p.id
    or p.booking_request_id is distinct from t.booking_request_id or p.rider_id is distinct from t.rider_id
    or p.method <> 'card' or t.payment_method <> 'card' or a.provider_name is distinct from 'stripe'
    or a.id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416'::uuid
    or evidence.state <> 'prepared' or evidence.provider_reference is distinct from provider_ref
    or evidence.payment_id is distinct from p.id or evidence.trip_id is distinct from t.id
    or a.requested_amount_fils <> amount_fils or a.currency <> 'JOD' or p.currency <> 'JOD' or t.currency <> 'JOD' then
    raise exception using errcode='42501',message='Canonical evidence unavailable.';
  end if;
  insert into private.p8_test_webhook_quarantine(provider_event_id,event_type,body_sha256,provider_reference,trip_id,payment_id,attempt_id,amount_fils,currency)
    values(event_id,event_kind,body_hash,provider_ref,t.id,p.id,a.id,amount_fils,currency)
    on conflict (provider_event_id) do nothing;
  if found then return 'quarantined'; end if;
  select * into stored from private.p8_test_webhook_quarantine where provider_event_id=event_id;
  if stored.event_type is distinct from event_kind or stored.body_sha256 is distinct from body_hash
    or stored.provider_reference is distinct from provider_ref or stored.trip_id is distinct from t.id
    or stored.payment_id is distinct from p.id or stored.attempt_id is distinct from a.id
    or stored.amount_fils is distinct from amount_fils or stored.currency is distinct from currency then
    raise exception using errcode='23505',message='Event identity conflicts.';
  end if;
  return 'duplicate';
end;
$$;
revoke all on function public.backend_quarantine_test_webhook(text,text,text,text,uuid,uuid,uuid,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.backend_quarantine_test_webhook(text,text,text,text,uuid,uuid,uuid,integer,text) to service_role;
commit;
