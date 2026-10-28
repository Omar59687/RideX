begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
\ir fixtures/r06_x2_reserved_target.sql
\ir fixtures/r06_x2_synthetic_approval.sql
create temporary table x2_command(command text);
insert into x2_command values ($cmd$select public.rider_recover_r06_x2_reserved_fixture(
 '8168236a-6a53-4a08-8dfa-f79e68fe8925','dda56345-4123-4a0c-9771-5287899d2344',
 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b','45ae3584-fa38-4fa5-b8c8-10efd79f8416',
 1,1,12,'8168236a-6a53-4a08-8dfa-f79e68fe8921','8168236a-6a53-4a08-8dfa-f79e68fe8923')$cmd$);
create function pg_temp.refused(mutation text, command text default null, expected_code text default '55000', expected_message text default null)
returns boolean language plpgsql as $$
begin
  begin
    if mutation <> '' then execute mutation; end if;
    execute coalesce(command,(select c.command from x2_command c));
    raise exception using errcode='PX001',message='unexpected success';
  exception when others then return sqlstate = expected_code and (expected_message is null or sqlerrm = expected_message);
  end;
end;
$$;
create function pg_temp.drift(tab regclass, assignment text)
returns boolean language sql as $$
 select pg_temp.refused(format('alter table %s disable trigger user; update %s set %s; alter table %s enable trigger user;',
 tab,tab,assignment,tab));
$$;
select set_config('request.jwt.claims','{"sub":"d3c3dc11-a840-4712-a6a4-599b4ae27329","role":"authenticated"}',true);

select ok(not has_table_privilege(role_name,table_name,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),
 role_name || ' cannot read/provision/alter protected ' || table_name)
from (values ('anon'),('authenticated'),('service_role')) roles(role_name)
cross join (values ('private.r06_x2_owner_approvals'),('private.r06_x2_recoveries'),
 ('private.r06_x2_late_observations'),('private.r06_x2_authorizations')) tables(table_name);
select ok((select bool_and(relrowsecurity) from pg_class where oid in (
 'private.r06_x2_owner_approvals'::regclass,'private.r06_x2_recoveries'::regclass,
 'private.r06_x2_late_observations'::regclass)),'private records have RLS');
select ok(not has_function_privilege('service_role','private.r06_x2_snapshot_digest()','EXECUTE'),
 'service client cannot obtain protected snapshot digest');
select ok(not has_function_privilege('authenticated',
 'public.backend_record_stripe_test_preparation_fenced(uuid,uuid,text)','EXECUTE'),
 'Rider cannot import backend evidence');
select ok(not has_function_privilege('service_role',
 'public.rider_recover_r06_x2_reserved_fixture(uuid,uuid,uuid,uuid,integer,integer,integer,uuid,uuid)','EXECUTE'),
 'service client cannot recover as Rider');
select ok(not has_function_privilege('service_role',
 'private.r06_x2_original_record(uuid,uuid,text)','EXECUTE'),'original record cannot bypass wrapper');
select ok(not has_function_privilege('service_role',
 'private.r06_x2_original_complete(uuid,public.payment_attempt_status,text,text)','EXECUTE'),
 'original completion cannot bypass wrapper');

select ok(pg_temp.refused('',replace(command,'8168236a-6a53-4a08-8dfa-f79e68fe8925',
 '8168236a-6a53-4a08-8dfa-f79e68fe8920'),'42501'),'wrong fixture denied') from x2_command;
