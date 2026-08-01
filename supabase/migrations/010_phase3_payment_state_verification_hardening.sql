begin;

alter table public.payment_attempts
  add column refund_id uuid references public.refunds (id) on delete restrict,
  add column verified_at timestamptz,
  add constraint payment_attempts_refund_association check (
    (type = 'refund' and refund_id is not null)
    or (type <> 'refund' and refund_id is null)
  );

create index payment_attempts_refund_created_at_idx
  on public.payment_attempts (refund_id, created_at desc)
  where refund_id is not null;

create or replace function private.reject_payment_attempt_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_setting('ridex.complete_payment_attempt', true) = 'on'
    and new.payment_id = old.payment_id
    and new.refund_id is not distinct from old.refund_id
    and new.type = old.type
    and new.requested_amount_fils = old.requested_amount_fils
    and new.currency = old.currency
    and new.idempotency_key = old.idempotency_key
    and new.created_at = old.created_at
    and old.status = 'pending'
    and new.status <> 'pending' then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'Payment attempts are append-only.';
end;
$$;

create or replace function public.backend_record_payment_attempt(target_payment_id uuid, attempt_type public.payment_attempt_type, amount_fils integer, attempt_key text, provider text default null)
returns public.payment_attempts language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype; result public.payment_attempts%rowtype; attempt_count integer;
begin
  if attempt_type = 'refund' then
    raise exception using errcode = '55000', message = 'Refund attempts require their canonical Refund operation.';
  end if;
  select * into payment from public.payments where id = target_payment_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  if attempt_type = 'adjustmentAuthorization' then raise exception using errcode = '55000', message = 'Card adjustment authorization is not supported.'; end if;
  if amount_fils <> payment.authorized_amount_fils or amount_fils < 0 then raise exception using errcode = '22023', message = 'Payment attempt amount must match the authorized amount.'; end if;
  select * into result from public.payment_attempts where payment_id = target_payment_id and idempotency_key = btrim(attempt_key);
  if found then return result; end if;
  if attempt_type in ('initialAuthorization', 'replacementAuthorization') then
    if payment.method <> 'card' then raise exception using errcode = '55000', message = 'Only Card payments can be authorized.'; end if;
    select count(*) into attempt_count from public.payment_attempts where payment_id = target_payment_id and type in ('initialAuthorization', 'replacementAuthorization');
    if attempt_count >= 2 then raise exception using errcode = '55000', message = 'Card authorization permits at most two attempts.'; end if;
  elsif attempt_type in ('capture', 'captureRetry') then
    select count(*) into attempt_count from public.payment_attempts where payment_id = target_payment_id and type in ('capture', 'captureRetry');
    if attempt_count >= 3 then raise exception using errcode = '55000', message = 'Capture permits at most three attempts.'; end if;
  end if;
  insert into public.payment_attempts (payment_id, type, requested_amount_fils, currency, idempotency_key, provider_name)
  values (target_payment_id, attempt_type, amount_fils, payment.currency, btrim(attempt_key), nullif(btrim(provider), '')) returning * into result;
  return result;
end;
$$;

create or replace function public.backend_complete_payment_attempt(target_attempt_id uuid, final_status public.payment_attempt_status, provider_reference text default null, failure_code text default null)
returns public.payment_attempts language plpgsql security definer set search_path = '' as $$
declare current_attempt public.payment_attempts%rowtype;
begin
  select * into current_attempt from public.payment_attempts where id = target_attempt_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Payment attempt was not found.'; end if;
  if current_attempt.type = 'refund' then raise exception using errcode = '55000', message = 'Refund attempts require their canonical Refund completion operation.'; end if;
  if current_attempt.status <> 'pending' then return current_attempt; end if;
  if final_status = 'pending' then raise exception using errcode = '22023', message = 'A payment attempt requires a terminal verified status.'; end if;
  perform set_config('ridex.complete_payment_attempt', 'on', true);
  update public.payment_attempts set status = final_status,
    provider_transaction_reference = coalesce(nullif(btrim(provider_reference), ''), provider_transaction_reference),
    sanitized_failure_code = nullif(btrim(failure_code), ''), completed_at = now(), verified_at = now()
  where id = current_attempt.id returning * into current_attempt;
  return current_attempt;
end;
$$;

