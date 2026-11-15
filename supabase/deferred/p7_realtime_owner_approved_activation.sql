-- EXPLICIT OWNER APPROVAL REQUIRED. Never put this file in migrations/.
-- Works only on a publication with ZERO existing member tables: no unknown
-- table/subscriber impact is assumed safe. Subscriber inventory and owner
-- authorization must be independently verified before running this file.
--
-- In the same administrator session, AFTER written approval and verifying
-- the Supabase project in the dashboard, explicitly set BOTH markers:
--   SET ridex.p7_target_ref = '<approved project ref>';
--   SET ridex.p7_realtime_approval = 'RIDEX_P7_REALTIME_REVIEWED';
-- These session markers are an accidental-execution brake, NOT authentication
-- or proof of the actual project identity.
BEGIN;
DO $activate$
DECLARE
  pub record;
  target_table text;
  table_oid oid;
  member_count bigint;
  tables constant text[] := array['trips','trip_status_events','driver_locations'];
BEGIN
  IF current_setting('ridex.p7_realtime_approval', true)
       IS DISTINCT FROM 'RIDEX_P7_REALTIME_REVIEWED'
     OR nullif(current_setting('ridex.p7_target_ref', true),'') IS NULL THEN
    RAISE EXCEPTION 'Explicit owner approval and separately verified target required'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO pub FROM pg_catalog.pg_publication
  WHERE pubname='supabase_realtime';
  IF NOT FOUND OR pub.puballtables THEN
    RAISE EXCEPTION 'Expected scoped supabase_realtime publication not found'
      USING ERRCODE='55000';
  END IF;
  IF NOT pub.pubinsert OR NOT pub.pubupdate THEN
    RAISE EXCEPTION 'INSERT and UPDATE are required for RideX subscribers'
      USING ERRCODE='55000';
  END IF;
  -- This intentionally disallows replay and avoids modifying publications
  -- shared by other tables. Another plan is needed if membership is nonempty.
  SELECT count(*) INTO member_count FROM pg_catalog.pg_publication_tables
  WHERE pubname='supabase_realtime';
  IF member_count <> 0 THEN
    RAISE EXCEPTION 'Publication already has % member tables; stop for subscriber review',member_count
      USING ERRCODE='55000';
  END IF;

  FOREACH target_table IN ARRAY tables LOOP
    table_oid := pg_catalog.to_regclass(pg_catalog.format('public.%I',target_table));
    IF table_oid IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class WHERE oid=table_oid
          AND relkind IN ('r','p') AND relrowsecurity
      ) OR NOT has_table_privilege('authenticated',table_oid,'SELECT')
      OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_policies
        WHERE schemaname='public' AND tablename=target_table
          AND cmd IN ('SELECT','ALL')
      ) THEN
      RAISE EXCEPTION 'Required RLS/SELECT contract missing: %',target_table
        USING ERRCODE='42501';
    END IF;
  END LOOP;

  -- Publication operations are global, so caller MUST separately approve
  -- the loss of DELETE/TRUNCATE notifications for every current subscriber.
  EXECUTE 'ALTER PUBLICATION supabase_realtime SET (publish = ''insert, update'')';
  FOREACH target_table IN ARRAY tables LOOP
    EXECUTE pg_catalog.format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',target_table);
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_publication
    WHERE pubname='supabase_realtime' AND pubinsert AND pubupdate
      AND NOT pubdelete AND NOT pubtruncate AND NOT puballtables
  ) OR (SELECT count(*) FROM pg_catalog.pg_publication_tables
          WHERE pubname='supabase_realtime') <> 3 THEN
    RAISE EXCEPTION 'Post-activation publication verification failed'
      USING ERRCODE='55000';
  END IF;
END
$activate$;
COMMIT;
