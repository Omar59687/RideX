begin;
select no_plan();
\ir fixtures/r06_x2_reserved_target.sql
\ir fixtures/r06_x2_synthetic_approval.sql
\ir fixtures/r06_x2_unrelated_financial_evidence.sql
create function pg_temp.refuses_evidence_erasure(setup text, mutation text)
returns boolean language plpgsql as $$
declare setup_completed boolean := false;
begin
  begin
    execute setup;
    setup_completed := true;
    execute mutation;
    raise exception using errcode='PX001',message='unexpected success';
  exception when others then return setup_completed and sqlstate='55000';
  end;
end;
$$;
select ok(pg_temp.refuses_evidence_erasure(
 'update public.processed_webhook_events set payment_id=''cbbb4b94-ac92-49b9-8b43-1f370c783e5b''',
 'delete from public.processed_webhook_events'), 'target webhook cannot be erased before recovery');
select ok(pg_temp.refuses_evidence_erasure(
 'update public.processed_webhook_events set payment_id=''cbbb4b94-ac92-49b9-8b43-1f370c783e5b''',
 'update public.processed_webhook_events set payment_id=null'), 'target webhook cannot be unlinked before recovery');
select ok(pg_temp.refuses_evidence_erasure(
 'update public.refunds set payment_id=''cbbb4b94-ac92-49b9-8b43-1f370c783e5b''',
 'delete from public.refunds'), 'target Refund cannot be erased before recovery');
select ok(pg_temp.refuses_evidence_erasure(
 'update public.refunds set payment_id=''cbbb4b94-ac92-49b9-8b43-1f370c783e5b''',
 'update public.refunds set payment_id=''cbbb4b94-ac92-49b9-8b43-1f370c783e50'''),
 'target Refund cannot be reassigned before recovery');
select ok(pg_temp.refuses_evidence_erasure(
 'insert into public.trip_change_requests(trip_id,rider_id,requested_destination) values
 (''dda56345-4123-4a0c-9771-5287899d2344'',''d3c3dc11-a840-4712-a6a4-599b4ae27329'',
 ''{"latitude":32.0,"longitude":36.0}'')',
 'delete from public.trip_change_requests'), 'target change-request evidence cannot be erased before recovery');
set local role service_role;
select lives_ok('update public.processed_webhook_events set provider_event_id=''LOCAL-unlinked-updated''',
 'unrelated webhook updates preserve baseline behavior');
select lives_ok('update public.refunds set reason_code=''LOCAL unrelated updated''',
 'unrelated Refund updates preserve baseline behavior');
reset role;
select set_config('request.jwt.claims','{"sub":"d3c3dc11-a840-4712-a6a4-599b4ae27329","role":"authenticated"}',true);
set local role authenticated;
select is(public.rider_recover_r06_x2_reserved_fixture(
 '8168236a-6a53-4a08-8dfa-f79e68fe8925','dda56345-4123-4a0c-9771-5287899d2344',
 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b','45ae3584-fa38-4fa5-b8c8-10efd79f8416',
 1,1,12,'8168236a-6a53-4a08-8dfa-f79e68fe8921','8168236a-6a53-4a08-8dfa-f79e68fe8923')->>'trip_status',
 'cancelledByRider','unrelated evidence does not block exact recovery');
reset role;
set local role service_role;
select throws_ok('update public.processed_webhook_events set payment_id=''cbbb4b94-ac92-49b9-8b43-1f370c783e5b''',
 '55000',null,'webhook NULL-to-target update cannot bypass the fence');
select throws_ok('update public.refunds set payment_id=''cbbb4b94-ac92-49b9-8b43-1f370c783e5b''',
 '55000',null,'existing unrelated Refund cannot be reassigned across the fence');
select throws_ok($cmd$insert into public.trip_change_requests(trip_id,rider_id,requested_destination) values
 ('dda56345-4123-4a0c-9771-5287899d2344','d3c3dc11-a840-4712-a6a4-599b4ae27329',
 '{"latitude":32.0,"longitude":36.0}')$cmd$,'55000',null,'late Trip change cannot cross recovery FK wait');
reset role;
select is((select count(*)::integer from public.processed_webhook_events where payment_id='cbbb4b94-ac92-49b9-8b43-1f370c783e5b'),
 0,'failed reassignment leaves no target webhook');
select is((select count(*)::integer from public.refunds where payment_id='cbbb4b94-ac92-49b9-8b43-1f370c783e5b'),
 0,'failed reassignment leaves no target Refund');
select is((select count(*)::integer from public.trip_change_requests),0,'failed insert leaves no unresolved Trip change');
select * from finish();
rollback;
