begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token) values
('00000000-0000-0000-0000-000000000000','90000000-0000-0000-0000-000000000001','authenticated','authenticated','rider-009@example.com','',now(),'{}','{"display_name":"Rider"}',now(),now(),'','','',''),
('00000000-0000-0000-0000-000000000000','90000000-0000-0000-0000-000000000002','authenticated','authenticated','driver-009@example.com','',now(),'{}','{"display_name":"Driver"}',now(),now(),'','','',''),
('00000000-0000-0000-0000-000000000000','90000000-0000-0000-0000-000000000003','authenticated','authenticated','admin-009@example.com','',now(),'{}','{"display_name":"Admin"}',now(),now(),'','','',''),
('00000000-0000-0000-0000-000000000000','90000000-0000-0000-0000-000000000004','authenticated','authenticated','other-009@example.com','',now(),'{}','{"display_name":"Other"}',now(),now(),'','','','');
update public.users set role = 'driver' where id = '90000000-0000-0000-0000-000000000002';
update public.users set role = 'admin' where id = '90000000-0000-0000-0000-000000000003';
delete from public.rider_profiles where user_id in ('90000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000003');
insert into public.driver_profiles (user_id,approval_status,is_online,is_available) values ('90000000-0000-0000-0000-000000000002','approved',false,false);
insert into public.vehicles (id,driver_id,vehicle_type_code,make,model,color,registration_plate,seat_capacity,is_active) values ('91000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000002','economy','Toyota','Camry','White','PM 009',4,true);
select public.backend_create_pricing_configuration('economy',500,300,50,200,1000,50,true);
insert into public.booking_requests (id,rider_id,pickup,destination,vehicle_type_code,payment_method,status) values
('92000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','{"latitude":31.95,"longitude":35.93}','{"latitude":31.98,"longitude":35.97}','economy','cash','matched'),
('92000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000001','{"latitude":31.94,"longitude":35.92}','{"latitude":31.99,"longitude":35.98}','economy','card','matched');
insert into public.fare_quotes (id,booking_request_id,rider_id,status,pickup,destination,ordered_stops,route_distance_meters,route_duration_seconds,vehicle_type_code,breakdown,fixed_fare_fils,pricing_configuration_id,pricing_version,quote_version,locked_at) values
('93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','locked','{"latitude":31.95,"longitude":35.93}','{"latitude":31.98,"longitude":35.97}','[]',1000,60,'economy','{"fixed_fare_fils":2000}',2000,(select id from public.pricing_configurations where is_active),1,1,now()),
('93000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000001','locked','{"latitude":31.94,"longitude":35.92}','{"latitude":31.99,"longitude":35.98}','[]',1000,60,'economy','{"fixed_fare_fils":2500}',2500,(select id from public.pricing_configurations where is_active),1,1,now());
insert into public.trips (id,booking_request_id,fare_quote_id,rider_id,driver_id,vehicle_id,status,payment_method,pickup,destination,route_distance_meters,route_duration_seconds,original_fare_fils,current_fare_fils) values
('94000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000001','completed','cash','{"latitude":31.95,"longitude":35.93}','{"latitude":31.98,"longitude":35.97}',1000,60,2000,2000),
('94000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000002','93000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000001','completed','card','{"latitude":31.94,"longitude":35.92}','{"latitude":31.99,"longitude":35.98}',1000,60,2500,2500);

