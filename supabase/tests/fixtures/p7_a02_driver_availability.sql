-- Synthetic actors only. Run in a fresh disposable local database.
insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at,
 confirmation_token,email_change,email_change_token_new,recovery_token)
select '00000000-0000-0000-0000-000000000000',
 ('a7020000-0000-0000-0000-00000000000'||n)::uuid,
 'authenticated','authenticated','p7-a02-'||n||'@example.com','',now(),
 '{"provider":"email","providers":["email"]}'::jsonb,'{"display_name":"P7 A02"}'::jsonb,
 now(),now(),'','','','' from generate_series(1,7) n;
update public.users set role='driver' where id in (
 'a7020000-0000-0000-0000-000000000001','a7020000-0000-0000-0000-000000000002',
 'a7020000-0000-0000-0000-000000000004','a7020000-0000-0000-0000-000000000005',
 'a7020000-0000-0000-0000-000000000006');
update public.users set role='admin' where id='a7020000-0000-0000-0000-000000000003';
update public.users set is_blocked=true where id='a7020000-0000-0000-0000-000000000006';
delete from public.rider_profiles where user_id between
 'a7020000-0000-0000-0000-000000000001' and 'a7020000-0000-0000-0000-000000000006';
insert into public.driver_profiles(user_id,approval_status,rejection_reason)
select id, (case right(id::text,1) when '4' then 'pending' when '5' then 'rejected'
 else 'approved' end),
 case when right(id::text,1)='5' then 'Test rejection' else null end
from public.users where role='driver' and id::text like 'a7020000-%';
insert into public.driver_availability(driver_id,state)
select user_id,'offline' from public.driver_profiles where user_id::text like 'a7020000-%';
insert into public.vehicles(id,driver_id,vehicle_type_code,make,model,color,registration_plate,seat_capacity,is_active)
values
('a7021000-0000-0000-0000-000000000001','a7020000-0000-0000-0000-000000000001','economy','Toyota','Camry','White','P7 A02 1',4,true),
('a7021000-0000-0000-0000-000000000002','a7020000-0000-0000-0000-000000000002','economy','Toyota','Camry','White','P7 A02 2',4,true),
('a7021000-0000-0000-0000-000000000003','a7020000-0000-0000-0000-000000000001','comfort','Toyota','Crown','Black','P7 A02 3',4,false);
