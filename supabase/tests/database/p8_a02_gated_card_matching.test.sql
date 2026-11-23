begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
\ir ../fixtures/p7_a04_matching.sql
insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method)
values('a7032000-0000-0000-0000-000000000099','a7020000-0000-0000-0000-000000000007','{"latitude":0,"longitude":0}','{"latitude":1,"longitude":1}','economy','card');
select public.backend_calculate_fare_quote('a7032000-0000-0000-0000-000000000099',1,2000,600,null);
select public.backend_lock_fare_quote((select id from public.fare_quotes where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1);
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000007',true);
set local role authenticated;
select throws_ok($$select public.rider_confirm_booking('a7032000-0000-0000-0000-000000000099',2,'card-off')$$,'55000',null,'default off denies Card confirmation');
select throws_ok($$update private.p8_card_matching_gate set enabled=true$$,'42501',null,'Rider cannot enable gate');
reset role;
set local role service_role;
select throws_ok($$update private.p8_card_matching_gate set enabled=true$$,'42501',null,'service role cannot enable gate');
reset role;
update private.p8_card_matching_gate set enabled=true;
savepoint blocked_rider;
update public.users set is_blocked=true where id='a7020000-0000-0000-0000-000000000007';
set local role authenticated;
select throws_ok($$select public.rider_confirm_booking('a7032000-0000-0000-0000-000000000099',2,'blocked-card')$$,'42501',null,'blocked Rider cannot confirm Card');
reset role;
rollback to blocked_rider;
set local role authenticated;
select throws_ok($$select public.rider_confirm_booking('a7032000-0000-0000-0000-000000000099',1,'card-stale')$$,'40001',null,'stale Card confirmation denied');
select lives_ok($$select public.rider_confirm_booking('a7032000-0000-0000-0000-000000000099',2,'card-confirm')$$,'Card confirmation enabled only by server gate');
reset role;
update private.p8_card_matching_gate set enabled=false;
select set_config('request.jwt.claim.role','service_role',true);
select throws_ok($$select * from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000099',3,3000,3)$$,'55000',null,'gate OFF denies Card discovery');
select throws_ok($$select public.backend_create_driver_match_offer('a7032000-0000-0000-0000-000000000099','a7020000-0000-0000-0000-000000000001','a7021000-0000-0000-0000-000000000001',3000,3)$$,'55000',null,'gate OFF denies Card offer');
update private.p8_card_matching_gate set enabled=true;
select ok((select count(*) > 0 from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000099',3,3000,3)),'gated Card discovery finds candidates');
create temp table card_offer as select (public.backend_create_driver_match_offer('a7032000-0000-0000-0000-000000000099','a7020000-0000-0000-0000-000000000001','a7021000-0000-0000-0000-000000000001',3000,3)).*;
grant select on card_offer to authenticated;
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000002',true);
set local role authenticated;
select throws_ok($$select public.driver_transition_trip((select id from card_offer),'accepted',1,'foreign-card')$$,'P0002',null,'foreign Driver cannot accept');
reset role;
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000001',true);
set local role authenticated;
select throws_ok($$select public.driver_transition_trip((select id from card_offer),'accepted',2,'stale-card')$$,'40001',null,'stale acceptance denied');
reset role;
update private.p8_card_matching_gate set enabled=false;
set local role authenticated;
select throws_ok($$select public.driver_transition_trip((select id from card_offer),'accepted',1,'gate-revoked')$$,'55000',null,'revoked gate denies acceptance');
reset role;
update private.p8_card_matching_gate set enabled=true;
set local role authenticated;
select lives_ok($$select public.driver_transition_trip((select id from card_offer),'accepted',1,'accept-card')$$,'owning Driver accepts canonical Card offer');
select lives_ok($$select public.driver_transition_trip((select id from card_offer),'accepted',1,'accept-card')$$,'same acceptance replay is safe');
reset role;
select is((select count(*) from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),1::bigint,'one canonical Card Trip');
select is((select count(*) from public.payments p join public.trips t on t.id=p.trip_id where t.booking_request_id='a7032000-0000-0000-0000-000000000099' and p.method='card' and p.card_status='cardPaymentPending'),1::bigint,'one linked pending Card Payment');
select is((select count(*) from public.receipts),0::bigint,'matching cannot issue receipt');
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000001',true);
set local role authenticated;
select throws_ok($$select public.driver_transition_trip((select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),'driverArriving',1,'no-authorization')$$,'55000',null,'Card Trip cannot progress before authorization');
reset role;
-- Trusted command is preparation only; this savepoint is local synthetic evidence.
select ok(not has_function_privilege('authenticated','public.backend_prepare_card_command(uuid,uuid,uuid,integer,integer,text,text,text)','execute'),'Rider and Driver roles cannot call the command');
-- Minimal isolated GoTrue session fixture; production table remains GoTrue-owned.
create table if not exists auth.sessions (id uuid primary key, user_id uuid, not_after timestamptz);
insert into auth.sessions(id,user_id,not_after) values
 ('55555555-5555-4555-8555-555555555555','a7020000-0000-0000-0000-000000000007',null),
 ('66666666-6666-4666-8666-666666666666','a7020000-0000-0000-0000-000000000007',now()-interval '1 second');
select ok(not has_function_privilege('service_role','public.backend_prepare_card_command(uuid,uuid,uuid,integer,integer,text,text,text)','execute'),'service cannot directly assert Rider to legacy command');
select ok(not has_function_privilege('authenticated','public.backend_prepare_card_authorization_for_session(uuid,uuid,bigint,uuid,uuid,integer,integer,text)','execute'),'client cannot invoke privileged session wrapper');
savepoint session_boundary;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select throws_ok($$select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',gen_random_uuid(),gen_random_uuid(),1,1,'authorize','direct-denied',null)$$,'42501',null,'service cannot invoke caller-asserted legacy command');
select throws_ok($$select public.backend_prepare_card_authorization_for_session('a7020000-0000-0000-0000-000000000007',gen_random_uuid(),extract(epoch from now())::bigint+300,(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'session-auth')$$,'42501',null,'missing or revoked session rejected');
select throws_ok($$select public.backend_prepare_card_authorization_for_session('a7020000-0000-0000-0000-000000000002','55555555-5555-4555-8555-555555555555',extract(epoch from now())::bigint+300,(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'session-auth')$$,'42501',null,'foreign actor cannot assert a session');
select throws_ok($$select public.backend_prepare_card_authorization_for_session('a7020000-0000-0000-0000-000000000007','66666666-6666-4666-8666-666666666666',extract(epoch from now())::bigint+300,(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'session-auth')$$,'42501',null,'expired session rejected');
select throws_ok($$select public.backend_prepare_card_authorization_for_session('a7020000-0000-0000-0000-000000000007','55555555-5555-4555-8555-555555555555',extract(epoch from now())::bigint-1,(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'session-auth')$$,'42501',null,'expired token rejected');
select lives_ok($$select public.backend_prepare_card_authorization_for_session('a7020000-0000-0000-0000-000000000007','55555555-5555-4555-8555-555555555555',extract(epoch from now())::bigint+300,(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'session-auth')$$,'verified session can prepare pending authorization');
reset role;
rollback to session_boundary;
-- Local regression fixture only: historical trusted primitive tests follow.
grant execute on function public.backend_prepare_card_command(uuid,uuid,uuid,integer,integer,text,text,text) to service_role;
savepoint trusted_commands;
savepoint blocked_actor;
update public.users set is_blocked=true where id='a7020000-0000-0000-0000-000000000007';
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select throws_ok($$select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'authorize','blocked-actor','stripe')$$,'42501',null,'blocked Rider cannot authorize through trusted command');
reset role;
rollback to blocked_actor;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select throws_ok($$select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000002',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'authorize','foreign-key','stripe')$$,'42501',null,'foreign actor cannot prepare command');
select throws_ok($$select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),2,1,'authorize','stale-key','stripe')$$,'40001',null,'stale Trip version rejected');
select throws_ok($$select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,2,'authorize','stale-payment','stripe')$$,'40001',null,'stale Payment version rejected');

select throws_ok($$select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),gen_random_uuid(),1,1,'authorize','wrong-payment','stripe')$$,'42501',null,'foreign or missing Payment link rejected');
reset role;
savepoint disabled_command;
update private.p8_card_matching_gate set enabled=false;
set local role service_role;
select throws_ok($$select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'authorize','disabled-command','stripe')$$,'55000',null,'default OFF gate denies command');
reset role;
rollback to disabled_command;
set local role service_role;

select throws_ok($$select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'capture','early-capture','stripe')$$,'55000',null,'capture before completion rejected');
create temp table command_result as select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'authorize','boundary-auth','stripe') as result;
select is((select result->>'outcome' from command_result),'PENDING','trusted authorization request only creates pending attempt');
select is(public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'authorize','boundary-auth','stripe')->>'attempt_id',(select result->>'attempt_id' from command_result),'exact retry preserves attempt');
select throws_ok($$select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'authorize','boundary-other','stripe')$$,'55000',null,'second authorization attempt denied');
savepoint unknown_evidence;
create temp table command_claim as select public.backend_claim_stripe_test_preparation('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select (result->>'attempt_id')::uuid from command_result),1,1,'boundary-auth') as result;
select public.backend_record_stripe_test_preparation_fenced((select (result->>'attempt_id')::uuid from command_result),(select (result->>'claimToken')::uuid from command_claim),null);
select is(public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,1,'authorize','boundary-auth','stripe')->>'outcome','UNKNOWN','unknown evidence is returned without a new attempt or dispatch');
rollback to unknown_evidence;
-- Fake provider evidence below is injected solely in this rolled-back test transaction.
select public.backend_complete_payment_attempt((select (result->>'attempt_id')::uuid from command_result),'succeeded','local-fake-auth',null);
select public.backend_transition_payment((select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,null,'cardPaymentAuthorized');
reset role;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.driver_transition_trip((select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),'driverArriving',1,'fake-arriving');
select public.driver_transition_trip((select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),'driverArrived',2,'fake-arrived');
select public.driver_transition_trip((select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),'inProgress',3,'fake-start');
select public.driver_transition_trip((select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),'completed',4,'fake-complete');
reset role;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
create temp table capture_result as select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),5,2,'capture','boundary-capture','stripe') as result;
select is((select result->>'outcome' from capture_result),'PENDING','trusted completion permits pending capture only');
select is(public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),5,2,'capture','boundary-capture','stripe')->>'attempt_id',(select result->>'attempt_id' from capture_result),'capture retry preserves attempt');
select throws_ok($$select public.backend_prepare_card_command('a7020000-0000-0000-0000-000000000007',(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),5,2,'capture','other-capture','stripe')$$,'55000',null,'duplicate capture denied');
-- Trusted synthetic completion is only performed in this disposable test transaction.
select public.backend_complete_payment_attempt((select (result->>'attempt_id')::uuid from capture_result),'succeeded','local-fake-capture',null);
select public.backend_transition_payment((select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),2,null,'cardPaymentSucceeded');
select is((select card_status::text from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),'cardPaymentSucceeded','trusted synthetic capture completes only after verified authorization and completion');
select is((select count(*) from public.receipts),0::bigint,'capture evidence alone does not fabricate a receipt');
reset role;
rollback to trusted_commands;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select lives_ok($$select public.backend_record_payment_attempt((select id from public.payments where trip_id=(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099')),'initialAuthorization',1600,'p8-card-attempt','stripe')$$,'backend creates one pending authorization attempt');
select lives_ok($$select public.backend_record_payment_attempt((select id from public.payments where trip_id=(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099')),'initialAuthorization',1600,'p8-card-attempt','stripe')$$,'authorization replay reuses same attempt');
select throws_ok($$select public.backend_record_payment_attempt((select id from public.payments where trip_id=(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099')),'initialAuthorization',1600,'p8-card-attempt-other','stripe')$$,'55000',null,'duplicate authorization rejected');
select throws_ok($$select public.backend_record_payment_attempt((select id from public.payments where trip_id=(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099')),'capture',1600,'p8-card-capture',null)$$,'55000',null,'capture before completed Trip denied');
create temp table local_claim as select public.backend_claim_stripe_test_preparation(
'a7020000-0000-0000-0000-000000000007',
(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),
(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),
(select id from public.payment_attempts where idempotency_key='p8-card-attempt'),1,1,'p8-card-attempt') as result;
select is((select result->>'disposition' from local_claim),'claimed','first reservation claims once without provider dispatch');
select is(public.backend_record_stripe_test_preparation_fenced((select id from public.payment_attempts where idempotency_key='p8-card-attempt'),(select (result->>'claimToken')::uuid from local_claim),null),'recorded','lost response records unknown evidence');
select is((public.backend_claim_stripe_test_preparation(
'a7020000-0000-0000-0000-000000000007',
(select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),
(select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),
(select id from public.payment_attempts where idempotency_key='p8-card-attempt'),1,1,'p8-card-attempt')->>'state'),'unknown','retry reads unknown without a new claim');
reset role;
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000007',true);
set local role authenticated;
select throws_ok($$select public.rider_cancel_trip((select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),1,'OTHER')$$,'55000',null,'pending authorization prevents cancellation and Driver release');
reset role;
select is((select state::text from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000001'),'onTrip','pending authorization retains Driver assignment');
select * from finish();
rollback;
