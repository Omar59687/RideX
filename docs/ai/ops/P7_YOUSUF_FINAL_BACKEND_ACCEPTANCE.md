# P7 Yousuf final backend acceptance

## Baseline and scope

Git state statements below describe the verified pre-delivery checkpoint. The later delivery commit and PR preserve this evidence and do not authorize hosted release or activation.

Latest synchronized main and branch HEAD: `9aab49971d6d21358c61908f6574b3dc35243f2b`. Branch: `feature/p7-yousuf-final-backend-acceptance`. Started from `7a815f5bff6c21b6927e202456c806c48b3d6ba0` after PRs #134/#135 merged, then safely fast-forwarded when #136 merged. #136 changed only Flutter/map files; Supabase source and backend test contracts did not change. All local work survived. PR #127 remains OPEN; #129 remains OPEN. No other worktree, hosted environment, feature flag, publication, Card/Stripe or financial settlement was changed. No commit, staging, push, PR or merge was performed.

Existing `cash-matching` and A03/A04/A05 remain the production architecture. This run adds operational expiry dispatch, reproducible real-Auth acceptance and concrete owner runbooks. It does not restart A01-A06 or duplicate matching/acceptance/payment logic.

## Implemented and reviewed

- New `backend_expire_due_booking_matches(integer default 25)` is bounded to 1-100 bookings, service-role-only, with an explicit trusted JWT-role check. Selects due 15-second offers OR expired 90-second searching windows; ordered canonical Booking rows use `FOR UPDATE SKIP LOCKED`. Calls the existing version-guarded A04 expiry RPC. Retains offer history, audit and reservation release. No Trip/payment/receipt creation.
- Migration creation and grants/revokes are one transaction. The existing security test's exact backend signature inventory now includes this one new RPC and retains all deny/client and service-only privilege assertions.
- Serialization failures defer a booking; other errors, including deadlock or statement timeout, roll back the transaction. The documented next tick retries canonical state. Suggested operator policy: batch 25, every 5s, 4s statement timeout. No job was created or activated, even locally.
- Manual activation supplies BOTH database role and the claim checked by auth.role(). The named-job replacement transaction leaves one reviewed job; observe cron.job and cron.job_run_details, batch return count, outstanding due state and existing audit records. Disable/unschedule only under owner approval; retain history. See [scheduler runbook](P7_MATCHING_EXPIRY_SCHEDULER.md).
- Eight new Deno cases inject malformed/unavailable Auth, profile and session responses and verify rejection without privileged writes. Existing endpoint guards, 429 behavior and credential separation remain unchanged.
- Read-only executable preflight: `supabase/ops/p7_matching_readonly_preflight.sql`. Checks driver active-Trip duplicates, Booking/Trip uniqueness, migration history, RPC signatures/ACLs/search paths, budget permissions, Auth session columns and Cron extension availability without mutation. Correct terminal statuses are used; no automatic repair.

## Real Auth verification

**26 PASS / 0 FAIL / 0 SKIP** through actual local GoTrue v2.197.0 and PostgREST v16.5, after all 36 application migrations on PostgreSQL 17.11. GoTrue itself creates Auth users/identities/sessions; no synthetic session table is substituted. Tests exercise signup, sign-in, /user identity, JWT/session association, own/foreign Booking RLS, blocked/missing/invalid/expired credentials, requests through the 30/31 admission boundary, privileged-RPC denial, real logout and session deletion, then denial of the still-unexpired JWT.

New disposable internal-network containers expose no host ports and use no existing credentials, stacks or volumes. A free explicit subnet avoids exhausted default Docker pools. Cleanup verifies ownership labels. Secrets and JWTs remain in process memory. Actual target schema/gateway configuration remains a separate approval-dependent check. The direct local GoTrue/PostgREST services do not exercise the hosted API-key gateway or deployed Edge runtime. The real guard's false budget response and Edge HTTP429/Retry-After mapping are verified separately. Details and exact repeat procedure: [real Auth report](../verification/P7_REAL_AUTH_ACCEPTANCE.md).

The ordinary session checks and service-role matching mutation are separate transactions. Revocation may occur after a check; an in-flight mutation can commit before the next guard notices. No atomic revocation, automatic compensation or full E2E guarantee is claimed.

## Migration and hosted deployment readiness

The 35-migration merged base plus `20261111103410_p7_matching_expiry_scheduler.sql` form the 36-file chain. No existing migration is rewritten. Local full replays, RPC grants, private-schema/budget permissions and concurrent budget tests pass. Target PostgreSQL/GoTrue/PostgREST/Cron versions, target catalog and actual historical migration state require read-only owner preflight. Duplicate nonterminal Trips must return zero rows; any conflict requires a separately approved recovery, never automatic deletion.

