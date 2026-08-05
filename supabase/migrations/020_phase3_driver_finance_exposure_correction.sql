begin;

create or replace function private.require_finance_reader(target_rider_id uuid, target_driver_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare caller public.users%rowtype;
begin
  select * into caller from public.users where id = auth.uid();
  if not found or caller.is_blocked then
    raise exception using errcode = '42501', message = 'A non-blocked finance participant is required.';
  end if;
  if caller.role = 'admin' or (caller.role = 'rider' and caller.id = target_rider_id) then return; end if;
  raise exception using errcode = '42501', message = 'Finance data does not belong to this user.';
end;
$$;

create or replace function private.require_receipt_reader(target_rider_id uuid, target_driver_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare caller public.users%rowtype;
begin
  select * into caller from public.users where id = auth.uid();
  if not found or caller.is_blocked then
    raise exception using errcode = '42501', message = 'A non-blocked finance participant is required.';
  end if;
  if caller.role = 'admin' or (caller.role = 'rider' and caller.id = target_rider_id)
    or (caller.role = 'driver' and caller.id = target_driver_id) then return; end if;
  raise exception using errcode = '42501', message = 'Finance data does not belong to this user.';
end;
$$;

create or replace function public.user_payment_summary(target_payment_id uuid)
returns table (id uuid, trip_id uuid, method public.payment_method, amount_fils integer, currency text, cash_status public.cash_payment_status, card_status public.card_payment_status, card_brand text, card_last_four text, authorized_at timestamptz, paid_at timestamptz, cancelled_at timestamptz, refunded_at timestamptz, failure_code text)
language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype;
begin
  select * into payment from public.payments as source_payment where source_payment.id = target_payment_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  perform private.require_finance_reader(payment.rider_id);
  return query select payment.id, payment.trip_id, payment.method, payment.final_amount_fils, payment.currency, payment.cash_status, payment.card_status, payment.card_brand, payment.card_last_four, payment.authorized_at, payment.paid_at, payment.cancelled_at, payment.refunded_at, payment.sanitized_failure_code;
end;
$$;

create or replace function public.user_payment_attempt_summaries(target_payment_id uuid)
returns table (id uuid, type public.payment_attempt_type, status public.payment_attempt_status, requested_amount_fils integer, currency text, failure_code text, created_at timestamptz, completed_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype;
begin
  select * into payment from public.payments as source_payment where source_payment.id = target_payment_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  perform private.require_finance_reader(payment.rider_id);
  return query select attempts.id, attempts.type, attempts.status, attempts.requested_amount_fils, attempts.currency, attempts.sanitized_failure_code, attempts.created_at, attempts.completed_at from public.payment_attempts attempts where attempts.payment_id = payment.id order by attempts.created_at, attempts.id;
end;
$$;

create or replace function public.user_refund_statuses(target_payment_id uuid)
returns table (id uuid, amount_fils integer, currency text, status public.payment_attempt_status, reason_code text, failure_code text, created_at timestamptz, completed_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype;
begin
  select * into payment from public.payments as source_payment where source_payment.id = target_payment_id;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  perform private.require_finance_reader(payment.rider_id);
  return query select refunds.id, refunds.amount_fils, refunds.currency, refunds.status, refunds.reason_code, refunds.sanitized_failure_code, refunds.created_at, refunds.completed_at from public.refunds where refunds.payment_id = payment.id order by refunds.created_at, refunds.id;
end;
$$;

create or replace function public.user_receipt_summary(target_receipt_id uuid)
returns table (id uuid, receipt_number text, trip_id uuid, amount_paid_fils integer, currency text, payment_method public.payment_method, card_brand text, card_last_four text, issued_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare receipt public.receipts%rowtype; trip public.trips%rowtype;
begin
  select * into receipt from public.receipts as source_receipt where source_receipt.id = target_receipt_id;
  if not found then raise exception using errcode = 'P0002', message = 'Receipt was not found.'; end if;
  select * into trip from public.trips as source_trip where source_trip.id = receipt.trip_id;
  perform private.require_receipt_reader(trip.rider_id, trip.driver_id);
  return query select receipt.id, receipt.receipt_number, receipt.trip_id, receipt.amount_paid_fils, receipt.currency, receipt.payment_method, receipt.card_brand, receipt.card_last_four, receipt.issued_at;
end;
$$;

revoke all on function private.require_finance_reader(uuid, uuid), private.require_receipt_reader(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.user_payment_summary(uuid), public.user_trip_payment_summary(uuid), public.user_payment_attempt_summaries(uuid), public.user_refund_statuses(uuid), public.user_receipt_summary(uuid), public.user_trip_receipt_summary(uuid) from public, anon, authenticated, service_role;
grant execute on function public.user_payment_summary(uuid), public.user_trip_payment_summary(uuid), public.user_payment_attempt_summaries(uuid), public.user_refund_statuses(uuid), public.user_receipt_summary(uuid), public.user_trip_receipt_summary(uuid) to authenticated;

commit;
