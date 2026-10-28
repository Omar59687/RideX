begin;

-- No approval/evidence rows are installed by this migration. An offline,
-- reviewed database owner must independently establish no dispatch AND drain
-- every old claim holder. A missing reference is never either proof.
create table private.r06_x2_owner_approvals (
  id uuid primary key,
  fixture_id uuid not null check (fixture_id = '8168236a-6a53-4a08-8dfa-f79e68fe8925'),
  rider_id uuid not null check (rider_id = 'd3c3dc11-a840-4712-a6a4-599b4ae27329'),
  trip_id uuid not null check (trip_id = 'dda56345-4123-4a0c-9771-5287899d2344'),
  payment_id uuid not null check (payment_id = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'),
  attempt_id uuid not null check (attempt_id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416'),
  fence_epoch text not null check (fence_epoch = 'r06-x2-permanent-dispatch-deny-v1'),
  quiescence_epoch uuid not null unique,
  owner_review_reference text not null check (length(btrim(owner_review_reference)) between 16 and 256),
  no_dispatch_provenance text not null check (length(btrim(no_dispatch_provenance)) between 16 and 256),
  no_dispatch_digest text not null check (no_dispatch_digest ~ '^[0-9a-f]{64}$'),
  quiescence_provenance text not null check (length(btrim(quiescence_provenance)) between 16 and 256),
  quiescence_digest text not null check (quiescence_digest ~ '^[0-9a-f]{64}$'),
  deployment_digest text not null check (deployment_digest ~ '^[0-9a-f]{64}$'),
  no_dispatch_assertion text not null check (no_dispatch_assertion = 'independently_verified_never_dispatched'),
  quiescence_assertion text not null check (quiescence_assertion = 'all_original_claim_holders_revoked_and_drained'),
  quiescent_since timestamptz not null,
  reviewed_at timestamptz not null,
  expires_at timestamptz not null,
  snapshot_digest text not null check (snapshot_digest ~ '^[0-9a-f]{64}$'),
  check (no_dispatch_provenance <> quiescence_provenance),
  check (no_dispatch_digest <> quiescence_digest),
  check (quiescent_since >= '2026-10-28T12:48:16.986561Z'::timestamptz),
  check (reviewed_at >= quiescent_since and expires_at > reviewed_at),
  check (expires_at <= reviewed_at + interval '1 hour')
);

-- The committed row is the durable revocation. A separate protected marker is
-- present only while the wrapper enters the canonical calls, never afterwards.
create table private.r06_x2_recoveries (
  trip_id uuid primary key check (trip_id = 'dda56345-4123-4a0c-9771-5287899d2344'),
  approval_id uuid not null unique references private.r06_x2_owner_approvals(id),
  request_id uuid not null unique,
  actor_id uuid not null,
  transaction_id bigint not null,
  recovered_at timestamptz not null default clock_timestamp(),
  result jsonb not null
);
create table private.r06_x2_late_observations (
  id bigint generated always as identity primary key,
  trip_id uuid not null references private.r06_x2_recoveries(trip_id),
  attempt_id uuid not null check (attempt_id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416'),
  observed_at timestamptz not null default clock_timestamp(),
  provider_reference text check (provider_reference ~ '^pi_[A-Za-z0-9]+$')
);
create table private.r06_x2_authorizations (
  transaction_id bigint primary key,
  trip_id uuid not null check (trip_id = 'dda56345-4123-4a0c-9771-5287899d2344'),
  actor_id uuid not null
);
alter table private.r06_x2_owner_approvals enable row level security;
alter table private.r06_x2_recoveries enable row level security;
alter table private.r06_x2_late_observations enable row level security;
alter table private.r06_x2_authorizations enable row level security;
revoke all on private.r06_x2_owner_approvals, private.r06_x2_recoveries,
  private.r06_x2_late_observations, private.r06_x2_authorizations from public, anon, authenticated, service_role;
revoke all on sequence private.r06_x2_late_observations_id_seq from public, anon, authenticated, service_role;

create function private.r06_x2_immutable()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = '55000', message = 'R06-X2 evidence is immutable.';
end;
$$;
create trigger r06_x2_approval_immutable before update or delete or truncate
  on private.r06_x2_owner_approvals for each statement execute function private.r06_x2_immutable();
create trigger r06_x2_recovery_immutable before update or delete or truncate
  on private.r06_x2_recoveries for each statement execute function private.r06_x2_immutable();
create trigger r06_x2_observation_immutable before update or delete or truncate
  on private.r06_x2_late_observations for each statement execute function private.r06_x2_immutable();

create function private.r06_x2_lock_financial_context()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = '55000', message = 'R06-X2 requires READ COMMITTED isolation.';
  end if;
  perform 1 from public.trips where id = 'dda56345-4123-4a0c-9771-5287899d2344' for update;
  perform 1 from public.payments where id = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b' for update;
  perform 1 from public.payment_attempts where id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416' for update;
  perform 1 from private.stripe_test_dispatch_reservations where attempt_id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416' for update;
end;
$$;

-- Keep the existing implementations byte-for-byte and delegate unrelated IDs.
alter function public.backend_claim_stripe_test_preparation(uuid,uuid,uuid,uuid,integer,integer,text)
  rename to r06_x2_original_claim;
alter function public.r06_x2_original_claim(uuid,uuid,uuid,uuid,integer,integer,text) set schema private;
create function public.backend_claim_stripe_test_preparation(
  actor_rider_id uuid, target_trip_id uuid, target_payment_id uuid, target_attempt_id uuid,
  expected_trip_version integer, expected_payment_version integer, operation_key text
) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Backend access required.';
  end if;
  if target_trip_id = 'dda56345-4123-4a0c-9771-5287899d2344'
    or target_payment_id = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'
    or target_attempt_id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416' then
    if target_trip_id is distinct from 'dda56345-4123-4a0c-9771-5287899d2344'::uuid
      or target_payment_id is distinct from 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'::uuid
      or target_attempt_id is distinct from '45ae3584-fa38-4fa5-b8c8-10efd79f8416'::uuid then
      raise exception using errcode = '42501', message = 'Canonical preparation context unavailable.';
    end if;
    perform private.r06_x2_lock_financial_context();
    if exists (select 1 from private.r06_x2_recoveries) then
      raise exception using errcode = '55000', message = 'R06-X2 dispatch claim is revoked.';
    end if;
  end if;
  return private.r06_x2_original_claim(actor_rider_id, target_trip_id, target_payment_id,
    target_attempt_id, expected_trip_version, expected_payment_version, operation_key);
end;
$$;

alter function public.backend_record_stripe_test_preparation(uuid,uuid,text) rename to r06_x2_original_record;
alter function public.r06_x2_original_record(uuid,uuid,text) set schema private;
create function public.backend_record_stripe_test_preparation(
  target_attempt_id uuid, original_claim_token uuid, prepared_reference text default null
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Backend access required.';
  end if;
  if target_attempt_id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416' then
    perform private.r06_x2_lock_financial_context();
    if exists (select 1 from private.r06_x2_recoveries) then
      raise exception using errcode = '55000', message = 'R06-X2 late result requires quarantine.';
    end if;
  end if;
  perform private.r06_x2_original_record(target_attempt_id, original_claim_token, prepared_reference);
end;
$$;

-- A late provider observation is evidence of a contradiction, never a fresh
-- preparation/authorization or a mutation of the old reservation/Attempt.
create function public.backend_record_stripe_test_preparation_fenced(
  target_attempt_id uuid, original_claim_token uuid, prepared_reference text default null
) returns text language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Backend access required.';
  end if;
  if target_attempt_id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416' then
    perform private.r06_x2_lock_financial_context();
    if exists (select 1 from private.r06_x2_recoveries) then
      if not exists (select 1 from private.stripe_test_dispatch_reservations
        where attempt_id = target_attempt_id and claim_token = original_claim_token) then
        raise exception using errcode = '42501', message = 'Original dispatch claim required.';
      end if;
      if prepared_reference is not null and prepared_reference !~ '^pi_[A-Za-z0-9]+$' then
        raise exception using errcode = '22023', message = 'Invalid preparation evidence.';
      end if;
      insert into private.r06_x2_late_observations(trip_id, attempt_id, provider_reference)
      values ('dda56345-4123-4a0c-9771-5287899d2344', target_attempt_id, prepared_reference);
      return 'quarantined';
    end if;
  end if;
  perform public.backend_record_stripe_test_preparation(target_attempt_id, original_claim_token, prepared_reference);
  return 'recorded';
end;
$$;

alter function public.backend_complete_payment_attempt(uuid,public.payment_attempt_status,text,text)
  rename to r06_x2_original_complete;
alter function public.r06_x2_original_complete(uuid,public.payment_attempt_status,text,text) set schema private;
create function public.backend_complete_payment_attempt(
  target_attempt_id uuid, final_status public.payment_attempt_status,
  provider_reference text default null, failure_code text default null
) returns public.payment_attempts language plpgsql security definer set search_path = '' as $$
begin
  if target_attempt_id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416' then
    perform private.r06_x2_lock_financial_context();
    if exists (select 1 from private.r06_x2_recoveries) then
      raise exception using errcode = '55000', message = 'R06-X2 Attempt is revoked; retain late evidence for review.';
    end if;
  end if;
  return private.r06_x2_original_complete(target_attempt_id, final_status, provider_reference, failure_code);
end;
$$;

create function private.r06_x2_guard_cancellation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.id = 'dda56345-4123-4a0c-9771-5287899d2344'
    and exists (select 1 from private.r06_x2_recoveries)
    and not exists (select 1 from private.r06_x2_authorizations
      where transaction_id = txid_current() and actor_id = auth.uid()) then
    raise exception using errcode = '55000', message = 'R06-X2 recovered Trip is immutable.';
  end if;
  if old.id = 'dda56345-4123-4a0c-9771-5287899d2344'
    and new.status is distinct from old.status
    and new.status in ('cancelledByRider','cancelledByDriver','cancelledByAdmin','failed')
    and not exists (select 1 from private.r06_x2_authorizations
      where transaction_id = txid_current() and actor_id = auth.uid()) then
    raise exception using errcode = '55000', message = 'R06-X2 requires guarded reserved recovery.';
  end if;
  return new;
end;
$$;
create trigger r06_x2_guard_cancellation before update on public.trips
  for each row execute function private.r06_x2_guard_cancellation();

create function private.r06_x2_guard_payment_cancellation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.id = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'
    and not exists (select 1 from private.r06_x2_authorizations
      where transaction_id = txid_current() and actor_id = auth.uid())
    and (exists (select 1 from private.r06_x2_recoveries)
      or (tg_op = 'UPDATE' and new.card_status = 'paymentCancelled' and old.card_status <> 'paymentCancelled')) then
    raise exception using errcode = '55000', message = 'R06-X2 Payment requires guarded recovery and is revoked afterwards.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger r06_x2_guard_payment_cancellation before update or delete on public.payments
  for each row execute function private.r06_x2_guard_payment_cancellation();

create function private.r06_x2_guard_history()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (
    (tg_table_name = 'payment_attempts' and
      (to_jsonb(new)->>'payment_id' = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'
        or to_jsonb(old)->>'payment_id' = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'
        or to_jsonb(new)->>'id' = '45ae3584-fa38-4fa5-b8c8-10efd79f8416'
        or to_jsonb(old)->>'id' = '45ae3584-fa38-4fa5-b8c8-10efd79f8416'))
    or (tg_table_name = 'stripe_test_dispatch_reservations' and
      (to_jsonb(new)->>'attempt_id' = '45ae3584-fa38-4fa5-b8c8-10efd79f8416'
        or to_jsonb(old)->>'attempt_id' = '45ae3584-fa38-4fa5-b8c8-10efd79f8416'))
  ) then
    -- Canonical RPCs acquire these parents before their DML. Also serialize a
    -- direct service-role insert before its FK wait, closing the phantom-insert
    -- gap. A noncanonical direct update with reversed locks can deadlock and
    -- abort; it can never commit across the recovery fence.
    perform private.r06_x2_lock_financial_context();
    if exists (select 1 from private.r06_x2_recoveries) then
      raise exception using errcode = '55000', message = 'R06-X2 original history is revoked and immutable.';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger r06_x2_guard_attempt_history before insert or update or delete on public.payment_attempts
  for each row execute function private.r06_x2_guard_history();
create trigger r06_x2_guard_reservation_history before insert or update or delete on private.stripe_test_dispatch_reservations
  for each row execute function private.r06_x2_guard_history();

-- Baseline service-role table DML must not insert financial evidence across an
-- FK wait after the recovery's absence checks. Only the target is serialized.
create function private.r06_x2_guard_new_financial_evidence()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if to_jsonb(new)->>'payment_id' = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'
    or to_jsonb(old)->>'payment_id' = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'
    or to_jsonb(new)->>'trip_id' = 'dda56345-4123-4a0c-9771-5287899d2344'
    or to_jsonb(old)->>'trip_id' = 'dda56345-4123-4a0c-9771-5287899d2344' then
    perform private.r06_x2_lock_financial_context();
    -- Reassignment is an insertion boundary too. Existing target evidence may
    -- never be reassigned/deleted to manufacture a clean approval snapshot.
    if exists (select 1 from private.r06_x2_recoveries)
      or (tg_op in ('UPDATE','DELETE') and (
        to_jsonb(old)->>'payment_id' = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'
        or to_jsonb(old)->>'trip_id' = 'dda56345-4123-4a0c-9771-5287899d2344')) then
      raise exception using errcode = '55000', message = 'R06-X2 late financial evidence requires offline review.';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger r06_x2_guard_new_receipt before insert on public.receipts
  for each row execute function private.r06_x2_guard_new_financial_evidence();
create trigger r06_x2_guard_new_refund before insert or update or delete on public.refunds
  for each row execute function private.r06_x2_guard_new_financial_evidence();
create trigger r06_x2_guard_new_webhook before insert or update or delete on public.processed_webhook_events
  for each row execute function private.r06_x2_guard_new_financial_evidence();
create trigger r06_x2_guard_trip_changes before insert or update or delete on public.trip_change_requests
  for each row execute function private.r06_x2_guard_new_financial_evidence();

-- Privately bind all evidence, including the token, without disclosing any raw
-- snapshot/token. This is NOT a provisioner and is never granted to API roles.
create function private.r06_x2_snapshot_digest()
returns text language sql stable security definer set search_path = '' as $$
  select encode(extensions.digest(convert_to(jsonb_build_array(
    (select to_jsonb(t) from public.trips t where id = 'dda56345-4123-4a0c-9771-5287899d2344'),
    (select to_jsonb(p) from public.payments p where id = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'),
    (select to_jsonb(a) from public.payment_attempts a where id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416'),
    (select to_jsonb(r) from private.stripe_test_dispatch_reservations r where attempt_id = '45ae3584-fa38-4fa5-b8c8-10efd79f8416'),
    (select to_jsonb(d) from public.driver_availability d where driver_id = 'f148a7ec-7e85-48ef-847f-8e9eea880e1b'),
    (select to_jsonb(d) from public.driver_profiles d where user_id = 'f148a7ec-7e85-48ef-847f-8e9eea880e1b'),
    (select to_jsonb(b) from public.booking_requests b where id = '84e8e5d2-4126-4c27-893b-b70e5318a184'),
    (select to_jsonb(q) from public.fare_quotes q where id = '90532842-03bf-4644-a656-2cad3edf37d1'),
    (select to_jsonb(v) from public.vehicles v where id = '48d007ab-c13c-4ff8-93f3-1dc7f1e6975d')
  )::text, 'UTF8'), 'sha256'), 'hex');
$$;

create function public.rider_recover_r06_x2_reserved_fixture(
  target_fixture_id uuid, target_trip_id uuid, target_payment_id uuid, target_attempt_id uuid,
  expected_trip_version integer, expected_payment_version integer, expected_driver_version integer,
  owner_approval_id uuid, recovery_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid;
  t public.trips%rowtype; p public.payments%rowtype; a public.payment_attempts%rowtype;
  r private.stripe_test_dispatch_reservations%rowtype; d public.driver_availability%rowtype;
  b public.booking_requests%rowtype; q public.fare_quotes%rowtype;
  approval private.r06_x2_owner_approvals%rowtype;
  prior private.r06_x2_recoveries%rowtype;
  cancelled_trip public.trips%rowtype; cancelled_payment public.payments%rowtype;
  final_driver public.driver_availability%rowtype;
  profile_before jsonb; vehicle_before jsonb;
  result jsonb;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = '55000', message = 'R06-X2 requires READ COMMITTED isolation.';
  end if;
  caller_id := private.require_nonblocked_rider();
  if auth.role() is distinct from 'authenticated'
    or caller_id is distinct from 'd3c3dc11-a840-4712-a6a4-599b4ae27329'::uuid
    or target_fixture_id is distinct from '8168236a-6a53-4a08-8dfa-f79e68fe8925'::uuid
    or target_trip_id is distinct from 'dda56345-4123-4a0c-9771-5287899d2344'::uuid
    or target_payment_id is distinct from 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b'::uuid
    or target_attempt_id is distinct from '45ae3584-fa38-4fa5-b8c8-10efd79f8416'::uuid then
    raise exception using errcode = '42501', message = 'R06-X2 target is unavailable to this Rider.';
  end if;
  if expected_trip_version is distinct from 1 or expected_payment_version is distinct from 1
    or expected_driver_version is distinct from 12 or owner_approval_id is null or recovery_request_id is null then
    raise exception using errcode = '22023', message = 'R06-X2 exact versions and review identifiers are required.';
  end if;
  -- Prevent a concurrent Rider block from slipping through the ownership check.
  -- Claim takes a compatible SHARE lock on this actor; Driver admin operations
  -- already serialize their active-Trip checks on the Trip lock below.
  perform 1 from public.users where id = caller_id for share;
  perform private.require_nonblocked_rider();
  perform private.r06_x2_lock_financial_context();
  select * into t from public.trips where id = target_trip_id;
  select * into p from public.payments where id = target_payment_id;
  select * into a from public.payment_attempts where id = target_attempt_id;
  select * into r from private.stripe_test_dispatch_reservations where attempt_id = target_attempt_id;
  -- Post-wait statements above and below intentionally take fresh RC snapshots.
  select * into prior from private.r06_x2_recoveries where trip_id = target_trip_id;
  if found then
    if prior.request_id <> recovery_request_id or prior.approval_id <> owner_approval_id then
      raise exception using errcode = '23505', message = 'R06-X2 recovery request conflicts; reconcile read-only.';
    end if;
    raise exception using errcode = '55000', message = 'R06-X2 already recovered; reconcile read-only.';
  end if;
  if t.id is null or p.id is null or a.id is null or r.attempt_id is null
    or t.rider_id <> caller_id or p.rider_id <> caller_id or r.rider_id <> caller_id
    or t.booking_request_id <> '84e8e5d2-4126-4c27-893b-b70e5318a184'
    or t.fare_quote_id <> '90532842-03bf-4644-a656-2cad3edf37d1'
    or t.driver_id is distinct from 'f148a7ec-7e85-48ef-847f-8e9eea880e1b'::uuid
    or t.vehicle_id is distinct from '48d007ab-c13c-4ff8-93f3-1dc7f1e6975d'::uuid
    or p.trip_id is distinct from t.id or p.booking_request_id <> t.booking_request_id
    or p.fare_quote_id <> t.fare_quote_id or a.payment_id <> p.id
    or r.trip_id <> t.id or r.payment_id <> p.id
    or t.status <> 'accepted' or t.payment_method <> 'card' or t.version <> expected_trip_version
    or p.version <> expected_payment_version or p.method <> 'card' or p.card_status <> 'cardPaymentPending'
    or t.original_fare_fils <> 2550 or t.current_fare_fils <> 2550
    or p.authorized_amount_fils <> 2550 or p.final_amount_fils <> 2550
    or t.currency <> 'JOD' or p.currency <> 'JOD' or a.currency <> 'JOD'
    or p.authorized_at is not null or p.paid_at is not null or p.cancelled_at is not null or p.refunded_at is not null
    or p.sanitized_failure_code is not null or p.provider_name is not null
    or p.card_brand is not null or p.card_last_four is not null
    or t.completed_at is not null or t.terminated_at is not null or t.in_progress_at is not null
    or t.driver_arriving_at is not null or t.driver_arrived_at is not null or t.termination_reason_code is not null
    or a.type <> 'initialAuthorization' or a.status <> 'pending' or a.authorization_cycle is distinct from 1
    or a.attempt_sequence <> 2 or a.provider_name is distinct from 'stripe'
    or a.requested_amount_fils <> 2550 or a.provider_transaction_reference is not null
    or a.completed_at is not null or a.verified_at is not null or a.refund_id is not null
    or a.sanitized_failure_code is not null or a.sanitized_failure_message is not null
    or a.created_at <> '2026-10-28T12:48:16.773058Z'::timestamptz
    or r.state <> 'reserved' or r.provider_reference is not null
    or r.created_at <> '2026-10-28T12:48:16.986561Z'::timestamptz
    or r.operation_key is distinct from a.idempotency_key
    or r.context is distinct from jsonb_build_object(
      'paymentId',p.id,'attemptId',a.id,'riderId',p.rider_id,'paymentVersion',p.version,
      'tripId',t.id,'tripVersion',t.version,'driverId',t.driver_id,
      'tripStatus',t.status,'method',p.method,'paymentStatus',p.card_status,
      'amountFils',p.authorized_amount_fils,'currency',p.currency,'idempotencyKey',a.idempotency_key)
    or (select count(*) from public.payments where trip_id = t.id or booking_request_id = t.booking_request_id) <> 1
    or (select count(*) from public.payment_attempts where payment_id = p.id) <> 1
    or (select count(*) from private.stripe_test_dispatch_reservations where trip_id = t.id or payment_id = p.id) <> 1
    or exists (select 1 from public.refunds where payment_id = p.id)
    or exists (select 1 from public.processed_webhook_events where payment_id = p.id)
    or exists (select 1 from public.receipts where trip_id = t.id or payment_id = p.id)
    or exists (select 1 from public.trip_change_requests where trip_id = t.id) then
    raise exception using errcode = '55000', message = 'R06-X2 financial context changed; recovery refused.';
  end if;
  select * into d from public.driver_availability where driver_id = t.driver_id for update;
  if d.driver_id is null or d.version <> expected_driver_version or d.state <> 'onTrip'
    or d.active_trip_id is distinct from t.id or d.vehicle_id is distinct from t.vehicle_id
    or d.reserved_booking_request_id is not null
    or not exists (select 1 from public.driver_profiles where user_id = t.driver_id and approval_status = 'approved' and version = 2)
    or not exists (select 1 from public.users where id = t.driver_id and role = 'driver' and not is_blocked)
    or not exists (select 1 from public.vehicles where id = t.vehicle_id and driver_id = t.driver_id and is_active)
    or exists (select 1 from public.trips where driver_id = t.driver_id and id <> t.id
      and status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed')) then
    raise exception using errcode = '55000', message = 'R06-X2 Driver context changed; recovery refused.';
  end if;
  select * into b from public.booking_requests where id = t.booking_request_id;
  select * into q from public.fare_quotes where id = t.fare_quote_id;
  if b.id is null or q.id is null or b.status <> 'matched' or b.version <> 5
    or b.rider_id <> caller_id or b.payment_method <> 'card' or b.fare_quote_id is distinct from q.id
    or b.matched_driver_id is distinct from t.driver_id or b.matched_vehicle_id is distinct from t.vehicle_id
    or q.booking_request_id <> b.id or q.rider_id <> caller_id or q.status <> 'locked'
    or q.fixed_fare_fils <> 2550 or q.currency <> 'JOD' then
    raise exception using errcode = '55000', message = 'R06-X2 Booking context changed; recovery refused.';
  end if;
  select * into approval from private.r06_x2_owner_approvals where id = owner_approval_id;
  if approval.id is null or approval.rider_id <> caller_id
    or approval.reviewed_at > clock_timestamp() or approval.expires_at <= clock_timestamp()
    or approval.snapshot_digest is distinct from private.r06_x2_snapshot_digest() then
    raise exception using errcode = '55000', message = 'R06-X2 trusted no-dispatch and quiescence review is unavailable.';
  end if;
  select to_jsonb(x) into profile_before from public.driver_profiles x where user_id = t.driver_id;
  select to_jsonb(x) into vehicle_before from public.vehicles x where id = t.vehicle_id;
  result := jsonb_build_object('fixture_id',target_fixture_id,'trip_id',t.id,'trip_status','cancelledByRider',
    'trip_version',t.version + 1,'payment_id',p.id,'payment_status','paymentCancelled',
    'payment_version',p.version + 1,'attempt_id',a.id,'attempt_status','pending',
    'driver_state','offline','driver_version',d.version + 1,'requires_provider_review',false);
  insert into private.r06_x2_recoveries(trip_id,approval_id,request_id,actor_id,transaction_id,result)
  values (t.id,approval.id,recovery_request_id,caller_id,txid_current(),result);
  insert into private.r06_x2_authorizations(transaction_id,trip_id,actor_id)
  values (txid_current(),t.id,caller_id);
  cancelled_trip := private.rider_cancel_trip(t.id, expected_trip_version, 'R06_X2_guarded_reserved_recovery');
  cancelled_payment := private.reconcile_cancelled_trip_payment(t.id);
  delete from private.r06_x2_authorizations where transaction_id = txid_current();
  select * into cancelled_trip from public.trips where id = t.id;
  select * into cancelled_payment from public.payments where id = p.id;
  select * into final_driver from public.driver_availability where driver_id = t.driver_id;
  if cancelled_trip.status <> 'cancelledByRider' or cancelled_trip.version <> t.version + 1
    or cancelled_trip.terminated_at is null or cancelled_trip.termination_reason_code <> 'R06_X2_guarded_reserved_recovery'
    or (to_jsonb(cancelled_trip) - array['status','version','updated_at','terminated_at','termination_reason_code'])
      is distinct from (to_jsonb(t) - array['status','version','updated_at','terminated_at','termination_reason_code'])
    or cancelled_payment.card_status <> 'paymentCancelled' or cancelled_payment.version <> p.version + 1
    or cancelled_payment.cancelled_at is null
    or (to_jsonb(cancelled_payment) - array['card_status','version','updated_at','cancelled_at'])
      is distinct from (to_jsonb(p) - array['card_status','version','updated_at','cancelled_at'])
    or final_driver.state <> 'offline' or final_driver.version <> d.version + 1
    or final_driver.active_trip_id is not null or final_driver.vehicle_id is not null
    or final_driver.reserved_booking_request_id is not null or final_driver.last_heartbeat_at is not null
    or (to_jsonb(final_driver) - array['state','version','updated_at','active_trip_id','vehicle_id','reserved_booking_request_id','last_heartbeat_at'])
      is distinct from (to_jsonb(d) - array['state','version','updated_at','active_trip_id','vehicle_id','reserved_booking_request_id','last_heartbeat_at'])
    or (select to_jsonb(x) from public.payment_attempts x where id = a.id) is distinct from to_jsonb(a)
    or (select to_jsonb(x) from private.stripe_test_dispatch_reservations x where attempt_id = a.id) is distinct from to_jsonb(r)
    or (select to_jsonb(x) from public.booking_requests x where id = b.id) is distinct from to_jsonb(b)
    or (select to_jsonb(x) from public.fare_quotes x where id = q.id) is distinct from to_jsonb(q)
    or (select to_jsonb(x) from public.driver_profiles x where user_id = t.driver_id) is distinct from profile_before
    or (select to_jsonb(x) from public.vehicles x where id = t.vehicle_id) is distinct from vehicle_before
    or (select count(*) from public.payment_attempts where payment_id = p.id) <> 1
    or exists (select 1 from public.receipts where trip_id = t.id or payment_id = p.id)
    or exists (select 1 from public.refunds where payment_id = p.id) then
    raise exception using errcode = '55000', message = 'R06-X2 recovery postconditions failed; transaction rolled back.';
  end if;
  perform private.write_audit_record(caller_id,'trip.r06_x2_guarded_recovery',caller_id,
    'trusted_no_dispatch_and_quiescence',jsonb_build_object('trip_id',t.id,'approval_id',approval.id),result);
  return result;
end;
$$;

-- Lost acknowledgements are resolved here with SELECTs only. Never auto-retry
-- the mutation. A quarantined late observation changes the reconciliation flag.
create function public.rider_read_r06_x2_recovery(target_fixture_id uuid, recovery_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare caller_id uuid; recovery private.r06_x2_recoveries%rowtype; needs_review boolean;
begin
  caller_id := private.require_nonblocked_rider();
  if auth.role() is distinct from 'authenticated'
    or caller_id is distinct from 'd3c3dc11-a840-4712-a6a4-599b4ae27329'::uuid
    or target_fixture_id is distinct from '8168236a-6a53-4a08-8dfa-f79e68fe8925'::uuid
    or recovery_request_id is null then
    raise exception using errcode = '42501', message = 'R06-X2 recovery is unavailable to this Rider.';
  end if;
  select * into recovery from private.r06_x2_recoveries where request_id = recovery_request_id and actor_id = caller_id;
  if not found then return jsonb_build_object('state','unresolved','retry_allowed',false); end if;
  needs_review := exists (select 1 from private.r06_x2_late_observations where trip_id = recovery.trip_id)
    or exists (select 1 from public.receipts where trip_id = recovery.trip_id)
    or exists (select 1 from public.refunds where payment_id = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b')
    or exists (select 1 from public.processed_webhook_events where payment_id = 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b');
  return recovery.result || jsonb_build_object('state',case when needs_review then 'review_required' else 'recovered' end,
    'retry_allowed',false,'requires_provider_review',needs_review);
end;
$$;

revoke all on function private.r06_x2_immutable(), private.r06_x2_lock_financial_context(),
  private.r06_x2_guard_cancellation(), private.r06_x2_guard_payment_cancellation(),
  private.r06_x2_guard_history(), private.r06_x2_guard_new_financial_evidence(), private.r06_x2_snapshot_digest(),
  private.r06_x2_original_claim(uuid,uuid,uuid,uuid,integer,integer,text),
  private.r06_x2_original_record(uuid,uuid,text),
  private.r06_x2_original_complete(uuid,public.payment_attempt_status,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.backend_claim_stripe_test_preparation(uuid,uuid,uuid,uuid,integer,integer,text),
  public.backend_record_stripe_test_preparation(uuid,uuid,text),
  public.backend_record_stripe_test_preparation_fenced(uuid,uuid,text),
  public.backend_complete_payment_attempt(uuid,public.payment_attempt_status,text,text),
  public.rider_recover_r06_x2_reserved_fixture(uuid,uuid,uuid,uuid,integer,integer,integer,uuid,uuid),
  public.rider_read_r06_x2_recovery(uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.backend_claim_stripe_test_preparation(uuid,uuid,uuid,uuid,integer,integer,text),
  public.backend_record_stripe_test_preparation(uuid,uuid,text),
  public.backend_record_stripe_test_preparation_fenced(uuid,uuid,text),
  public.backend_complete_payment_attempt(uuid,public.payment_attempt_status,text,text) to service_role;
grant execute on function public.rider_recover_r06_x2_reserved_fixture(uuid,uuid,uuid,uuid,integer,integer,integer,uuid,uuid),
  public.rider_read_r06_x2_recovery(uuid,uuid) to authenticated;

commit;
