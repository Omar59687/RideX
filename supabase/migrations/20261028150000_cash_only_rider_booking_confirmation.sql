-- Temporarily restrict new Rider booking confirmations to canonical Cash
-- bookings until a server-side Card authorization gate is available.
-- Keep the existing RPC contract, authorization, row lock, quote validation,
-- idempotency, audit, grants, and SECURITY DEFINER protections intact.
create or replace function public.rider_confirm_booking(
  target_booking_request_id uuid,
  expected_version integer,
  idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_booking public.booking_requests%rowtype;
  payload_fingerprint text;
  canonical_result jsonb;
  claimed_result jsonb;
begin
  caller_id := private.require_nonblocked_rider();
  if expected_version is null or expected_version < 1 then
    raise exception using errcode = '22023', message = 'A positive expected version is required.';
  end if;
  canonical_result := jsonb_build_object(
    'booking_request_id', target_booking_request_id,
    'status', 'confirmed'
  );
  payload_fingerprint := encode(
    extensions.digest(
      convert_to(concat_ws('|', target_booking_request_id::text, expected_version::text), 'UTF8'),
      'sha256'
    ),
    'hex'
  );
  claimed_result := private.claim_command_idempotency_key(
    caller_id, 'booking', idempotency_key, payload_fingerprint, canonical_result
  );
  if claimed_result ? 'error' then
    return claimed_result;
  end if;

  select * into current_booking
  from public.booking_requests
  where id = target_booking_request_id and rider_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Booking was not found for this Rider.';
  end if;
  -- Historical confirmed bookings are recovered unchanged, including Card
  -- bookings created before this temporary policy.
  if current_booking.status = 'confirmed' then
    return claimed_result;
  end if;
  if current_booking.status <> 'draft' then
    raise exception using errcode = '55000', message = 'Only a draft booking can be confirmed.';
  end if;
  if current_booking.version <> expected_version then
    raise exception using errcode = '40001', message = 'Booking version is stale.';
  end if;
  if current_booking.fare_quote_id is null or not exists (
    select 1 from public.fare_quotes
    where id = current_booking.fare_quote_id
      and booking_request_id = current_booking.id
      and status = 'locked'
  ) then
    raise exception using errcode = '55000', message = 'Booking confirmation requires its active locked FareQuote.';
  end if;
  if current_booking.payment_method is distinct from 'cash'::public.payment_method then
    raise exception using errcode = '55000', message = 'Only Cash bookings can be confirmed until Card authorization is available.';
  end if;

  update public.booking_requests
  set status = 'confirmed', confirmed_at = now()
  where id = current_booking.id;
  perform private.write_audit_record(
    caller_id, 'booking.confirmed', caller_id, null,
    jsonb_build_object('booking_request_id', current_booking.id, 'status', current_booking.status),
    canonical_result
  );
  return canonical_result;
end;
$$;

-- Preserve the established authenticated-only RPC boundary explicitly.
revoke all on function public.rider_confirm_booking(uuid, integer, text)
  from public, anon, authenticated, service_role;
grant execute on function public.rider_confirm_booking(uuid, integer, text)
  to authenticated;
