begin;

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null unique references public.booking_requests (id) on delete restrict,
  trip_id uuid unique references public.trips (id) on delete restrict,
  rider_id uuid not null references public.rider_profiles (user_id) on delete restrict,
  method public.payment_method not null,
  fare_quote_id uuid not null references public.fare_quotes (id) on delete restrict,
  authorized_amount_fils integer not null,
  final_amount_fils integer not null,
  currency text not null default 'JOD',
  cash_status public.cash_payment_status,
  card_status public.card_payment_status,
  provider_name text,
  card_brand text,
  card_last_four text,
  authorized_at timestamptz,
  paid_at timestamptz,
  cancelled_at timestamptz,
  refunded_at timestamptz,
  sanitized_failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  constraint payments_method_status_compatible check (
    (method = 'cash' and cash_status is not null and card_status is null and provider_name is null and card_brand is null and card_last_four is null)
    or (method = 'card' and cash_status is null and card_status is not null)
  ),
  constraint payments_money_valid check (currency = 'JOD' and authorized_amount_fils >= 0 and final_amount_fils >= 0),
  constraint payments_card_summary_safe check (
    card_brand is null or char_length(btrim(card_brand)) between 1 and 32
  ),
  constraint payments_card_last_four_safe check (card_last_four is null or card_last_four ~ '^[0-9]{4}$'),
  constraint payments_provider_name_bounded check (provider_name is null or char_length(btrim(provider_name)) between 1 and 64),
  constraint payments_failure_code_bounded check (sanitized_failure_code is null or sanitized_failure_code ~ '^[A-Z0-9_]{1,64}$'),
  constraint payments_version_positive check (version > 0)
);

create table public.payment_attempts (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id) on delete restrict,
  type public.payment_attempt_type not null,
  status public.payment_attempt_status not null default 'pending',
  requested_amount_fils integer not null,
  currency text not null default 'JOD',
  idempotency_key text not null,
  provider_name text,
  provider_transaction_reference text,
  sanitized_failure_code text,
  sanitized_failure_message text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint payment_attempts_money_valid check (requested_amount_fils >= 0 and currency = 'JOD'),
  constraint payment_attempts_idempotency_key_bounded check (char_length(btrim(idempotency_key)) between 1 and 128),
  constraint payment_attempts_provider_name_bounded check (provider_name is null or char_length(btrim(provider_name)) between 1 and 64),
  constraint payment_attempts_provider_reference_bounded check (provider_transaction_reference is null or char_length(btrim(provider_transaction_reference)) between 1 and 256),
  constraint payment_attempts_failure_code_bounded check (sanitized_failure_code is null or sanitized_failure_code ~ '^[A-Z0-9_]{1,64}$'),
  constraint payment_attempts_failure_message_bounded check (sanitized_failure_message is null or char_length(btrim(sanitized_failure_message)) between 1 and 256),
  constraint payment_attempts_completion_valid check ((status = 'pending' and completed_at is null) or (status <> 'pending' and completed_at is not null)),
  constraint payment_attempts_payment_idempotency_unique unique (payment_id, idempotency_key),
  constraint payment_attempts_provider_reference_unique unique (provider_name, provider_transaction_reference)
);

create unique index payment_attempts_one_active_card_authorization_idx
  on public.payment_attempts (payment_id)
  where type in ('initialAuthorization', 'replacementAuthorization') and status = 'pending';
create unique index payment_attempts_one_successful_capture_idx
  on public.payment_attempts (payment_id)
  where type in ('capture', 'captureRetry') and status = 'succeeded';
create index payment_attempts_payment_created_at_idx on public.payment_attempts (payment_id, created_at desc);

create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id) on delete restrict,
  amount_fils integer not null,
  currency text not null default 'JOD',
  status public.payment_attempt_status not null default 'pending',
  reason_code text not null,
  requested_by_admin_id uuid not null references public.users (id) on delete restrict,
  provider_name text,
  provider_refund_reference text,
  sanitized_failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  version integer not null default 1,
  constraint refunds_money_valid check (amount_fils >= 0 and currency = 'JOD'),
  constraint refunds_reason_bounded check (char_length(btrim(reason_code)) between 1 and 100),
  constraint refunds_provider_name_bounded check (provider_name is null or char_length(btrim(provider_name)) between 1 and 64),
  constraint refunds_provider_reference_bounded check (provider_refund_reference is null or char_length(btrim(provider_refund_reference)) between 1 and 256),
  constraint refunds_failure_code_bounded check (sanitized_failure_code is null or sanitized_failure_code ~ '^[A-Z0-9_]{1,64}$'),
  constraint refunds_completion_valid check ((status = 'pending' and completed_at is null) or (status <> 'pending' and completed_at is not null)),
  constraint refunds_version_positive check (version > 0),
  constraint refunds_provider_reference_unique unique (provider_name, provider_refund_reference)
);

