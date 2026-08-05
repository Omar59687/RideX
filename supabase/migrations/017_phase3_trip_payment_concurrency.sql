begin;

create or replace function private.ensure_trip_payment(target_trip_id uuid)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_trip public.trips%rowtype;
  current_payment public.payments%rowtype;
begin
  select * into current_trip
  from public.trips
  where id = target_trip_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Trip was not found.';
  end if;

  insert into public.payments (
    booking_request_id, trip_id, rider_id, method, fare_quote_id,
    authorized_amount_fils, final_amount_fils, currency,
    cash_status, card_status
  ) values (
    current_trip.booking_request_id, current_trip.id, current_trip.rider_id,
    current_trip.payment_method, current_trip.fare_quote_id,
    current_trip.original_fare_fils, current_trip.current_fare_fils,
    current_trip.currency,
    case when current_trip.payment_method = 'cash'
      then 'cashSelected'::public.cash_payment_status end,
    case when current_trip.payment_method = 'card'
      then 'cardPaymentPending'::public.card_payment_status end
  )
  on conflict (booking_request_id) do nothing;

  select * into current_payment
  from public.payments
  where booking_request_id = current_trip.booking_request_id
  for update;
  if not found
    or current_payment.trip_id is distinct from current_trip.id
    or current_payment.booking_request_id <> current_trip.booking_request_id
    or current_payment.rider_id <> current_trip.rider_id
    or current_payment.method <> current_trip.payment_method
    or current_payment.fare_quote_id <> current_trip.fare_quote_id
    or current_payment.currency <> current_trip.currency
    or current_payment.authorized_amount_fils <> current_trip.original_fare_fils
    or (
      current_payment.method = 'card'
      and current_payment.final_amount_fils <> current_trip.current_fare_fils
    ) then
    raise exception using errcode = '55000',
      message = 'Payment must reconcile with its locked FareQuote and Trip.';
  end if;
  return current_payment;
end;
$$;

