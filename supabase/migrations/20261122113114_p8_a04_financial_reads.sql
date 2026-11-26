begin;
-- A missing row, unauthorized actor, and inconsistent Payment link all return
-- no row. Receipt evidence is returned only when every canonical link agrees.
create function public.user_trip_financial_read_v1(target_trip_id uuid)
returns table (
 contract_version integer, trip_id uuid, trip_version integer, trip_status public.trip_status,
 payment_id uuid, payment_version integer, payment_method public.payment_method,
 amount_fils integer, currency text, cash_status public.cash_payment_status,
 card_status public.card_payment_status, receipt_evidence text, receipt_id uuid,
 receipt_number text, receipt_amount_fils integer, receipt_currency text, receipt_issued_at timestamptz
) language sql stable security definer set search_path='' as $$
 select 1,t.id,t.version,t.status,p.id,p.version,p.method,p.final_amount_fils,p.currency,
 p.cash_status,p.card_status,case when r.id is null then 'unverified' else 'linked' end,
 r.id,r.receipt_number,r.amount_paid_fils,r.currency,r.issued_at
 from public.trips t
 join public.payments p on p.trip_id=t.id and p.rider_id=t.rider_id
   and p.booking_request_id=t.booking_request_id and p.fare_quote_id=t.fare_quote_id
   and p.method=t.payment_method and p.currency=t.currency
 left join public.receipts r on r.trip_id=t.id and r.payment_id=p.id
   and r.fare_quote_id=t.fare_quote_id and r.payment_method=p.method and r.currency=p.currency
 where t.id=target_trip_id and private.can_read_canonical_payment(t.rider_id);
$$;
-- Tuple keyset is stable for ties; cursor must be an entire (timestamp,id) pair.
create function public.user_trip_history_v1(page_size integer default 20, before_created_at timestamptz default null, before_trip_id uuid default null)
returns table (contract_version integer, trip_id uuid, trip_version integer, trip_status public.trip_status,
 created_at timestamptz, payment_id uuid, payment_version integer, payment_method public.payment_method)
language plpgsql stable security definer set search_path='' as $$
begin
 if page_size is null or page_size < 1 or page_size > 50 or (before_created_at is null) <> (before_trip_id is null) then
   raise exception using errcode='22023',message='Invalid pagination.';
 end if;
 return query
 select 1,t.id,t.version,t.status,t.created_at,p.id,p.version,p.method
 from public.trips t
 left join public.payments p on p.trip_id=t.id and p.rider_id=t.rider_id
   and p.booking_request_id=t.booking_request_id and p.fare_quote_id=t.fare_quote_id
   and p.method=t.payment_method and p.currency=t.currency
 where private.can_read_canonical_payment(t.rider_id)
   and (before_created_at is null or (t.created_at,t.id) < (before_created_at,before_trip_id))
 order by t.created_at desc,t.id desc limit page_size;
end;
$$;
revoke all on function public.user_trip_financial_read_v1(uuid), public.user_trip_history_v1(integer,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.user_trip_financial_read_v1(uuid), public.user_trip_history_v1(integer,timestamptz,uuid) to authenticated;
commit;
