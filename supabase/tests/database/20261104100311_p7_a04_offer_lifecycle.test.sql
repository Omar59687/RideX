begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
\ir ../fixtures/p7_a04_matching.sql
create function pg_temp.make_offer(b integer,d integer,r integer default 3000)
returns public.driver_match_offers language sql as $$
select public.backend_create_driver_match_offer(
 ('a7032000-0000-0000-0000-'||lpad(b::text,12,'0'))::uuid,
 ('a7020000-0000-0000-0000-'||lpad(d::text,12,'0'))::uuid,
 ('a7021000-0000-0000-0000-'||lpad(d::text,12,'0'))::uuid,r,
 (select version from public.booking_requests where id=('a7032000-0000-0000-0000-'||lpad(b::text,12,'0'))::uuid));
$$;
create temp table saved_offers as select (pg_temp.make_offer(1,1)).*;
select is((select count(*) from public.driver_match_offers),1::bigint,'one canonical offer created');
select is((select state::text from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000001'),'reserved','offer atomically reserves Driver');
select is((select expires_at-offered_at from saved_offers),interval '15 seconds','offer lifetime stays fifteen seconds');
select is((pg_temp.make_offer(1,1)).id,(select id from saved_offers),'lost-response retry returns same ID');
select is((select count(*) from public.audit_records where action='matching.offer_created'),1::bigint,'retry writes no duplicate audit');
select throws_ok($$select pg_temp.make_offer(1,1,5000)$$,'23505',null,'creation retry cannot alter radius');
select throws_ok($$select pg_temp.make_offer(2,1)$$,'42501',null,'Driver cannot reserve two bookings');
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000001',true);
set local role authenticated;
select throws_ok($$select public.driver_decline_match_offer((select id from public.driver_match_offers),2,'stale-decline')$$,'40001',null,'decline rejects stale offer version');
select lives_ok($$select public.driver_decline_match_offer((select id from public.driver_match_offers),1,'decline-1')$$,'owning Driver declines');
select lives_ok($$select public.driver_decline_match_offer((select id from public.driver_match_offers),1,'decline-1')$$,'decline retry is idempotent');
reset role;
select is((select status::text from public.driver_match_offers),'declined','offer becomes declined');
select is((select state::text from public.driver_availability where driver_id= 'a7020000-0000-0000-0000-000000000001'),'available','decline releases exact reservation');
select is((pg_temp.make_offer(1,1)).status::text,'declined','creation retry cannot resurrect declined offer');
select is((select count(*) from public.audit_records where action='matching.offer_declined'),1::bigint,'one decline audit');
savepoint bad_candidate;
update public.users set is_blocked=true where id='a7020000-0000-0000-0000-000000000002';
select throws_ok($$select pg_temp.make_offer(2,2)$$,'42501',null,'blocked after discovery denied at offer time');
rollback to bad_candidate;
savepoint bad_candidate;
update public.vehicles set vehicle_type_code='comfort' where id='a7021000-0000-0000-0000-000000000002';
select throws_ok($$select pg_temp.make_offer(2,2)$$,'42501',null,'category changed after discovery denied at offer time');
rollback to bad_candidate;
savepoint bad_candidate;
update public.driver_locations set longitude=1 where driver_id='a7020000-0000-0000-0000-000000000002';
select throws_ok($$select pg_temp.make_offer(2,2)$$,'55000',null,'moved outside radius after discovery denied at offer time');
rollback to bad_candidate;
savepoint bad_candidate;
insert into public.driver_locations(driver_id,sequence,latitude,longitude,accuracy_meters,recorded_at) values('a7020000-0000-0000-0000-000000000002',2,0,0,100,clock_timestamp());
select throws_ok($$select pg_temp.make_offer(2,2)$$,'55000',null,'newest inaccurate GPS never falls back denied at offer time');
rollback to bad_candidate;
savepoint bad_candidate;
update public.driver_locations set recorded_at=clock_timestamp()-interval '61 seconds' where driver_id='a7020000-0000-0000-0000-000000000002';
select throws_ok($$select pg_temp.make_offer(2,2)$$,'55000',null,'stale GPS denied at offer time');
rollback to bad_candidate;
savepoint bad_candidate;
update public.driver_locations set recorded_at=clock_timestamp()+interval '6 seconds' where driver_id='a7020000-0000-0000-0000-000000000002';
select throws_ok($$select pg_temp.make_offer(2,2)$$,'55000',null,'future GPS denied at offer time');
rollback to bad_candidate;
create temp table accept_offer as select (pg_temp.make_offer(2,2)).*;
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000001',true);
set local role authenticated;
select throws_ok($$select public.driver_decline_match_offer((select id from public.driver_match_offers where driver_id='a7020000-0000-0000-0000-000000000002'),1,'foreign')$$,'P0002',null,'foreign Driver cannot see/decline another offer');
reset role;
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000002',true);
set local role authenticated;
select throws_ok($$select public.driver_transition_trip((select id from public.driver_match_offers where driver_id=auth.uid()),'accepted',2,'stale-accept')$$,'40001',null,'accept rejects stale version');
select lives_ok($$select public.driver_transition_trip((select id from public.driver_match_offers where driver_id=auth.uid()),'accepted',1,'accept-2')$$,'owning Driver accepts once');
select lives_ok($$select public.driver_transition_trip((select id from public.driver_match_offers where driver_id=auth.uid()),'accepted',1,'accept-2')$$,'accept lost-response retry succeeds');
reset role;
select is((select count(*) from public.trips),1::bigint,'one Trip despite retry');
select is((select count(*) from public.payments),1::bigint,'existing Phase 6 Payment creation is not duplicated');
select is((select count(*) from public.receipts),0::bigint,'acceptance does not settle or issue receipt');
select is((select state::text from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000002'),'onTrip','winner is onTrip');
select has_index('public','trips','trips_one_nonterminal_per_driver_idx','one nonterminal Trip per Driver is a database invariant');
select throws_ok($$insert into public.trips(booking_request_id,fare_quote_id,rider_id,driver_id,vehicle_id,payment_method,pickup,destination,route_distance_meters,route_duration_seconds,original_fare_fils,current_fare_fils)
select id,fare_quote_id,rider_id,'a7020000-0000-0000-0000-000000000002','a7021000-0000-0000-0000-000000000002',payment_method,pickup,destination,2000,600,1600,1600 from public.booking_requests where id='a7032000-0000-0000-0000-000000000003'$$,'23505',null,'trusted direct insert cannot create a second active Trip');
-- Even a trusted inconsistent aggregate cannot bypass the active-Trip check.
savepoint conflicting_trip;
update public.driver_availability set state='available',active_trip_id=null where driver_id='a7020000-0000-0000-0000-000000000002';
select throws_ok($$select pg_temp.make_offer(3,2)$$,'42501',null,'existing active Trip blocks another offer');
rollback to conflicting_trip;
-- Fault injection verifies the entire existing assignment/payment wrapper rolls back.
savepoint forced_failure;
select pg_temp.make_offer(3,8);
create function pg_temp.fail_trip_insert() returns trigger language plpgsql as $$
begin raise exception using errcode='XX000',message='Synthetic assignment failure.'; end; $$;
create trigger p7_a04_test_fail_trip before insert on public.trips for each row execute function pg_temp.fail_trip_insert();
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000008',true);
set local role authenticated;
select throws_ok($$select public.driver_transition_trip((select id from public.driver_match_offers where driver_id=auth.uid()),'accepted',1,'forced-failure')$$,'XX000',null,'injected Trip failure aborts assignment');
reset role;
select is((select count(*) from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000003'),0::bigint,'failed assignment leaves no Trip');
select is((select status::text from public.driver_match_offers where driver_id='a7020000-0000-0000-0000-000000000008'),'offered','failed assignment preserves live offer');
select is((select state::text from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000008'),'reserved','failed assignment preserves reservation');
select is((select count(*) from public.command_idempotency_keys where idempotency_key='forced-failure'),0::bigint,'failed assignment does not consume command key');
rollback to forced_failure;
-- A newer valid sequence is recomputed, not blindly rejected or silently ignored.
savepoint newer_fix;
insert into public.driver_locations(driver_id,sequence,latitude,longitude,accuracy_meters,recorded_at)
values('a7020000-0000-0000-0000-000000000008',2,0,0,10,clock_timestamp());
select pg_temp.make_offer(3,8);
select is((select new_data->>'location_sequence' from public.audit_records where action='matching.offer_created' and target_user_id='a7020000-0000-0000-0000-000000000008'),'2','offer audit records latest server sequence');
rollback to newer_fix;
create temp table expiring_offer as select (pg_temp.make_offer(3,8)).*;
update public.driver_match_offers set offered_at=now()-interval '16 seconds',expires_at=now()-interval '1 second'
where id=(select id from expiring_offer);
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000008',true);
set local role authenticated;
select throws_ok($$select public.driver_transition_trip((select id from public.driver_match_offers where driver_id=auth.uid()),'accepted',2,'expired-accept')$$,'55000',null,'expired offer cannot be accepted');
reset role;
savepoint decline_expired;
set local role authenticated;
select lives_ok($$select public.driver_decline_match_offer((select id from public.driver_match_offers where driver_id=auth.uid()),2,'expired-decline')$$,'decline after deadline returns canonical expired offer');
select lives_ok($$select public.driver_decline_match_offer((select id from public.driver_match_offers where driver_id=auth.uid()),2,'expired-decline')$$,'expired-decline lost response retry remains idempotent');
reset role;
rollback to decline_expired;
select public.backend_expire_booking_match_offers('a7032000-0000-0000-0000-000000000003',4);
select is((select status::text from public.driver_match_offers where id=(select id from expiring_offer)),'expired','expiry command materializes terminal offer');
select is((select state::text from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000008'),'available','expiry releases reservation');
select lives_ok($$select public.backend_expire_booking_match_offers('a7032000-0000-0000-0000-000000000003',4)$$,'expiry retry is safe');
create temp table search_offer as select (pg_temp.make_offer(4,8)).*;
update public.booking_requests set searching_at=clock_timestamp()-interval '91 seconds' where id='a7032000-0000-0000-0000-000000000004';
select public.backend_expire_booking_match_offers('a7032000-0000-0000-0000-000000000004',5);
select is((select status::text from public.booking_requests where id='a7032000-0000-0000-0000-000000000004'),'expired','search window terminates booking');
select is((select state::text from public.driver_availability where driver_id='a7020000-0000-0000-0000-000000000008'),'available','search expiry releases live offers');
set local role anon;
select throws_ok($$select public.driver_decline_match_offer(gen_random_uuid(),1,'anon')$$,'42501',null,'anonymous cannot decline');
select throws_ok($$select public.backend_expire_booking_match_offers(gen_random_uuid(),1)$$,'42501',null,'anonymous cannot expire bookings');
reset role;
set local role authenticated;
select throws_ok($$select public.backend_create_driver_match_offer(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),3000,1)$$,'42501',null,'client cannot create offers');
select throws_ok($$select public.backend_expire_booking_match_offers(gen_random_uuid(),1)$$,'42501',null,'client cannot run expiry service');
reset role;
select ok(not has_function_privilege('service_role','private.current_matching_gps(uuid,double precision,double precision,timestamptz)','execute'),'shared GPS implementation stays private');
select * from finish();
rollback;
