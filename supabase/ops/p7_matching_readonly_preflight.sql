-- Manual owner-approved target inspection only. No repair, grants or job changes.
begin read only;
select current_database() as database_name, current_user as inspecting_role,
       version() as server_version;
select version, name from supabase_migrations.schema_migrations order by version;
select driver_id, count(*) as active_trip_count, array_agg(id order by id) as trip_ids
from public.trips
where status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed')
group by driver_id having count(*) > 1;
select booking_request_id, count(*) as trip_count
from public.trips group by booking_request_id having count(*) > 1;
select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as result, p.prosecdef, p.proconfig, p.proacl,
       pg_get_userbyid(p.proowner) as owner,
       has_function_privilege('anon',p.oid,'execute') as anon_execute,
       has_function_privilege('authenticated',p.oid,'execute') as rider_driver_execute,
       has_function_privilege('service_role',p.oid,'execute') as backend_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
 ('rider_matching_session_is_active','rider_matching_request_guard',
  'backend_find_nearby_driver_candidates','backend_create_driver_match_offer',
  'backend_expire_booking_match_offers','backend_expire_due_booking_matches',
  'driver_transition_trip','driver_decline_match_offer') order by p.proname;
select has_schema_privilege('authenticated','private','usage') as client_private_usage,
       has_table_privilege('authenticated','private.rider_matching_request_budget','select,insert,update,delete') as client_budget_access,
       has_table_privilege('service_role','private.rider_matching_request_budget','select,insert,update,delete') as backend_direct_budget_access;
select column_name, data_type from information_schema.columns
where table_schema='auth' and table_name='sessions' order by ordinal_position;
select extname, extversion from pg_extension where extname in ('pg_cron','pgcrypto','pgtap');
select to_regclass('cron.job') as cron_job_catalog,
       to_regclass('cron.job_run_details') as cron_run_catalog;
commit;