create or replace function public.backend_record_refund_attempt(target_refund_id uuid, attempt_key text, provider text default null)
returns public.payment_attempts language plpgsql security definer set search_path = '' as $$
declare current_refund public.refunds%rowtype; payment public.payments%rowtype; result public.payment_attempts%rowtype; attempt_count integer;
begin
  select * into current_refund from public.refunds where id = target_refund_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Refund was not found.'; end if;
  select * into payment from public.payments where id = current_refund.payment_id for update;
  if payment.method <> 'card' or payment.card_status <> 'refundPending' then raise exception using errcode = '55000', message = 'Refund attempts require a pending Card refund.'; end if;
  if current_refund.status <> 'pending' or current_refund.amount_fils <> payment.final_amount_fils or current_refund.currency <> 'JOD' or payment.currency <> 'JOD' then raise exception using errcode = '55000', message = 'Refund must match the full pending Payment amount in JOD.'; end if;
  select * into result from public.payment_attempts where payment_id = payment.id and idempotency_key = btrim(attempt_key);
  if found then
    if result.refund_id is distinct from current_refund.id then raise exception using errcode = '55000', message = 'Payment attempt idempotency key is already associated with another operation.'; end if;
    return result;
  end if;
  select count(*) into attempt_count from public.payment_attempts where refund_id = current_refund.id;
  if attempt_count >= 3 then raise exception using errcode = '55000', message = 'Refund permits at most three attempts.'; end if;
  insert into public.payment_attempts (payment_id, refund_id, type, requested_amount_fils, currency, idempotency_key, provider_name)
  values (payment.id, current_refund.id, 'refund', current_refund.amount_fils, current_refund.currency, btrim(attempt_key), nullif(btrim(provider), '')) returning * into result;
  return result;
end;
$$;

create or replace function public.backend_complete_refund_attempt(target_attempt_id uuid, final_status public.payment_attempt_status, provider_reference text default null, failure_code text default null)
returns public.payment_attempts language plpgsql security definer set search_path = '' as $$
declare current_attempt public.payment_attempts%rowtype; current_refund public.refunds%rowtype; payment public.payments%rowtype;
begin
  select * into current_attempt from public.payment_attempts where id = target_attempt_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Payment attempt was not found.'; end if;
  if current_attempt.type <> 'refund' or current_attempt.refund_id is null then raise exception using errcode = '55000', message = 'A canonical Refund attempt is required.'; end if;
  if current_attempt.status <> 'pending' then return current_attempt; end if;
  if final_status = 'pending' then raise exception using errcode = '22023', message = 'A Refund attempt requires a terminal verified status.'; end if;
  select * into current_refund from public.refunds where id = current_attempt.refund_id for update;
  select * into payment from public.payments where id = current_refund.payment_id for update;
  if current_refund.status <> 'pending' or payment.method <> 'card' or payment.card_status <> 'refundPending'
    or current_attempt.payment_id <> payment.id or current_attempt.requested_amount_fils <> payment.final_amount_fils
    or current_attempt.currency <> 'JOD' or current_refund.amount_fils <> payment.final_amount_fils or current_refund.currency <> payment.currency then
    raise exception using errcode = '55000', message = 'Refund attempt no longer matches its pending Payment.';
  end if;
  if final_status = 'succeeded' and nullif(btrim(provider_reference), '') is null then raise exception using errcode = '22023', message = 'A verified Refund requires a provider reference.'; end if;
  perform set_config('ridex.complete_payment_attempt', 'on', true);
  update public.payment_attempts set status = final_status,
    provider_transaction_reference = coalesce(nullif(btrim(provider_reference), ''), provider_transaction_reference),
    sanitized_failure_code = nullif(btrim(failure_code), ''), completed_at = now(), verified_at = now()
  where id = current_attempt.id returning * into current_attempt;
  if final_status = 'succeeded' then
    update public.refunds set status = 'succeeded', provider_name = current_attempt.provider_name,
      provider_refund_reference = current_attempt.provider_transaction_reference, sanitized_failure_code = null, completed_at = current_attempt.completed_at
    where id = current_refund.id;
    update public.payments set card_status = 'refunded', refunded_at = current_attempt.completed_at where id = payment.id;
    perform private.write_audit_record(null, 'payment.refund_completed', payment.rider_id, null,
      jsonb_build_object('payment_id', payment.id, 'refund_id', current_refund.id),
      jsonb_build_object('attempt_id', current_attempt.id, 'provider_reference', current_attempt.provider_transaction_reference));
  else
    update public.refunds set sanitized_failure_code = nullif(btrim(failure_code), '') where id = current_refund.id;
    perform private.write_audit_record(null, 'payment.refund_attempt_failed', payment.rider_id, null,
      jsonb_build_object('payment_id', payment.id, 'refund_id', current_refund.id),
      jsonb_build_object('attempt_id', current_attempt.id, 'status', final_status, 'failure_code', nullif(btrim(failure_code), '')));
  end if;
  return current_attempt;