select ok(pg_temp.refused('',replace(command,'dda56345-4123-4a0c-9771-5287899d2344',
 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba'),'42501'),'historical fixture cannot enter X2') from x2_command;
select ok(pg_temp.refused('',replace(command,'cbbb4b94-ac92-49b9-8b43-1f370c783e5b',
 'cbbb4b94-ac92-49b9-8b43-1f370c783e50'),'42501'),'wrong payment denied') from x2_command;
select ok(pg_temp.refused('',replace(command,'45ae3584-fa38-4fa5-b8c8-10efd79f8416',
 '45ae3584-fa38-4fa5-b8c8-10efd79f8410'),'42501'),'wrong Attempt denied') from x2_command;
select ok(pg_temp.refused('',replace(command,'1,1,12','2,1,12'),'22023'),'caller Trip version must match assessment') from x2_command;
select ok(pg_temp.refused('',replace(command,'1,1,12','1,2,12'),'22023'),'caller Payment version must match assessment') from x2_command;
select ok(pg_temp.refused('',replace(command,'1,1,12','1,1,13'),'22023'),'caller Driver version must match assessment') from x2_command;
select ok(pg_temp.refused($m$select set_config('request.jwt.claims',
 '{"sub":"d3c3dc11-a840-4712-a6a4-599b4ae27320","role":"authenticated"}',true)$m$,null,'42501'),
 'foreign Rider denied');
select ok(pg_temp.refused($m$select set_config('request.jwt.claims',
 '{"sub":"f148a7ec-7e85-48ef-847f-8e9eea880e1b","role":"authenticated"}',true)$m$,null,'42501'),
 'Driver cannot recover as Rider');
select ok(pg_temp.refused($m$select set_config('request.jwt.claims',
 '{"sub":"d3c3dc11-a840-4712-a6a4-599b4ae27329","role":"service_role"}',true)$m$,null,'42501'),
 'service JWT is not owning Rider authorization');
select ok(pg_temp.refused('update public.users set is_blocked=true where role=''rider''',null,'42501'),
 'blocked Rider denied');
select ok(pg_temp.refused('update public.users set role=''admin'' where role=''rider''',null,'42501'),
 'non Rider owner role denied');

select ok(pg_temp.drift(tab::regclass,assignment),label)
from (values
 ('public.trips','version=2','stale Trip rejected'),
 ('public.payments','version=2','stale Payment rejected'),
 ('public.driver_availability','version=13','stale Driver rejected'),
 ('public.trips','status=''driverArriving''','advanced Trip rejected'),
 ('public.payments','authorized_at=now()','authorization evidence rejected'),
 ('public.payments','paid_at=now()','settlement evidence rejected'),
 ('public.payments','refunded_at=now()','refund evidence rejected'),
 ('public.payments','sanitized_failure_code=''LOCAL_FAILURE''','payment failure evidence rejected'),
 ('public.payments','provider_name=''stripe''','unexpected Payment provider rejected'),
 ('public.payments','authorized_amount_fils=2540','wrong approved amount rejected'),
 ('public.payment_attempts','provider_name=null','null Attempt provider rejected'),
 ('public.payment_attempts','provider_name=''different''','wrong Attempt provider rejected'),
 ('public.payment_attempts','provider_transaction_reference=''pi_LocalEvidence''','existing Attempt reference rejected'),
 ('public.payment_attempts','sanitized_failure_code=''LOCAL_FAILURE''','Attempt failure evidence rejected'),
 ('public.payment_attempts','authorization_cycle=2','wrong authorization cycle rejected'),
 ('public.payment_attempts','created_at=now()','wrong creation evidence rejected'),
 ('private.stripe_test_dispatch_reservations','state=''unknown''','unknown reservation rejected'),
 ('private.stripe_test_dispatch_reservations','state=''prepared'',provider_reference=''pi_LocalEvidence''','prepared reservation rejected'),
 ('private.stripe_test_dispatch_reservations','context=context||''{"tripVersion":2}''::jsonb','conflicting reservation context rejected'),
 ('public.driver_availability','state=''offline'',vehicle_id=null,active_trip_id=null','Driver already released rejected'),
 ('public.driver_profiles','approval_status=''pending''','unapproved Driver rejected'),
 ('public.driver_profiles','version=3','Driver profile version drift rejected'),
 ('public.vehicles','is_active=false','inactive vehicle rejected'),
 ('public.booking_requests','version=6','Booking drift rejected'),
 ('public.fare_quotes','fixed_fare_fils=2540','FareQuote drift rejected')
) cases(tab,assignment,label);
select ok(pg_temp.refused('alter table public.trips disable trigger user; update public.trips set driver_id=null,vehicle_id=null; alter table public.trips enable trigger user;',null,'23502'),
 'missing active Driver relationship is rejected by canonical schema');
select ok(pg_temp.refused('alter table public.payment_attempts alter column attempt_sequence set generated by default; alter table public.payment_attempts disable trigger user; update public.payment_attempts set attempt_sequence=1; alter table public.payment_attempts enable trigger user;'),
 'wrong GLOBAL sequence rejected');
select ok(pg_temp.refused('delete from private.stripe_test_dispatch_reservations'), 'missing reservation rejected');
select ok(pg_temp.refused('delete from private.stripe_test_dispatch_reservations; alter table public.payment_attempts disable trigger user; delete from public.payment_attempts; alter table public.payment_attempts enable trigger user;'),
 'missing original Attempt rejected');
select ok(pg_temp.refused('delete from private.stripe_test_dispatch_reservations; alter table public.payment_attempts disable trigger user; delete from public.payment_attempts; alter table public.payment_attempts enable trigger user; delete from public.payments;'),
 'missing Payment rejected');
select ok(pg_temp.refused($m$insert into public.payment_attempts(payment_id,type,status,requested_amount_fils,currency,
 idempotency_key,provider_name,authorization_cycle) values ('cbbb4b94-ac92-49b9-8b43-1f370c783e5b',
 'providerStatusVerification','pending',2550,'JOD','local-extra-evidence','stripe',null)$m$),
 'conflicting additional Attempt rejected');
select ok(pg_temp.refused($m$insert into public.refunds(payment_id,amount_fils,reason_code,requested_by_admin_id)
 values ('cbbb4b94-ac92-49b9-8b43-1f370c783e5b',2550,'local_review','d3c3dc11-a840-4712-a6a4-599b4ae27329')$m$),
 'Refund row rejected');
select ok(pg_temp.refused($m$insert into public.receipts(receipt_number,trip_id,fare_quote_id,payment_id,
 rider_snapshot,driver_snapshot,vehicle_snapshot,pickup_snapshot,destination_snapshot,ordered_stops_snapshot,
 fare_breakdown_snapshot,amount_paid_fils,payment_method,source_versions)
 values ('RDX-20261028-LOCALX22','dda56345-4123-4a0c-9771-5287899d2344','90532842-03bf-4644-a656-2cad3edf37d1',
 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b','{}','{}','{}','{}','{}','[]','{}',2550,'card','{}')$m$),
 'existing receipt evidence rejected');
select ok(pg_temp.refused($m$select public.backend_record_processed_webhook_event('stripe','LOCAL-preexisting-event',
 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b')$m$), 'existing provider event evidence rejected');

select ok(pg_temp.refused('alter table private.r06_x2_owner_approvals disable trigger user; delete from private.r06_x2_owner_approvals; alter table private.r06_x2_owner_approvals enable trigger user;'),
 'missing trusted review fails closed');
select ok(pg_temp.refused('alter table private.r06_x2_owner_approvals disable trigger user; update private.r06_x2_owner_approvals set snapshot_digest=repeat(''9'',64); alter table private.r06_x2_owner_approvals enable trigger user;'),
 'conflicting approval digest fails closed');
select ok(pg_temp.refused('alter table private.r06_x2_owner_approvals disable trigger user; update private.r06_x2_owner_approvals set quiescent_since=now()-interval ''3 minutes'',expires_at=now()-interval ''1 second'',reviewed_at=now()-interval ''2 minutes''; alter table private.r06_x2_owner_approvals enable trigger user;'),
 'expired review fails closed');
select ok(pg_temp.refused('update private.r06_x2_owner_approvals set owner_review_reference=''replacement review''','select 1'),
 'approval UPDATE rejected even for owner');
select ok(pg_temp.refused('delete from private.r06_x2_owner_approvals','select 1'), 'approval DELETE rejected even for owner');
select ok(pg_temp.refused('truncate private.r06_x2_owner_approvals cascade','select 1'), 'approval TRUNCATE rejected even for owner');
select ok(pg_temp.refused('alter table private.r06_x2_owner_approvals disable trigger user; update private.r06_x2_owner_approvals set no_dispatch_assertion=''no_reference_seen'';','select 1','23514'),
 'absence of references cannot substitute for independently verified no dispatch');
select ok(pg_temp.refused('alter table private.r06_x2_owner_approvals disable trigger user; update private.r06_x2_owner_approvals set quiescence_assertion=''no_active_worker_seen'';','select 1','23514'),
 'incomplete worker evidence cannot substitute for revoked and drained claim holders');
select ok(pg_temp.refused('alter table private.r06_x2_owner_approvals disable trigger user; update private.r06_x2_owner_approvals set no_dispatch_provenance=quiescence_provenance;','select 1','23514'),
 'one provenance cannot pretend to be independent proofs');
select ok(pg_temp.refused($m$select set_config('ridex.r06_x2_authorized','on',true); select set_config('ridex.complete_payment_attempt','on',true)$m$,
 $cmd$select public.rider_cancel_trip('dda56345-4123-4a0c-9771-5287899d2344',1,'spoofed_marker')$cmd$),
 'generic cancellation cannot bypass guard with spoofed markers');
select ok(pg_temp.refused('update public.payments set card_status=''paymentCancelled'',cancelled_at=now()','select 1'),
 'direct financial cancellation cannot bypass guarded recovery');

-- Deliberately corrupt a canonical postcondition inside the same transaction;
-- failure must roll back Trip, Payment, Driver, revocation, event and audit.
create function pg_temp.corrupt_driver_release() returns trigger language plpgsql as $$
begin if new.state='offline' then new.last_heartbeat_at:=now(); end if; return new; end $$;
create temp table x2_audit_before_failure as select count(*)::integer as count from public.audit_records;
select ok(pg_temp.refused('create trigger zz_x2_corrupt before update on public.driver_availability for each row execute function pg_temp.corrupt_driver_release()',null,'55000',
 'R06-X2 recovery postconditions failed; transaction rolled back.'),
 'complete postcondition failure rolls back');
select is((select status::text from public.trips),'accepted','rollback retains accepted Trip');
select is((select card_status::text from public.payments),'cardPaymentPending','rollback retains pending Payment');
select is((select state::text from public.driver_availability),'onTrip','rollback retains Driver assignment');
select is((select count(*)::integer from private.r06_x2_recoveries),0,'rollback leaves no recovery fence');
select is((select count(*)::integer from public.trip_status_events),0,'rollback leaves no status event');
select is((select count(*)::integer from public.audit_records),(select count from x2_audit_before_failure),'rollback leaves no cancellation audit');

-- API privileges are exercised using actual roles, including service-role
-- attempts to forge approval and markers (not just catalogue assertions).
set local role service_role;
select throws_ok($cmd$insert into private.r06_x2_owner_approvals(id) values (gen_random_uuid())$cmd$,
 '42501',null,'service_role cannot provision approvals');
reset role;
set local role authenticated;
select throws_ok($cmd$insert into private.r06_x2_recoveries(trip_id) values ('dda56345-4123-4a0c-9771-5287899d2344')$cmd$,
 '42501',null,'Rider cannot forge a cancellation marker');
select throws_ok($cmd$insert into private.r06_x2_authorizations(transaction_id,trip_id,actor_id)
 values (txid_current(),'dda56345-4123-4a0c-9771-5287899d2344',auth.uid())$cmd$,
 '42501',null,'Rider cannot forge a transient canonical authorization');
select is(public.rider_read_r06_x2_recovery('8168236a-6a53-4a08-8dfa-f79e68fe8925',
 '8168236a-6a53-4a08-8dfa-f79e68fe8923')->>'state','unresolved','uncertain pre-commit outcome reconciles read-only');
select is(public.rider_read_r06_x2_recovery('8168236a-6a53-4a08-8dfa-f79e68fe8925',
 '8168236a-6a53-4a08-8dfa-f79e68fe8923')->>'retry_allowed','false','uncertain outcome never grants a mutation retry');
reset role;
create temp table x2_originals as select to_jsonb(a) as attempt,to_jsonb(r) as reservation,
 to_jsonb(b) as booking,to_jsonb(q) as quote
 from public.payment_attempts a cross join private.stripe_test_dispatch_reservations r
 cross join public.booking_requests b cross join public.fare_quotes q;
set local role authenticated;
select is(public.rider_recover_r06_x2_reserved_fixture(
 '8168236a-6a53-4a08-8dfa-f79e68fe8925','dda56345-4123-4a0c-9771-5287899d2344',
 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b','45ae3584-fa38-4fa5-b8c8-10efd79f8416',
 1,1,12,'8168236a-6a53-4a08-8dfa-f79e68fe8921','8168236a-6a53-4a08-8dfa-f79e68fe8923')->>'trip_status',
 'cancelledByRider','exact owner, approved reserved fixture, GLOBAL sequence 2 recovers');
select is(public.rider_read_r06_x2_recovery('8168236a-6a53-4a08-8dfa-f79e68fe8925',
 '8168236a-6a53-4a08-8dfa-f79e68fe8923')->>'state','recovered','lost response reconciles durable recovery');
reset role;
select ok((select to_jsonb(a)=o.attempt and to_jsonb(r)=o.reservation and to_jsonb(b)=o.booking and to_jsonb(q)=o.quote
 from public.payment_attempts a cross join private.stripe_test_dispatch_reservations r
 cross join public.booking_requests b cross join public.fare_quotes q cross join x2_originals o),
 'original Attempt/reservation/token/Booking/FareQuote remain byte-for-byte unchanged');
select is((select version from public.trips),2,'canonical Trip version advances once');
select is((select version from public.payments),2,'canonical Payment version advances once');
select is((select version from public.driver_availability),13,'canonical Driver release advances once');
select is((select state::text from public.driver_availability),'offline','recovery leaves Driver offline');
select is((select count(*)::integer from public.receipts),0,'recovery creates no receipt');
select is((select count(*)::integer from public.refunds),0,'recovery creates no refund');
select is((select count(*)::integer from private.r06_x2_authorizations),0,'canonical authorization ends before wrapper returns');
select ok(not exists (select 1 from public.audit_records where action='trip.r06_x2_guarded_recovery'
 and (previous_data||new_data||request_context)::text ~ 'claimToken|claim_token|pi_|snapshot_digest|provenance'),
 'recovery audit is sanitized and excludes private evidence');
select set_config('request.jwt.claims','{"sub":"f148a7ec-7e85-48ef-847f-8e9eea880e1b","role":"authenticated"}',true);
set local role authenticated;
select is((public.driver_set_availability('available','48d007ab-c13c-4ff8-93f3-1dc7f1e6975d',13)).state::text,
 'available','separate authenticated canonical Driver restoration works after verified cancellation');
reset role;
select set_config('request.jwt.claims','{"sub":"d3c3dc11-a840-4712-a6a4-599b4ae27329","role":"authenticated"}',true);
select ok(pg_temp.refused(''), 'duplicate mutation refuses and directs read-only reconciliation');
select ok(pg_temp.refused('',replace(command,'8168236a-6a53-4a08-8dfa-f79e68fe8923',
 '8168236a-6a53-4a08-8dfa-f79e68fe8924'),'23505'),'conflicting recovery request denied') from x2_command;
select ok(pg_temp.refused('', $cmd$select public.backend_complete_payment_attempt(
 '45ae3584-fa38-4fa5-b8c8-10efd79f8416','failed','pi_LocalLateFailure')$cmd$),
 'late failed completion cannot mutate pending immutable original Attempt');
select ok(pg_temp.refused($m$select set_config('request.jwt.claims','{"role":"service_role"}',true)$m$,
 $cmd$select public.backend_claim_stripe_test_preparation('d3c3dc11-a840-4712-a6a4-599b4ae27329',
 'dda56345-4123-4a0c-9771-5287899d2344','cbbb4b94-ac92-49b9-8b43-1f370c783e5b',
 '45ae3584-fa38-4fa5-b8c8-10efd79f8416',1,1,'r06-x2-synthetic-operation')$cmd$),
 'old claim cannot be reclaimed after revocation');
set local role service_role;
select set_config('ridex.complete_payment_attempt','on',true);
select throws_ok($cmd$update public.payment_attempts set status='failed',completed_at=now(),verified_at=now()$cmd$,
 '55000',null,'service role cannot spoof a completion marker past the durable fence');
select throws_ok($cmd$update public.payments set card_status='cardPaymentFailed'$cmd$,
 '55000',null,'service role cannot rewrite recovered Payment status');
select throws_ok($cmd$insert into public.payment_attempts(payment_id,type,requested_amount_fils,currency,idempotency_key)
 values ('cbbb4b94-ac92-49b9-8b43-1f370c783e5b','providerStatusVerification',2550,'JOD','local-late-insert')$cmd$,
 '55000',null,'service role cannot append an Attempt after recovery');
select throws_ok($cmd$insert into public.refunds(payment_id,amount_fils,reason_code,requested_by_admin_id)
 values ('cbbb4b94-ac92-49b9-8b43-1f370c783e5b',2550,'local_review','d3c3dc11-a840-4712-a6a4-599b4ae27329')$cmd$,
 '55000',null,'service role cannot insert a Refund across the fence');
select throws_ok($cmd$select public.backend_record_processed_webhook_event('stripe','LOCAL-late-event',
 'cbbb4b94-ac92-49b9-8b43-1f370c783e5b')$cmd$,
 '55000',null,'late provider event is refused for offline review');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(public.backend_record_stripe_test_preparation_fenced('45ae3584-fa38-4fa5-b8c8-10efd79f8416',
 (select claim_token from private.stripe_test_dispatch_reservations),'pi_LocalLateEvidence'),
 'quarantined','late provider result has explicit quarantine outcome');
select is(public.backend_record_stripe_test_preparation_fenced('45ae3584-fa38-4fa5-b8c8-10efd79f8416',
 (select claim_token from private.stripe_test_dispatch_reservations),null),
 'quarantined','uncertain acknowledgement cannot overwrite stronger late evidence');
select is((select count(*)::integer from private.r06_x2_late_observations where provider_reference='pi_LocalLateEvidence'),
 1,'strong late observation remains durable');
select ok(pg_temp.refused('', $cmd$select public.backend_record_stripe_test_preparation_fenced(
 '45ae3584-fa38-4fa5-b8c8-10efd79f8416',gen_random_uuid(),'pi_Foreign')$cmd$,'42501'),
 'forged claim cannot import late evidence');
select ok(pg_temp.refused('', $cmd$select public.backend_record_stripe_test_preparation(
 '45ae3584-fa38-4fa5-b8c8-10efd79f8416',(select claim_token from private.stripe_test_dispatch_reservations),'pi_Legacy')$cmd$),
 'legacy record RPC cannot bypass quarantine');
select set_config('request.jwt.claims','{"sub":"d3c3dc11-a840-4712-a6a4-599b4ae27329","role":"authenticated"}',true);
select is(public.rider_read_r06_x2_recovery('8168236a-6a53-4a08-8dfa-f79e68fe8925',
 '8168236a-6a53-4a08-8dfa-f79e68fe8923')->>'requires_provider_review','true',
 'read-only reconciliation exposes late contradiction without provider references');
select is(public.rider_read_r06_x2_recovery('8168236a-6a53-4a08-8dfa-f79e68fe8925',
 '8168236a-6a53-4a08-8dfa-f79e68fe8923')->>'state','review_required','late contradiction blocks a clean reconciliation');
select ok(not (public.rider_read_r06_x2_recovery('8168236a-6a53-4a08-8dfa-f79e68fe8925',
 '8168236a-6a53-4a08-8dfa-f79e68fe8923')::text ~ 'claimToken|claim_token|pi_'),
 'reconciliation does not disclose tokens or provider references');
select ok(pg_temp.refused('truncate private.r06_x2_recoveries cascade','select 1'), 'durable revocation cannot be truncated');
select ok(pg_temp.refused('delete from private.r06_x2_late_observations','select 1'), 'late observations cannot be deleted');
select ok((select to_jsonb(a)=o.attempt and to_jsonb(r)=o.reservation from public.payment_attempts a
 cross join private.stripe_test_dispatch_reservations r cross join x2_originals o),
 'late observations preserve original Attempt and reservation completely');
select * from finish();
rollback;
