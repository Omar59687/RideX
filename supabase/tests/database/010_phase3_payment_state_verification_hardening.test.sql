begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token) values
('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000001','authenticated','authenticated','rider-010@example.com','',now(),'{}','{"display_name":"Rider"}',now(),now(),'','','',''),
('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000002','authenticated','authenticated','driver-010@example.com','',now(),'{}','{"display_name":"Driver"}',now(),now(),'','','',''),
('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000003','authenticated','authenticated','admin-010@example.com','',now(),'{}','{"display_name":"Admin"}',now(),now(),'','','',''),
('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000004','authenticated','authenticated','blocked-010@example.com','',now(),'{}','{"display_name":"Blocked"}',now(),now(),'','','','');
update public.users set role = 'driver' where id = 'a0000000-0000-0000-0000-000000000002';
update public.users set role = 'admin' where id = 'a0000000-0000-0000-0000-000000000003';
update public.users set is_blocked = true where id = 'a0000000-0000-0000-0000-000000000004';
delete from public.rider_profiles where user_id in ('a0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000003');
insert into public.driver_profiles (user_id,approval_status,is_online,is_available) values ('a0000000-0000-0000-0000-000000000002','approved',false,false);
insert into public.vehicles (id,driver_id,vehicle_type_code,make,model,color,registration_plate,seat_capacity,is_active) values ('a1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002','economy','Toyota','Camry','White','PM 010',4,true);
select public.backend_create_pricing_configuration('economy',500,300,50,200,1000,50,true);

do $$
declare sequence_number integer; booking_id uuid; quote_id uuid; trip_id uuid;
begin
  for sequence_number in 1..5 loop
    booking_id := ('a2000000-0000-0000-0000-' || lpad(sequence_number::text, 12, '0'))::uuid;
    quote_id := ('a3000000-0000-0000-0000-' || lpad(sequence_number::text, 12, '0'))::uuid;
    trip_id := ('a4000000-0000-0000-0000-' || lpad(sequence_number::text, 12, '0'))::uuid;
    insert into public.booking_requests (id,rider_id,pickup,destination,vehicle_type_code,payment_method,status) values
      (booking_id,'a0000000-0000-0000-0000-000000000001','{"latitude":31.95,"longitude":35.93}','{"latitude":31.98,"longitude":35.97}','economy','card','matched');
    insert into public.fare_quotes (id,booking_request_id,rider_id,status,pickup,destination,ordered_stops,route_distance_meters,route_duration_seconds,vehicle_type_code,breakdown,fixed_fare_fils,pricing_configuration_id,pricing_version,quote_version,locked_at) values
      (quote_id,booking_id,'a0000000-0000-0000-0000-000000000001','locked','{"latitude":31.95,"longitude":35.93}','{"latitude":31.98,"longitude":35.97}','[]',1000,60,'economy','{"fixed_fare_fils":2500}',2500,(select id from public.pricing_configurations where is_active),1,1,now());
    insert into public.trips (id,booking_request_id,fare_quote_id,rider_id,driver_id,vehicle_id,status,payment_method,pickup,destination,route_distance_meters,route_duration_seconds,original_fare_fils,current_fare_fils) values
      (trip_id,booking_id,quote_id,'a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000001','completed','card','{"latitude":31.95,"longitude":35.93}','{"latitude":31.98,"longitude":35.97}',1000,60,2500,2500);
    perform public.backend_create_payment(trip_id);
  end loop;
end;
$$;

create function public.test_settle_card_payment(target_payment_id uuid, auth_key text, capture_key text)
returns void language plpgsql set search_path = '' as $$
declare current_payment public.payments%rowtype; current_attempt public.payment_attempts%rowtype;
begin
  select * into current_payment from public.payments where id = target_payment_id;
  if current_payment.card_status = 'cardPaymentPending' then
    select * into current_attempt from public.backend_record_payment_attempt(target_payment_id, 'initialAuthorization', current_payment.authorized_amount_fils, auth_key, 'provider');
    perform public.backend_complete_payment_attempt(current_attempt.id, 'succeeded', 'auth-' || auth_key);
    select * into current_payment from public.payments where id = target_payment_id;
    perform public.backend_transition_payment(target_payment_id, current_payment.version, null, 'cardPaymentAuthorized');
  end if;
  select * into current_attempt from public.backend_record_payment_attempt(target_payment_id, 'capture', current_payment.authorized_amount_fils, capture_key, 'provider');
  perform public.backend_complete_payment_attempt(current_attempt.id, 'succeeded', 'capture-' || capture_key);
  select * into current_payment from public.payments where id = target_payment_id;
  perform public.backend_transition_payment(target_payment_id, current_payment.version, null, 'cardPaymentSucceeded');
