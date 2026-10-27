begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
\ir fixtures/r06_retirement_target.sql

insert into public.payment_attempts (
  payment_id, type, status, requested_amount_fils, currency, idempotency_key,
  provider_name, provider_transaction_reference, sanitized_failure_code,
  created_at, completed_at, authorization_cycle
)
values (
  '44444444-4444-4444-8444-444444444438', 'capture', 'failed', 2000,
  'JOD', 'r06-retirement-unexpected-capture', 'stripe',
  'pi_unexpected_capture_reference', 'DECLINED', now(), now(), 1
);

select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.rider_retire_r06_card_fixture(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 1,
    '44444444-4444-4444-8444-444444444438', 1,
    (select id from public.payment_attempts
     where idempotency_key='r06-retirement-original-authorization'))$$,
  '55000', 'R06 payment attempt history is not eligible for retirement.',
  'a provider-backed non-authorization Attempt blocks retirement');
select is((select status::text from public.trips
  where id='ceff7eb6-2d1f-4744-9cbc-243d80d550ba'),
  'accepted', 'unexpected Attempt evidence leaves the Trip active');

select * from finish();
rollback;
