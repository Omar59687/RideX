begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
\ir fixtures/r06_retirement_target.sql

select ok(has_function_privilege('authenticated',
  'public.rider_retire_r06_card_fixture(uuid,integer,uuid,integer,uuid)', 'EXECUTE'),
  'authenticated role can call the guarded Rider operation');
select ok(not has_function_privilege('anon',
  'public.rider_retire_r06_card_fixture(uuid,integer,uuid,integer,uuid)', 'EXECUTE'),
  'anon cannot call the guarded Rider operation');
select ok(not has_function_privilege('service_role',
  'public.rider_retire_r06_card_fixture(uuid,integer,uuid,integer,uuid)', 'EXECUTE'),
  'service_role cannot impersonate the Rider operation');
select ok(not has_table_privilege('authenticated',
  'private.r06_retirement_authorizations', 'INSERT'),
  'authenticated cannot forge a guarded cancellation marker');
select ok((select relrowsecurity from pg_class where oid='public.payment_attempts'::regclass),
  'the existing Attempt RLS boundary remains enabled');
select is((select count(*) from pg_policies
  where schemaname='public' and tablename='payment_attempts' and cmd in ('SELECT','ALL')),
  0::bigint, 'the migration adds no direct Attempt SELECT policy');

create temporary table r06_attempt_before as
select to_jsonb(attempts) as evidence
from public.payment_attempts as attempts
where idempotency_key = 'r06-retirement-original-authorization';

select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_retire_r06_card_fixture(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 1,
    '44444444-4444-4444-8444-444444444438', 1,
    (select id from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'))$$,
  '42501', 'R06 retirement target is unavailable to this Rider.',
  'a different Rider cannot retire the exact historical Trip');

update public.users set is_blocked = true
where id = '22000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.rider_retire_r06_card_fixture(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 1,
    '44444444-4444-4444-8444-444444444438', 1,
    (select id from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'))$$,
  '42501', 'Only a non-blocked Rider can manage bookings.',
  'blocked owning Rider is denied');
update public.users set is_blocked = false
where id = '22000000-0000-0000-0000-000000000001';
select set_config('ridex.r06_attempt_id',
  (select id::text from public.payment_attempts
   where idempotency_key='r06-retirement-original-authorization'), true);
set local role authenticated;
select throws_ok(
  $$select public.rider_cancel_trip(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 1, 'generic_bypass_attempt')$$,
  '55000', 'The historical R06 Trip requires guarded retirement.',
  'the generic Rider cancellation cannot bypass the fixture guard');
reset role;

select throws_ok(
  $$select public.rider_retire_r06_card_fixture(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 999,
    '44444444-4444-4444-8444-444444444438', 1,
    (select id from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'))$$,
  '40001', 'R06 Trip version changed; re-preflight is required.',
  'stale Trip version is rejected');
select throws_ok(
  $$select public.rider_retire_r06_card_fixture(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 1,
    '44444444-4444-4444-8444-444444444438', 999,
    (select id from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'))$$,
  '40001', 'R06 Payment version changed; re-preflight is required.',
  'stale Payment version is rejected');
select throws_ok(
  $$select public.rider_retire_r06_card_fixture(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 1,
    '44444444-4444-4444-8444-444444444438', 1,
    '00000000-0000-4000-8000-000000000099')$$,
  '55000', 'R06 authorization evidence is not eligible for retirement.',
  'incorrect Attempt identity is rejected');
select throws_ok(
  $$select public.rider_retire_r06_card_fixture(
    '22400000-0000-0000-0000-000000000001', 1,
    '44444444-4444-4444-8444-444444444438', 1,
    (select id from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'))$$,
  '42501', 'R06 retirement target is not authorized.',
  'a different Trip cannot use the R06-only RPC');

set local role authenticated;
select lives_ok(
  $$select public.rider_retire_r06_card_fixture(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 1,
    '44444444-4444-4444-8444-444444444438', 1,
    pg_catalog.current_setting('ridex.r06_attempt_id')::uuid)$$,
  'the exact historical fixture is cancelled by its owning Rider');
reset role;
select is((select status::text from public.trips where id='ceff7eb6-2d1f-4744-9cbc-243d80d550ba'),
  'cancelledByRider', 'canonical Trip transition is retained');
select is((select card_status::text from public.payments where id='44444444-4444-4444-8444-444444444438'),
  'paymentCancelled', 'canonical payment reconciliation is retained');
select is((select status::text from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'),
  'pending', 'pending authorization evidence is not rewritten');
select is((select to_jsonb(attempts) from public.payment_attempts as attempts
  where idempotency_key='r06-retirement-original-authorization'),
  (select evidence from r06_attempt_before), 'Attempt bytes including timestamp and operation key are preserved');
select is((select count(*) from public.receipts where trip_id='ceff7eb6-2d1f-4744-9cbc-243d80d550ba'),
  0::bigint, 'retirement does not issue a Receipt');
select is((select count(*) from private.r06_retirement_authorizations
  where trip_id='ceff7eb6-2d1f-4744-9cbc-243d80d550ba'),
  0::bigint, 'transaction authorization marker is removed before commit');
select is((select count(*) from private.stripe_test_dispatch_reservations
  where trip_id='ceff7eb6-2d1f-4744-9cbc-243d80d550ba'),
  0::bigint, 'retirement does not create or retain a reservation');
select is((select state::text from public.driver_availability
  where driver_id='22000000-0000-0000-0000-000000000002'),
  'offline', 'canonical Rider cancellation releases Driver availability to offline');

select set_config('request.jwt.claim.role', 'service_role', true);
select throws_ok(
  $$select public.backend_complete_payment_attempt(
    (select id from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'),
    'failed', 'pi_late_completion')$$,
  '55000', 'The retired R06 authorization evidence is immutable.',
  'late backend completion cannot rewrite the retired Attempt');
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select status::text from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'),
  'pending', 'late completion rejection preserves Attempt state');

-- Existing Rider cancellation remains available and unchanged for ordinary Trips.
select lives_ok(
  $$select public.rider_cancel_trip('22400000-0000-0000-0000-000000000001', 1, 'normal_test_cancel')$$,
  'ordinary Rider cancellation keeps its existing contract');
select is((select card_status::text from public.payments
  where trip_id='22400000-0000-0000-0000-000000000001'),
  'paymentCancelled', 'ordinary Card cancellation still reconciles Payment');

select * from finish();
rollback;
