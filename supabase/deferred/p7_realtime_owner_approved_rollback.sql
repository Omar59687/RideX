-- EXPLICIT OWNER ROLLBACK APPROVAL REQUIRED. Do not auto-run.
-- For a confirmed clean initial publication that had ZERO member tables,
-- INSERT/UPDATE/DELETE/TRUNCATE true before RideX activation ONLY.
-- Verify current subscribers and source/target environment independently.
-- In the same administrator session, set:
--   SET ridex.p7_target_ref = '<approved project ref>';
--   SET ridex.p7_realtime_rollback_approval = 'RIDEX_P7_REALTIME_ROLLBACK_REVIEWED';
BEGIN;
DO $rollback$
DECLARE
  target_table text;
  tables constant text[] := array['trips','trip_status_events','driver_locations'];
BEGIN
  IF current_setting('ridex.p7_realtime_rollback_approval',true)
       IS DISTINCT FROM 'RIDEX_P7_REALTIME_ROLLBACK_REVIEWED'
    OR nullif(current_setting('ridex.p7_target_ref',true),'') IS NULL THEN
    RAISE EXCEPTION 'Explicit rollback approval and verified target required'
      USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_publication
      WHERE pubname='supabase_realtime' AND NOT puballtables
        AND pubinsert AND pubupdate AND NOT pubdelete AND NOT pubtruncate
    ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_publication_tables
      WHERE pubname='supabase_realtime'
        AND NOT (schemaname='public' AND tablename=ANY(tables))
    ) OR (SELECT count(*) FROM pg_catalog.pg_publication_tables
        WHERE pubname='supabase_realtime') <> 3 THEN
    RAISE EXCEPTION 'Publication does not match sole RideX membership; refusing rollback'
      USING ERRCODE='55000';
  END IF;
  FOREACH target_table IN ARRAY tables LOOP
    EXECUTE pg_catalog.format('ALTER PUBLICATION supabase_realtime DROP TABLE public.%I',target_table);
  END LOOP;
  -- Restore historical operations only after membership is EMPTY.
  EXECUTE 'ALTER PUBLICATION supabase_realtime SET (publish = ''insert, update, delete, truncate'')';
END
$rollback$;
COMMIT;