create or replace function private.require_verified_card_progression(target_trip_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_payment public.payments%rowtype;
begin
  current_payment := private.ensure_trip_payment(target_trip_id);
  if current_payment.method = 'card' and (
    current_payment.card_status <> 'cardPaymentAuthorized'
    or not exists (
      select 1
      from public.payment_attempts
      where payment_id = current_payment.id
        and type in ('initialAuthorization', 'replacementAuthorization')
        and status = 'succeeded'
        and verified_at = completed_at
        and completed_at >= created_at
        and completed_at <= created_at + interval '2 minutes'
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Card Trip progression requires a verified authorized Payment.';
  end if;
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
begin
  select * into current_trip
  from public.trips
  where id = target_trip_id
  for update;
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
      raise exception using errcode = '55000',
        message = 'Settled Cash Payment cannot be cancelled.';
    end if;
  else
    if current_payment.card_status = 'paymentCancelled' then
      return current_payment;
    end if;
    if current_payment.card_status not in ('cardPaymentPending', 'cardPaymentFailed')
      or exists (
        select 1 from public.payment_attempts
        where payment_id = current_payment.id
          and type in ('initialAuthorization', 'replacementAuthorization')
          and status = 'succeeded'
      ) then
      raise exception using errcode = '55000',
        message = 'Card Payment requires trusted provider reconciliation before cancellation.';
    end if;
    update public.payments
    set card_status = 'paymentCancelled', cancelled_at = now()
    where id = current_payment.id
    returning * into current_payment;
  end if;
  return current_payment;
end;
$$;

create or replace function private.settle_cash_trip_and_issue_receipt(target_trip_id uuid)
returns public.receipts
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_trip public.trips%rowtype;
  current_payment public.payments%rowtype;
  issued_receipt public.receipts%rowtype;
begin
  select * into current_trip
  from public.trips
  where id = target_trip_id
  for update;
  if not found or current_trip.status <> 'completed'
    or current_trip.payment_method <> 'cash' then
    raise exception using errcode = '55000',
      message = 'Cash settlement requires a completed Cash Trip.';
  end if;
  if exists (
    select 1 from public.trip_change_requests
    where trip_id = current_trip.id and status = 'approved'
  ) then
    raise exception using errcode = '55000',
      message = 'An approved fare adjustment must be applied before completion.';
  end if;

  current_payment := private.ensure_trip_payment(current_trip.id);
  if current_payment.cash_status = 'cashSelected' then
    update public.payments
    set final_amount_fils = current_trip.current_fare_fils,
        cash_status = 'paid',
        paid_at = now()
    where id = current_payment.id
    returning * into current_payment;
  elsif current_payment.cash_status <> 'paid'
    or current_payment.final_amount_fils <> current_trip.current_fare_fils then
    raise exception using errcode = '55000',
      message = 'Cash Payment is not eligible for atomic settlement.';
  end if;

  select * into issued_receipt
  from public.backend_issue_receipt(current_payment.id);
  return issued_receipt;
end;
$$;

-- Preserve the verified implementations while enforcing positive versions at
-- every remaining public boundary.
alter function public.rider_cancel_trip(uuid, integer, text) set schema private;
alter function public.admin_terminate_trip(uuid, integer, public.trip_status, text) set schema private;
alter function public.rider_create_trip_change_request(uuid, integer, jsonb, jsonb, text) set schema private;
alter function public.rider_cancel_trip_change_request(uuid, integer) set schema private;
alter function public.rider_approve_trip_change_request(uuid, integer, integer) set schema private;
alter function public.backend_price_trip_change_request(uuid, integer, integer, integer, text) set schema private;
alter function public.backend_apply_trip_fare_adjustment(uuid, integer, integer) set schema private;
alter function public.backend_transition_payment(uuid, integer, public.cash_payment_status, public.card_payment_status) set schema private;
alter function public.admin_request_refund(uuid, integer, text) set schema private;

create or replace function public.driver_transition_trip(
  target_id uuid,
  requested_status public.trip_status,
  expected_version integer,
  idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  locked_user public.users%rowtype;
  locked_profile public.driver_profiles%rowtype;
  result jsonb;
  target_trip_id uuid;
  current_trip public.trips%rowtype;
begin
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023',
      message = 'A positive expected version is required.';
  end if;

  if requested_status = 'accepted' then
    select * into locked_user from public.users where id = caller_id for update;
    select * into locked_profile from public.driver_profiles where user_id = caller_id for update;
    if caller_id is null or not found or locked_user.role <> 'driver'
      or locked_user.is_blocked or locked_profile.approval_status <> 'approved' then
      raise exception using errcode = '42501',
        message = 'Only an approved, non-blocked Driver can manage vehicles or availability.';
    end if;
    result := private.driver_transition_trip(
      target_id, requested_status, expected_version, idempotency_key
    );
    if result ? 'error' then
      return result;
    end if;
    target_trip_id := (result ->> 'trip_id')::uuid;
    perform private.ensure_trip_payment(target_trip_id);
    return result;
  end if;

  select * into current_trip
  from public.trips
  where id = target_id and driver_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0002',
      message = 'Trip was not found for this Driver.';
  end if;
  perform private.ensure_trip_payment(current_trip.id);
  if requested_status in ('driverArriving', 'driverArrived', 'inProgress') then
    perform private.require_verified_card_progression(current_trip.id);
  end if;

  result := private.driver_transition_trip(
    target_id, requested_status, expected_version, idempotency_key
  );
  if requested_status = 'completed' and current_trip.payment_method = 'cash' then
    perform private.settle_cash_trip_and_issue_receipt(current_trip.id);
  elsif requested_status = 'cancelledByDriver' then
    perform private.reconcile_cancelled_trip_payment(current_trip.id);
  end if;
  return result;
end;
$$;

create function public.rider_cancel_trip(
  target_trip_id uuid, expected_version integer, reason_code text
)
returns public.trips
language plpgsql security definer set search_path = ''
as $$
declare result public.trips%rowtype;
begin
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  result := private.rider_cancel_trip(target_trip_id, expected_version, reason_code);
  perform private.reconcile_cancelled_trip_payment(result.id);
  return result;
end;
$$;

create function public.admin_terminate_trip(
  target_trip_id uuid, expected_version integer,
  terminal_status public.trip_status, reason_code text
)
returns public.trips
language plpgsql security definer set search_path = ''
as $$
declare result public.trips%rowtype;
begin
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  result := private.admin_terminate_trip(
    target_trip_id, expected_version, terminal_status, reason_code
  );
  perform private.reconcile_cancelled_trip_payment(result.id);
  return result;
end;
$$;

create function public.rider_create_trip_change_request(
  target_trip_id uuid, expected_trip_version integer,
  requested_destination jsonb, requested_stops jsonb default '[]'::jsonb,
  rider_note text default null
)
returns public.trip_change_requests
language plpgsql security definer set search_path = ''
as $$
begin
  if expected_trip_version is null or expected_trip_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  return private.rider_create_trip_change_request(
    target_trip_id, expected_trip_version, requested_destination,
    requested_stops, rider_note
  );
end;
$$;

create function public.rider_cancel_trip_change_request(
  target_request_id uuid, expected_request_version integer
)
returns public.trip_change_requests
language plpgsql security definer set search_path = ''
as $$
begin
  if expected_request_version is null or expected_request_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  return private.rider_cancel_trip_change_request(
    target_request_id, expected_request_version
  );
end;
$$;

create function public.rider_approve_trip_change_request(
  target_request_id uuid, expected_request_version integer,
  expected_trip_version integer
)
returns public.trip_change_requests
language plpgsql security definer set search_path = ''
as $$
begin
  if expected_request_version is null or expected_request_version < 1
    or expected_trip_version is null or expected_trip_version < 1 then
    raise exception using errcode = '22023', message = 'Positive expected versions are required.';
  end if;
  return private.rider_approve_trip_change_request(
    target_request_id, expected_request_version, expected_trip_version
  );
end;
$$;

create function public.backend_price_trip_change_request(
  target_request_id uuid, expected_request_version integer,
  route_distance_meters integer, route_duration_seconds integer,
  route_geometry_reference text default null
)
returns public.fare_adjustments
language plpgsql security definer set search_path = ''
as $$
begin
  if expected_request_version is null or expected_request_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  return private.backend_price_trip_change_request(
    target_request_id, expected_request_version, route_distance_meters,
    route_duration_seconds, route_geometry_reference
  );
end;
$$;

create function public.backend_apply_trip_fare_adjustment(
  target_adjustment_id uuid, expected_adjustment_version integer,
  expected_trip_version integer
)
returns public.trips
language plpgsql security definer set search_path = ''
as $$
begin
  if expected_adjustment_version is null or expected_adjustment_version < 1
    or expected_trip_version is null or expected_trip_version < 1 then
    raise exception using errcode = '22023', message = 'Positive expected versions are required.';
  end if;
  return private.backend_apply_trip_fare_adjustment(
    target_adjustment_id, expected_adjustment_version, expected_trip_version
  );
end;
$$;

create function public.backend_transition_payment(
  target_payment_id uuid, expected_version integer,
  next_cash_status public.cash_payment_status default null,
  next_card_status public.card_payment_status default null
)
returns public.payments
language plpgsql security definer set search_path = ''
as $$
begin
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  return private.backend_transition_payment(
    target_payment_id, expected_version, next_cash_status, next_card_status
  );
end;
$$;

create function public.admin_request_refund(
  target_payment_id uuid, expected_payment_version integer, reason text
)
returns public.refunds
language plpgsql security definer set search_path = ''
as $$
begin
  if expected_payment_version is null or expected_payment_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  return private.admin_request_refund(
    target_payment_id, expected_payment_version, reason
  );
end;
$$;

-- Reconcile any locally existing Trip rows when this additive migration is
-- applied to a nonempty environment.
do $$
declare target_trip_id uuid;
begin
  for target_trip_id in select id from public.trips order by created_at, id loop
    perform private.ensure_trip_payment(target_trip_id);
  end loop;
end;
$$;

revoke all on function private.ensure_trip_payment(uuid),
  private.require_verified_card_progression(uuid),
  private.reconcile_cancelled_trip_payment(uuid),
  private.settle_cash_trip_and_issue_receipt(uuid),
  private.rider_cancel_trip(uuid, integer, text),
  private.admin_terminate_trip(uuid, integer, public.trip_status, text),
  private.rider_create_trip_change_request(uuid, integer, jsonb, jsonb, text),
  private.rider_cancel_trip_change_request(uuid, integer),
  private.rider_approve_trip_change_request(uuid, integer, integer),
  private.backend_price_trip_change_request(uuid, integer, integer, integer, text),
  private.backend_apply_trip_fare_adjustment(uuid, integer, integer),
  private.backend_transition_payment(uuid, integer, public.cash_payment_status, public.card_payment_status),
  private.admin_request_refund(uuid, integer, text)
from public, anon, authenticated, service_role;

revoke all on function public.rider_cancel_trip(uuid, integer, text),
  public.admin_terminate_trip(uuid, integer, public.trip_status, text),
  public.rider_create_trip_change_request(uuid, integer, jsonb, jsonb, text),
  public.rider_cancel_trip_change_request(uuid, integer),
  public.rider_approve_trip_change_request(uuid, integer, integer),
  public.backend_price_trip_change_request(uuid, integer, integer, integer, text),
  public.backend_apply_trip_fare_adjustment(uuid, integer, integer),
  public.backend_transition_payment(uuid, integer, public.cash_payment_status, public.card_payment_status),
  public.admin_request_refund(uuid, integer, text)
from public, anon, authenticated, service_role;

grant execute on function public.rider_cancel_trip(uuid, integer, text),
  public.rider_create_trip_change_request(uuid, integer, jsonb, jsonb, text),
  public.rider_cancel_trip_change_request(uuid, integer),
  public.rider_approve_trip_change_request(uuid, integer, integer),
  public.admin_terminate_trip(uuid, integer, public.trip_status, text),
  public.admin_request_refund(uuid, integer, text)
to authenticated;

grant execute on function public.backend_price_trip_change_request(uuid, integer, integer, integer, text),
  public.backend_apply_trip_fare_adjustment(uuid, integer, integer),
  public.backend_transition_payment(uuid, integer, public.cash_payment_status, public.card_payment_status)
to service_role;

commit;
