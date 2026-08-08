begin;

create or replace function public.backend_lock_fare_quote(
  target_fare_quote_id uuid,
  expected_booking_version integer,
  expected_quote_version integer
)
returns public.fare_quotes
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_quote public.fare_quotes%rowtype;
  current_booking public.booking_requests%rowtype;
  ordered_stops jsonb;
begin
  if expected_booking_version is null or expected_booking_version < 1
    or expected_quote_version is null or expected_quote_version < 1 then
    raise exception using errcode = '22023', message = 'Positive expected versions are required.';
  end if;
  select * into target_quote from public.fare_quotes
  where id = target_fare_quote_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'FareQuote was not found.'; end if;
  select * into current_booking from public.booking_requests
  where id = target_quote.booking_request_id for update;
  if current_booking.status <> 'draft' then
    raise exception using errcode = '55000', message = 'A FareQuote can be locked only for a draft booking.';
  end if;
  if current_booking.version <> expected_booking_version then
    raise exception using errcode = '40001', message = 'Booking version is stale.';
  end if;
  if target_quote.quote_version <> expected_quote_version then
    raise exception using errcode = '40001', message = 'FareQuote version is stale.';
  end if;
  if target_quote.status <> 'calculated' or target_quote.expires_at <= now() then
    raise exception using errcode = '55000', message = 'Only an unexpired calculated FareQuote can be locked.';
  end if;
  ordered_stops := private.booking_ordered_stops(current_booking.id);
  if target_quote.pickup <> current_booking.pickup
    or target_quote.destination <> current_booking.destination
    or target_quote.ordered_stops <> ordered_stops
    or target_quote.vehicle_type_code <> current_booking.vehicle_type_code then
    raise exception using errcode = '40001', message = 'FareQuote inputs are stale.';
  end if;
  update public.fare_quotes set status = 'superseded', superseded_at = now()
  where booking_request_id = current_booking.id and status = 'locked';
  update public.fare_quotes set status = 'locked', locked_at = now()
  where id = target_quote.id returning * into target_quote;
  update public.booking_requests set fare_quote_id = target_quote.id
  where id = current_booking.id;
  return target_quote;
end;
$$;

create or replace function public.backend_price_trip_change_request(
  target_request_id uuid,
  expected_request_version integer,
  route_distance_meters integer,
  route_duration_seconds integer,
  route_geometry_reference text default null
)
returns public.fare_adjustments
language plpgsql
security definer
set search_path = ''
as $$
begin
  if expected_request_version is null or expected_request_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  perform target_request_id, route_distance_meters, route_duration_seconds,
    route_geometry_reference;
  raise exception using errcode = '0A000',
    message = 'Full-route Cash change pricing is retired; use the remaining-route pricing operation.';
end;
$$;

create function public.backend_price_trip_change_request_remaining(
  target_request_id uuid,
  expected_request_version integer,
  new_remaining_distance_meters integer,
  new_remaining_duration_seconds integer,
  original_remaining_distance_meters integer,
  original_remaining_duration_seconds integer,
  route_geometry_reference text default null
)
returns public.fare_adjustments
language sql
security definer
set search_path = ''
as $$
  select private.backend_price_trip_change_request_remaining(
    target_request_id, expected_request_version,
    new_remaining_distance_meters, new_remaining_duration_seconds,
    original_remaining_distance_meters, original_remaining_duration_seconds,
    route_geometry_reference
  );
$$;

alter table public.payment_attempts
  add column attempt_sequence bigint;

with ordered_attempts as (
  select id, row_number() over (order by created_at, id)::bigint as sequence_value
  from public.payment_attempts
)
update public.payment_attempts as attempts
set attempt_sequence = ordered_attempts.sequence_value
from ordered_attempts
where attempts.id = ordered_attempts.id;

alter table public.payment_attempts
  alter column attempt_sequence set not null,
  alter column attempt_sequence add generated always as identity;

select setval(
  pg_get_serial_sequence('public.payment_attempts', 'attempt_sequence'),
  (select coalesce(max(attempt_sequence), 0) + 1 from public.payment_attempts),
  false
);

create index payment_attempts_payment_attempt_sequence_idx
  on public.payment_attempts (payment_id, attempt_sequence desc);
create index payment_attempts_refund_attempt_sequence_idx
  on public.payment_attempts (refund_id, attempt_sequence desc)
  where refund_id is not null;