[Deployment runbook](P7_MATCHING_DEPLOYMENT_RUNBOOK.md) provides exact CLI3.1.0/psql/backup/dry-run/post-deployment commands, explicitly targeting the approved project and using --skip-vault to avoid unrelated Vault updates. It includes backup verification, stop conditions and manual recovery guidance. Its commands are READY FOR OWNER APPROVAL; this run is not hosted authorization. Keep integration flags off, do not disable JWT verification or prune functions. Scheduler activation is a separate owner action after migration, Auth/gateway and manual batch acceptance.

## GPS, Realtime and Moath handoff

Backend accepts only latest-sequence GPS with recorded/received age<=60s, accuracy<=50m, device future skew<=5s and no future server receipt; stale/invalid latest evidence cannot fall back to an older sample. Current available mode uses low accuracy, 50m distance filter, 30s minimum update interval and a 120s maximum meaningful-publish interval. That maximum is not a heartbeat guarantee: the Geolocator movement stream can remain silent while stationary. Client validation also permits older/future-dated evidence than matching. Backend rejection remains correct.

Omar owns the smallest correction: credible <=50m acquisition and fresh-location publication/heartbeat at <=30s, including stationary devices; do not relabel an old fix as current or relax server policy. Required sequence, accuracy, freshness, skew and negative cases are in [Moath's eight-step E2E handoff](P7_MOATH_CASH_E2E_HANDOFF.md). No Omar files changed.

PR #127 is still review-only/open; real Realtime delivery and DELETE/TRUNCATE publication safety remain unresolved. No deferred publication migration was copied or enabled. Canonical authenticated Driver polling can be used only with real participant-scoped data; it is not evidence of event delivery.

Moath's path: approved Cash Rider confirms canonical Booking/locked Quote -> authenticated cash-matching -> A03/A04 offer -> owning approved Driver reads Offer -> driver_transition_trip accepts current Offer/version/idempotency key -> actual canonical Trip -> Rider participant-scoped assignment/tracking reread. Use two approved accounts on two emulators/devices and one approved environment. Exact requests, actor grants, expected data, retry/error behavior and flags are in the handoff. No approved account/project was invented. Execution remains NOT RUN.

## Local verification

On exact latest main `9aab499`, full Flutter completed **2615 PASS / 0 FAIL / 4 SKIP**. The 68 focused contract/architecture/GPS tests also passed on the earlier main before the map-only fast-forward. Analyzer remains **18 diagnostics: 0 errors, 3 warnings, 15 informational**; full diagnostic locations are in the evidence JSON. No Dart source is changed by this work. The historical 22 failures and 24 analyzer diagnostics are superseded by main fixes; they are not reported as current. No tests were hidden, waived or skipped to achieve a pass.

Scheduler development exposed fixture timing/actor/version mistakes and the expected new-RPC inventory mismatch. Those were corrected to match A04's exact 15s constraint and real roles/versions. Existing assertions and financial invariants remain intact. Early real-Auth startup failures were isolated harness configuration issues (Docker subnet, pg_hba, Auth search_path/default JWT role and empty 204 parsing), corrected without changing production Auth/guards.

## Remaining work by owner

- Yousuf: obtain approval for exact target/catalog/backup/migration/gateway checks and the single Cron job; capture hosted sanitized acceptance evidence. All independently executable local backend work is complete once the closeout checks pass.
- Omar: GPS acquisition/cadence and stationary fresh-fix heartbeat; safe publication disposition and real event delivery/subscription teardown.
- Moath: authorized Driver reader/acceptance and canonical Trip recovery on the approved target; execute two-device journey with approved accounts.
- Sanad: controlled Confirmation/Searching/assignment/tracking integration and supported-device acceptance; coordinate 429 delay UX. Main fixes now compile/test successfully in the earlier latest-main run; this patch changes no UI.
- Team/owners: named accounts, one controlled nonproduction environment, P6-R07/R08 acceptance and P6-R09 exit disposition. Card/Stripe, financial settlement and live matching remain restricted.

## Acceptance matrix

| Requirement | Classification | Evidence or exact remaining gate |
|---|---|---|
| Existing matching architecture and Cash invariants | COMPLETE | A03/A04/A05 and Driver acceptance preserved |
| Local Auth/session/RLS/admission | LOCALLY VERIFIED | Real GoTrue/PostgREST 26 assertions plus Deno negative cases |
| Migration replay/grants/budget races | LOCALLY VERIFIED | Full36-chain and private/service/client assertions |
| Bounded expiry dispatch/history/audit | LOCALLY VERIFIED | Scheduler 17 pgTAP and 2 concurrency scenarios |
| Single job activation/observability/rollback procedure | READY FOR OWNER APPROVAL | Manual named-job SQL; no active job |
| Real hosted Auth/gateway/deployment | NOT RUN | Explicit target and account approval required |
| GPS matching compatibility | BLOCKED | Omar's <=30s fresh-fix publication and quality evidence |
| Realtime publication/delivery | BLOCKED | Omar/owners resolve #127 and live event evidence |
| Moath eight-step E2E preparation | READY FOR OWNER APPROVAL | Complete actor/API/data/device instructions |
| Two-emulator/device E2E | NOT RUN | Approved environment/accounts, GPS and delivery/read gates |
| P6/Card restrictions | COMPLETE | No Card/Stripe or settlement activation; P6 gates preserved |



Routing: Sol gpt-6.1-sol (harness medium), independent Codex gpt-6-luna tasks with high reasoning. Luna scopes covered Auth research/draft, database verification/runbook, expiry implementation/tests, GPS/Realtime handoff and two independent security rounds. Sol completed unfinished Auth/race tests, corrected fixtures/actor assumptions and CLI/preflight details, resolved the review objections and owns integrated acceptance.

## Final verification closeout

All results below are actual completed local runs, not inherited PASS claims:

- `deno test --node-modules-dir=auto` from supabase/functions: **191 PASS / 0 FAIL / 0 SKIP**, actual process exit 0. Includes **65 matching/Auth tests**. No network/environment permissions or live provider operations enabled.
- Edge entrypoint type check: PASS. Canonical-LF format check on six matching source/test files: PASS; this accounts for Windows checkout CRLF conversion without changing production source.
- `python supabase/tests/ops/p7_real_auth_http_acceptance.py`: **26 PASS / 0 FAIL / 0 SKIP**, real Auth/PostgREST and 36 migrations. The direct service HTTP assertion returns false for budget exhaustion; Deno separately proves Edge 429 and Retry-After 60.
- `python supabase/tests/ops/p7_a02_local_test.py`: **1317 PASS / 0 FAIL / 0 SKIP / 0 incomplete**.
- `python supabase/tests/ops/p7_matching_guard_local_test.py`: **27 SQL PASS + 2 budget races PASS**.
- `python supabase/tests/ops/p7_expiry_scheduler_local_test.py`: **17 SQL PASS + 2 scheduler scenarios PASS** (SKIP LOCKED contention; expiry wins against real waiting acceptance with no Trip/payment creation).
- `python supabase/tests/ops/p7_a04_concurrency_test.py`: **19 independent-session races PASS**, including cancellation, acceptance, expiry, block and lost-response recovery.
- Total SQL assertions **1361 PASS / 0 FAIL / 0 SKIP**; independent-session scenarios **23 PASS / 0 FAIL**. Final commands completed **six full 36-migration replays**, including two guard replays and one on a real GoTrue schema. Repeated development runs are not added to these totals. The guard runner's old static 35 caption is superseded by its two actual 36 migration-chain headers.
- Python harness syntax, all new-file whitespace/credential/path checks and git diff --check: PASS.
- Hosted operations, Cron activation, publication changes and real two-device E2E: **NOT RUN**, each count0 executed.

[Machine-readable evidence](../verification/P7_FINAL_BACKEND_LOCAL_EVIDENCE.json) records final counters, every analyzer diagnostic and hashes of the verified code. No temporary logs, Docker credentials or machine paths are included.

Independent final Luna review accepted the local backend with stated limits, after rechecking the corrected Cron role claim, precise rollback/retry semantics, ownership-checked resource cleanup and unchanged deny/client grants. Sol inspected and reproduced all numeric results. No hosted release approval is implied.

## Final verdict

**YOUSUF BACKEND HANDOFF READY** for local engineering handoff and owner review. Operational procedures and backend tests are complete; the prepared handoff precisely identifies all approval, target, GPS/Realtime and device gates. Hosted deployment/job activation and the actual Rider-to-Driver E2E remain unapproved and unexecuted.

## Changed-file inventory and Git state

All following files are unstaged/uncommitted on the isolated feature branch. Existing branches/worktrees are preserved; no generated platform files or caches are part of the change.

- `docs/ai/ops/P7_MATCHING_DEPLOYMENT_RUNBOOK.md`
- `docs/ai/ops/P7_MATCHING_EXPIRY_SCHEDULER.md`
- `docs/ai/ops/P7_MOATH_CASH_E2E_HANDOFF.md`
- `docs/ai/ops/P7_YOUSUF_FINAL_BACKEND_ACCEPTANCE.md`
- `docs/ai/verification/P7_FINAL_BACKEND_LOCAL_EVIDENCE.json`
- `docs/ai/verification/P7_REAL_AUTH_ACCEPTANCE.md`
- `supabase/functions/_shared/matching/cash_matching_auth_acceptance_test.ts`
- `supabase/migrations/20261111103410_p7_matching_expiry_scheduler.sql`
- `supabase/ops/p7_matching_readonly_preflight.sql`
- `supabase/tests/database/013_phase3_rls_rpc_hardening.test.sql`
- `supabase/tests/database/20261111103410_p7_matching_expiry_scheduler.test.sql`
- `supabase/tests/ops/p7_expiry_scheduler_local_test.py`
- `supabase/tests/ops/p7_real_auth_http_acceptance.py`
