-- Synthetic fixture factory only. Give independent simultaneous Trip scenarios
-- independent approved Drivers/vehicles instead of violating P7-A04 uniqueness.
create function pg_temp.add_matching_fixture_driver(driver_id uuid, vehicle_id uuid)
returns void language plpgsql as $$
begin
  insert into auth.users(instance_id,id,aud,role,email,raw_user_meta_data,created_at,updated_at)
  values('00000000-0000-0000-0000-000000000000',driver_id,'authenticated','authenticated',
    driver_id::text||'@example.com','{"display_name":"Independent fixture Driver"}',now(),now());
  update public.users set role='driver' where id=driver_id;
  delete from public.rider_profiles where user_id=driver_id;
  insert into public.driver_profiles(user_id,approval_status) values(driver_id,'approved');
  insert into public.driver_availability(driver_id,state) values(driver_id,'offline');
  insert into public.vehicles(id,driver_id,vehicle_type_code,make,model,color,registration_plate,seat_capacity,is_active)
  values(vehicle_id,driver_id,'economy','Toyota','Camry','White','P7 '||right(replace(driver_id::text,'-',''),20),4,true);
end;
$$;
