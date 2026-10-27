begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
\ir fixtures/r06_retirement_target.sql

update public.trips set status = 'driverArriving'
where id = 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba';
select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$select public.rider_cancel_trip(
    'ceff7eb6-2d1f-4744-9cbc-243d80d550ba', 2, 'generic_later_state_bypass')$$,
  '55000', 'The historical R06 Trip requires guarded retirement.',
  'generic Rider cancellation cannot bypass the guard after Trip progression');
reset role;

select is((select status::text from public.trips
  where id='ceff7eb6-2d1f-4744-9cbc-243d80d550ba'),
  'driverArriving', 'blocked generic cancellation preserves the current Trip state');
select * from finish();
rollback;
