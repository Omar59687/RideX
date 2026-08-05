begin;

create or replace function private.contains_payment_card_data(value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(regexp_replace(value, '[^0-9]', '', 'g') ~ '[0-9]{13,19}', false)
    or coalesce(value ~* '(cvv|cvc|card[[:space:]]*verification|security[[:space:]]*code)[^0-9]{0,20}[0-9]{3,4}', false);
$$;

create or replace function private.is_safe_notification_payload(value jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) = 'object'
    and private.is_safe_json_content(value - 'destination', 512)
    and (
      value = '{}'::jsonb
      or (value ? 'trip_id' and value - 'trip_id' = '{}'::jsonb and (value ->> 'trip_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      or (value ? 'payment_id' and value - 'payment_id' = '{}'::jsonb and (value ->> 'payment_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      or (value ? 'receipt_id' and value - 'receipt_id' = '{}'::jsonb and (value ->> 'receipt_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      or (value ? 'help_request_id' and value - 'help_request_id' = '{}'::jsonb and (value ->> 'help_request_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      or (value = '{"destination":"notifications"}'::jsonb)
      or (value ->> 'destination' = 'trip' and value - 'destination' - 'trip_id' = '{}'::jsonb and (value ->> 'trip_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      or (value ->> 'destination' = 'payment' and value - 'destination' - 'payment_id' = '{}'::jsonb and (value ->> 'payment_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      or (value ->> 'destination' = 'receipt' and value - 'destination' - 'receipt_id' = '{}'::jsonb and (value ->> 'receipt_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      or (value ->> 'destination' = 'help_request' and value - 'destination' - 'help_request_id' = '{}'::jsonb and (value ->> 'help_request_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    );
$$;

create or replace function public.user_create_help_request(
  requested_category_code text, requested_subject text, requested_message text,
  requested_priority public.help_request_priority default 'normal', target_trip_id uuid default null,
  target_payment_id uuid default null, requested_idempotency_key text default null
)
returns public.help_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  result public.help_requests%rowtype;
  normalized_category text := btrim(requested_category_code);
  normalized_subject text := btrim(requested_subject);
  normalized_message text := btrim(requested_message);
  normalized_key text := nullif(btrim(requested_idempotency_key), '');
begin
  caller_id := private.require_nonblocked_rider_or_driver();
  if private.contains_payment_card_data(normalized_subject)
    or private.contains_payment_card_data(normalized_message) then
    raise exception using errcode = '22023', message = 'HelpRequest content must not include payment card data.';
  end if;
  if target_trip_id is not null and not exists (
    select 1 from public.trips where id = target_trip_id and (rider_id = caller_id or driver_id = caller_id)
  ) then raise exception using errcode = '42501', message = 'Help request Trip must belong to the requester.'; end if;
  if target_payment_id is not null and not exists (
    select 1 from public.payments where id = target_payment_id and rider_id = caller_id
  ) then raise exception using errcode = '42501', message = 'Help request Payment must belong to the requester.'; end if;
  if target_trip_id is not null and target_payment_id is not null and not exists (
    select 1 from public.payments where id = target_payment_id and trip_id = target_trip_id
  ) then raise exception using errcode = '22023', message = 'Help request Payment must match its Trip.'; end if;
  insert into public.help_requests (requester_user_id, category_code, subject, message, priority, trip_id, payment_id, idempotency_key)
  values (caller_id, normalized_category, normalized_subject, normalized_message, requested_priority,
    target_trip_id, target_payment_id, normalized_key)
  on conflict (requester_user_id, idempotency_key) where idempotency_key is not null do nothing returning * into result;
  if not found then
    select * into result from public.help_requests
    where requester_user_id = caller_id and idempotency_key = normalized_key for share;
    if result.category_code <> normalized_category or result.subject <> normalized_subject
      or result.message <> normalized_message or result.priority <> requested_priority
      or result.trip_id is distinct from target_trip_id or result.payment_id is distinct from target_payment_id then
      perform private.write_audit_record(caller_id, 'help_request.idempotency_payload_mismatch', caller_id, null,
        jsonb_build_object('help_request_id', result.id), jsonb_build_object('help_request_id', result.id));
      raise exception using errcode = '55000', message = 'HelpRequest retry does not match the existing HelpRequest.';
    end if;
  else
    perform private.write_audit_record(caller_id, 'help_request.created', caller_id, null,
      '{}'::jsonb, jsonb_build_object('help_request_id', result.id, 'category_code', result.category_code));
  end if;
  return result;
end;
$$;

create or replace function public.admin_resolve_help_request(
  target_help_request_id uuid, expected_version integer, requested_resolution_summary text
)
returns public.help_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  result public.help_requests%rowtype;
  normalized_summary text := btrim(requested_resolution_summary);
begin
  caller_id := private.require_nonblocked_admin();
  if expected_version is null or expected_version < 1 then raise exception using errcode = '22023', message = 'A positive expected version is required.'; end if;
  if char_length(normalized_summary) not between 1 and 1000 then raise exception using errcode = '22023', message = 'A bounded resolution summary is required.'; end if;
  if private.contains_payment_card_data(normalized_summary) then raise exception using errcode = '22023', message = 'HelpRequest resolution must not include payment card data.'; end if;
  select * into result from public.help_requests where id = target_help_request_id for update;
  if not found or result.status <> 'assigned' then raise exception using errcode = '55000', message = 'Only assigned HelpRequests can be resolved.'; end if;
  if result.version <> expected_version then raise exception using errcode = '40001', message = 'Help request version is stale.'; end if;
  update public.help_requests set status = 'resolved', resolution_summary = normalized_summary, resolved_at = now()
    where id = result.id returning * into result;
  perform private.write_audit_record(caller_id, 'help_request.resolved', result.requester_user_id, null,
    jsonb_build_object('help_request_id', result.id, 'version', expected_version), jsonb_build_object('version', result.version));
  return result;
end;
$$;

create or replace function private.require_finance_reader(target_rider_id uuid, target_driver_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare caller public.users%rowtype;
begin
  select * into caller from public.users where id = auth.uid();
  if not found or caller.is_blocked then raise exception using errcode = '42501', message = 'A non-blocked finance participant is required.'; end if;
  if caller.role = 'admin' or (caller.role = 'rider' and caller.id = target_rider_id)
    or (target_driver_id is not null and caller.role = 'driver' and caller.id = target_driver_id) then return; end if;
  raise exception using errcode = '42501', message = 'Finance data does not belong to this user.';
end;
$$;

create function public.user_payment_summary(target_payment_id uuid)
returns table (id uuid, trip_id uuid, method public.payment_method, amount_fils integer, currency text, cash_status public.cash_payment_status, card_status public.card_payment_status, card_brand text, card_last_four text, authorized_at timestamptz, paid_at timestamptz, cancelled_at timestamptz, refunded_at timestamptz, failure_code text)
language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype; trip_driver_id uuid;
begin
  select * into payment from public.payments as source_payment where source_payment.id = target_payment_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  select source_trip.driver_id into trip_driver_id from public.trips as source_trip where source_trip.id = payment.trip_id;
  perform private.require_finance_reader(payment.rider_id, trip_driver_id);
  return query select payment.id, payment.trip_id, payment.method, payment.final_amount_fils, payment.currency, payment.cash_status, payment.card_status, payment.card_brand, payment.card_last_four, payment.authorized_at, payment.paid_at, payment.cancelled_at, payment.refunded_at, payment.sanitized_failure_code;
end;
$$;

create function public.user_trip_payment_summary(target_trip_id uuid)
returns table (id uuid, trip_id uuid, method public.payment_method, amount_fils integer, currency text, cash_status public.cash_payment_status, card_status public.card_payment_status, card_brand text, card_last_four text, authorized_at timestamptz, paid_at timestamptz, cancelled_at timestamptz, refunded_at timestamptz, failure_code text)
language plpgsql security definer set search_path = '' as $$
declare payment_id uuid;
begin
  select source_payment.id into payment_id from public.payments as source_payment where source_payment.trip_id = target_trip_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  return query select * from public.user_payment_summary(payment_id);
end;
$$;

create function public.user_payment_attempt_summaries(target_payment_id uuid)
returns table (id uuid, type public.payment_attempt_type, status public.payment_attempt_status, requested_amount_fils integer, currency text, failure_code text, created_at timestamptz, completed_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype; trip_driver_id uuid;
begin
  select * into payment from public.payments as source_payment where source_payment.id = target_payment_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  select source_trip.driver_id into trip_driver_id from public.trips as source_trip where source_trip.id = payment.trip_id;
  perform private.require_finance_reader(payment.rider_id, trip_driver_id);
  return query select attempts.id, attempts.type, attempts.status, attempts.requested_amount_fils, attempts.currency, attempts.sanitized_failure_code, attempts.created_at, attempts.completed_at from public.payment_attempts attempts where attempts.payment_id = payment.id order by attempts.created_at, attempts.id;
end;
$$;

create function public.user_refund_statuses(target_payment_id uuid)
returns table (id uuid, amount_fils integer, currency text, status public.payment_attempt_status, reason_code text, failure_code text, created_at timestamptz, completed_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype; trip_driver_id uuid;
begin
  select * into payment from public.payments as source_payment where source_payment.id = target_payment_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  select source_trip.driver_id into trip_driver_id from public.trips as source_trip where source_trip.id = payment.trip_id;
  perform private.require_finance_reader(payment.rider_id, trip_driver_id);
  return query select refunds.id, refunds.amount_fils, refunds.currency, refunds.status, refunds.reason_code, refunds.sanitized_failure_code, refunds.created_at, refunds.completed_at from public.refunds where refunds.payment_id = payment.id order by refunds.created_at, refunds.id;
end;
$$;

create function public.user_receipt_summary(target_receipt_id uuid)
returns table (id uuid, receipt_number text, trip_id uuid, amount_paid_fils integer, currency text, payment_method public.payment_method, card_brand text, card_last_four text, issued_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare receipt public.receipts%rowtype; trip public.trips%rowtype;
begin
  select * into receipt from public.receipts as source_receipt where source_receipt.id = target_receipt_id;
  if not found then raise exception using errcode = 'P0002', message = 'Receipt was not found.'; end if;
  select * into trip from public.trips as source_trip where source_trip.id = receipt.trip_id;
  perform private.require_finance_reader(trip.rider_id, trip.driver_id);
  return query select receipt.id, receipt.receipt_number, receipt.trip_id, receipt.amount_paid_fils, receipt.currency, receipt.payment_method, receipt.card_brand, receipt.card_last_four, receipt.issued_at;
end;
$$;

create function public.user_trip_receipt_summary(target_trip_id uuid)
returns table (id uuid, receipt_number text, trip_id uuid, amount_paid_fils integer, currency text, payment_method public.payment_method, card_brand text, card_last_four text, issued_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare receipt_id uuid;
begin
  select source_receipt.id into receipt_id from public.receipts as source_receipt where source_receipt.trip_id = target_trip_id;
  if not found then raise exception using errcode = 'P0002', message = 'Receipt was not found.'; end if;
  return query select * from public.user_receipt_summary(receipt_id);
end;
$$;

drop policy if exists payments_rider_or_admin_select on public.payments;
drop policy if exists payment_attempts_rider_or_admin_select on public.payment_attempts;
drop policy if exists refunds_rider_or_admin_select on public.refunds;
drop policy if exists receipts_participant_or_admin_select on public.receipts;
revoke select on table public.payments, public.payment_attempts, public.refunds, public.receipts from authenticated;
-- Preserve the baseline grant matrix for clients that prepare finance queries,
-- while the removed SELECT policies make every whole-row result set empty.
grant select on table public.payments, public.payment_attempts, public.refunds, public.receipts to authenticated;

revoke all on function private.contains_payment_card_data(text), private.require_finance_reader(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.user_payment_summary(uuid), public.user_trip_payment_summary(uuid), public.user_payment_attempt_summaries(uuid), public.user_refund_statuses(uuid), public.user_receipt_summary(uuid), public.user_trip_receipt_summary(uuid) from public, anon, authenticated, service_role;
grant execute on function public.user_payment_summary(uuid), public.user_trip_payment_summary(uuid), public.user_payment_attempt_summaries(uuid), public.user_refund_statuses(uuid), public.user_receipt_summary(uuid), public.user_trip_receipt_summary(uuid) to authenticated;

commit;