create or replace function private.has_current_verified_card_authorization(target_payment_id uuid)
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
  order by attempt_sequence desc
  limit 1;

  return found
    and current_authorization.status = 'succeeded'
    and current_authorization.verified_at = current_authorization.completed_at
    and current_authorization.completed_at >= current_authorization.created_at
    and current_authorization.completed_at <= current_authorization.created_at + interval '2 minutes'
    and current_authorization.requested_amount_fils = payment.authorized_amount_fils
    and current_authorization.currency = payment.currency
    and not exists (
      select 1 from public.payment_attempts as void_attempt
      where void_attempt.payment_id = payment.id
        and void_attempt.type = 'voidAuthorization'
        and void_attempt.status = 'succeeded'
        and void_attempt.verified_at = void_attempt.completed_at
        and void_attempt.attempt_sequence > current_authorization.attempt_sequence
    );
end;
$$;

create or replace function private.require_verified_card_progression(target_trip_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare current_payment public.payments%rowtype;
begin
  current_payment := private.ensure_trip_payment(target_trip_id);
  if current_payment.method = 'card' and (
    current_payment.card_status <> 'cardPaymentAuthorized'
    or not private.has_current_verified_card_authorization(current_payment.id)
  ) then
    raise exception using errcode = '55000',
      message = 'Card Trip progression requires a verified authorized Payment.';
  end if;
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
declare payment public.payments%rowtype; trip public.trips%rowtype;
begin
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  select * into payment from public.payments where id = target_payment_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  if payment.version <> expected_version then raise exception using errcode = '40001', message = 'Payment version is stale.'; end if;
  select * into trip from public.trips where id = payment.trip_id for share;
  if payment.method = 'cash' then
    if next_card_status is not null or next_cash_status not in ('paid', 'cancelled')
      or (next_cash_status = 'paid' and trip.status <> 'completed') then
      raise exception using errcode = '55000', message = 'Invalid Cash payment transition.';
    end if;
    update public.payments set cash_status = next_cash_status,
      paid_at = case when next_cash_status = 'paid' then now() else paid_at end,
      cancelled_at = case when next_cash_status = 'cancelled' then now() else cancelled_at end
    where id = payment.id returning * into payment;
  else
    if next_cash_status is not null or next_card_status is null
      or next_card_status in ('refundPending', 'refunded') then
      raise exception using errcode = '55000', message = 'Invalid Card payment transition.';
    end if;
    if not (
      (payment.card_status = 'cardPaymentPending' and next_card_status in ('cardPaymentAuthorized', 'cardPaymentFailed', 'paymentCancelled'))
      or (payment.card_status = 'cardPaymentAuthorized' and next_card_status in ('cardPaymentPending', 'cardPaymentSucceeded', 'cardPaymentFailed', 'paymentCancelled'))
      or (payment.card_status = 'cardPaymentFailed' and next_card_status in ('cardPaymentPending', 'cardPaymentSucceeded'))
    ) then raise exception using errcode = '55000', message = 'Invalid Card payment transition.'; end if;
    if next_card_status = 'cardPaymentAuthorized'
      and not private.has_current_verified_card_authorization(payment.id) then
      raise exception using errcode = '55000',
        message = 'Card authorization requires a verified two-minute authorization attempt.';
    end if;
    if next_card_status = 'cardPaymentSucceeded' and (
      trip.status <> 'completed' or not exists (
        select 1 from public.payment_attempts where payment_id = payment.id
          and type in ('capture', 'captureRetry') and status = 'succeeded'
      )
    ) then raise exception using errcode = '55000', message = 'Card success requires a completed Trip and verified Capture.'; end if;
    update public.payments set card_status = next_card_status,
      authorized_at = case when next_card_status = 'cardPaymentAuthorized' then now() else authorized_at end,
      paid_at = case when next_card_status = 'cardPaymentSucceeded' then now() else paid_at end,
      cancelled_at = case when next_card_status = 'paymentCancelled' then now() else cancelled_at end
    where id = payment.id returning * into payment;
  end if;
  perform private.write_audit_record(null, 'payment.state_transition', payment.rider_id, null,
    jsonb_build_object('payment_id', payment.id, 'version', expected_version),
    jsonb_build_object('version', payment.version, 'cash_status', payment.cash_status, 'card_status', payment.card_status));
  return payment;
end;
$$;

create or replace function public.backend_record_refund_attempt(
  target_refund_id uuid, attempt_key text, provider text default null
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
  if normalized_key is null then raise exception using errcode = '22023', message = 'A Refund attempt idempotency key is required.'; end if;
  select * into current_refund from public.refunds where id = target_refund_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Refund was not found.'; end if;
  select * into payment from public.payments where id = current_refund.payment_id for update;
  if payment.method <> 'card' or payment.card_status <> 'refundPending' then
    raise exception using errcode = '55000', message = 'Refund attempts require a pending Card refund.';
  end if;
  if current_refund.status <> 'pending' or current_refund.amount_fils <> payment.final_amount_fils
    or current_refund.currency <> payment.currency then
    raise exception using errcode = '55000', message = 'Refund must match the full pending Payment amount in JOD.';
  end if;
  select * into result from public.payment_attempts
  where payment_id = payment.id and idempotency_key = normalized_key;
  if found then
    if result.refund_id = current_refund.id and result.type = 'refund'
      and result.payment_id = payment.id
      and result.requested_amount_fils = current_refund.amount_fils
      and result.currency = current_refund.currency
      and result.provider_name is not distinct from normalized_provider then
      return result;
    end if;
    raise exception using errcode = '55000',
      message = 'Refund attempt idempotency key is already associated with different operation data.';
  end if;
  select count(*) into attempt_count from public.payment_attempts where refund_id = current_refund.id;
  if attempt_count >= 3 then raise exception using errcode = '55000', message = 'Refund permits at most three attempts.'; end if;
  select * into prior_attempt from public.payment_attempts where refund_id = current_refund.id
  order by attempt_sequence desc limit 1;
  if found and prior_attempt.status not in ('failed', 'cancelled') then
    raise exception using errcode = '55000', message = 'A Refund retry requires the preceding attempt to complete unsuccessfully.';
  end if;
  insert into public.payment_attempts (
    payment_id, refund_id, type, requested_amount_fils, currency, idempotency_key, provider_name
  ) values (
    payment.id, current_refund.id, 'refund', current_refund.amount_fils,
    current_refund.currency, normalized_key, normalized_provider
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.backend_complete_refund_attempt(
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
  current_refund public.refunds%rowtype;
  payment public.payments%rowtype;
  normalized_reference text := nullif(btrim(provider_reference), '');
  normalized_failure text := nullif(btrim(failure_code), '');
begin
  if final_status is null or final_status = 'pending' then
    raise exception using errcode = '22023', message = 'A Refund attempt requires a terminal verified status.';
  end if;
  select * into current_attempt from public.payment_attempts where id = target_attempt_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Payment attempt was not found.'; end if;
  if current_attempt.type <> 'refund' or current_attempt.refund_id is null then
    raise exception using errcode = '55000', message = 'A canonical Refund attempt is required.';
  end if;
  if current_attempt.status <> 'pending' then
    if current_attempt.status = final_status
      and current_attempt.provider_transaction_reference is not distinct from normalized_reference
      and current_attempt.sanitized_failure_code is not distinct from normalized_failure then
      return current_attempt;
    end if;
    raise exception using errcode = '55000',
      message = 'A terminal Refund attempt cannot be completed with different data.';
  end if;
  select * into current_refund from public.refunds where id = current_attempt.refund_id for update;
  select * into payment from public.payments where id = current_refund.payment_id for update;
  if current_refund.status <> 'pending' or payment.method <> 'card'
    or payment.card_status <> 'refundPending' or current_attempt.payment_id <> payment.id
    or current_attempt.requested_amount_fils <> current_refund.amount_fils
    or current_attempt.currency <> current_refund.currency
    or current_refund.amount_fils <> payment.final_amount_fils
    or current_refund.currency <> payment.currency then
    raise exception using errcode = '55000', message = 'Refund attempt no longer matches its pending Payment.';
  end if;
  if final_status = 'succeeded' and normalized_reference is null then
    raise exception using errcode = '22023', message = 'A verified Refund requires a provider reference.';
  end if;
  perform set_config('ridex.complete_payment_attempt', 'on', true);
  update public.payment_attempts set status = final_status,
    provider_transaction_reference = normalized_reference,
    sanitized_failure_code = normalized_failure, completed_at = now(), verified_at = now()
  where id = current_attempt.id returning * into current_attempt;
  if final_status = 'succeeded' then
    update public.refunds set status = 'succeeded', provider_name = current_attempt.provider_name,
      provider_refund_reference = current_attempt.provider_transaction_reference,
      sanitized_failure_code = null, completed_at = current_attempt.completed_at
    where id = current_refund.id;
    update public.payments set card_status = 'refunded', refunded_at = current_attempt.completed_at
    where id = payment.id;
    perform private.write_audit_record(null, 'payment.refund_completed', payment.rider_id, null,
      jsonb_build_object('payment_id', payment.id, 'refund_id', current_refund.id),
      jsonb_build_object('attempt_id', current_attempt.id, 'provider_reference', current_attempt.provider_transaction_reference));
  else
    update public.refunds set sanitized_failure_code = normalized_failure where id = current_refund.id;
    perform private.write_audit_record(null, 'payment.refund_attempt_failed', payment.rider_id, null,
      jsonb_build_object('payment_id', payment.id, 'refund_id', current_refund.id),
      jsonb_build_object('attempt_id', current_attempt.id, 'status', final_status, 'failure_code', normalized_failure));
  end if;
  return current_attempt;
end;
$$;

create or replace function private.is_safe_notification_payload(value jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_typeof(value) = 'object'
    and private.is_safe_json_content(value - 'destination', 512)
    and (
      value = '{"destination":"notifications"}'::jsonb
      or (value ->> 'destination' = 'trip' and value - 'destination' - 'trip_id' = '{}'::jsonb
        and (value ->> 'trip_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      or (value ->> 'destination' = 'payment' and value - 'destination' - 'payment_id' = '{}'::jsonb
        and (value ->> 'payment_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      or (value ->> 'destination' = 'receipt' and value - 'destination' - 'receipt_id' = '{}'::jsonb
        and (value ->> 'receipt_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      or (value ->> 'destination' = 'help_request' and value - 'destination' - 'help_request_id' = '{}'::jsonb
        and (value ->> 'help_request_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    ), false);
$$;

create or replace function private.enforce_notification_reference_authorization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare destination text := new.safe_payload ->> 'destination'; reference_id uuid;
begin
  if not private.is_safe_notification_payload(new.safe_payload) then
    raise exception using errcode = '23514', message = 'Notification payload must use an allowlisted destination and identifier.';
  end if;
  if destination = 'notifications' then return new; end if;
  if destination = 'trip' then
    reference_id := (new.safe_payload ->> 'trip_id')::uuid;
    if not exists (select 1 from public.trips where id = reference_id
      and new.recipient_user_id in (rider_id, driver_id)) then
      raise exception using errcode = '42501', message = 'Notification Trip is not authorized for its recipient.';
    end if;
  elsif destination = 'payment' then
    reference_id := (new.safe_payload ->> 'payment_id')::uuid;
    if not exists (select 1 from public.payments where id = reference_id
      and rider_id = new.recipient_user_id) then
      raise exception using errcode = '42501', message = 'Notification Payment is not authorized for its recipient.';
    end if;
  elsif destination = 'receipt' then
    reference_id := (new.safe_payload ->> 'receipt_id')::uuid;
    if not exists (
      select 1 from public.receipts as receipt
      join public.trips as trip on trip.id = receipt.trip_id
      where receipt.id = reference_id
        and new.recipient_user_id in (trip.rider_id, trip.driver_id)
    ) then raise exception using errcode = '42501', message = 'Notification Receipt is not authorized for its recipient.'; end if;
  elsif destination = 'help_request' then
    reference_id := (new.safe_payload ->> 'help_request_id')::uuid;
    if not exists (select 1 from public.help_requests where id = reference_id
      and new.recipient_user_id in (requester_user_id, assigned_admin_id)) then
      raise exception using errcode = '42501', message = 'Notification HelpRequest is not authorized for its recipient.';
    end if;
  end if;
  return new;
end;
$$;

create trigger notifications_enforce_reference_authorization
before insert or update of recipient_user_id, safe_payload on public.notifications
for each row execute function private.enforce_notification_reference_authorization();

revoke all on function private.has_current_verified_card_authorization(uuid),
  private.enforce_notification_reference_authorization(),
  private.backend_price_trip_change_request_remaining(uuid, integer, integer, integer, integer, integer, text)
from public, anon, authenticated, service_role;

revoke all on function public.backend_price_trip_change_request(uuid, integer, integer, integer, text)
from public, anon, authenticated, service_role;
grant execute on function public.backend_price_trip_change_request(uuid, integer, integer, integer, text)
to service_role;
revoke all on function public.backend_price_trip_change_request_remaining(uuid, integer, integer, integer, integer, integer, text)
from public, anon, authenticated, service_role;
grant execute on function public.backend_price_trip_change_request_remaining(uuid, integer, integer, integer, integer, integer, text)
to service_role;

commit;
