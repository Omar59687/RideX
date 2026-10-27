begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
\ir fixtures/r06_retirement_target.sql

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok(
  $$select public.backend_complete_payment_attempt(
    (select id from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'),
    'failed', 'pi_test_provider_failure')$$,
  'backend completion records provider-backed failure using its canonical RPC');
select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_retire_r06_card_fixture(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 1,
    '44444444-4444-4444-8444-444444444438', 1,
    (select id from public.payment_attempts where idempotency_key='r06-retirement-original-authorization'))$$,
  '55000', 'R06 authorization evidence is not eligible for retirement.',
  'provider-backed failed authorization cannot be retired');
select is((select status::text from public.trips where id='ceff7eb6-2d1f-4744-9cbc-243d80d550ba'),
  'accepted', 'provider evidence rejection leaves Trip active');
select is((select card_status::text from public.payments where id='44444444-4444-4444-8444-444444444438'),
  'cardPaymentPending', 'provider evidence rejection does not cancel Payment');
select is((select provider_transaction_reference from public.payment_attempts
  where idempotency_key='r06-retirement-original-authorization'),
  'pi_test_provider_failure', 'provider reference is preserved as evidence');
select * from finish();
rollback;
