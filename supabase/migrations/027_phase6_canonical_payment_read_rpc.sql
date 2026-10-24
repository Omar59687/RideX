-- Phase 6 proposal ONLY: not deployed. Preserve the intentional deny-all
-- direct SELECT RLS policies on public.payments (migration 019).
-- Migration number 027 requires Dev 1 numbering/security review before apply.
begin;

create function public.user_canonical_payment_record(target_payment_id uuid)
returns table (
  id uuid, booking_request_id uuid, trip_id uuid, rider_id uuid,
  method public.payment_method, final_amount_fils integer, currency text,
  cash_status public.cash_payment_status, card_status public.card_payment_status,
  version integer, card_brand text, card_last_four text
)
language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype;
begin
  select * into payment from public.payments as source_payment
    where source_payment.id = target_payment_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Payment was not found.';
  end if;
  -- Reuse existing nonblocked Admin / exact Rider-only finance boundary.
  -- Drivers can access restricted receipts, NOT payment records.
  perform private.require_finance_reader(payment.rider_id);
  return query
    select payment.id, payment.booking_request_id, payment.trip_id,
           payment.rider_id, payment.method, payment.final_amount_fils,
           payment.currency, payment.cash_status, payment.card_status,
           payment.version, payment.card_brand, payment.card_last_four;
end;
$$;

create function public.admin_recent_canonical_payments()
returns table (
  id uuid, booking_request_id uuid, trip_id uuid, rider_id uuid,
  method public.payment_method, final_amount_fils integer, currency text,
  cash_status public.cash_payment_status, card_status public.card_payment_status,
  version integer, card_brand text, card_last_four text
)
language plpgsql security definer set search_path = '' as $$
declare caller public.users%rowtype;
begin
  select * into caller from public.users where id = auth.uid();
  if not found or caller.is_blocked or caller.role <> 'admin' then
    raise exception using errcode = '42501',
      message = 'Active administrator access is required.';
  end if;

  -- A bounded, server-authorized, minimal financial presentation contract.
  -- Never return provider refs, payment attempt metadata, receipt snapshots,
  -- billing secrets, authorization credentials, or raw finance rows.
  return query
    select p.id, p.booking_request_id, p.trip_id, p.rider_id,
           p.method, p.final_amount_fils, p.currency, p.cash_status,
           p.card_status, p.version, p.card_brand, p.card_last_four
      from public.payments as p
      order by p.created_at desc, p.id asc
      limit 50;
end;
$$;

revoke all on function public.user_canonical_payment_record(uuid),
  public.admin_recent_canonical_payments() from public, anon, authenticated, service_role;
grant execute on function public.user_canonical_payment_record(uuid),
  public.admin_recent_canonical_payments() to authenticated;

-- No direct payments SELECT policy or broad privilege is introduced.
commit;
