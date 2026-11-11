# P7 matching expiry scheduler

## Scope

The service-role-only `public.backend_expire_due_booking_matches(integer)` dispatches bounded work to the existing version-guarded A04 expiry RPC. Default batch size is 25; callers may request 1–100. Candidate rows use `FOR UPDATE SKIP LOCKED`. A booking is due when a live offer's own `expires_at` has passed (15 seconds), or the booking's matching window reaches 90 seconds. The A04 RPC owns locking, state transitions, audit history, and reservation release. The scheduler adds no state machine and does not create Trips or financial records.

Only serialization failures are suppressed for retry on the next tick. Other database errors abort the call. Use a four-second statement timeout and batch size 25. The SECURITY DEFINER function has an empty search_path. The caller must have the service_role execute grant and the trusted service-role JWT claim; neither Rider nor Driver can invoke it.

## Manual activation (operator action only)

Prerequisites: reviewed production migration is applied; Supabase Cron is available; operator is connected as database administrator. Inspect for existing jobs first:

```sql
select jobid, jobname, schedule, command, active
from cron.job
where jobname = 'ridex-p7-matching-expiry';
```

Review any existing row and its run history before modifying it. Perform this explicit upsert in an admin transaction; it never runs as part of a migration:

```sql
begin;
select cron.unschedule(jobid) from cron.job
where jobname = 'ridex-p7-matching-expiry';
select cron.schedule(
  'ridex-p7-matching-expiry',
  '5 seconds',
  $job$
    set statement_timeout = '4s';
    set role service_role;
    select set_config('request.jwt.claim.role','service_role',true);
    select public.backend_expire_due_booking_matches(25);
    reset role;
  $job$
);
commit;
```

The command explicitly assumes the Supabase Cron database connection can `SET ROLE service_role`. Confirm that operational prerequisite before activation. Re-running the reviewed upsert leaves exactly one job with the same name and schedule. No `cron.schedule` call is made by this repository migration or test runner.

## Observe and roll back

```sql
select jobid, jobname, schedule, active from cron.job
where jobname = 'ridex-p7-matching-expiry';
select * from cron.job_run_details
where jobid = (select jobid from cron.job where jobname = 'ridex-p7-matching-expiry')
order by start_time desc limit 50;
select action, count(*) from public.audit_records
where action in ('matching.offer_expired', 'matching.search_expired')
group by action;
```

Run details expose success, errors, and duration. A successful call's returned integer is the processed booking count; inspect server logs or invoke manually with `SET ROLE service_role` to capture it. To disable, set the job inactive with `cron.alter_job(jobid, active := false)`; to remove it, `select cron.unschedule(jobid)` in an administrator transaction. Rollback is manual. Do not alter the scheduler function migration to remove an activated job.

## Local verification

`python supabase/tests/ops/p7_expiry_scheduler_local_test.py` creates a fresh network-disabled Docker PostgreSQL cluster using the cached Supabase image, replays every migration, and runs the scheduler pgTAP file. The database test checks grants, limits, 15-second expiry, idempotent retry, audit, and unchanged trip/payment state.

Serialization failures are deferred per booking. Other errors, including deadlock (40P01) or statement timeout, abort the transaction; the next tick retries canonical due work. No partial transaction effects commit on failure. Inspect failed runs rather than claiming every conflict was skipped.

Final local verification: all 36 migrations replayed, 17 scheduler pgTAP assertions passed, and two independent-session scenarios passed. No scheduled job was registered.
