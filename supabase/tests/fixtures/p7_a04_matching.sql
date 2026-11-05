\ir p7_a02_driver_availability.sql
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
do $$ declare n integer; b uuid; q uuid; begin
  for n in 2..4 loop
    b := ('a7032000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
    insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method)
      values(b,'a7020000-0000-0000-0000-000000000007','{"latitude":0,"longitude":0}','{"latitude":1,"longitude":1}','economy','cash');
    select id into q from public.backend_calculate_fare_quote(b,1,2000,600,null);
    perform public.backend_lock_fare_quote(q,1,1);
    update public.booking_requests set status='confirmed',confirmed_at=now() where id=b;
  end loop;
end; $$;
