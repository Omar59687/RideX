begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
\ir fixtures/r06_retirement_target.sql

insert into private.stripe_test_dispatch_reservations (
  attempt_id, payment_id, trip_id, rider_id, operation_key, context
)
values (
  (select id from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'),
  '44444444-4444-4444-8444-444444444438',
  'ceff7eb6-2d1f-4744-9cbc-243d80d550ba',
  '22000000-0000-0000-0000-000000000001',
  'r06-retirement-reservation-test', '{}'::jsonb
);
select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_retire_r06_card_fixture(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 1,
    '44444444-4444-4444-8444-444444444438', 1,
    (select id from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'))$$,
  '55000', 'R06 dispatch reservation exists; retirement is refused.',
  'existing Stripe dispatch reservation blocks retirement');
select is((select status::text from public.trips where id='ceff7eb6-2d1f-4744-9cbc-243d80d550ba'),
  'accepted', 'reservation rejection leaves Trip active');
select is((select card_status::text from public.payments where id='44444444-4444-4444-8444-444444444438'),
  'cardPaymentPending', 'reservation rejection leaves Payment pending');
select is((select status::text from public.payment_attempts
  where idempotency_key='r06-retirement-original-authorization'),
  'pending', 'reservation rejection preserves Attempt');
select * from finish();
rollback;
