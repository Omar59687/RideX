begin;

alter table public.payment_attempts
  add column authorization_cycle integer;

with ordered_authorizations as (
  select id,
    row_number() over (
      partition by payment_id order by attempt_sequence
    )::integer as cycle
  from public.payment_attempts
  where type in ('initialAuthorization', 'replacementAuthorization')
)
update public.payment_attempts as attempts
set authorization_cycle = ordered_authorizations.cycle
from ordered_authorizations
where attempts.id = ordered_authorizations.id;

with cycle_bound_attempts as (
  select attempts.id,
    (
      select max(authorizations.authorization_cycle)
      from public.payment_attempts as authorizations
      where authorizations.payment_id = attempts.payment_id
        and authorizations.type in ('initialAuthorization', 'replacementAuthorization')
        and authorizations.attempt_sequence <= attempts.attempt_sequence
    ) as cycle
  from public.payment_attempts as attempts
  where attempts.type in ('voidAuthorization', 'capture', 'captureRetry')
)
update public.payment_attempts as attempts
set authorization_cycle = cycle_bound_attempts.cycle
from cycle_bound_attempts
where attempts.id = cycle_bound_attempts.id;

do $$
begin
  if exists (
    select 1
    from (
      select type,
        row_number() over (
          partition by payment_id order by attempt_sequence
        ) as authorization_number
      from public.payment_attempts
      where type in ('initialAuthorization', 'replacementAuthorization')
    ) as ordered_authorizations
    where (authorization_number = 1 and type <> 'initialAuthorization')
      or (authorization_number = 2 and type <> 'replacementAuthorization')
      or authorization_number > 2
  ) then
    raise exception using errcode = '55000',
      message = 'Migration 022 found invalid historical initial/replacement authorization ordering.';
  end if;
  if exists (
    select 1
    from public.payment_attempts as replacement
    join public.payment_attempts as initial
      on initial.payment_id = replacement.payment_id
      and initial.authorization_cycle = replacement.authorization_cycle - 1
      and initial.type = 'initialAuthorization'
    where replacement.type = 'replacementAuthorization'
      and initial.status not in ('failed', 'cancelled')
      and not (
        initial.status = 'succeeded'
        and exists (
          select 1
          from public.payment_attempts as release
          where release.payment_id = replacement.payment_id
            and release.type = 'voidAuthorization'
            and release.status = 'succeeded'
            and release.verified_at = release.completed_at
            and release.attempt_sequence > initial.attempt_sequence
            and release.attempt_sequence < replacement.attempt_sequence
        )
      )
  ) then
    raise exception using errcode = '55000',
      message = 'Migration 022 found a historical replacement authorization without a failed or released initial authorization.';
  end if;
  if exists (
    select 1 from public.payment_attempts
    where type in ('voidAuthorization', 'capture', 'captureRetry')
      and authorization_cycle is null
  ) then
    raise exception using errcode = '55000',
      message = 'Migration 022 found a void or Capture without a preceding authorization cycle.';
  end if;
  if exists (
    select 1
    from public.payment_attempts
    where type in ('capture', 'captureRetry') and status = 'pending'
    group by payment_id
    having count(*) > 1
  ) then
    raise exception using errcode = '55000',
      message = 'Migration 022 found multiple pending Capture attempts for one Payment.';
  end if;
  if exists (
    select 1
    from public.payment_attempts
    group by idempotency_key
    having count(*) > 1
  ) then
    raise exception using errcode = '55000',
      message = 'Migration 022 found an idempotency key associated with multiple Payments.';
  end if;
end;
$$;

alter table public.payment_attempts
  add constraint payment_attempts_authorization_cycle_valid check (
    (
      type in (
        'initialAuthorization', 'replacementAuthorization',
        'voidAuthorization', 'capture', 'captureRetry'
      )
      and authorization_cycle is not null
      and authorization_cycle > 0
    )
    or (
      type not in (
        'initialAuthorization', 'replacementAuthorization',
        'voidAuthorization', 'capture', 'captureRetry'
      )
      and authorization_cycle is null
    )
  );

create unique index payment_attempts_authorization_cycle_unique_idx
  on public.payment_attempts (payment_id, authorization_cycle)
  where type in ('initialAuthorization', 'replacementAuthorization');

