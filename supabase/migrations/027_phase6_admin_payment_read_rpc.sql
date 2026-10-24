-- Phase 6 proposal: scoped canonical Payment reads. Preserve migration 019's
-- deny-all direct SELECT RLS boundary on public.payments.
begin;

create or replace function private.can_read_canonical_payment(target_rider_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.users as caller
     where caller.id = auth.uid()
       and caller.is_blocked is false
       and (
         caller.role = 'admin'
         or (caller.role = 'rider' and caller.id = target_rider_id)
       )
  );
$$;

-- Unauthorized and nonexistent IDs both produce an empty result. In
-- particular, this RPC does not disclose whether another user's Payment ID
-- exists. Drivers are not payment readers under migration 020.
create function public.user_canonical_payment_record(target_payment_id uuid)
returns table (
  id uuid,
  booking_request_id uuid,
  trip_id uuid,
  rider_id uuid,
  method public.payment_method,
  final_amount_fils integer,
  currency text,
  cash_status public.cash_payment_status,
  card_status public.card_payment_status,
  version integer,
  card_brand text,
  card_last_four text
)
language sql
stable
security definer
set search_path = ''
as $$
  select payment.id,
         payment.booking_request_id,
         payment.trip_id,
         payment.rider_id,
         payment.method,
         payment.final_amount_fils,
         payment.currency,
         payment.cash_status,
         payment.card_status,
         payment.version,
         payment.card_brand,
         payment.card_last_four
    from public.payments as payment
   where payment.id = target_payment_id
     and private.can_read_canonical_payment(payment.rider_id);
$$;

create function public.admin_recent_canonical_payments()
returns table (
  id uuid,
  booking_request_id uuid,
  trip_id uuid,
  rider_id uuid,
  method public.payment_method,
  final_amount_fils integer,
  currency text,
  cash_status public.cash_payment_status,
  card_status public.card_payment_status,
  version integer,
  card_brand text,
  card_last_four text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- Reuse the established server-side authorization boundary. The helper
  -- checks the current profile and blocked state, not client JWT role claims.
  perform private.require_nonblocked_admin();

  return query
    select payment.id,
           payment.booking_request_id,
           payment.trip_id,
           payment.rider_id,
           payment.method,
           payment.final_amount_fils,
           payment.currency,
           payment.cash_status,
           payment.card_status,
           payment.version,
           payment.card_brand,
           payment.card_last_four
      from public.payments as payment
     order by payment.created_at desc, payment.id asc
     limit 50;
end;
$$;

revoke all on function private.can_read_canonical_payment(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.user_canonical_payment_record(uuid),
  public.admin_recent_canonical_payments()
  from public, anon, authenticated, service_role;
grant execute on function public.user_canonical_payment_record(uuid),
  public.admin_recent_canonical_payments() to authenticated;

commit;