end;
$$;

select has_column('public','payment_attempts','refund_id','Refund attempts retain their canonical Refund association');
select throws_ok($$select public.backend_record_payment_attempt((select id from public.payments limit 1),'refund',2500,'generic-refund')$$,'55000','Refund attempts require their canonical Refund operation.','generic unassociated Refund attempts are rejected');

select lives_ok($$select public.backend_record_payment_attempt((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),'initialAuthorization',2500,'auth-pending','provider')$$,'pending authorization is recorded');
select throws_ok($$select public.backend_transition_payment((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),1,null,'cardPaymentAuthorized')$$,'55000','Card authorization requires a verified two-minute authorization attempt.','pending authorization cannot authorize Card payment');
select lives_ok($$select public.backend_complete_payment_attempt((select id from public.payment_attempts where idempotency_key='auth-pending'),'failed',null,'DECLINED')$$,'failed authorization is completed through trusted backend');
select throws_ok($$select public.backend_transition_payment((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),1,null,'cardPaymentAuthorized')$$,'55000','Card authorization requires a verified two-minute authorization attempt.','failed authorization cannot authorize Card payment');
select lives_ok($$select public.backend_record_payment_attempt((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),'replacementAuthorization',2500,'auth-success','provider')$$,'second authorization is recorded');
select lives_ok($$select public.backend_complete_payment_attempt((select id from public.payment_attempts where idempotency_key='auth-success'),'succeeded','auth-success-provider')$$,'successful authorization is verified by trusted backend');
select lives_ok($$select public.backend_transition_payment((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),1,null,'cardPaymentAuthorized')$$,'successful authorization within two minutes authorizes Card payment');
select throws_ok($$select public.backend_record_payment_attempt((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),'initialAuthorization',2500,'auth-third','provider')$$,'55000','Card authorization permits at most two attempts.','more than two authorizations are rejected');

