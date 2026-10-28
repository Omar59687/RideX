-- Synthetic LOCAL-ONLY recreation. No hosted approval or claim token data.
insert into auth.users(id,email,raw_user_meta_data) values
 ('d3c3dc11-a840-4712-a6a4-599b4ae27329','r06-x2-rider@example.invalid','{}'),
 ('f148a7ec-7e85-48ef-847f-8e9eea880e1b','r06-x2-driver@example.invalid','{}'),
 ('d3c3dc11-a840-4712-a6a4-599b4ae27320','r06-x2-other@example.invalid','{}');
update public.users set role = 'driver' where id = 'f148a7ec-7e85-48ef-847f-8e9eea880e1b';
delete from public.rider_profiles where user_id = 'f148a7ec-7e85-48ef-847f-8e9eea880e1b';
insert into public.driver_profiles(user_id,approval_status,version) values
 ('f148a7ec-7e85-48ef-847f-8e9eea880e1b','approved',2);
insert into public.vehicles(id,driver_id,vehicle_type_code,make,model,color,registration_plate,seat_capacity,is_active)
 values ('48d007ab-c13c-4ff8-93f3-1dc7f1e6975d','f148a7ec-7e85-48ef-847f-8e9eea880e1b',
 'economy','Toyota','Camry','White','LOCAL X2',4,true);
select public.backend_create_pricing_configuration('economy',500,300,50,200,1000,50,true);
insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method,status,version,matched_driver_id,matched_vehicle_id)
 values ('84e8e5d2-4126-4c27-893b-b70e5318a184','d3c3dc11-a840-4712-a6a4-599b4ae27329',
 '{"latitude":31.9,"longitude":35.9}','{"latitude":32.0,"longitude":36.0}','economy','card','matched',5,
 'f148a7ec-7e85-48ef-847f-8e9eea880e1b','48d007ab-c13c-4ff8-93f3-1dc7f1e6975d');
insert into public.fare_quotes(id,booking_request_id,rider_id,status,pickup,destination,route_distance_meters,
 route_duration_seconds,vehicle_type_code,breakdown,fixed_fare_fils,pricing_configuration_id,pricing_version,quote_version,locked_at)
 values ('90532842-03bf-4644-a656-2cad3edf37d1','84e8e5d2-4126-4c27-893b-b70e5318a184',
 'd3c3dc11-a840-4712-a6a4-599b4ae27329','locked','{"latitude":31.9,"longitude":35.9}',
 '{"latitude":32.0,"longitude":36.0}',4000,1200,'economy','{"fixed_fare_fils":2550}',2550,
 (select id from public.pricing_configurations where is_active and vehicle_type_code='economy'),1,1,now());
-- Fixture setup is owner-only and may bypass mutation triggers; API tests never do.
alter table public.booking_requests disable trigger user;
update public.booking_requests set fare_quote_id = '90532842-03bf-4644-a656-2cad3edf37d1'
 where id = '84e8e5d2-4126-4c27-893b-b70e5318a184';
alter table public.booking_requests enable trigger user;
insert into public.trips(id,booking_request_id,fare_quote_id,rider_id,driver_id,vehicle_id,status,payment_method,
 pickup,destination,route_distance_meters,route_duration_seconds,original_fare_fils,current_fare_fils)
 values ('dda56345-4123-4a0c-9771-5287899d2344','84e8e5d2-4126-4c27-893b-b70e5318a184',
 '90532842-03bf-4644-a656-2cad3edf37d1','d3c3dc11-a840-4712-a6a4-599b4ae27329',
 'f148a7ec-7e85-48ef-847f-8e9eea880e1b','48d007ab-c13c-4ff8-93f3-1dc7f1e6975d','accepted','card',
 '{"latitude":31.9,"longitude":35.9}','{"latitude":32.0,"longitude":36.0}',4000,1200,2550,2550);
insert into public.payments(id,booking_request_id,trip_id,rider_id,method,fare_quote_id,
 authorized_amount_fils,final_amount_fils,card_status)
 values ('cbbb4b94-ac92-49b9-8b43-1f370c783e5b','84e8e5d2-4126-4c27-893b-b70e5318a184',
 'dda56345-4123-4a0c-9771-5287899d2344','d3c3dc11-a840-4712-a6a4-599b4ae27329','card',
 '90532842-03bf-4644-a656-2cad3edf37d1',2550,2550,'cardPaymentPending');
insert into public.payment_attempts(id,payment_id,type,status,requested_amount_fils,currency,idempotency_key,
 provider_name,authorization_cycle,attempt_sequence,created_at)
 overriding system value values ('45ae3584-fa38-4fa5-b8c8-10efd79f8416','cbbb4b94-ac92-49b9-8b43-1f370c783e5b',
 'initialAuthorization','pending',2550,'JOD','r06-x2-synthetic-operation','stripe',1,2,'2026-10-28T12:48:16.773058Z');
insert into private.stripe_test_dispatch_reservations(attempt_id,payment_id,trip_id,rider_id,operation_key,context,created_at)
 select a.id,p.id,t.id,t.rider_id,a.idempotency_key,jsonb_build_object(
 'paymentId',p.id,'attemptId',a.id,'riderId',p.rider_id,'paymentVersion',p.version,
 'tripId',t.id,'tripVersion',t.version,'driverId',t.driver_id,'tripStatus',t.status,
 'method',p.method,'paymentStatus',p.card_status,'amountFils',p.authorized_amount_fils,
 'currency',p.currency,'idempotencyKey',a.idempotency_key),'2026-10-28T12:48:16.986561Z'
 from public.payment_attempts a join public.payments p on p.id = a.payment_id
 join public.trips t on t.id = p.trip_id;
insert into public.driver_availability(driver_id,state,vehicle_id,active_trip_id,version)
 values ('f148a7ec-7e85-48ef-847f-8e9eea880e1b','onTrip','48d007ab-c13c-4ff8-93f3-1dc7f1e6975d',
 'dda56345-4123-4a0c-9771-5287899d2344',12);
