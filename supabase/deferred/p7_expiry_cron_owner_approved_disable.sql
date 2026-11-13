-- EXPLICIT OWNER APPROVAL REQUIRED. Does not delete any job/history.
-- For incidents only, after verifying the intended target and scheduled job.
--   SET ridex.p7_target_ref = '<approved project ref>';
--   SET ridex.p7_cron_disable_approval = 'RIDEX_P7_CRON_DISABLE_REVIEWED';
BEGIN;
DO $disable$
DECLARE
  job_id bigint;
BEGIN
  IF current_setting('ridex.p7_cron_disable_approval',true)
        IS DISTINCT FROM 'RIDEX_P7_CRON_DISABLE_REVIEWED'
     OR nullif(current_setting('ridex.p7_target_ref',true),'') IS NULL THEN
    RAISE EXCEPTION 'Explicit disable approval and verified target required'
      USING ERRCODE='42501';
  END IF;
  IF pg_catalog.to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION 'No Cron job catalog' USING ERRCODE='55000';
  END IF;
  SELECT jobid INTO job_id FROM cron.job WHERE jobname='ridex-p7-matching-expiry';
  IF job_id IS NULL THEN
    RAISE EXCEPTION 'Named job missing; no changes made' USING ERRCODE='55000';
  END IF;
  PERFORM cron.alter_job(job_id, active := false);
END
$disable$;
COMMIT;