insert into public.payment_attempts (payment_id,type,requested_amount_fils,currency,idempotency_key,created_at) values ((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000002'),'initialAuthorization',2500,'JOD','auth-stale',now()-interval '3 minutes');
select lives_ok($$select public.backend_complete_payment_attempt((select id from public.payment_attempts where idempotency_key='auth-stale'),'succeeded','auth-stale-provider')$$,'stale authorization receives a trusted completion');
select throws_ok($$select public.backend_transition_payment((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000002'),1,null,'cardPaymentAuthorized')$$,'55000','Card authorization requires a verified two-minute authorization attempt.','stale successful authorization cannot authorize Card payment');
select lives_ok($$select public.backend_record_payment_attempt((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000003'),'initialAuthorization',2500,'auth-failed','provider')$$,'failed authorization fixture is recorded');
select lives_ok($$select public.backend_complete_payment_attempt((select id from public.payment_attempts where idempotency_key='auth-failed'),'failed',null,'DECLINED')$$,'failed authorization fixture is completed');
select throws_ok($$select public.backend_transition_payment((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000003'),1,null,'cardPaymentAuthorized')$$,'55000','Card authorization requires a verified two-minute authorization attempt.','another failed authorization cannot authorize Card payment');

select public.test_settle_card_payment((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000004'),'refund-retry-auth','refund-retry-capture');
select public.test_settle_card_payment((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000005'),'refund-success-auth','refund-success-capture');
select public.test_settle_card_payment((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),'refund-full-auth','refund-full-capture');

set local role authenticated; select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000003',true); select set_config('request.jwt.claim.role','authenticated',true);
select lives_ok($$select public.admin_request_refund((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000004'),3,'duplicate_charge')$$,'Admin creates retry Refund');
select lives_ok($$select public.admin_request_refund((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000005'),3,'duplicate_charge')$$,'Admin creates success Refund');
select lives_ok($$select public.admin_request_refund((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),3,'duplicate_charge')$$,'Admin creates full Refund');
reset role;

select throws_ok($$select public.backend_transition_payment((select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),4,null,'refunded')$$,'55000','Invalid Card payment transition.','direct transition to refunded without verified Refund completion is rejected');
select lives_ok($$select public.backend_record_refund_attempt((select id from public.refunds where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001')),'refund-full-1','provider')$$,'Refund attempt is recorded through dedicated operation');
select is((select refund_id from public.payment_attempts where idempotency_key='refund-full-1'),(select id from public.refunds where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001')),'Refund attempt is linked to canonical Refund');
select is((select public.backend_record_refund_attempt((select id from public.refunds where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001')),'refund-full-1','provider')).id,(select id from public.payment_attempts where idempotency_key='refund-full-1'),'repeated Refund attempt creation is idempotent');
select lives_ok($$select public.backend_complete_refund_attempt((select id from public.payment_attempts where idempotency_key='refund-full-1'),'succeeded','refund-provider-1')$$,'verified Refund completion succeeds');
select is((select status::text from public.refunds where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001')),'succeeded','successful Refund completion finalizes canonical Refund');
select is((select card_status::text from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),'refunded','successful Refund completion atomically finalizes Payment');
select ok((select refunded_at is not null from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000001'),'successful Refund completion sets refunded_at');
select is((select public.backend_complete_refund_attempt((select id from public.payment_attempts where idempotency_key='refund-full-1'),'succeeded','refund-provider-1')).id,(select id from public.payment_attempts where idempotency_key='refund-full-1'),'repeated Refund completion is idempotent');

select lives_ok($$select public.backend_record_refund_attempt((select id from public.refunds where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000004')),'refund-retry-1','provider')$$,'first Refund attempt is allowed');
select lives_ok($$select public.backend_complete_refund_attempt((select id from public.payment_attempts where idempotency_key='refund-retry-1'),'failed',null,'PROVIDER_UNAVAILABLE')$$,'failed Refund attempt is recorded');
select is((select status::text from public.refunds where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000004')),'pending','failed Refund attempt leaves canonical Refund pending');
select is((select card_status::text from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000004'),'refundPending','failed Refund attempt leaves Payment refundPending');
select lives_ok($$select public.backend_record_refund_attempt((select id from public.refunds where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000004')),'refund-retry-2','provider')$$,'second Refund attempt is allowed');
select lives_ok($$select public.backend_complete_refund_attempt((select id from public.payment_attempts where idempotency_key='refund-retry-2'),'failed',null,'PROVIDER_UNAVAILABLE')$$,'second Refund failure is recorded');
select lives_ok($$select public.backend_record_refund_attempt((select id from public.refunds where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000004')),'refund-retry-3','provider')$$,'third total Refund attempt is allowed');
select throws_ok($$select public.backend_record_refund_attempt((select id from public.refunds where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000004')),'refund-retry-4','provider')$$,'55000','Refund permits at most three attempts.','fourth total Refund attempt is rejected');

update public.refunds set amount_fils = 1 where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000005');
select throws_ok($$select public.backend_record_refund_attempt((select id from public.refunds where payment_id=(select id from public.payments where booking_request_id='a2000000-0000-0000-0000-000000000005')),'refund-wrong-amount','provider')$$,'55000','Refund must match the full pending Payment amount in JOD.','Refund amount and currency must match the full Payment');

set local role authenticated; select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',true); select set_config('request.jwt.claim.role','authenticated',true);
select throws_ok($$select public.backend_record_refund_attempt((select id from public.refunds limit 1),'rider-refund','provider')$$,'42501',null,'Rider cannot invoke backend Refund operations');
select throws_ok($$insert into public.payment_attempts (payment_id,type,requested_amount_fils,currency,idempotency_key) values ((select id from public.payments limit 1),'refund',1,'JOD','client-refund')$$,'42501',null,'direct client Refund writes remain denied');
reset role;
set local role authenticated; select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000002',true); select set_config('request.jwt.claim.role','authenticated',true);
select throws_ok($$select public.backend_record_refund_attempt((select id from public.refunds limit 1),'driver-refund','provider')$$,'42501',null,'Driver cannot invoke backend Refund operations');
reset role;
set local role authenticated; select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000004',true); select set_config('request.jwt.claim.role','authenticated',true);
select throws_ok($$select public.backend_record_refund_attempt((select id from public.refunds limit 1),'blocked-refund','provider')$$,'42501',null,'blocked caller cannot invoke backend Refund operations');
reset role;
set local role anon;
select throws_ok($$select public.backend_record_refund_attempt((select id from public.refunds limit 1),'anon-refund','provider')$$,'42501',null,'anonymous caller cannot invoke backend Refund operations');
reset role;
select ok(not has_function_privilege('authenticated','public.backend_record_refund_attempt(uuid,text,text)','EXECUTE'),'authenticated does not receive Refund execution privileges');
select ok(not has_function_privilege('anon','public.backend_complete_refund_attempt(uuid,public.payment_attempt_status,text,text)','EXECUTE'),'anonymous does not receive Refund completion privileges');
select ok(has_function_privilege('service_role','public.backend_record_refund_attempt(uuid,text,text)','EXECUTE'),'only intended trusted role receives Refund execution privilege');
select ok((select count(*) from public.audit_records where action in ('payment.refund_attempt_failed','payment.refund_completed')) = 3,'Refund failure and completion audit behavior is present');

select * from finish();
rollback;