create unique index refunds_one_active_per_payment_idx on public.refunds (payment_id) where status = 'pending';
create index refunds_payment_created_at_idx on public.refunds (payment_id, created_at desc);

create table public.receipts (
  id uuid primary key default gen_random_uuid(),
  receipt_number text not null unique,
  trip_id uuid not null unique references public.trips (id) on delete restrict,
  fare_quote_id uuid not null references public.fare_quotes (id) on delete restrict,
  payment_id uuid not null unique references public.payments (id) on delete restrict,
  rider_snapshot jsonb not null,
  driver_snapshot jsonb not null,
  vehicle_snapshot jsonb not null,
  pickup_snapshot jsonb not null,
  destination_snapshot jsonb not null,
  ordered_stops_snapshot jsonb not null,
  fare_breakdown_snapshot jsonb not null,
  cash_adjustments_snapshot jsonb not null default '[]'::jsonb,
  amount_paid_fils integer not null,
  currency text not null default 'JOD',
  payment_method public.payment_method not null,
  card_brand text,
  card_last_four text,
  safe_provider_reference text,
  refund_id uuid unique references public.refunds (id) on delete restrict,
  issued_at timestamptz not null default now(),
  source_versions jsonb not null,
  constraint receipts_number_format check (receipt_number ~ '^RDX-[0-9]{8}-[A-Z0-9]{8}$'),
  constraint receipts_snapshot_objects check (
    jsonb_typeof(rider_snapshot) = 'object' and jsonb_typeof(driver_snapshot) = 'object'
    and jsonb_typeof(vehicle_snapshot) = 'object' and jsonb_typeof(pickup_snapshot) = 'object'
    and jsonb_typeof(destination_snapshot) = 'object' and jsonb_typeof(fare_breakdown_snapshot) = 'object'
    and jsonb_typeof(ordered_stops_snapshot) = 'array' and jsonb_typeof(cash_adjustments_snapshot) = 'array'
    and jsonb_typeof(source_versions) = 'object'
  ),
  constraint receipts_money_valid check (amount_paid_fils >= 0 and currency = 'JOD'),
  constraint receipts_card_summary_safe check (card_brand is null or char_length(btrim(card_brand)) between 1 and 32),
  constraint receipts_card_last_four_safe check (card_last_four is null or card_last_four ~ '^[0-9]{4}$'),
  constraint receipts_provider_reference_bounded check (safe_provider_reference is null or char_length(btrim(safe_provider_reference)) between 1 and 256)
);

create index receipts_trip_issued_at_idx on public.receipts (trip_id, issued_at desc);

create table public.processed_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider_name text not null,
  provider_event_id text not null,
  payment_id uuid references public.payments (id) on delete restrict,
  processed_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '90 days'),
  constraint processed_webhook_events_provider_bounded check (char_length(btrim(provider_name)) between 1 and 64),
  constraint processed_webhook_events_event_id_bounded check (char_length(btrim(provider_event_id)) between 1 and 256),
  constraint processed_webhook_events_retention_exact check (expires_at = processed_at + interval '90 days'),
  constraint processed_webhook_events_provider_event_unique unique (provider_name, provider_event_id)
);
create index processed_webhook_events_expires_at_idx on public.processed_webhook_events (expires_at);

create trigger payments_set_updated_at before update on public.payments for each row execute function public.set_updated_at();
create trigger payments_bump_version before update on public.payments for each row execute function private.bump_optimistic_version();
create trigger refunds_set_updated_at before update on public.refunds for each row execute function public.set_updated_at();
create trigger refunds_bump_version before update on public.refunds for each row execute function private.bump_optimistic_version();

create or replace function private.reject_payment_attempt_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_setting('ridex.complete_payment_attempt', true) = 'on'
    and new.payment_id = old.payment_id
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
create trigger payment_attempts_append_only before update or delete on public.payment_attempts
for each row execute function private.reject_payment_attempt_mutation();

create or replace function private.reject_receipt_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin raise exception using errcode = '55000', message = 'Receipt financial snapshots are immutable.'; end;
$$;
create trigger receipts_immutable before update or delete on public.receipts
for each row execute function private.reject_receipt_mutation();

