-- EXPLICIT OWNER APPROVAL REQUIRED. Never put this file in migrations/.
-- The pg_cron extension MUST be installed and reviewed separately in the
-- target project. Does not enable pg_cron, overwrite jobs, or read any secret.
-- In the SAME database administrator session after target identity and
-- worker SET ROLE capability have been independently verified, run:
--   SET ridex.p7_target_ref = '<approved project ref>';
--   SET ridex.p7_cron_approval = 'RIDEX_P7_CRON_REVIEWED';
-- These session markers only deter mistakes; they are NOT authentication.
BEGIN;
DO $preflight$
DECLARE
  rpc_oid oid := pg_catalog.to_regprocedure(
    'public.backend_expire_due_booking_matches(integer)');
BEGIN
  IF current_setting('ridex.p7_cron_approval', true)
       IS DISTINCT FROM 'RIDEX_P7_CRON_REVIEWED'
     OR nullif(current_setting('ridex.p7_target_ref', true),'') IS NULL THEN
    RAISE EXCEPTION 'Explicit owner approval and separately verified target required'
      USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname='pg_cron')
     OR pg_catalog.to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION 'pg_cron not installed; enable it through a separately approved operator action'
      USING ERRCODE='55000';
  END IF;
  IF rpc_oid IS NULL OR NOT has_function_privilege('service_role',rpc_oid,'EXECUTE')
      OR has_function_privilege('authenticated',rpc_oid,'EXECUTE')
      OR has_function_privilege('anon',rpc_oid,'EXECUTE')
      OR NOT pg_catalog.pg_has_role(current_user,'service_role','SET') THEN
    RAISE EXCEPTION 'Expiry RPC ACL or cron job owner SET ROLE capability is not verified'
      USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname='ridex-p7-matching-expiry') THEN
    RAISE EXCEPTION 'An expiry job already exists; review it rather than replacing it'
      USING ERRCODE='55000';
  END IF;
END
$preflight$;

-- One bounded, service-role-only DB call per 5 seconds. pg_cron's background
-- worker runs its command in one implicit transaction: never put SQL BEGIN or
-- COMMIT inside $job$. SET LOCAL stays scoped to that implicit transaction.
-- Failure aborts that transaction and is recorded by Cron, without JWT keys.
SELECT cron.schedule(
  'ridex-p7-matching-expiry',
  '5 seconds',
  $job$
    SET LOCAL statement_timeout='4s';
    SET LOCAL ROLE service_role;
    SELECT set_config('request.jwt.claim.role','service_role',true);
    SELECT public.backend_expire_due_booking_matches(25);
  $job$
);
COMMIT;
