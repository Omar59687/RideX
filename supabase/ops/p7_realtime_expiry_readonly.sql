-- RideX P7 owner closeout: read-only, safe on shared/hosted databases.
-- This file never changes publication operations, memberships, jobs, grants,
-- Trips, Payments, Auth, or any other state.
BEGIN TRANSACTION READ ONLY;

SELECT current_database() AS database_name, session_user AS inspecting_user,
       current_setting('server_version') AS postgres_version;

-- No client/subscriber inventory can be completed from SQL catalog entries
-- alone; inspect applications and Realtime subscriptions outside this query.
SELECT p.pubname, p.puballtables, p.pubinsert, p.pubupdate,
       p.pubdelete, p.pubtruncate,
       count(t.tablename) FILTER (WHERE t.tablename IS NOT NULL) AS member_tables,
       array_remove(array_agg(t.schemaname || '.' || t.tablename
                            ORDER BY t.schemaname, t.tablename), NULL) AS members
FROM pg_catalog.pg_publication AS p
LEFT JOIN pg_catalog.pg_publication_tables AS t USING (pubname)
WHERE p.pubname = 'supabase_realtime'
GROUP BY p.pubname, p.puballtables, p.pubinsert, p.pubupdate,
         p.pubdelete, p.pubtruncate;

-- Table-level policy existence is not a participant negative-read test.
SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled,
       c.relreplident AS replica_identity,
       has_table_privilege('authenticated', c.oid, 'SELECT') AS authenticated_select,
       count(pol.policyname) FILTER (WHERE pol.cmd IN ('SELECT','ALL')) AS select_policies
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_policies AS pol
  ON pol.schemaname = n.nspname AND pol.tablename = c.relname
WHERE n.nspname = 'public'
  AND c.relkind IN ('r','p')
  AND c.relname IN ('trips','trip_status_events','driver_locations')
GROUP BY c.oid, c.relname, c.relrowsecurity, c.relreplident
ORDER BY c.relname;

SELECT extname, extversion FROM pg_catalog.pg_extension
WHERE extname IN ('pg_cron','pg_net');
SELECT pg_catalog.to_regclass('cron.job') AS cron_jobs_table,
       pg_catalog.to_regclass('cron.job_run_details') AS cron_history_table,
       pg_catalog.to_regprocedure('public.backend_expire_due_booking_matches(integer)')
         AS expiry_rpc;

SELECT p.proname AS function_name, p.prosecdef AS security_definer,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') AS service_execute
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='backend_expire_due_booking_matches'
  AND pg_catalog.pg_get_function_identity_arguments(p.oid)='batch_limit integer';

-- Counts only: do not dump identifiable or financial rows into logs.
SELECT (SELECT count(*) FROM public.booking_requests
          WHERE status='searching' AND searching_at IS NOT NULL
            AND searching_at + interval '90 seconds' <= clock_timestamp())
          AS overdue_searches,
       (SELECT count(*) FROM public.driver_match_offers
          WHERE status='offered' AND expires_at <= clock_timestamp())
          AS overdue_offers;

COMMIT;
