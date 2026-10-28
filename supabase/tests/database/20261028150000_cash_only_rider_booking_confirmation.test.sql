begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '28100000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'cash-confirm-rider@example.test', '', now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '28100000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'other-confirm-rider@example.test', '', now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '28100000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'blocked-confirm-rider@example.test', '', now(), '{}', '{}', now(), now(), '', '', '', '');
update public.users set is_blocked = true where id = '28100000-0000-0000-0000-000000000003';

insert into public.booking_requests (
  id, rider_id, pickup, destination, vehicle_type_code, payment_method,
  status, version, confirmed_at
) values
  ('28200000-0000-0000-0000-000000000001', '28100000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash', 'draft', 1, null),
  ('28200000-0000-0000-0000-000000000002', '28100000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'card', 'draft', 1, null),
  ('28200000-0000-0000-0000-000000000003', '28100000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash', 'draft', 1, null),
  ('28200000-0000-0000-0000-000000000004', '28100000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'card', 'draft', 2, null),
  ('28200000-0000-0000-0000-000000000005', '28100000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash', 'draft', 1, null),
  ('28200000-0000-0000-0000-000000000006', '28100000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash', 'draft', 1, null),
  ('28200000-0000-0000-0000-000000000007', '28100000-0000-0000-0000-000000000002', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash', 'draft', 1, null),
  ('28200000-0000-0000-0000-000000000008', '28100000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}', 'economy', 'cash', 'draft', 1, null);

insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination,
  route_distance_meters, route_duration_seconds, vehicle_type_code,
  breakdown, fixed_fare_fils, pricing_configuration_id, pricing_version,
  quote_version, created_at, expires_at, locked_at
)
select
  ('28300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('28200000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  case when n = 7 then '28100000-0000-0000-0000-000000000002'::uuid else '28100000-0000-0000-0000-000000000001'::uuid end,
  case when n = 6 then 'calculated'::public.fare_quote_status else 'locked'::public.fare_quote_status end,
  '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}',
  3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700,
  (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active),
  (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active),
  1, now(), now() + interval '10 minutes', case when n = 6 then null else now() end
from generate_series(1, 7) n;

-- Seed the historical Card command's original ledger claim so this checks replay
-- behavior without causing the recovery call to claim a fresh idempotency key.
insert into public.command_idempotency_keys (
  actor_user_id, command_scope, idempotency_key, payload_fingerprint, canonical_result
) values (
  '28100000-0000-0000-0000-000000000001', 'booking', 'historical-card-recovery',
  encode(extensions.digest(convert_to('28200000-0000-0000-0000-000000000004|2', 'UTF8'), 'sha256'), 'hex'),
  jsonb_build_object('booking_request_id', '28200000-0000-0000-0000-000000000004'::uuid, 'status', 'confirmed')
);

alter table public.booking_requests disable trigger booking_requests_bump_optimistic_version;
alter table public.booking_requests disable trigger booking_requests_enforce_transition;
update public.booking_requests b
set fare_quote_id = ('28300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
    status = case when n = 4 then 'confirmed'::public.booking_request_status else b.status end,
    confirmed_at = case when n = 4 then now() else b.confirmed_at end
from generate_series(1, 7) n
where b.id = ('28200000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid;
alter table public.booking_requests enable trigger booking_requests_enforce_transition;
alter table public.booking_requests enable trigger booking_requests_bump_optimistic_version;

select ok(has_function_privilege('authenticated', 'public.rider_confirm_booking(uuid,integer,text)', 'EXECUTE'), 'authenticated retains confirmation execute');
select ok(not has_function_privilege('anon', 'public.rider_confirm_booking(uuid,integer,text)', 'EXECUTE'), 'anon cannot execute confirmation');
select ok(not has_function_privilege('service_role', 'public.rider_confirm_booking(uuid,integer,text)', 'EXECUTE'), 'service_role cannot execute confirmation');
select ok((select prosecdef from pg_proc where oid = 'public.rider_confirm_booking(uuid,integer,text)'::regprocedure), 'confirmation remains SECURITY DEFINER');
select ok((select proconfig @> array['search_path=""'] from pg_proc where oid = 'public.rider_confirm_booking(uuid,integer,text)'::regprocedure), 'confirmation retains an empty search path');

set local role authenticated;
select set_config('request.jwt.claim.sub', '28100000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.rider_update_booking_draft(
  '28200000-0000-0000-0000-000000000008', 1,
  '{"latitude":31.95,"longitude":35.93}'::jsonb,
  '{"latitude":31.98,"longitude":35.97}'::jsonb,
  'economy'::public.vehicle_type_code, 'card'::public.payment_method, '[]'::jsonb
 )$$, 'Rider can persist Card on an authorized draft');
select is((select payment_method::text from public.booking_requests where id = '28200000-0000-0000-0000-000000000008'), 'card', 'persisted Card method is canonical');
reset role;

insert into public.fare_quotes (
  id, booking_request_id, rider_id, status, pickup, destination,
  route_distance_meters, route_duration_seconds, vehicle_type_code,
  breakdown, fixed_fare_fils, pricing_configuration_id, pricing_version,
  quote_version, created_at, expires_at, locked_at
) values (
  '28300000-0000-0000-0000-000000000008', '28200000-0000-0000-0000-000000000008',
  '28100000-0000-0000-0000-000000000001', 'calculated',
  '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.98,"longitude":35.97}',
  3000, 600, 'economy', '{"fixed_fare_fils":1700}', 1700,
  (select id from public.pricing_configurations where vehicle_type_code = 'economy' and is_active),
  (select pricing_version from public.pricing_configurations where vehicle_type_code = 'economy' and is_active),
  1, now(), now() + interval '10 minutes', null
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '28100000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.rider_lock_fare_quote(
  '28200000-0000-0000-0000-000000000008', '28300000-0000-0000-0000-000000000008', 2, 1
 )$$, 'Rider locks the valid FareQuote for the Card draft');
select is((select status::text from public.fare_quotes where id = '28300000-0000-0000-0000-000000000008'), 'locked', 'FareQuote is canonically locked');
select is((select version from public.booking_requests where id = '28200000-0000-0000-0000-000000000008'), 3, 'locking the Card draft quote advances its booking version');
select throws_ok($$select public.rider_confirm_booking('28200000-0000-0000-0000-000000000008', 3, 'card-updated-confirm')$$, '55000', 'Only Cash bookings can be confirmed until Card authorization is available.', 'direct RPC rejects Card persisted through draft update');
select is((select payment_method::text from public.booking_requests where id = '28200000-0000-0000-0000-000000000008'), 'card', 'rejected updated booking retains canonical Card method');
select is((select status::text from public.booking_requests where id = '28200000-0000-0000-0000-000000000008'), 'draft', 'Card rejection after draft update preserves status');
select is((select version from public.booking_requests where id = '28200000-0000-0000-0000-000000000008'), 3, 'Card rejection after draft update preserves version');
reset role;
select is((select count(*)::integer from public.audit_records where action = 'booking.confirmed' and new_data->>'booking_request_id' = '28200000-0000-0000-0000-000000000008'), 0, 'Card rejection after draft update writes no confirmation audit');

set local role authenticated;
select set_config('request.jwt.claim.sub', '28100000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(public.rider_confirm_booking('28200000-0000-0000-0000-000000000001', 1, 'cash-confirm-1')->>'status', 'confirmed', 'valid locked Cash booking confirms');
select throws_ok($$select public.rider_confirm_booking('28200000-0000-0000-0000-000000000002', 1, 'card-confirm-2')$$, '55000', 'Only Cash bookings can be confirmed until Card authorization is available.', 'direct authenticated RPC rejects canonical Card');
select is((select status::text from public.booking_requests where id = '28200000-0000-0000-0000-000000000002'), 'draft', 'Card rejection preserves booking status');
select is((select version from public.booking_requests where id = '28200000-0000-0000-0000-000000000002'), 1, 'Card rejection preserves booking version');
reset role;
select is((select count(*)::integer from public.audit_records where action = 'booking.confirmed' and new_data->>'booking_request_id' = '28200000-0000-0000-0000-000000000002'), 0, 'Card rejection writes no confirmation audit');
set local role authenticated;
select set_config('request.jwt.claim.sub', '28100000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.rider_confirm_booking('28200000-0000-0000-0000-000000000007', 1, 'wrong-owner')$$, 'P0002', 'Booking was not found for this Rider.', 'wrong Rider cannot confirm another Rider booking');
select throws_ok($$select public.rider_confirm_booking('28200000-0000-0000-0000-000000000005', 2, 'stale-version')$$, '40001', 'Booking version is stale.', 'stale booking version is rejected');
select throws_ok($$select public.rider_confirm_booking('28200000-0000-0000-0000-000000000006', 1, 'unlocked-quote')$$, '55000', 'Booking confirmation requires its active locked FareQuote.', 'unlocked quote is rejected');
select is(public.rider_confirm_booking('28200000-0000-0000-0000-000000000001', 1, 'cash-confirm-1')->>'status', 'confirmed', 'same idempotency key replays canonical result');
select is(public.rider_confirm_booking('28200000-0000-0000-0000-000000000001', 1, 'cash-confirm-other-payload')->>'status', 'confirmed', 'confirmed booking recovery returns canonical result');
select is(public.rider_confirm_booking('28200000-0000-0000-0000-000000000004', 2, 'historical-card-recovery')->>'status', 'confirmed', 'historical confirmed booking recovers before policy checks');
select is((select status::text from public.booking_requests where id = '28200000-0000-0000-0000-000000000004'), 'confirmed', 'historical confirmed booking remains unchanged');
select is((select version from public.booking_requests where id = '28200000-0000-0000-0000-000000000004'), 2, 'historical recovery preserves version');
select is((select payment_method::text from public.booking_requests where id = '28200000-0000-0000-0000-000000000004'), 'card', 'historical confirmed Card method is preserved');
reset role;
select is((select count(*)::integer from public.audit_records where action = 'booking.confirmed' and new_data->>'booking_request_id' = '28200000-0000-0000-0000-000000000004'), 0, 'historical Card replay writes no new confirmation audit');
select is((select count(*)::integer from public.command_idempotency_keys where actor_user_id = '28100000-0000-0000-0000-000000000001' and command_scope = 'booking' and idempotency_key = 'historical-card-recovery'), 1, 'historical Card replay reuses existing idempotency ledger entry');
-- A fresh-key recovery call may claim a new ledger row under the unchanged RPC contract.

set local role authenticated;
select set_config('request.jwt.claim.sub', '28100000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.rider_confirm_booking('28200000-0000-0000-0000-000000000001', 1, 'blocked-rider')$$, '42501', 'Only a non-blocked Rider can manage bookings.', 'blocked Rider is rejected');
reset role;

select * from finish();
rollback;