end;
$$;

create or replace function public.backend_transition_payment(target_payment_id uuid, expected_version integer, next_cash_status public.cash_payment_status default null, next_card_status public.card_payment_status default null)
returns public.payments language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype; trip public.trips%rowtype;
begin
  select * into payment from public.payments where id = target_payment_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  if payment.version <> expected_version then raise exception using errcode = '40001', message = 'Payment version is stale.'; end if;
  select * into trip from public.trips where id = payment.trip_id for share;
  if payment.method = 'cash' then
    if next_card_status is not null or next_cash_status not in ('paid', 'cancelled') or (next_cash_status = 'paid' and trip.status <> 'completed') then raise exception using errcode = '55000', message = 'Invalid Cash payment transition.'; end if;
    update public.payments set cash_status = next_cash_status, paid_at = case when next_cash_status = 'paid' then now() else paid_at end, cancelled_at = case when next_cash_status = 'cancelled' then now() else cancelled_at end where id = payment.id returning * into payment;
  else
    if next_cash_status is not null or next_card_status is null or next_card_status in ('refundPending', 'refunded') then raise exception using errcode = '55000', message = 'Invalid Card payment transition.'; end if;
    if not ((payment.card_status = 'cardPaymentPending' and next_card_status in ('cardPaymentAuthorized', 'cardPaymentFailed', 'paymentCancelled')) or
      (payment.card_status = 'cardPaymentAuthorized' and next_card_status in ('cardPaymentPending', 'cardPaymentSucceeded', 'cardPaymentFailed', 'paymentCancelled')) or
      (payment.card_status = 'cardPaymentFailed' and next_card_status in ('cardPaymentPending', 'cardPaymentSucceeded'))) then raise exception using errcode = '55000', message = 'Invalid Card payment transition.'; end if;
    if next_card_status = 'cardPaymentAuthorized' and not exists (select 1 from public.payment_attempts where payment_id = payment.id and type in ('initialAuthorization', 'replacementAuthorization') and status = 'succeeded' and verified_at = completed_at and completed_at >= created_at and completed_at <= created_at + interval '2 minutes') then raise exception using errcode = '55000', message = 'Card authorization requires a verified two-minute authorization attempt.'; end if;
    if next_card_status = 'cardPaymentSucceeded' and (trip.status <> 'completed' or not exists (select 1 from public.payment_attempts where payment_id = payment.id and type in ('capture', 'captureRetry') and status = 'succeeded')) then raise exception using errcode = '55000', message = 'Card success requires a completed Trip and verified Capture.'; end if;
    update public.payments set card_status = next_card_status, authorized_at = case when next_card_status = 'cardPaymentAuthorized' then now() else authorized_at end, paid_at = case when next_card_status = 'cardPaymentSucceeded' then now() else paid_at end, cancelled_at = case when next_card_status = 'paymentCancelled' then now() else cancelled_at end where id = payment.id returning * into payment;
  end if;
  perform private.write_audit_record(null, 'payment.state_transition', payment.rider_id, null, jsonb_build_object('payment_id', payment.id, 'version', expected_version), jsonb_build_object('version', payment.version, 'cash_status', payment.cash_status, 'card_status', payment.card_status));
  return payment;
end;
$$;

revoke all on function public.backend_record_refund_attempt(uuid, text, text), public.backend_complete_refund_attempt(uuid, public.payment_attempt_status, text, text) from public, anon, authenticated, service_role;
grant execute on function public.backend_record_refund_attempt(uuid, text, text), public.backend_complete_refund_attempt(uuid, public.payment_attempt_status, text, text) to service_role;

commit;