create or replace function private.payment_matches_trip_and_quote(target_payment public.payments)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.trips trips join public.fare_quotes quotes on quotes.id = trips.fare_quote_id
    where trips.id = target_payment.trip_id and trips.booking_request_id = target_payment.booking_request_id
      and trips.rider_id = target_payment.rider_id and trips.payment_method = target_payment.method
      and quotes.id = target_payment.fare_quote_id and quotes.status = 'locked'
      and quotes.currency = target_payment.currency and target_payment.authorized_amount_fils = quotes.fixed_fare_fils
      and target_payment.final_amount_fils = trips.current_fare_fils and target_payment.currency = trips.currency
  );
$$;

create or replace function private.can_read_payment(target_payment_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.users users join public.payments payments on payments.id = target_payment_id
    where users.id = auth.uid() and not users.is_blocked
      and (users.role = 'admin' or (users.role = 'rider' and users.id = payments.rider_id))
  );
$$;

create or replace function private.can_read_receipt(target_receipt_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.users users join public.receipts receipts on receipts.id = target_receipt_id
    join public.trips trips on trips.id = receipts.trip_id
    where users.id = auth.uid() and not users.is_blocked
      and (users.role = 'admin' or (users.role = 'rider' and users.id = trips.rider_id)
        or (users.role = 'driver' and users.id = trips.driver_id))
  );
$$;

create or replace function public.backend_create_payment(target_trip_id uuid)
returns public.payments language plpgsql security definer set search_path = '' as $$
declare current_trip public.trips%rowtype; created_payment public.payments%rowtype;
begin
  select * into current_trip from public.trips where id = target_trip_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Trip was not found.'; end if;
  insert into public.payments (booking_request_id, trip_id, rider_id, method, fare_quote_id, authorized_amount_fils, final_amount_fils, currency, cash_status, card_status)
  values (current_trip.booking_request_id, current_trip.id, current_trip.rider_id, current_trip.payment_method, current_trip.fare_quote_id, current_trip.original_fare_fils, current_trip.current_fare_fils, current_trip.currency,
    case when current_trip.payment_method = 'cash' then 'cashSelected'::public.cash_payment_status end,
    case when current_trip.payment_method = 'card' then 'cardPaymentPending'::public.card_payment_status end)
  on conflict (booking_request_id) do nothing returning * into created_payment;
  if not found then select * into created_payment from public.payments where booking_request_id = current_trip.booking_request_id; end if;
  if not private.payment_matches_trip_and_quote(created_payment) then raise exception using errcode = '55000', message = 'Payment must reconcile with its locked FareQuote and Trip.'; end if;
  return created_payment;
end;
$$;

create or replace function public.backend_record_payment_attempt(target_payment_id uuid, attempt_type public.payment_attempt_type, amount_fils integer, attempt_key text, provider text default null)
returns public.payment_attempts language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype; result public.payment_attempts%rowtype; attempt_count integer;
begin
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
  elsif attempt_type = 'refund' then
    select count(*) into attempt_count from public.payment_attempts where payment_id = target_payment_id and type = 'refund';
    if attempt_count >= 3 then raise exception using errcode = '55000', message = 'Refund permits at most three attempts.'; end if;
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
  if current_attempt.status <> 'pending' then return current_attempt; end if;
  if final_status = 'pending' then raise exception using errcode = '22023', message = 'A payment attempt requires a terminal verified status.'; end if;
  perform set_config('ridex.complete_payment_attempt', 'on', true);
  update public.payment_attempts set status = final_status,
    provider_transaction_reference = coalesce(nullif(btrim(provider_reference), ''), provider_transaction_reference),
    sanitized_failure_code = nullif(btrim(failure_code), ''), completed_at = now()
  where id = current_attempt.id returning * into current_attempt;
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
    if next_cash_status is not null or next_card_status is null then raise exception using errcode = '55000', message = 'Invalid Card payment transition.'; end if;
    if not ((payment.card_status = 'cardPaymentPending' and next_card_status in ('cardPaymentAuthorized', 'cardPaymentFailed', 'paymentCancelled')) or
      (payment.card_status = 'cardPaymentAuthorized' and next_card_status in ('cardPaymentPending', 'cardPaymentSucceeded', 'cardPaymentFailed', 'paymentCancelled')) or
      (payment.card_status = 'cardPaymentFailed' and next_card_status in ('cardPaymentPending', 'cardPaymentSucceeded')) or
      (payment.card_status = 'cardPaymentSucceeded' and next_card_status = 'refundPending') or
      (payment.card_status = 'refundPending' and next_card_status in ('refundPending', 'refunded'))) then raise exception using errcode = '55000', message = 'Invalid Card payment transition.'; end if;
    if next_card_status = 'cardPaymentAuthorized' and not exists (select 1 from public.payment_attempts where payment_id = payment.id and type in ('initialAuthorization', 'replacementAuthorization') and status = 'pending' and created_at > now() - interval '2 minutes') then raise exception using errcode = '55000', message = 'Card authorization requires a live two-minute attempt.'; end if;
    if next_card_status = 'cardPaymentSucceeded' and (trip.status <> 'completed' or not exists (select 1 from public.payment_attempts where payment_id = payment.id and type in ('capture', 'captureRetry') and status = 'succeeded')) then raise exception using errcode = '55000', message = 'Card success requires a completed Trip and verified Capture.'; end if;
    update public.payments set card_status = next_card_status, authorized_at = case when next_card_status = 'cardPaymentAuthorized' then now() else authorized_at end, paid_at = case when next_card_status = 'cardPaymentSucceeded' then now() else paid_at end, refunded_at = case when next_card_status = 'refunded' then now() else refunded_at end, cancelled_at = case when next_card_status = 'paymentCancelled' then now() else cancelled_at end where id = payment.id returning * into payment;
  end if;
  perform private.write_audit_record(null, 'payment.state_transition', payment.rider_id, null, jsonb_build_object('payment_id', payment.id, 'version', expected_version), jsonb_build_object('version', payment.version, 'cash_status', payment.cash_status, 'card_status', payment.card_status));
  return payment;