select has_table('public','payments','payments table exists');
select has_table('public','payment_attempts','payment attempts table exists');
select has_table('public','refunds','refunds table exists');
select has_table('public','receipts','receipts table exists');
select has_table('public','processed_webhook_events','webhook event table exists');
select has_index('public','payment_attempts','payment_attempts_one_active_card_authorization_idx','one active authorization index exists');
select has_index('public','payment_attempts','payment_attempts_one_successful_capture_idx','one successful capture index exists');
select has_index('public','refunds','refunds_one_active_per_payment_idx','one active refund index exists');
select has_index('public','processed_webhook_events','processed_webhook_events_expires_at_idx','webhook retention index exists');
select ok((select relrowsecurity from pg_class where oid='public.payments'::regclass),'payments have RLS');
select ok((select relrowsecurity from pg_class where oid='public.receipts'::regclass),'receipts have RLS');
select lives_ok($$select public.backend_create_payment('94000000-0000-0000-0000-000000000001')$$,'backend creates Cash payment');
select lives_ok($$select public.backend_create_payment('94000000-0000-0000-0000-000000000002')$$,'backend creates Card payment');
select is((select count(*) from public.payments),2::bigint,'one canonical payment exists per Trip');
select is((select cash_status::text from public.payments where method='cash'),'cashSelected','Cash uses its separate lifecycle');
select is((select card_status::text from public.payments where method='card'),'cardPaymentPending','Card uses its separate lifecycle');
select is((select public.backend_create_payment('94000000-0000-0000-0000-000000000001')).id,(select id from public.payments where method='cash'),'payment creation is idempotent');
select throws_ok($$select public.backend_record_payment_attempt((select id from public.payments where method='cash'),'initialAuthorization',2000,'cash-auth')$$,'55000','Only Card payments can be authorized.','Cash cannot authorize');
select lives_ok($$select public.backend_record_payment_attempt((select id from public.payments where method='card'),'initialAuthorization',2500,'auth-1','provider')$$,'first authorization is recorded');
select lives_ok($$select public.backend_complete_payment_attempt((select id from public.payment_attempts where idempotency_key='auth-1'),'failed',null,'DECLINED')$$,'first authorization receives a verified terminal result');
select lives_ok($$select public.backend_record_payment_attempt((select id from public.payments where method='card'),'replacementAuthorization',2500,'auth-2','provider')$$,'second authorization is recorded');
select throws_ok($$select public.backend_transition_payment((select id from public.payments where method='card'),1,null,'cardPaymentAuthorized')$$,'55000','Card authorization requires a verified two-minute authorization attempt.','pending replacement authorization cannot authorize Card payment');
select lives_ok($$select public.backend_complete_payment_attempt((select id from public.payment_attempts where idempotency_key='auth-2'),'succeeded','auth-2-provider')$$,'replacement authorization is completed through trusted backend');
select lives_ok($$select public.backend_transition_payment((select id from public.payments where method='card'),1,null,'cardPaymentAuthorized')$$,'verified replacement authorization authorizes Card payment');
select throws_ok($$select public.backend_record_payment_attempt((select id from public.payments where method='card'),'initialAuthorization',2500,'auth-3','provider')$$,'55000','Card authorization permits at most two attempts.','third authorization is rejected');
select throws_ok($$update public.payment_attempts set status='failed'$$,'55000','Payment attempts are append-only.','attempts cannot be rewritten');
select lives_ok($$select public.backend_transition_payment((select id from public.payments where method='cash'),1,'paid',null)$$,'completed Cash Trip settles Cash payment');
select lives_ok($$select public.backend_issue_receipt((select id from public.payments where method='cash'))$$,'settled Cash payment issues receipt');
select matches((select receipt_number from public.receipts where payment_id=(select id from public.payments where method='cash')),'^RDX-[0-9]{8}-[A-Z0-9]{8}$','receipt number has approved format');
select throws_ok($$update public.receipts set amount_paid_fils=1$$,'55000','Receipt financial snapshots are immutable.','receipt facts are immutable');
select lives_ok($$select public.backend_record_payment_attempt((select id from public.payments where method='card'),'capture',2500,'capture-1','provider')$$,'capture attempt is recorded');
select throws_ok($$select public.backend_transition_payment((select id from public.payments where method='card'),2,null,'cardPaymentSucceeded')$$,'55000','Card success requires a completed Trip and verified Capture.','Card cannot settle without successful Capture');
select lives_ok($$select public.backend_complete_payment_attempt((select id from public.payment_attempts where idempotency_key='capture-1'),'succeeded','capture-1-provider')$$,'capture is completed through trusted backend');
select lives_ok($$select public.backend_transition_payment((select id from public.payments where method='card'),2,null,'cardPaymentSucceeded')$$,'verified capture settles Card payment');
set local role authenticated; select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000003',true); select set_config('request.jwt.claim.role','authenticated',true);
select lives_ok($$select public.admin_request_refund((select id from public.user_trip_payment_summary('94000000-0000-0000-0000-000000000002')),3,'duplicate_charge')$$,'Admin requests a full Card refund');
select is((select amount_fils from public.user_refund_statuses((select id from public.user_trip_payment_summary('94000000-0000-0000-0000-000000000002')))),2500,'refund is full payment value');
select is((select card_status::text from public.user_trip_payment_summary('94000000-0000-0000-0000-000000000002')),'refundPending','refund request retains pending status');
select lives_ok($$select public.admin_request_refund((select id from public.user_trip_payment_summary('94000000-0000-0000-0000-000000000002')),4,'duplicate_charge')$$,'active refund request is idempotent');
reset role;
select lives_ok($$select public.backend_record_processed_webhook_event('provider','event-1',(select id from public.payments where method='card'))$$,'webhook event is recorded');
select is((select public.backend_record_processed_webhook_event('provider','event-1',(select id from public.payments where method='card'))).id,(select id from public.processed_webhook_events),'duplicate webhook returns original record');
select is((select expires_at-processed_at from public.processed_webhook_events),interval '90 days','webhook IDs retain for ninety days');
set local role authenticated; select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000001',true); select set_config('request.jwt.claim.role','authenticated',true);
select is((select count(*) from public.user_trip_payment_summary('94000000-0000-0000-0000-000000000001')) + (select count(*) from public.user_trip_payment_summary('94000000-0000-0000-0000-000000000002')),2::bigint,'Rider reads own payment summaries');
select is((select count(*) from public.user_trip_receipt_summary('94000000-0000-0000-0000-000000000001')),1::bigint,'Rider reads own receipt summary');
select throws_ok($$insert into public.payments (booking_request_id,rider_id,method,fare_quote_id,authorized_amount_fils,final_amount_fils,cash_status) values ('92000000-0000-0000-0000-000000000001',auth.uid(),'cash','93000000-0000-0000-0000-000000000001',1,1,'paid')$$,'42501',null,'clients cannot directly write payments');
reset role;
set local role authenticated; select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000002',true); select set_config('request.jwt.claim.role','authenticated',true);
select is_empty($$select * from public.payments$$,'Driver cannot read payments');
select is((select count(*) from public.user_trip_receipt_summary('94000000-0000-0000-0000-000000000001')),1::bigint,'assigned Driver reads restricted receipt summary');
reset role;
set local role authenticated; select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000004',true); select set_config('request.jwt.claim.role','authenticated',true);
select is_empty($$select * from public.payments$$,'unrelated Rider cannot read payments');
select throws_ok($$select * from public.user_trip_receipt_summary('94000000-0000-0000-0000-000000000001')$$,'42501','Finance data does not belong to this user.','unrelated Rider cannot read receipt summaries');
reset role;
select ok(not has_function_privilege('authenticated','public.backend_create_payment(uuid)','EXECUTE'),'payment creation is backend-only');
select ok(has_function_privilege('service_role','public.backend_create_payment(uuid)','EXECUTE'),'service role can create payments');
select ok(has_function_privilege('authenticated','public.admin_request_refund(uuid,integer,text)','EXECUTE'),'authenticated can reach guarded refund RPC');
select ok(not has_function_privilege('anon','public.admin_request_refund(uuid,integer,text)','EXECUTE'),'anonymous cannot request refunds');
select is((select count(*) from pg_proc where oid in ('public.backend_create_payment(uuid)'::regprocedure,'public.backend_record_payment_attempt(uuid,public.payment_attempt_type,integer,text,text)'::regprocedure,'public.backend_transition_payment(uuid,integer,public.cash_payment_status,public.card_payment_status)'::regprocedure,'public.backend_issue_receipt(uuid)'::regprocedure,'public.backend_record_processed_webhook_event(text,text,uuid)'::regprocedure,'public.admin_request_refund(uuid,integer,text)'::regprocedure) and prosecdef),6::bigint,'financial mutation functions are SECURITY DEFINER');
select is((select count(*) from public.audit_records where action in ('payment.state_transition','receipt.issued','payment.refund_requested')),5::bigint,'financial transitions and issuance are audited');
select * from finish();
rollback;
