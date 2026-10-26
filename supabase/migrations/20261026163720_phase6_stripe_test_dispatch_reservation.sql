begin;

-- Separate preparation evidence: never advances Payment/Attempt state or proves authorization.
create table private.stripe_test_dispatch_reservations (
  attempt_id uuid primary key references public.payment_attempts(id) on delete restrict,
  payment_id uuid not null unique references public.payments(id) on delete restrict,
  trip_id uuid not null references public.trips(id) on delete restrict,
  rider_id uuid not null references public.users(id) on delete restrict,
  operation_key text not null unique check (operation_key ~ '^[A-Za-z0-9:_-]{8,128}$'),
  claim_token uuid not null unique default gen_random_uuid(),
  context jsonb not null,
  state text not null default 'reserved' check (state in ('reserved','unknown','prepared')),
  provider_reference text unique check (provider_reference ~ '^pi_[A-Za-z0-9]+$'),
  created_at timestamptz not null default now(),
  check ((state = 'prepared') = (provider_reference is not null))
);
alter table private.stripe_test_dispatch_reservations enable row level security;
revoke all on private.stripe_test_dispatch_reservations from public, anon, authenticated, service_role;

create function public.backend_claim_stripe_test_preparation(
  actor_rider_id uuid, target_trip_id uuid, target_payment_id uuid,
  target_attempt_id uuid, expected_trip_version integer,
  expected_payment_version integer, operation_key text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t public.trips%rowtype;
  p public.payments%rowtype;
  a public.payment_attempts%rowtype;
  r private.stripe_test_dispatch_reservations%rowtype;
  snapshot jsonb;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501', message='Backend access required.';
  end if;
  -- Follow existing backend operation lock order: Trip, Payment, Attempt.
  select * into t from public.trips where id=target_trip_id for update;
  select * into p from public.payments where id=target_payment_id for update;
  select * into a from public.payment_attempts where id=target_attempt_id for update;
  perform 1 from public.users where id=actor_rider_id and role='rider' and not is_blocked for share;
  if not found or t.id is null or p.id is null or a.id is null
    or t.rider_id is distinct from actor_rider_id or p.rider_id is distinct from actor_rider_id
    or p.trip_id is distinct from t.id or a.payment_id is distinct from p.id
    or t.status <> 'accepted' or t.payment_method <> 'card' or t.driver_id is null
    or p.method <> 'card' or p.card_status <> 'cardPaymentPending'
    or a.type <> 'initialAuthorization' or a.status <> 'pending'
    or a.authorization_cycle is distinct from 1 or a.provider_name is distinct from 'stripe'
    or a.created_at > now() or a.created_at <= now() - interval '2 minutes'
    or a.provider_transaction_reference is not null
    or a.idempotency_key is distinct from operation_key
    or operation_key is null or operation_key !~ '^[A-Za-z0-9:_-]{8,128}$'
    or p.authorized_amount_fils <= 0 or p.authorized_amount_fils > 99999999
    or p.authorized_amount_fils % 10 <> 0
    or p.final_amount_fils <> p.authorized_amount_fils
    or t.original_fare_fils <> p.authorized_amount_fils
    or t.current_fare_fils <> p.final_amount_fils
    or a.requested_amount_fils <> p.authorized_amount_fils
    or t.currency <> 'JOD' or p.currency <> 'JOD' or a.currency <> 'JOD'
  then raise exception using errcode='42501', message='Canonical preparation context unavailable.';
  end if;
  if expected_trip_version is null or expected_payment_version is null
    or t.version <> expected_trip_version or p.version <> expected_payment_version then
    raise exception using errcode='40001', message='Canonical preparation version changed.';
  end if;
  snapshot := jsonb_build_object(
    'paymentId',p.id,'attemptId',a.id,'riderId',p.rider_id,'paymentVersion',p.version,
    'tripId',t.id,'tripVersion',t.version,'driverId',t.driver_id,
    'tripStatus',t.status,'method',p.method,'paymentStatus',p.card_status,
    'amountFils',p.authorized_amount_fils,'currency',p.currency,'idempotencyKey',a.idempotency_key);
  select * into r from private.stripe_test_dispatch_reservations where attempt_id=a.id;
  if found then
    if r.context <> snapshot then
      raise exception using errcode='23505', message='Preparation evidence conflicts.';
    end if;
    -- Never return the dispatch token on a repeat, reclaim a lease, or authorize replay.
    return jsonb_build_object('disposition','existing','state',r.state,
      'context',r.context,'reference',r.provider_reference);
  end if;
  insert into private.stripe_test_dispatch_reservations
    (attempt_id,payment_id,trip_id,rider_id,operation_key,context)
    values(a.id,p.id,t.id,p.rider_id,a.idempotency_key,snapshot) returning * into r;
  return jsonb_build_object('disposition','claimed','state',r.state,
    'context',r.context,'claimToken',r.claim_token,'reference',null);
end;
$$;

create function public.backend_record_stripe_test_preparation(
  target_attempt_id uuid, original_claim_token uuid, prepared_reference text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare r private.stripe_test_dispatch_reservations%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501', message='Backend access required.';
  end if;
  select * into r from private.stripe_test_dispatch_reservations where attempt_id=target_attempt_id for update;
  if not found or r.claim_token is distinct from original_claim_token then
    raise exception using errcode='42501', message='Original dispatch claim required.';
  end if;
  if prepared_reference is not null and prepared_reference !~ '^pi_[A-Za-z0-9]+$' then
    raise exception using errcode='22023', message='Invalid preparation evidence.';
  end if;
  if r.state='prepared' then
    if prepared_reference is not null and r.provider_reference <> prepared_reference then
      raise exception using errcode='23505', message='Preparation evidence conflicts.';
    end if;
    return; -- unknown/lost acknowledgements cannot downgrade stronger evidence.
  end if;
  update private.stripe_test_dispatch_reservations
    set state=case when prepared_reference is null then 'unknown' else 'prepared' end,
        provider_reference=prepared_reference
    where attempt_id=target_attempt_id;
end;
$$;

create function public.backend_read_stripe_test_preparation(
  target_attempt_id uuid, actor_rider_id uuid
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r private.stripe_test_dispatch_reservations%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501', message='Backend access required.';
  end if;
  perform 1 from public.users where id=actor_rider_id and role='rider' and not is_blocked;
  if not found then raise exception using errcode='42501', message='Rider access unavailable.'; end if;
  select s.* into r from private.stripe_test_dispatch_reservations s
    join public.payments p on p.id=s.payment_id and p.rider_id=s.rider_id and p.trip_id=s.trip_id
    join public.trips t on t.id=s.trip_id and t.rider_id=s.rider_id
    where s.attempt_id=target_attempt_id and s.rider_id=actor_rider_id;
  if not found then return null; end if;
  return jsonb_build_object('disposition','existing','state',r.state,
    'context',r.context,'reference',r.provider_reference);
end;
$$;
revoke all on function public.backend_claim_stripe_test_preparation(uuid,uuid,uuid,uuid,integer,integer,text),
  public.backend_record_stripe_test_preparation(uuid,uuid,text),
  public.backend_read_stripe_test_preparation(uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.backend_claim_stripe_test_preparation(uuid,uuid,uuid,uuid,integer,integer,text),
  public.backend_record_stripe_test_preparation(uuid,uuid,text),
  public.backend_read_stripe_test_preparation(uuid,uuid) to service_role;

commit;