create unique index payment_attempts_one_pending_capture_idx
  on public.payment_attempts (payment_id)
  where type in ('capture', 'captureRetry') and status = 'pending';

create unique index payment_attempts_idempotency_key_global_idx
  on public.payment_attempts (idempotency_key);

create or replace function private.current_authorization_cycle(target_payment_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(max(authorization_cycle), 0)
  from public.payment_attempts
  where payment_id = target_payment_id
    and type in ('initialAuthorization', 'replacementAuthorization');
$$;

create or replace function private.has_verified_card_void(
  target_payment_id uuid,
  target_authorization_cycle integer
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_authorization_cycle is not null
    and target_authorization_cycle > 0
    and exists (
      select 1
      from public.payment_attempts
      where payment_id = target_payment_id
        and type = 'voidAuthorization'
        and authorization_cycle = target_authorization_cycle
        and status = 'succeeded'
        and verified_at = completed_at
        and completed_at >= created_at
    );
$$;

create or replace function private.has_current_verified_card_authorization(
  target_payment_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  payment public.payments%rowtype;
  current_authorization public.payment_attempts%rowtype;
begin
  select * into payment from public.payments where id = target_payment_id;
  if not found or payment.method <> 'card' then return false; end if;

  select * into current_authorization
  from public.payment_attempts
  where payment_id = payment.id
    and type in ('initialAuthorization', 'replacementAuthorization')
  order by authorization_cycle desc, attempt_sequence desc
  limit 1;

  return found
    and current_authorization.status = 'succeeded'
    and current_authorization.verified_at = current_authorization.completed_at
    and current_authorization.completed_at >= current_authorization.created_at
    and current_authorization.completed_at
      <= current_authorization.created_at + interval '2 minutes'
    and current_authorization.requested_amount_fils = payment.authorized_amount_fils
    and current_authorization.currency = payment.currency
    and not private.has_verified_card_void(
      payment.id, current_authorization.authorization_cycle
    );
end;
$$;

create or replace function private.reject_payment_attempt_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_setting('ridex.complete_payment_attempt', true) = 'on'
    and new.payment_id = old.payment_id
    and new.refund_id is not distinct from old.refund_id
    and new.type = old.type
    and new.requested_amount_fils = old.requested_amount_fils
    and new.currency = old.currency
    and new.idempotency_key = old.idempotency_key
    and new.provider_name is not distinct from old.provider_name
    and new.created_at = old.created_at
    and new.attempt_sequence = old.attempt_sequence
    and new.authorization_cycle is not distinct from old.authorization_cycle
    and old.status = 'pending'
    and new.status <> 'pending' then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'Payment attempts are append-only.';
end;
$$;

create or replace function public.backend_record_payment_attempt(
  target_payment_id uuid,
  attempt_type public.payment_attempt_type,
  amount_fils integer,
  attempt_key text,
  provider text default null
)
returns public.payment_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  payment public.payments%rowtype;
  trip public.trips%rowtype;
  result public.payment_attempts%rowtype;
  latest_authorization public.payment_attempts%rowtype;
  latest_capture public.payment_attempts%rowtype;
  attempt_count integer;
  operation_cycle integer;
  target_trip_id uuid;
  normalized_key text := nullif(btrim(attempt_key), '');
  normalized_provider text := nullif(btrim(provider), '');
begin
  if normalized_key is null or amount_fils is null or amount_fils < 0 then
    raise exception using errcode = '22023', message = 'Payment attempt inputs are invalid.';
  end if;

  select trip_id into target_trip_id from public.payments where id = target_payment_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  select * into trip from public.trips where id = target_trip_id for update;
  if not found then raise exception using errcode = '55000', message = 'Payment must have a canonical Trip.'; end if;
  select * into payment from public.payments where id = target_payment_id for update;
  if payment.trip_id is distinct from trip.id then
    raise exception using errcode = '55000', message = 'Payment must retain its canonical Trip.';
  end if;

  select * into latest_authorization
  from public.payment_attempts
  where payment_id = payment.id
    and type in ('initialAuthorization', 'replacementAuthorization')
  order by authorization_cycle desc, attempt_sequence desc
  limit 1;

  operation_cycle := case
    when attempt_type = 'initialAuthorization' then 1
    when attempt_type = 'replacementAuthorization' and latest_authorization.type = 'replacementAuthorization'
      then latest_authorization.authorization_cycle
    when attempt_type = 'replacementAuthorization'
      then coalesce(latest_authorization.authorization_cycle, 0) + 1
    when attempt_type in ('voidAuthorization', 'capture', 'captureRetry')
      then coalesce(latest_authorization.authorization_cycle, 0)
    else null
  end;

  select * into result
  from public.payment_attempts
  where idempotency_key = normalized_key;
  if found then
    if result.payment_id = payment.id
      and result.type = attempt_type
      and result.requested_amount_fils = amount_fils
      and result.currency = payment.currency
      and result.provider_name is not distinct from normalized_provider
      and result.refund_id is null
      and result.authorization_cycle is not distinct from operation_cycle then
      return result;
    end if;
    perform private.write_audit_record(
      null, 'payment.attempt_idempotency_payload_mismatch', payment.rider_id, null,
      jsonb_build_object('payment_id', payment.id, 'attempt_id', result.id),
      jsonb_build_object(
        'operation', attempt_type,
        'amount_fils', amount_fils,
        'currency', payment.currency,
        'authorization_cycle', operation_cycle
      )
    );
    raise exception using errcode = '55000',
      message = 'Payment attempt idempotency key is already associated with different operation data.';
  end if;

  if attempt_type = 'refund' then
    raise exception using errcode = '55000', message = 'Refund attempts require their canonical Refund operation.';
  end if;
  if attempt_type in ('adjustmentAuthorization', 'providerStatusVerification') then
    raise exception using errcode = '55000', message = 'Payment attempt type is not available through this operation.';
  end if;

  if attempt_type = 'initialAuthorization' then
    if payment.method <> 'card' or trip.status <> 'accepted'
      or payment.card_status <> 'cardPaymentPending'
      or amount_fils <> payment.authorized_amount_fils then
      raise exception using errcode = '55000',
        message = 'Initial authorization requires an accepted pending Card Payment.';
    end if;
    if latest_authorization.id is not null then
      raise exception using errcode = '55000',
        message = 'Initial authorization must be the first authorization attempt.';
    end if;
  elsif attempt_type = 'replacementAuthorization' then
    if payment.method <> 'card'
      or trip.status not in ('accepted', 'driverArriving', 'driverArrived')
      or payment.card_status not in ('cardPaymentPending', 'cardPaymentFailed')
      or amount_fils <> payment.authorized_amount_fils
      or latest_authorization.id is null
      or latest_authorization.type <> 'initialAuthorization' then
      raise exception using errcode = '55000',
        message = 'Replacement authorization requires one valid preceding initial authorization.';
    end if;
    if latest_authorization.status not in ('failed', 'cancelled')
      and not (
        latest_authorization.status = 'succeeded'
        and private.has_verified_card_void(
          payment.id, latest_authorization.authorization_cycle
        )
      ) then
      raise exception using errcode = '55000',
        message = 'Replacement authorization requires a failed authorization or verified release.';
    end if;
    select count(*) into attempt_count
    from public.payment_attempts
    where payment_id = payment.id
      and type in ('initialAuthorization', 'replacementAuthorization');
    if attempt_count >= 2 then
      raise exception using errcode = '55000', message = 'Card authorization permits at most two attempts.';
    end if;
  elsif attempt_type = 'capture' then
    if payment.method <> 'card' or trip.status <> 'completed'
      or payment.card_status <> 'cardPaymentAuthorized'
      or amount_fils <> payment.final_amount_fils
      or not private.has_current_verified_card_authorization(payment.id) then
      raise exception using errcode = '55000',
        message = 'Capture requires a completed Trip with the current authorized Card Payment.';
    end if;
    if exists (
      select 1 from public.payment_attempts
      where payment_id = payment.id and type in ('capture', 'captureRetry')
    ) then
      raise exception using errcode = '55000', message = 'Only one initial Capture attempt is permitted.';
    end if;
  elsif attempt_type = 'captureRetry' then
    select * into latest_capture
    from public.payment_attempts
    where payment_id = payment.id and type in ('capture', 'captureRetry')
    order by attempt_sequence desc
    limit 1;
    if payment.method <> 'card' or trip.status <> 'completed'
      or payment.card_status <> 'cardPaymentFailed'
      or amount_fils <> payment.final_amount_fils
      or latest_capture.id is null
      or latest_capture.status <> 'failed'
      or latest_capture.authorization_cycle <> operation_cycle then
      raise exception using errcode = '55000',
        message = 'Capture retry requires the latest current-cycle Capture attempt to have failed.';
    end if;
    select count(*) into attempt_count
    from public.payment_attempts
    where payment_id = payment.id and type in ('capture', 'captureRetry');
    if attempt_count >= 3 then
      raise exception using errcode = '55000', message = 'Capture permits at most three attempts.';
    end if;
  elsif attempt_type = 'voidAuthorization' then
    if payment.method <> 'card'
      or trip.status not in ('accepted', 'driverArriving', 'driverArrived')
      or payment.card_status <> 'cardPaymentAuthorized'
      or amount_fils <> payment.authorized_amount_fils
      or operation_cycle < 1
      or not private.has_current_verified_card_authorization(payment.id) then
      raise exception using errcode = '55000',
        message = 'Authorization void requires the current pre-start authorized Card Payment.';
    end if;
    if exists (
      select 1 from public.payment_attempts
      where payment_id = payment.id
        and type = 'voidAuthorization'
        and authorization_cycle = operation_cycle
        and status in ('pending', 'succeeded')
    ) then
      raise exception using errcode = '55000',
        message = 'Current authorization already has a pending or successful void.';
    end if;
  end if;

  insert into public.payment_attempts (
    payment_id, type, requested_amount_fils, currency, idempotency_key,
    provider_name, authorization_cycle
  ) values (
    payment.id, attempt_type, amount_fils, payment.currency, normalized_key,
    normalized_provider, operation_cycle
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.backend_complete_payment_attempt(
  target_attempt_id uuid,
  final_status public.payment_attempt_status,
  provider_reference text default null,
  failure_code text default null
)
returns public.payment_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_attempt public.payment_attempts%rowtype;
  payment public.payments%rowtype;
  trip public.trips%rowtype;
  target_payment_id uuid;
  target_trip_id uuid;
  normalized_reference text := nullif(btrim(provider_reference), '');
  normalized_failure text := nullif(btrim(failure_code), '');
begin
  if final_status is null or final_status = 'pending' then
    raise exception using errcode = '22023', message = 'A payment attempt requires a terminal verified status.';
  end if;
  select payment_id into target_payment_id
  from public.payment_attempts where id = target_attempt_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment attempt was not found.'; end if;
  select trip_id into target_trip_id from public.payments where id = target_payment_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  select * into trip from public.trips where id = target_trip_id for update;
  select * into payment from public.payments where id = target_payment_id for update;
  select * into current_attempt from public.payment_attempts where id = target_attempt_id for update;
  if current_attempt.type = 'refund' then
    raise exception using errcode = '55000', message = 'Refund attempts require their canonical Refund completion operation.';
  end if;
  if current_attempt.status <> 'pending' then
    if current_attempt.status = final_status
      and current_attempt.provider_transaction_reference is not distinct from normalized_reference
      and current_attempt.sanitized_failure_code is not distinct from normalized_failure then
      return current_attempt;
    end if;
    raise exception using errcode = '55000',
      message = 'A terminal Payment attempt cannot be completed with different data.';
  end if;
  if final_status = 'succeeded' and normalized_reference is null then
    raise exception using errcode = '22023', message = 'A successful Payment attempt requires a provider reference.';
  end if;

  if final_status = 'succeeded'
    and current_attempt.type in ('initialAuthorization', 'replacementAuthorization')
    and (
      payment.method <> 'card'
      or payment.card_status not in ('cardPaymentPending', 'cardPaymentFailed')
      or trip.status not in ('accepted', 'driverArriving', 'driverArrived')
      or current_attempt.authorization_cycle
        <> private.current_authorization_cycle(payment.id)
      or current_attempt.requested_amount_fils <> payment.authorized_amount_fils
      or current_attempt.currency <> payment.currency
    ) then
    raise exception using errcode = '55000',
      message = 'Authorization completion no longer matches the current Card cycle.';
  end if;
  if final_status = 'succeeded' and current_attempt.type = 'voidAuthorization'
    and (
      payment.method <> 'card'
      or payment.card_status <> 'cardPaymentAuthorized'
      or trip.status not in ('accepted', 'driverArriving', 'driverArrived')
      or current_attempt.authorization_cycle
        <> private.current_authorization_cycle(payment.id)
      or current_attempt.requested_amount_fils <> payment.authorized_amount_fils
      or current_attempt.currency <> payment.currency
    ) then
    raise exception using errcode = '55000',
      message = 'Authorization void no longer matches the current Card cycle.';
  end if;
  if final_status = 'succeeded'
    and current_attempt.type in ('capture', 'captureRetry')
    and (
      payment.method <> 'card'
      or payment.card_status not in ('cardPaymentAuthorized', 'cardPaymentFailed')
      or trip.status <> 'completed'
      or current_attempt.authorization_cycle
        <> private.current_authorization_cycle(payment.id)
      or current_attempt.requested_amount_fils <> payment.final_amount_fils
      or current_attempt.currency <> payment.currency
      or not private.has_current_verified_card_authorization(payment.id)
    ) then
    raise exception using errcode = '55000',
      message = 'Capture completion no longer matches the current authorized Card cycle.';
  end if;

  perform set_config('ridex.complete_payment_attempt', 'on', true);
  update public.payment_attempts
  set status = final_status,
      provider_transaction_reference = normalized_reference,
      sanitized_failure_code = normalized_failure,
      completed_at = now(),
      verified_at = now()
  where id = current_attempt.id
  returning * into current_attempt;
  return current_attempt;
end;
$$;

create or replace function public.backend_record_refund_attempt(
  target_refund_id uuid,
  attempt_key text,
  provider text default null
)
returns public.payment_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_refund public.refunds%rowtype;
  payment public.payments%rowtype;
  result public.payment_attempts%rowtype;
  prior_attempt public.payment_attempts%rowtype;
  attempt_count integer;
  normalized_key text := nullif(btrim(attempt_key), '');
  normalized_provider text := nullif(btrim(provider), '');
begin
  if normalized_key is null then
    raise exception using errcode = '22023', message = 'A Refund attempt idempotency key is required.';
  end if;
  select * into current_refund from public.refunds where id = target_refund_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Refund was not found.'; end if;
  select * into payment from public.payments where id = current_refund.payment_id for update;
  if payment.method <> 'card' or payment.card_status <> 'refundPending' then
    raise exception using errcode = '55000', message = 'Refund attempts require a pending Card refund.';
  end if;
  if current_refund.status <> 'pending'
    or current_refund.amount_fils <> payment.final_amount_fils
    or current_refund.currency <> payment.currency then
    raise exception using errcode = '55000', message = 'Refund must match the full pending Payment amount in JOD.';
  end if;
  select * into result
  from public.payment_attempts
  where idempotency_key = normalized_key;
  if found then
    if result.refund_id = current_refund.id
      and result.type = 'refund'
      and result.payment_id = payment.id
      and result.requested_amount_fils = current_refund.amount_fils
      and result.currency = current_refund.currency
      and result.provider_name is not distinct from normalized_provider
      and result.authorization_cycle is null then
      return result;
    end if;
    raise exception using errcode = '55000',
      message = 'Refund attempt idempotency key is already associated with different operation data.';
  end if;
  select count(*) into attempt_count
  from public.payment_attempts where refund_id = current_refund.id;
  if attempt_count >= 3 then
    raise exception using errcode = '55000', message = 'Refund permits at most three attempts.';
  end if;
  select * into prior_attempt
  from public.payment_attempts
  where refund_id = current_refund.id
  order by attempt_sequence desc
  limit 1;
  if found and prior_attempt.status not in ('failed', 'cancelled') then
    raise exception using errcode = '55000',
      message = 'A Refund retry requires the preceding attempt to complete unsuccessfully.';
  end if;
  insert into public.payment_attempts (
    payment_id, refund_id, type, requested_amount_fils, currency,
    idempotency_key, provider_name, authorization_cycle
  ) values (
    payment.id, current_refund.id, 'refund', current_refund.amount_fils,
    current_refund.currency, normalized_key, normalized_provider, null
  ) returning * into result;
  return result;
end;
$$;

create or replace function private.reconcile_cancelled_trip_payment(target_trip_id uuid)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_trip public.trips%rowtype;
  current_payment public.payments%rowtype;
  current_authorization public.payment_attempts%rowtype;
begin
  select * into current_trip from public.trips where id = target_trip_id for update;
  if not found or current_trip.status not in (
    'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed'
  ) then
    raise exception using errcode = '55000',
      message = 'Payment cancellation requires a terminal cancelled Trip.';
  end if;

  current_payment := private.ensure_trip_payment(current_trip.id);
  if current_payment.method = 'cash' then
    if current_payment.cash_status = 'cashSelected' then
      update public.payments
      set cash_status = 'cancelled', cancelled_at = now()
      where id = current_payment.id
      returning * into current_payment;
    elsif current_payment.cash_status <> 'cancelled' then
      raise exception using errcode = '55000', message = 'Settled Cash Payment cannot be cancelled.';
    end if;
    return current_payment;
  end if;

  if current_payment.card_status = 'paymentCancelled' then return current_payment; end if;
  if current_payment.card_status not in (
    'cardPaymentPending', 'cardPaymentAuthorized', 'cardPaymentFailed'
  ) then
    raise exception using errcode = '55000',
      message = 'Card Payment is not eligible for cancellation.';
  end if;
  select * into current_authorization
  from public.payment_attempts
  where payment_id = current_payment.id
    and type in ('initialAuthorization', 'replacementAuthorization')
  order by authorization_cycle desc, attempt_sequence desc
  limit 1;
  if found and current_authorization.status = 'succeeded'
    and not private.has_verified_card_void(
      current_payment.id, current_authorization.authorization_cycle
    ) then
    raise exception using errcode = '55000',
      message = 'Card Payment requires a verified current-cycle void before cancellation.';
  end if;
  update public.payments
  set card_status = 'paymentCancelled', cancelled_at = now()
  where id = current_payment.id
  returning * into current_payment;
  return current_payment;
end;
$$;

create or replace function public.backend_transition_payment(
  target_payment_id uuid,
  expected_version integer,
  next_cash_status public.cash_payment_status default null,
  next_card_status public.card_payment_status default null
)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  payment public.payments%rowtype;
  trip public.trips%rowtype;
  current_authorization public.payment_attempts%rowtype;
  latest_capture public.payment_attempts%rowtype;
  target_trip_id uuid;
begin
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  select trip_id into target_trip_id from public.payments where id = target_payment_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  select * into trip from public.trips where id = target_trip_id for update;
  select * into payment from public.payments where id = target_payment_id for update;
  if payment.trip_id is distinct from trip.id then
    raise exception using errcode = '55000', message = 'Payment must retain its canonical Trip.';
  end if;
  if payment.version <> expected_version then raise exception using errcode = '40001', message = 'Payment version is stale.'; end if;

  if payment.method = 'cash' then
    if next_card_status is not null or next_cash_status is null then
      raise exception using errcode = '55000', message = 'Invalid Cash payment transition.';
    end if;
    if next_cash_status = 'paid' then
      raise exception using errcode = '55000',
        message = 'Cash Payment can be paid only by atomic trusted Trip completion.';
    end if;
    if next_cash_status <> 'cancelled'
      or trip.status not in (
        'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed'
      ) then
      raise exception using errcode = '55000',
        message = 'Cash Payment cancellation requires a terminal cancelled Trip.';
    end if;
    if payment.cash_status = 'cancelled' then return payment; end if;
    if payment.cash_status <> 'cashSelected' then
      raise exception using errcode = '55000', message = 'Settled Cash Payment cannot be cancelled.';
    end if;
    update public.payments
    set cash_status = 'cancelled', cancelled_at = now()
    where id = payment.id
    returning * into payment;
  else
    if next_cash_status is not null or next_card_status is null
      or next_card_status in ('refundPending', 'refunded') then
      raise exception using errcode = '55000', message = 'Invalid Card payment transition.';
    end if;
    if not (
      (payment.card_status = 'cardPaymentPending'
        and next_card_status in ('cardPaymentAuthorized', 'cardPaymentFailed', 'paymentCancelled'))
      or (payment.card_status = 'cardPaymentAuthorized'
        and next_card_status in ('cardPaymentPending', 'cardPaymentSucceeded', 'cardPaymentFailed', 'paymentCancelled'))
      or (payment.card_status = 'cardPaymentFailed'
        and next_card_status in ('cardPaymentPending', 'cardPaymentSucceeded', 'paymentCancelled'))
    ) then
      raise exception using errcode = '55000', message = 'Invalid Card payment transition.';
    end if;

    select * into current_authorization
    from public.payment_attempts
    where payment_id = payment.id
      and type in ('initialAuthorization', 'replacementAuthorization')
    order by authorization_cycle desc, attempt_sequence desc
    limit 1;

    if next_card_status = 'cardPaymentAuthorized'
      and not private.has_current_verified_card_authorization(payment.id) then
      raise exception using errcode = '55000',
        message = 'Card authorization requires the current verified authorization cycle.';
    end if;
    if payment.card_status = 'cardPaymentAuthorized'
      and next_card_status = 'cardPaymentPending'
      and (
        trip.status not in ('accepted', 'driverArriving', 'driverArrived')
        or current_authorization.id is null
        or not private.has_verified_card_void(
          payment.id, current_authorization.authorization_cycle
        )
      ) then
      raise exception using errcode = '55000',
        message = 'A new authorization cycle requires verified release of the current authorization.';
    end if;
    if next_card_status = 'cardPaymentFailed' and (
      (payment.card_status = 'cardPaymentPending' and not exists (
        select 1 from public.payment_attempts
        where payment_id = payment.id
          and type in ('initialAuthorization', 'replacementAuthorization')
          and authorization_cycle = private.current_authorization_cycle(payment.id)
          and status in ('failed', 'cancelled')
      ))
      or (payment.card_status = 'cardPaymentAuthorized' and (
        trip.status <> 'completed' or not exists (
          select 1 from public.payment_attempts
          where payment_id = payment.id
            and type in ('capture', 'captureRetry')
            and authorization_cycle = private.current_authorization_cycle(payment.id)
            and status = 'failed'
        )
      ))
    ) then
      raise exception using errcode = '55000',
        message = 'Card failure requires a verified failed current-cycle operation.';
    end if;
    if payment.card_status = 'cardPaymentFailed'
      and next_card_status = 'cardPaymentPending'
      and trip.status not in ('accepted', 'driverArriving', 'driverArrived') then
      raise exception using errcode = '55000',
        message = 'Authorization retry is available only before Trip start.';
    end if;
    if next_card_status = 'cardPaymentSucceeded' then
      select * into latest_capture
      from public.payment_attempts
      where payment_id = payment.id
        and type in ('capture', 'captureRetry')
        and authorization_cycle = private.current_authorization_cycle(payment.id)
      order by attempt_sequence desc
      limit 1;
      if trip.status <> 'completed' or not found
        or latest_capture.status <> 'succeeded'
        or latest_capture.verified_at <> latest_capture.completed_at then
        raise exception using errcode = '55000',
          message = 'Card success requires the latest verified current-cycle Capture.';
      end if;
    end if;
    if next_card_status = 'paymentCancelled' then
      if trip.status not in (
        'cancelledByRider', 'cancelledByDriver', 'cancelledByAdmin', 'failed'
      ) then
        raise exception using errcode = '55000',
          message = 'Payment cancellation requires a terminal cancelled Trip.';
      end if;
      if current_authorization.id is not null
        and current_authorization.status = 'succeeded'
        and not private.has_verified_card_void(
          payment.id, current_authorization.authorization_cycle
        ) then
        raise exception using errcode = '55000',
          message = 'Card Payment requires a verified current-cycle void before cancellation.';
      end if;
    end if;

    update public.payments
    set card_status = next_card_status,
        authorized_at = case when next_card_status = 'cardPaymentAuthorized' then now() else authorized_at end,
        paid_at = case when next_card_status = 'cardPaymentSucceeded' then now() else paid_at end,
        cancelled_at = case when next_card_status = 'paymentCancelled' then now() else cancelled_at end
    where id = payment.id
    returning * into payment;
  end if;
  perform private.write_audit_record(
    null, 'payment.state_transition', payment.rider_id, null,
    jsonb_build_object('payment_id', payment.id, 'version', expected_version),
    jsonb_build_object(
      'version', payment.version,
      'cash_status', payment.cash_status,
      'card_status', payment.card_status,
      'authorization_cycle', private.current_authorization_cycle(payment.id)
    )
  );
  return payment;
end;
$$;

revoke all on function private.current_authorization_cycle(uuid),
  private.has_verified_card_void(uuid, integer)
from public, anon, authenticated, service_role;

commit;
