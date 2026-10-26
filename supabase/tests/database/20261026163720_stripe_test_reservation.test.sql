\ir fixtures/r06_card_context.sql
select no_plan();
set search_path=public,extensions;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
create temporary table r06_claims(tag text primary key, result jsonb);
create temporary table r06_before as select md5(string_agg(to_jsonb(a)::text,',' order by id)) as digest from public.payment_attempts a;
create function pg_temp.claim_r06(actor uuid default '22000000-0000-0000-0000-000000000001',
  tv integer default 1, pv integer default 1, op text default 'r06-original-authorization')
returns jsonb language sql as $$
  select public.backend_claim_stripe_test_preparation(actor,
    '22400000-0000-0000-0000-000000000001','22500000-0000-0000-0000-000000000001',
    (select id from public.payment_attempts where idempotency_key='r06-original-authorization'),tv,pv,op);
$$;
select ok(not has_function_privilege('anon','public.backend_claim_stripe_test_preparation(uuid,uuid,uuid,uuid,integer,integer,text)','EXECUTE'),'anonymous cannot claim');
select ok(not has_function_privilege('authenticated','public.backend_claim_stripe_test_preparation(uuid,uuid,uuid,uuid,integer,integer,text)','EXECUTE'),'Rider/Admin client cannot claim');
select ok(has_function_privilege('service_role','public.backend_claim_stripe_test_preparation(uuid,uuid,uuid,uuid,integer,integer,text)','EXECUTE'),'only backend receives claim grant');
select ok(not has_table_privilege('service_role','private.stripe_test_dispatch_reservations','INSERT'),'service has no direct reservation writes');
select ok(not has_table_privilege('authenticated','private.stripe_test_dispatch_reservations','SELECT'),'client cannot read claim tokens/evidence');
select ok((select relrowsecurity from pg_class where oid='private.stripe_test_dispatch_reservations'::regclass),'reservation RLS enabled');
select throws_ok($$select pg_temp.claim_r06('22000000-0000-0000-0000-000000000004')$$,'42501','Canonical preparation context unavailable.','foreign actor cannot claim');
select throws_ok($$select pg_temp.claim_r06(tv=>999)$$,'40001','Canonical preparation version changed.','stale Trip version rejected');
select throws_ok($$select pg_temp.claim_r06(pv=>999)$$,'40001','Canonical preparation version changed.','stale Payment version rejected');
select throws_ok($$select pg_temp.claim_r06(op=>'rotated-operation-key')$$,'42501','Canonical preparation context unavailable.','wrong original operation key rejected');
select throws_ok($$select public.backend_claim_stripe_test_preparation(
  '22000000-0000-0000-0000-000000000001','22400000-0000-0000-0000-000000000002',
  '22500000-0000-0000-0000-000000000002',
  (select id from public.payment_attempts where idempotency_key='r06-expired-authorization'),
  1,1,'r06-expired-authorization')$$,'42501','Canonical preparation context unavailable.','expired original authorization attempt cannot dispatch');
update public.users set is_blocked=true where id='22000000-0000-0000-0000-000000000001';
select throws_ok($$select pg_temp.claim_r06()$$,'42501','Canonical preparation context unavailable.','blocked Rider rejected');
update public.users set is_blocked=false where id='22000000-0000-0000-0000-000000000001';
insert into r06_claims values('first',pg_temp.claim_r06());
insert into r06_claims values('duplicate',pg_temp.claim_r06());
select is((select result->>'disposition' from r06_claims where tag='first'),'claimed','first durable claim wins');
select is((select result->>'disposition' from r06_claims where tag='duplicate'),'existing','duplicate has no dispatch permission');
select ok((select result ? 'claimToken' from r06_claims where tag='first'),'winner receives claim token');
select ok(not(select result ? 'claimToken' from r06_claims where tag='duplicate'),'duplicate never receives claim token');
select is((select count(*) from private.stripe_test_dispatch_reservations),1::bigint,'exactly one reservation exists');
select is((select operation_key from private.stripe_test_dispatch_reservations),'r06-original-authorization','original key persisted unchanged');
select is((select state from private.stripe_test_dispatch_reservations),'reserved','reserved is uncertain, not payment success');
select throws_ok($$select public.backend_record_stripe_test_preparation(
  (select id from public.payment_attempts where idempotency_key='r06-original-authorization'),
  '00000000-0000-4000-8000-000000000000','pi_Foreign')$$,'42501','Original dispatch claim required.','wrong token cannot attach evidence');
select public.backend_record_stripe_test_preparation(
  (select attempt_id from private.stripe_test_dispatch_reservations),
  (select claim_token from private.stripe_test_dispatch_reservations),null);
select is((select state from private.stripe_test_dispatch_reservations),'unknown','unknown outcome retained');
select is(pg_temp.claim_r06()->>'disposition','existing','unknown cannot be reclaimed');
select public.backend_record_stripe_test_preparation(
  (select attempt_id from private.stripe_test_dispatch_reservations),
  (select claim_token from private.stripe_test_dispatch_reservations),'pi_LocalFixture');
select public.backend_record_stripe_test_preparation(
  (select attempt_id from private.stripe_test_dispatch_reservations),
  (select claim_token from private.stripe_test_dispatch_reservations),null);
select is((select state from private.stripe_test_dispatch_reservations),'prepared','stronger evidence cannot be downgraded');
select is((select provider_reference from private.stripe_test_dispatch_reservations),'pi_LocalFixture','trusted provider reference retained');
select throws_ok($$select public.backend_record_stripe_test_preparation(
  (select attempt_id from private.stripe_test_dispatch_reservations),
  (select claim_token from private.stripe_test_dispatch_reservations),'pi_Conflicting')$$,'23505','Preparation evidence conflicts.','conflicting references rejected');
select is(public.backend_read_stripe_test_preparation(
  (select attempt_id from private.stripe_test_dispatch_reservations),
  '22000000-0000-0000-0000-000000000001')->>'reference','pi_LocalFixture','read-only reconciliation retrieves stored exact identifier');
select ok(public.backend_read_stripe_test_preparation(
  (select attempt_id from private.stripe_test_dispatch_reservations),
  '22000000-0000-0000-0000-000000000004') is null,'foreign owner receives no reservation');
select is((select md5(string_agg(to_jsonb(a)::text,',' order by id)) from public.payment_attempts a),
  (select digest from r06_before),'attempt bytes/status unchanged');
select is((select card_status::text from public.payments where id='22500000-0000-0000-0000-000000000001'),'cardPaymentPending','preparation never authorizes Payment');
select is((select count(*) from public.receipts),0::bigint,'no receipt issued');
select ok(not has_table_privilege('service_role','private.stripe_test_dispatch_reservations','DELETE'),'no backend direct deletion grant');
select * from finish();
rollback;
