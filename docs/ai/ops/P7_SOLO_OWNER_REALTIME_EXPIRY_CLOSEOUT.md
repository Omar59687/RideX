# RideX Phase 7 — owner-only Realtime / matching expiry closure

**Source baseline:** `origin/main` commit `4797bbda96e2a63ff2b37e3d9de9e49c41962f2b` (2026-11-13). This package adds **new** operator scripts and local guard tests only; it does not replace any existing Flutter, database, Edge Function, or deferred migration contract. It is **not** a deployment/acceptance record.

## Current verified hosted state (read-only)

Target: Supabase project `ykasivejjchupswqyxpm` — ACTIVE_HEALTHY. `supabase_realtime` exists, `puballtables=false`, I/U/D/T are true, and **zero tables** are members. `trips`, `trip_status_events`, and `driver_locations` have RLS, authenticated SELECT access, one SELECT policy each, and default replica identity. The `backend_expire_due_booking_matches(integer)` function exists and permits execution by `service_role`, not `authenticated`/`anon`. `pg_cron` is not installed. No hosted operations were performed by this source patch.

## Why existing application code is not replaced

- `SupabaseTripRealtimeSource`: Trip INSERT/UPDATE and status-event INSERT are only hints, followed by authenticated canonical reads.
- `SupabaseRiderTripLocationSource`: location INSERT is only a hint, followed by participant-scoped location reads and freshness/sequence checks.
- B09 Driver offer polling already supplies a bounded read-only offer-discovery mechanism independent of publication membership. It does not replace Rider live location delivery.
- `supabase/deferred/20261106120000_phase7_realtime_publication_membership.sql` already refuses to add tables while DELETE/TRUNCATE are globally enabled. Keep this original file unchanged.

## Deliverables (all deferred, no hosted writes)

1. `supabase/ops/p7_realtime_expiry_readonly.sql`: safe read-only publication, RLS, RPC and overdue work inventory, without exposing user/account/payment rows.
2. `supabase/deferred/p7_realtime_owner_approved_activation.sql`: single-transaction, deliberately **non-idempotent** Realtime operation+membership change. It refuses to touch any publication with existing members, refuses missing RLS/SELECT policies, requires explicit session approval markers and separate operator confirmation of the target. Only after that does it set `publish='insert,update'` and add exactly three canonical tables. It does not change RLS/grants/replica identity.
3. `supabase/deferred/p7_realtime_owner_approved_rollback.sql`: exact three-table inverse, provided the initial publication was empty with I/U/D/T enabled. It refuses drift or other members. It restores old publication operations **only after dropping all three members**. Requires separate approval.
4. `supabase/deferred/p7_expiry_cron_owner_approved_activation.sql`: refuses missing `pg_cron`, wrong RPC ACLs, absent operator SET ROLE permission, or existing same-name job. After independent approval schedules a DB-only five-second job using a **transaction-scoped** `service_role` and JWT role setting with four-second timeout and batch 25. The job has **no explicit `BEGIN`/`COMMIT` inside `$job$`**: pg_cron supplies an implicit transaction, and explicit transaction commands caused `EndTransactionBlock: unexpected state BEGIN` in the local background-worker test. No HTTP, external service key, or `pg_net` is used.
5. `supabase/deferred/p7_expiry_cron_owner_approved_disable.sql`: deactivates only the named job without unscheduling or deleting its history; requires explicit approval.
6. `supabase/tests/ops/test_p7_activation_contract.py`: offline fail-closed source-contract tests; not a PostgreSQL execution test.

## Before any approved Realtime activation

- Confirm the exact Supabase project and a recoverable backup/restore point. A previous project inspection found backup/PITR unavailable, so **do not assume recovery is available**.
- Inventory **all existing users of the shared publication** (application channel listeners, external integrations, maintenance processes). An empty `pg_publication_tables` does **not** prove no subscribers exist. Have the owner approve the global removal of DELETE/TRUNCATE, or **do not activate**.
- Verify the three table RLS policies and real positive/negative participant reads. An RLS policy existing in the catalog is not proof of correct row-level behavior.
- Apply and verify first on an isolated **nonproduction** Supabase project, using Rider and Driver normal-user JWTs. Keep the original deferred membership migration untouched. Run the read-only preflight and manually verify the output.
- In an owner-approved administrative SQL session only, set session markers exactly as documented at the top of the proposed activation file. **Markers are not authentication** and cannot verify a project ID; confirm target in Dashboard before running it.
- Verify publication operations, three table memberships, receiving INSERT/UPDATE/status INSERT/location INSERT with correctly scoped actor subscriptions, foreign-user rejection, refresh after reconnect and no DELETE/TRUNCATE delivery. If observations fail, **do not promote**.

## Before any approved expiry activation

- Enable Supabase Cron / `pg_cron` as a separate approved operator step. Do not simply paste the script into the hosted SQL editor today.
- Verify the exact account/project, backup, database version, service-role execution boundaries and ability of the Cron job owner to `SET ROLE service_role` in its worker environment (not merely the interactive SQL session).
- Run a **single approved manual expiry batch** on a disposable test booking and validate offer expiry after 15 seconds, search-window expiry after 90 seconds, idempotency, unchanged Trip/Payment/Receipt and driver reservation release. Never expire or cancel unrelated historical Trips.
- Inspect `cron.job` before creating a job and record job ID/history. After approved activation monitor `cron.job_run_details`, outstanding offers/searches and SQL cost. Test disable procedure in nonproduction. Disable only the named job if anything unexpected happens.
- An interval of five seconds is justified by the short offer lifetime, but creates frequent jobs. Observe compute use and budget; alerts are not a spending cap.

## Verification matrix / closure criteria

| Area | Code-side state | Still required |
|---|---|---|
| Realtime publication | Guarded owner-only preparation | Isolated Postgres test; authorized hosted operation after backup and subscriber review |
| Rider and Driver subscriptions | Existing source preserved | Two-session live WebSocket, reconnect, stale/foreign/terminal tests |
| Matching expiry | Guarded owner-only scheduling prepared | Install Cron, worker-role check, test-only run, monitor/disable, explicit approval |
| Cash E2E | Previously recorded accepted Cash Trip | Fresh independent fixture or legitimate clean recovery; full GPS continuity/cancellation acceptance |

## Safe local validation (Windows)

From `C:\RideX-P7-Owner-Validation-20261113` after reviewing/applying this patch:

```powershell
python -m unittest discover -s supabase/tests/ops -p 'test_p7_activation_contract.py' -v

git diff --check
git status --short
```

For Supabase preflight, run only `supabase/ops/p7_realtime_expiry_readonly.sql` on the explicitly selected database, using your approved SQL editor. Do **not** execute anything under `supabase/deferred/` without separate, explicit owner approval and the preceding checks.

References: https://supabase.com/docs/guides/realtime/postgres-changes ; https://supabase.com/docs/guides/cron/install ; https://supabase.com/docs/guides/cron/quickstart.
