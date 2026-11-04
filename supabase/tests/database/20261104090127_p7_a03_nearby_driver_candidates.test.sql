begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
\ir ../fixtures/p7_a02_driver_availability.sql
-- Reuse canonical P7-A02 actors; add a third equally eligible Driver.
insert into auth.users(instance_id,id,aud,role,email,raw_user_meta_data,created_at,updated_at)
values('00000000-0000-0000-0000-000000000000','a7020000-0000-0000-0000-000000000008','authenticated','authenticated','p7-a03-8@example.com','{"display_name":"Candidate 8"}',now(),now());
update public.users set role='driver' where id='a7020000-0000-0000-0000-000000000008';
delete from public.rider_profiles where user_id='a7020000-0000-0000-0000-000000000008';
insert into public.driver_profiles(user_id,approval_status) values('a7020000-0000-0000-0000-000000000008','approved');
insert into public.vehicles(id,driver_id,vehicle_type_code,make,model,color,registration_plate,seat_capacity,is_active)
values('a7021000-0000-0000-0000-000000000008','a7020000-0000-0000-0000-000000000008','economy','Toyota','Camry','White','P7 A03 8',4,true);
insert into public.driver_availability(driver_id,state) values('a7020000-0000-0000-0000-000000000008','offline');
update public.driver_availability a set state='available',vehicle_id=v.id
from public.vehicles v where v.driver_id=a.driver_id and v.is_active;
select public.backend_create_pricing_configuration('economy',500,300,50,200,1000,50,true);
insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method)
values('a7032000-0000-0000-0000-000000000001','a7020000-0000-0000-0000-000000000007','{"latitude":0,"longitude":0}','{"latitude":1,"longitude":1}','economy','cash');
select public.backend_calculate_fare_quote('a7032000-0000-0000-0000-000000000001',1,2000,600,null);
select public.backend_lock_fare_quote((select id from public.fare_quotes where booking_request_id='a7032000-0000-0000-0000-000000000001'),1,1);
update public.booking_requests set status='confirmed',confirmed_at=now() where id='a7032000-0000-0000-0000-000000000001';
insert into public.driver_locations(driver_id,sequence,latitude,longitude,accuracy_meters,recorded_at,received_at)
select driver_id,1,0,0,10,statement_timestamp(),statement_timestamp() from public.driver_availability where state='available';
select set_config('request.jwt.claim.role','service_role',true);
create function pg_temp.candidates(radius integer default 3000, max_count integer default 3)
returns table(driver_id uuid,vehicle_id uuid,availability_version integer,vehicle_version integer,location_sequence bigint,distance_meters double precision)
language sql as $$ select * from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000001',(select version from public.booking_requests where id='a7032000-0000-0000-0000-000000000001'),radius,max_count) $$;
-- Full row snapshots prove discovery does not mutate canonical or finance state.
create temp table before_discovery as
select 'booking' kind,to_jsonb(b) payload from public.booking_requests b
union all select 'availability',to_jsonb(a) from public.driver_availability a
union all select 'location',to_jsonb(l) from public.driver_locations l
union all select 'vehicle',to_jsonb(v) from public.vehicles v
union all select 'quote',to_jsonb(q) from public.fare_quotes q
union all select 'offer',to_jsonb(o) from public.driver_match_offers o
union all select 'trip',to_jsonb(t) from public.trips t
union all select 'payment',to_jsonb(p) from public.payments p
union all select 'audit',to_jsonb(r) from public.audit_records r;
select is((select count(*) from pg_temp.candidates()),3::bigint,'three nearby eligible Drivers');
select results_eq($$select driver_id from pg_temp.candidates()$$,$$select * from (values('a7020000-0000-0000-0000-000000000001'::uuid),('a7020000-0000-0000-0000-000000000002'::uuid),('a7020000-0000-0000-0000-000000000008'::uuid)) expected(driver_id) order by driver_id$$,'equal distances use stable Driver UUID tie-break');
select is((select count(*) from pg_temp.candidates(3000,1)),1::bigint,'result limit applied');
select ok((select bool_and(location_sequence=1 and availability_version=2 and vehicle_version=1 and distance_meters=0) from pg_temp.candidates()),'versions and sequence are canonical observations');
select results_eq($$select kind,payload from before_discovery order by kind,payload$$,$$
select kind,payload from (
select 'booking' kind,to_jsonb(b) payload from public.booking_requests b
union all select 'availability',to_jsonb(a) from public.driver_availability a
union all select 'location',to_jsonb(l) from public.driver_locations l
union all select 'vehicle',to_jsonb(v) from public.vehicles v
union all select 'quote',to_jsonb(q) from public.fare_quotes q
union all select 'offer',to_jsonb(o) from public.driver_match_offers o
union all select 'trip',to_jsonb(t) from public.trips t
union all select 'payment',to_jsonb(p) from public.payments p
union all select 'audit',to_jsonb(r) from public.audit_records r) x order by kind,payload$$,'discovery changes no Booking, availability, GPS, vehicle, quote, offer, Trip, Payment or audit row');
savepoint candidate_case;
update public.users set is_blocked=true where id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'blocked Driver excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_profiles set approval_status='pending' where user_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'pending Driver excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_profiles set approval_status='rejected',rejection_reason='Test' where user_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'rejected Driver excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.vehicles set vehicle_type_code='comfort' where id='a7021000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'wrong category excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.vehicles set is_active=false where id='a7021000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'inactive vehicle excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_availability set vehicle_id='a7021000-0000-0000-0000-000000000002' where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'foreign vehicle excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_availability set state='offline',vehicle_id=null where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'offline Driver excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_availability set state='reserved',reserved_booking_request_id='a7032000-0000-0000-0000-000000000001' where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'reserved Driver excluded');
rollback to candidate_case;
savepoint candidate_case;
delete from public.driver_locations where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'missing GPS excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set recorded_at=statement_timestamp()-interval '61 seconds' where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'stale device fix excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set received_at=statement_timestamp()-interval '61 seconds' where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'stale server receipt excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set received_at=statement_timestamp()+interval '1 second' where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'future server receipt excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set recorded_at=statement_timestamp()+interval '6 seconds' where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'future device fix excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set accuracy_meters=50.01 where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'inaccurate GPS excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set accuracy_meters=50 where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),1::bigint,'accuracy boundary inclusive');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set recorded_at=statement_timestamp()+interval '4 seconds' where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),1::bigint,'small device clock skew accepted');
rollback to candidate_case;
savepoint candidate_case;
delete from public.driver_locations;
select is((select count(*) from pg_temp.candidates()),0::bigint,'no results without locations');
rollback to candidate_case;
savepoint candidate_case;
insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method)
select 'a7032000-0000-0000-0000-000000000002',rider_id,pickup,destination,vehicle_type_code,payment_method from public.booking_requests where id='a7032000-0000-0000-0000-000000000001';
select public.backend_calculate_fare_quote('a7032000-0000-0000-0000-000000000002',1,2000,600,null);
select public.backend_lock_fare_quote((select id from public.fare_quotes where booking_request_id='a7032000-0000-0000-0000-000000000002'),1,1);
update public.booking_requests set status='confirmed',confirmed_at=now() where id='a7032000-0000-0000-0000-000000000002';
insert into public.trips(id,booking_request_id,fare_quote_id,rider_id,driver_id,vehicle_id,payment_method,pickup,destination,route_distance_meters,route_duration_seconds,original_fare_fils,current_fare_fils)
select 'a7034000-0000-0000-0000-000000000001',id,fare_quote_id,rider_id,'a7020000-0000-0000-0000-000000000001','a7021000-0000-0000-0000-000000000001',payment_method,pickup,destination,2000,600,1600,1600 from public.booking_requests where id='a7032000-0000-0000-0000-000000000002';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'actual nonterminal Trip excludes inconsistent available Driver');
rollback to candidate_case;
savepoint candidate_case;
insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method)
select 'a7032000-0000-0000-0000-000000000002',rider_id,pickup,destination,vehicle_type_code,payment_method from public.booking_requests where id='a7032000-0000-0000-0000-000000000001';
select public.backend_calculate_fare_quote('a7032000-0000-0000-0000-000000000002',1,2000,600,null);
select public.backend_lock_fare_quote((select id from public.fare_quotes where booking_request_id='a7032000-0000-0000-0000-000000000002'),1,1);
update public.booking_requests set status='confirmed',confirmed_at=now() where id='a7032000-0000-0000-0000-000000000002';
insert into public.trips(id,booking_request_id,fare_quote_id,rider_id,driver_id,vehicle_id,payment_method,pickup,destination,route_distance_meters,route_duration_seconds,original_fare_fils,current_fare_fils)
select 'a7034000-0000-0000-0000-000000000001',id,fare_quote_id,rider_id,'a7020000-0000-0000-0000-000000000001','a7021000-0000-0000-0000-000000000001',payment_method,pickup,destination,2000,600,1600,1600 from public.booking_requests where id='a7032000-0000-0000-0000-000000000002'; update public.driver_availability set state='onTrip',active_trip_id='a7034000-0000-0000-0000-000000000001' where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'onTrip Driver excluded');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set longitude=degrees((3000+-0.01)/6371008.8) where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates(3000,3) where driver_id='a7020000-0000-0000-0000-000000000001'),1::bigint,'3000m inside radius boundary');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set longitude=degrees((3000+0)/6371008.8) where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates(3000,3) where driver_id='a7020000-0000-0000-0000-000000000001'),1::bigint,'3000m inclusive radius boundary');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set longitude=degrees((3000+0.01)/6371008.8) where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates(3000,3) where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'3000m outside radius boundary');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set longitude=degrees((5000+-0.01)/6371008.8) where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates(5000,3) where driver_id='a7020000-0000-0000-0000-000000000001'),1::bigint,'5000m inside radius boundary');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set longitude=degrees((5000+0)/6371008.8) where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates(5000,3) where driver_id='a7020000-0000-0000-0000-000000000001'),1::bigint,'5000m inclusive radius boundary');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set longitude=degrees((5000+0.01)/6371008.8) where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates(5000,3) where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'5000m outside radius boundary');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set longitude=degrees((8000+-0.01)/6371008.8) where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates(8000,3) where driver_id='a7020000-0000-0000-0000-000000000001'),1::bigint,'8000m inside radius boundary');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set longitude=degrees((8000+0)/6371008.8) where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates(8000,3) where driver_id='a7020000-0000-0000-0000-000000000001'),1::bigint,'8000m inclusive radius boundary');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set longitude=degrees((8000+0.01)/6371008.8) where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates(8000,3) where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'8000m outside radius boundary');
rollback to candidate_case;
savepoint candidate_case;
update public.driver_locations set longitude=0.01 where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select driver_id::text from pg_temp.candidates() limit 1),'a7020000-0000-0000-0000-000000000002'::text,'distance precedes UUID in ranking');
rollback to candidate_case;
savepoint candidate_case;
insert into public.driver_locations(driver_id,sequence,latitude,longitude,accuracy_meters,recorded_at) values('a7020000-0000-0000-0000-000000000001',2,0,0,100,statement_timestamp());
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'bad latest sequence never falls back');
rollback to candidate_case;
set local role authenticated;
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000001',true);
select throws_ok($$select public.driver_record_location(null,1,0,0,10,null,null,clock_timestamp())$$,'23505',null,'duplicate or lower sequence rejected by canonical GPS RPC');
select throws_ok($$select public.driver_record_location(null,0,0,0,10,null,null,clock_timestamp())$$,'23505',null,'duplicate or lower sequence rejected by canonical GPS RPC');
select throws_ok($$select public.driver_record_location(null,2,0,0,10,null,null,now()-interval '1 minute')$$,'23505',null,'out-of-order timestamp rejected by canonical GPS RPC');
reset role;
select set_config('request.jwt.claim.role','service_role',true);
select throws_ok($$select * from pg_temp.candidates(null,3)$$,'22023',null,'unsupported radius null rejected');
select throws_ok($$select * from pg_temp.candidates(0,3)$$,'22023',null,'unsupported radius 0 rejected');
select throws_ok($$select * from pg_temp.candidates(2999,3)$$,'22023',null,'unsupported radius 2999 rejected');
select throws_ok($$select * from pg_temp.candidates(8001,3)$$,'22023',null,'unsupported radius 8001 rejected');
select throws_ok($$select * from pg_temp.candidates(2147483647,3)$$,'22023',null,'unsupported radius 2147483647 rejected');
select throws_ok($$select * from pg_temp.candidates(3000,null)$$,'22023',null,'unsupported limit null rejected');
select throws_ok($$select * from pg_temp.candidates(3000,0)$$,'22023',null,'unsupported limit 0 rejected');
select throws_ok($$select * from pg_temp.candidates(3000,4)$$,'22023',null,'unsupported limit 4 rejected');
select throws_ok($$select * from pg_temp.candidates(3000,2147483647)$$,'22023',null,'unsupported limit 2147483647 rejected');
select throws_ok($$select * from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000001',null)$$,'22023',null,'invalid or stale booking version null rejected');
select throws_ok($$select * from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000001',0)$$,'22023',null,'invalid or stale booking version 0 rejected');
select throws_ok($$select * from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000001',1)$$,'40001',null,'invalid or stale booking version 1 rejected');
select throws_ok($$select * from public.backend_find_nearby_driver_candidates(gen_random_uuid(),1)$$,'P0002',null,'missing booking rejected');
savepoint booking_case;
update public.users set is_blocked=true where id='a7020000-0000-0000-0000-000000000007';
select throws_ok($$select * from pg_temp.candidates()$$,'42501',null,'blocked Rider rejected');
rollback to booking_case;
savepoint booking_case;
update public.booking_requests set status='searching',searching_at=now()-interval '91 seconds' where id='a7032000-0000-0000-0000-000000000001';
select throws_ok($$select * from pg_temp.candidates()$$,'55000',null,'expired search window rejected');
rollback to booking_case;
set local role anon;
select throws_ok($$select * from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000001',3)$$,'42501',null,'anon cannot discover Driver locations');
reset role;
set local role authenticated;
select throws_ok($$select * from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000001',3)$$,'42501',null,'authenticated cannot discover Driver locations');
reset role;
select set_config('request.jwt.claim.role','authenticated',true);
select throws_ok($$select * from pg_temp.candidates()$$,'42501',null,'definer also validates service-role context');
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select is((select count(*) from pg_temp.candidates()),3::bigint,'real service_role can discover candidates');
reset role;
-- Freeze reference time within one statement to exercise exact timestamp edges.
create function pg_temp.location_boundary(record_offset interval, receipt_offset interval)
returns bigint language plpgsql as $$
declare result bigint;
begin
  update public.driver_locations set recorded_at=statement_timestamp()+record_offset,
    received_at=statement_timestamp()+receipt_offset
  where driver_id='a7020000-0000-0000-0000-000000000001';
  select count(*) into result from pg_temp.candidates()
  where driver_id='a7020000-0000-0000-0000-000000000001';
  return result;
end;
$$;
savepoint boundary_case;
select is(pg_temp.location_boundary('-60 seconds','-60 seconds'),1::bigint,'exact 60-second recorded and received age accepted');
rollback to boundary_case;
savepoint boundary_case;
select is(pg_temp.location_boundary('-60.000001 seconds','0 seconds'),0::bigint,'older recorded age excluded');
rollback to boundary_case;
savepoint boundary_case;
select is(pg_temp.location_boundary('0 seconds','-60.000001 seconds'),0::bigint,'older receipt age excluded');
rollback to boundary_case;
savepoint boundary_case;
select is(pg_temp.location_boundary('5 seconds','0 seconds'),1::bigint,'exact 5-second future skew accepted');
rollback to boundary_case;
savepoint boundary_case;
select is(pg_temp.location_boundary('5.000001 seconds','0 seconds'),0::bigint,'future skew beyond boundary excluded');
rollback to boundary_case;
savepoint boundary_case;
select is(pg_temp.location_boundary('0 seconds','0.000001 seconds'),0::bigint,'any future server receipt excluded');
rollback to boundary_case;
savepoint card_case;
insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method)
select 'a7032000-0000-0000-0000-000000000003',rider_id,pickup,destination,vehicle_type_code,'card' from public.booking_requests where id='a7032000-0000-0000-0000-000000000001';
select public.backend_calculate_fare_quote('a7032000-0000-0000-0000-000000000003',1,2000,600,null);
select public.backend_lock_fare_quote((select id from public.fare_quotes where booking_request_id='a7032000-0000-0000-0000-000000000003'),1,1);
select throws_ok($$select * from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000003',2)$$,'55000',null,'draft booking cannot enter discovery');
update public.booking_requests set status='confirmed',confirmed_at=now() where id='a7032000-0000-0000-0000-000000000003';
select throws_ok($$select * from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000003',3)$$,'55000',null,'historical confirmed Card booking remains unavailable');
rollback to card_case;
savepoint offer_case;
select public.backend_create_driver_match_offer('a7032000-0000-0000-0000-000000000001','a7020000-0000-0000-0000-000000000001','a7021000-0000-0000-0000-000000000001',3000,3);
update public.driver_match_offers set status='cancelled',responded_at=now() where booking_request_id='a7032000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),0::bigint,'prior offer excluded even after reservation release');
rollback to offer_case;
-- No spatial extension is required, including across the longitude seam.
savepoint seam_case;
insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method)
values('a7032000-0000-0000-0000-000000000004','a7020000-0000-0000-0000-000000000007','{"latitude":0,"longitude":179.99}','{"latitude":1,"longitude":179.99}','economy','cash');
select public.backend_calculate_fare_quote('a7032000-0000-0000-0000-000000000004',1,2000,600,null);
select public.backend_lock_fare_quote((select id from public.fare_quotes where booking_request_id='a7032000-0000-0000-0000-000000000004'),1,1);
update public.booking_requests set status='confirmed',confirmed_at=now() where id='a7032000-0000-0000-0000-000000000004';
update public.driver_locations set longitude=-179.99 where driver_id='a7020000-0000-0000-0000-000000000001';
select is((select count(*) from public.backend_find_nearby_driver_candidates('a7032000-0000-0000-0000-000000000004',3)),1::bigint,'nearby Driver across antimeridian included');
rollback to seam_case;
savepoint upload_case;
set local role authenticated;
select set_config('request.jwt.claim.sub','a7020000-0000-0000-0000-000000000001',true);
select public.driver_record_location(null,2,0,0,10,null,null,clock_timestamp());
reset role;
select set_config('request.jwt.claim.role','service_role',true);
select is((select location_sequence from pg_temp.candidates() where driver_id='a7020000-0000-0000-0000-000000000001'),2::bigint,'latest real GPS upload is returned once');
rollback to upload_case;
select is((select provolatile::text from pg_proc where oid='public.backend_find_nearby_driver_candidates(uuid,integer,integer,integer)'::regprocedure),'s','discovery remains a statement-snapshot STABLE reader');
select * from finish();
rollback;
