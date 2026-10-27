begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select set_config('ridex.r06_fixture_provider', '__NULL__', true);
\ir fixtures/r06_retirement_target.sql

select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('ridex.r06_attempt_id',
  (select id::text from public.payment_attempts
   where idempotency_key='r06-retirement-original-authorization'), true);
set local role authenticated;
select throws_ok(
  $$select public.rider_retire_r06_card_fixture(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 1,
    '44444444-4444-4444-8444-444444444438', 1,
    pg_catalog.current_setting('ridex.r06_attempt_id')::uuid)$$,
  '55000', 'R06 authorization evidence is not eligible for retirement.',
  'NULL provider identity is rejected');
reset role;
select is((select status::text from public.trips
  where id='ceff7eb6-2d1f-4744-9cbc-243d80d550ba'),
  'accepted', 'NULL provider rejection leaves the Trip active');
select * from finish();
rollback;
