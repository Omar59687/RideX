# RideX Phase 7 — owner-only Realtime / matching expiry closure

**Source baseline:** `origin/main` commit `4797bbda96e2a63ff2b37e3d9de9e49c41962f2b` (2026-11-13). This package adds **new** operator scripts and local guard tests only; it does not replace any existing Flutter, database, Edge Function, or deferred migration contract. It is **not** a deployment/acceptance record.

## Integrated closeout checkpoint — 2026-11-15

- Current GitHub baseline inspected: `0508731c33bd25780e5fe224e7a2efcff86afc0f` (`origin/main`). The guarded package commit `9dc06dd4cfba6dd98862052e4a980da6ed7b4b0a` is based on `4797bbd`; it merged cleanly into an isolated checkout of the newer main, retaining PR #145/#146 history. No push, PR, deployment, or hosted write was performed.
- Current-main GitHub Actions run [43583972835](https://github.com/Omar59687/RideX/actions/runs/43583972835) reported 2,794 Flutter tests passed and 6 skipped; the configured Rider-router invocation passed 2 tests. Analyze completed with the repository's 20 non-gating diagnostics. Two D05 live Realtime tests are intentionally skipped in CI. This CI predates the local controller fix below.
- CI also logged a `StateError: Cannot fire new event. Controller is already firing an event` when a Driver presentation listener synchronously disconnected delivery during a pending publication. The controller now invalidates captured views immediately but defers nested listener notification to a microtask; the existing regression test now asserts no Flutter framework error and no command handoff. Flutter is unavailable in this environment, so this correction is **IMPLEMENTED, NOT LOCALLY VERIFIED**.
- Current environment has Python only among project verification tools; Flutter/Dart, Deno, Docker, Supabase CLI, and psql are absent. The offline activation-contract suite passes 7 tests. Cron worker, PostgreSQL/RLS, Realtime publication, actual WebSocket, and post-fix Flutter suites were not run.
- Read-only hosted inventory still shows no `pg_cron` installation/job and an empty `supabase_realtime` publication with INSERT/UPDATE/DELETE/TRUNCATE enabled. The guarded scripts remain under `supabase/deferred/`; no unsafe publication migration was added to automatic discovery. Hosted activation remains blocked on owner approval, subscriber inventory, recoverable backup/restore evidence, and nonproduction actor-level validation.
- Read-only migration parity found a pre-existing hosted history mismatch: source migration `20261028140221_phase6_r06_x2_guarded_reserved_recovery.sql` is absent from the hosted migration history while later migrations are recorded. Preserve the existing R06/X2 recovery fences; do not bulk deploy, rewrite migration history, or execute the missing migration as part of this closeout.
- The two hosted Drivers remain associated with accepted, nonterminal Trips; both are offline/on-trip and current GPS evidence is stale or belongs to a different Trip. This is not evidence of stale pointers or corruption. Do not reset availability or modify Trips directly. Use a dedicated isolated nonproduction Driver/vehicle fixture; any hosted canonical Trip cancellation requires explicit owner approval and the owning Rider's authenticated canonical RPC with a freshly read version.

### Android Maps and later physical acceptance

Android manifest metadata uses `${MAPS_API_KEY}`. `android/app/build.gradle` injects it from the `GOOGLE_MAPS_API_KEY` Dart define or the untracked `android/local.properties` `MAPS_API_KEY` property; the Android application ID is `com.ridex.app`. No key is committed. Configure the Maps key in the local ignored property or secure build environment and restrict it to this Android package plus the signing certificate SHA-1 fingerprint, with only the required Maps SDK enabled. Confirm a missing/invalid key displays the existing unavailable map fallback; rendered Maps remain **DEFERRED MANUAL ACCEPTANCE** until verified on a physical device.

For the later approved nonproduction two-device run, verify `flutter devices`, use distinct Rider/Driver test identities, confirm both target the same approved Supabase project, and launch the Rider with `--dart-define=RIDEX_ENABLE_CASH_MATCHING_INTEGRATION=true`; launch Driver without `RIDEX_ENABLE_TEST_DRIVER_CASH`. Complete Cash booking, real offer delivery/acceptance, same canonical Trip verification, GPS freshness/movement, reconnect/background recovery, and cancellation/terminal cleanup. Capture evidence without secrets. Do not run against hosted production or enable payment execution.

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