end;
$$;

create or replace function public.admin_request_refund(target_payment_id uuid, expected_payment_version integer, reason text)
returns public.refunds language plpgsql security definer set search_path = '' as $$
declare caller_id uuid; payment public.payments%rowtype; created_refund public.refunds%rowtype;
begin
  caller_id := private.require_nonblocked_admin();
  if char_length(btrim(coalesce(reason, ''))) not between 1 and 100 then raise exception using errcode = '22023', message = 'A bounded refund reason is required.'; end if;
  select * into payment from public.payments where id = target_payment_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  if payment.version <> expected_payment_version then raise exception using errcode = '40001', message = 'Payment version is stale.'; end if;
  select * into created_refund from public.refunds where payment_id = payment.id and status = 'pending';
  if found then return created_refund; end if;
  if payment.method <> 'card' or payment.card_status <> 'cardPaymentSucceeded' then raise exception using errcode = '55000', message = 'Only a succeeded Card payment can be fully refunded.'; end if;
  insert into public.refunds (payment_id, amount_fils, currency, reason_code, requested_by_admin_id) values (payment.id, payment.final_amount_fils, payment.currency, btrim(reason), caller_id) returning * into created_refund;
  update public.payments set card_status = 'refundPending' where id = payment.id;
  perform private.write_audit_record(caller_id, 'payment.refund_requested', payment.rider_id, btrim(reason), jsonb_build_object('payment_id', payment.id), jsonb_build_object('refund_id', created_refund.id, 'amount_fils', created_refund.amount_fils));
  return created_refund;
end;
$$;

