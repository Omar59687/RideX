begin;

-- Private transaction marker lets only the guarded R06 wrapper enter the
-- existing canonical cancellation path for this one historical Trip.
create table private.r06_retirement_authorizations (
  transaction_id bigint not null,
  trip_id uuid not null,
  actor_id uuid not null,
  primary key (transaction_id, trip_id)
);
revoke all on table private.r06_retirement_authorizations
  from public, anon, authenticated, service_role;

-- One-purpose cancellation guard for the approved historical R06 Card Trip.
-- The owning Rider still performs canonical cancellation. This wrapper
-- serializes protected evidence checks with reservation and payment work.
create function public.rider_retire_r06_card_fixture(
  target_trip_id uuid,
  expected_trip_version integer,
  target_payment_id uuid,
  expected_payment_version integer,
  target_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_trip public.trips%rowtype;
  current_payment public.payments%rowtype;
  original_attempt public.payment_attempts%rowtype;
  current_attempt public.payment_attempts%rowtype;
  cancelled_trip public.trips%rowtype;
  cancelled_payment public.payments%rowtype;
begin
  -- Reservation absence relies on a fresh statement snapshot after waiting
  -- for the claimer's parent-row locks. Fail closed if caller configuration
  -- changes the REST transaction isolation contract.
  if pg_catalog.current_setting('transaction_isolation') is distinct from 'read committed' then
    raise exception using errcode = '55000',
      message = 'R06 retirement requires READ COMMITTED isolation.';
  end if;

  caller_id := private.require_nonblocked_rider();
  if target_trip_id is distinct from 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba'::uuid then
    raise exception using errcode = '42501',
      message = 'R06 retirement target is not authorized.';
  end if;
  if expected_trip_version is null or expected_trip_version < 1
    or expected_payment_version is null or expected_payment_version < 1
    or target_payment_id is null or target_attempt_id is null then
    raise exception using errcode = '22023',
      message = 'R06 retirement versions and evidence identifiers are required.';
  end if;

  -- Match the canonical backend order: Trip, Payment, Attempt. Reservation
  -- claim uses the same parent locks before inserting its reservation row.
  select * into current_trip
  from public.trips
  where id = target_trip_id and rider_id = caller_id
  for update;
  if not found then
    raise exception using errcode = '42501',
      message = 'R06 retirement target is unavailable to this Rider.';
  end if;
  if current_trip.version <> expected_trip_version then
    raise exception using errcode = '40001',
      message = 'R06 Trip version changed; re-preflight is required.';
  end if;
  if current_trip.status <> 'accepted' or current_trip.payment_method <> 'card' then
    raise exception using errcode = '55000',
      message = 'R06 Trip state is not eligible for retirement.';
  end if;

  select * into current_payment
  from public.payments
  where id = target_payment_id and trip_id = current_trip.id
    and rider_id = caller_id
  for update;
  if not found then
    raise exception using errcode = '55000',
      message = 'R06 Payment evidence is unavailable.';
  end if;
  if current_payment.version <> expected_payment_version then
    raise exception using errcode = '40001',
      message = 'R06 Payment version changed; re-preflight is required.';
  end if;
  if current_payment.method <> 'card'
    or current_payment.card_status <> 'cardPaymentPending'
    or current_payment.authorized_at is not null
    or current_payment.paid_at is not null
    or current_payment.cancelled_at is not null
    or current_payment.refunded_at is not null
    or current_payment.final_amount_fils <> current_trip.current_fare_fils
    or current_payment.authorized_amount_fils <> current_trip.original_fare_fils
    or current_payment.currency <> current_trip.currency then
    raise exception using errcode = '55000',
      message = 'R06 Payment state is not eligible for retirement.';
  end if;

  select * into original_attempt
  from public.payment_attempts
  where id = target_attempt_id and payment_id = current_payment.id
  for update;
  if not found
    or original_attempt.type <> 'initialAuthorization'
    or original_attempt.status <> 'pending'
    or original_attempt.authorization_cycle <> 1
    or original_attempt.provider_name is distinct from 'stripe'
    or original_attempt.provider_transaction_reference is not null
    or original_attempt.completed_at is not null
    or original_attempt.verified_at is not null
    or original_attempt.refund_id is not null
    or original_attempt.requested_amount_fils <> current_payment.authorized_amount_fils
    or original_attempt.currency <> current_payment.currency then
    raise exception using errcode = '55000',
      message = 'R06 authorization evidence is not eligible for retirement.';
  end if;
  if (
    select count(*) from public.payment_attempts as attempts
    where attempts.payment_id = current_payment.id
  ) <> 1 or exists (
    select 1 from public.payment_attempts as attempts
    where attempts.payment_id = current_payment.id
      and attempts.provider_transaction_reference is not null
  ) then
    raise exception using errcode = '55000',
      message = 'R06 payment attempt history is not eligible for retirement.';
  end if;

  -- A claim must lock the rows held above before it can insert. This query
  -- follows any waited-for claim commit under READ COMMITTED.
  if exists (
    select 1
    from private.stripe_test_dispatch_reservations as reservations
    where reservations.attempt_id = original_attempt.id
      or reservations.payment_id = current_payment.id
      or reservations.trip_id = current_trip.id
  ) then
    raise exception using errcode = '55000',
      message = 'R06 dispatch reservation exists; retirement is refused.';
  end if;
  if exists (
    select 1 from public.receipts where trip_id = current_trip.id
  ) then
    raise exception using errcode = '55000',
      message = 'R06 receipt evidence exists; retirement is refused.';
  end if;

  -- Preserve canonical ownership, transition, audit, availability release,
  -- and financial reconciliation behavior in this transaction.
  insert into private.r06_retirement_authorizations (
    transaction_id, trip_id, actor_id
  ) values (pg_catalog.txid_current(), current_trip.id, caller_id);
  cancelled_trip := private.rider_cancel_trip(
    current_trip.id, expected_trip_version, 'R06_historical_test_fixture_retirement'
  );
  cancelled_payment := private.reconcile_cancelled_trip_payment(cancelled_trip.id);
  delete from private.r06_retirement_authorizations
  where transaction_id = pg_catalog.txid_current()
    and trip_id = current_trip.id;

  select * into current_attempt
  from public.payment_attempts
  where id = original_attempt.id and payment_id = current_payment.id;
  if current_attempt is distinct from original_attempt then
    raise exception using errcode = '55000',
      message = 'R06 authorization evidence changed during retirement.';
  end if;
  if cancelled_trip.status <> 'cancelledByRider'
    or cancelled_payment.card_status <> 'paymentCancelled'
    or exists (select 1 from public.receipts where trip_id = current_trip.id) then
    raise exception using errcode = '55000',
      message = 'R06 retirement result failed reconciliation.';
  end if;

  return pg_catalog.jsonb_build_object(
    'trip_id', cancelled_trip.id,
    'trip_status', cancelled_trip.status,
    'trip_version', cancelled_trip.version,
    'payment_id', cancelled_payment.id,
    'payment_status', cancelled_payment.card_status,
    'payment_version', cancelled_payment.version,
    'attempt_id', current_attempt.id,
    'attempt_status', current_attempt.status,
    'receipt_count', 0
  );
end;
$$;

-- Prevent the still-public generic cancellation RPC from bypassing the
-- evidence guard for this exact Trip. Other Rider cancellations are unchanged.
create function private.guard_r06_generic_cancellation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.id = 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba'::uuid
    and old.status in ('accepted', 'driverArriving', 'driverArrived')
    and new.status in ('cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed')
    and not exists (
      select 1 from private.r06_retirement_authorizations as approvals
      where approvals.transaction_id = pg_catalog.txid_current()
        and approvals.trip_id = old.id
        and approvals.actor_id = auth.uid()
    ) then
    raise exception using errcode = '55000',
      message = 'The historical R06 Trip requires guarded retirement.';
  end if;
  return new;
end;
$$;

create trigger trips_guard_r06_cancellation
before update of status on public.trips
for each row execute function private.guard_r06_generic_cancellation();

revoke all on function private.guard_r06_generic_cancellation()
  from public, anon, authenticated, service_role;

-- The legacy completion RPC permits a failed provider response to be recorded
-- after Trip cancellation. For this exact fixture, keep the pending Attempt
-- immutable after retirement so a late backend response cannot rewrite the
-- evidence after the guarded transaction commits.
create function private.reject_late_r06_authorization_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_trip_status public.trip_status;
  target_card_status public.card_payment_status;
begin
  if old.type = 'initialAuthorization'
    and old.status = 'pending' and new.status <> 'pending' then
    select trips.status, payments.card_status
    into target_trip_status, target_card_status
    from public.payments as payments
    join public.trips as trips on trips.id = payments.trip_id
    where payments.id = old.payment_id
      and trips.id = 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba'::uuid;
    if found and (
      target_trip_status in ('cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed')
      or target_card_status = 'paymentCancelled'
    ) then
      raise exception using errcode = '55000',
        message = 'The retired R06 authorization evidence is immutable.';
    end if;
  end if;
  return new;
end;
$$;

create trigger payment_attempts_reject_late_r06_completion
before update on public.payment_attempts
for each row execute function private.reject_late_r06_authorization_completion();

revoke all on function private.reject_late_r06_authorization_completion()
  from public, anon, authenticated, service_role;

revoke all on function public.rider_retire_r06_card_fixture(uuid, integer, uuid, integer, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.rider_retire_r06_card_fixture(uuid, integer, uuid, integer, uuid)
  to authenticated;

commit;
