begin;
\ir fixtures/r06_x2_reserved_target.sql
\ir fixtures/r06_x2_synthetic_approval.sql
commit;
begin isolation level repeatable read;
select no_plan();
select set_config('request.jwt.claims','{"sub":"d3c3dc11-a840-4712-a6a4-599b4ae27329","role":"authenticated"}',true);
select throws_ok($cmd$select public.rider_recover_r06_x2_reserved_fixture(
 '8168236a-6a53-4a08-8dfa-f79e68fe8925','dda56345-4123-4a0c-9771-5287899d2344',
 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b','45ae3584-fa38-4fa5-b8c8-10efd79f8416',
 1,1,12,'8168236a-6a53-4a08-8dfa-f79e68fe8921','8168236a-6a53-4a08-8dfa-f79e68fe8923')$cmd$,
 '55000','R06-X2 requires READ COMMITTED isolation.','recovery rejects a stale transaction snapshot');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok($cmd$select public.backend_claim_stripe_test_preparation(
 'd3c3dc11-a840-4712-a6a4-599b4ae27329','dda56345-4123-4a0c-9771-5287899d2344',
 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b','45ae3584-fa38-4fa5-b8c8-10efd79f8416',1,1,'r06-x2-synthetic-operation')$cmd$,
 '55000','R06-X2 requires READ COMMITTED isolation.','target claim rejects repeatable read');
select throws_ok($cmd$select public.backend_complete_payment_attempt(
 '45ae3584-fa38-4fa5-b8c8-10efd79f8416','failed','pi_Local')$cmd$,
 '55000','R06-X2 requires READ COMMITTED isolation.','target completion rejects repeatable read');
select throws_ok($cmd$select public.backend_record_stripe_test_preparation(
 '45ae3584-fa38-4fa5-b8c8-10efd79f8416',gen_random_uuid(),'pi_Local')$cmd$,
 '55000','R06-X2 requires READ COMMITTED isolation.','target result rejects repeatable read');
select * from finish();
rollback;