create or replace function public.backend_issue_receipt(target_payment_id uuid)
returns public.receipts language plpgsql security definer set search_path = '' as $$
declare payment public.payments%rowtype; trip public.trips%rowtype; quote public.fare_quotes%rowtype; result public.receipts%rowtype;
begin
  select * into payment from public.payments where id = target_payment_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Payment was not found.'; end if;
  select * into result from public.receipts where payment_id = payment.id;
  if found then return result; end if;
  select * into trip from public.trips where id = payment.trip_id for share;
  select * into quote from public.fare_quotes where id = payment.fare_quote_id for share;
  if trip.status <> 'completed' or not private.payment_matches_trip_and_quote(payment)
    or not ((payment.method = 'cash' and payment.cash_status = 'paid') or (payment.method = 'card' and payment.card_status = 'cardPaymentSucceeded')) then raise exception using errcode = '55000', message = 'Receipt requires a completed Trip and settled Payment.'; end if;
  insert into public.receipts (receipt_number, trip_id, fare_quote_id, payment_id, rider_snapshot, driver_snapshot, vehicle_snapshot, pickup_snapshot, destination_snapshot, ordered_stops_snapshot, fare_breakdown_snapshot, cash_adjustments_snapshot, amount_paid_fils, currency, payment_method, card_brand, card_last_four, source_versions)
  select 'RDX-' || to_char(now() at time zone 'UTC', 'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)), trip.id, quote.id, payment.id,
    jsonb_build_object('rider_id', trip.rider_id), jsonb_build_object('driver_id', trip.driver_id), jsonb_build_object('vehicle_id', trip.vehicle_id), trip.pickup, trip.destination,
    coalesce((select jsonb_agg(jsonb_build_object('sequence', sequence, 'location', location, 'label', label) order by sequence) from public.trip_stops where trip_id = trip.id), '[]'::jsonb), quote.breakdown,
    coalesce((select jsonb_agg(jsonb_build_object('id', id, 'adjustment_fils', adjustment_fils, 'breakdown', breakdown) order by created_at) from public.fare_adjustments where trip_id = trip.id and status = 'applied'), '[]'::jsonb),
    payment.final_amount_fils, payment.currency, payment.method, payment.card_brand, payment.card_last_four,
    jsonb_build_object('trip_version', trip.version, 'payment_version', payment.version, 'fare_quote_version', quote.quote_version)
  returning * into result;
  perform private.write_audit_record(null, 'receipt.issued', payment.rider_id, null, jsonb_build_object('payment_id', payment.id), jsonb_build_object('receipt_id', result.id, 'receipt_number', result.receipt_number));
  return result;
end;
$$;

create or replace function public.backend_record_processed_webhook_event(provider text, event_id text, target_payment_id uuid default null)
returns public.processed_webhook_events language plpgsql security definer set search_path = '' as $$
declare result public.processed_webhook_events%rowtype;
begin
  insert into public.processed_webhook_events (provider_name, provider_event_id, payment_id) values (btrim(provider), btrim(event_id), target_payment_id)
  on conflict (provider_name, provider_event_id) do nothing returning * into result;
  if not found then select * into result from public.processed_webhook_events where provider_name = btrim(provider) and provider_event_id = btrim(event_id); end if;
  return result;
end;
$$;

alter table public.payments enable row level security;
alter table public.payment_attempts enable row level security;
alter table public.refunds enable row level security;
alter table public.receipts enable row level security;
alter table public.processed_webhook_events enable row level security;
create policy payments_rider_or_admin_select on public.payments for select to authenticated using (private.can_read_payment(id));
create policy payment_attempts_rider_or_admin_select on public.payment_attempts for select to authenticated using (private.can_read_payment(payment_id));
create policy refunds_rider_or_admin_select on public.refunds for select to authenticated using (private.can_read_payment(payment_id));
create policy receipts_participant_or_admin_select on public.receipts for select to authenticated using (private.can_read_receipt(id));

revoke all on table public.payments, public.payment_attempts, public.refunds, public.receipts, public.processed_webhook_events from public, anon, authenticated, service_role;
grant select on table public.payments, public.payment_attempts, public.refunds, public.receipts to authenticated;
grant select, insert, update, delete on table public.payments, public.payment_attempts, public.refunds, public.receipts, public.processed_webhook_events to service_role;
revoke all on function private.reject_payment_attempt_mutation(), private.reject_receipt_mutation(), private.payment_matches_trip_and_quote(public.payments), private.can_read_payment(uuid), private.can_read_receipt(uuid) from public, anon, authenticated, service_role;
grant execute on function private.can_read_payment(uuid), private.can_read_receipt(uuid) to authenticated;
revoke all on function public.backend_create_payment(uuid), public.backend_record_payment_attempt(uuid, public.payment_attempt_type, integer, text, text), public.backend_complete_payment_attempt(uuid, public.payment_attempt_status, text, text), public.backend_transition_payment(uuid, integer, public.cash_payment_status, public.card_payment_status), public.admin_request_refund(uuid, integer, text), public.backend_issue_receipt(uuid), public.backend_record_processed_webhook_event(text, text, uuid) from public, anon, authenticated, service_role;
grant execute on function public.admin_request_refund(uuid, integer, text) to authenticated;
grant execute on function public.backend_create_payment(uuid), public.backend_record_payment_attempt(uuid, public.payment_attempt_type, integer, text, text), public.backend_complete_payment_attempt(uuid, public.payment_attempt_status, text, text), public.backend_transition_payment(uuid, integer, public.cash_payment_status, public.card_payment_status), public.backend_issue_receipt(uuid), public.backend_record_processed_webhook_event(text, text, uuid) to service_role;

commit;
