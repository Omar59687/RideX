# P7-A02 local database verification — 2026-11-04

> Initial verification record below is retained as history. The final regression
> resolution section supersedes its NEEDS FIXES disposition.

## Scope and isolation

Branch: `feature/p7-a-matching-backend`; source HEAD: `83896280689e68d1b01f17e9a97362c9d70d861a` plus the uncommitted P7-A02 implementation.
Initial Git status contained the five P7-A02 implementation/test files; they were preserved.

Container: `ridex-r06-x2-cf504845f957`, newly created from
`public.ecr.aws/supabase/postgres:17.11.0.006` using the repository's
`supabase/tests/ops/r06_x2_local_test.py` cluster/bootstrap helpers.
Network mode `none`, no published ports, no mounts, fresh initdb under `/tmp`.
SQL used only `docker exec` and the new cluster's `/tmp` Unix socket.
No SQL, reset, migration, stop, or removal targeted `supabase_db_ridex` or other existing services.
Resources are retained for review. PostgreSQL socket readiness passed.
The inherited image healthcheck does not target this custom cluster/socket;
the container's healthcheck label is not the readiness evidence.

This is PostgreSQL 17.11, not the existing stack's 17.6. The repository's minimal
Auth bootstrap is reused; it does not verify GoTrue, PostgREST, Realtime, devices,
or hosted deployment. No provider calls or real financial operations occurred.
Synthetic finance regression rows exist only in disposable cloned databases.

## Commands and results

From the assigned worktree:

```powershell
python supabase/tests/ops/p7_a02_local_test.py
python supabase/tests/ops/r06_x2_local_test.py --existing-new-container ridex-r06-x2-cf504845f957
git diff --check
docker exec ridex-r06-x2-cf504845f957 pg_isready -h /tmp -U postgres
```

The first command expands test-owned `\ir` fixtures and adapts existing dblink
`host=db` transport in memory to `host=/tmp`. Every test file gets a separate
fresh clone. Historical SQL files are not edited for transport.

- Canonical chain: all **32 migrations applied**, exact migration history,
  zero recovery approvals provisioned. The R06 command independently replayed
  the same chain twice more, successfully.
- First command: **1,141 PASS / 1 FAIL / 0 SKIP**, 28 files. It correctly exits 1.
- Additional R06 command: **252 PASS / 0 FAIL / 0 SKIP**, 14 files,
  plus **16 PASS / 0 FAIL independent-session races**. Exits 0.
- Cash tests (39 assertions) occur in both commands. Deduplicated coverage:
  **1,354 PASS / 1 FAIL / 0 SKIP** across 40 distinct pgTAP files.
- `git diff --check`: PASS. Socket readiness: accepting connections.

### First-command breakdown

| Group | Pass | Fail | Skip |
|---|---:|---:|---:|
| 004–023 authorization/Phase 3 regressions | 931 | 1 | 0 |
| Phase 5: 025, 026, 026 concurrency | 67 | 0 | 0 |
| Phase 6: 027 canonical payment reader | 52 | 0 | 0 |
| Cash confirmation and concurrency | 39 | 0 | 0 |
| P7-A02 focused | 41 | 0 | 0 |
| P7-A02 concurrency | 11 | 0 | 0 |

The modified 015 lifecycle suite passed 31 assertions, including four new
reservation/active-Trip assertions. Together with the 41 focused and 11 new
concurrency assertions, **all 56 P7-A02-authored assertions passed**.
Existing 016 Driver lifecycle concurrency passed 37 assertions.

## Baseline failure, independently reproduced

`013_phase3_rls_rpc_hardening.test.sql`, assertion 11:
`all backend-only Phase 3 RPCs are isolated to service_role`.
Actual qualified catalog count **21**, hard-coded expected count **20**.

Created `p7_a02_baseline` in the same isolated cluster and applied all 31 canonical
migrations preceding P7-A02. Ran the unchanged 013 test with the same bootstrap:
**43 PASS / 1 FAIL / 0 SKIP**, identical assertion and actual/expected values.
These baseline rerun counts are separate from totals above.

The assertion counts all current `public.backend_%` service-only routines rather
than a fixed Phase 3 inventory; later migrations add routines to that namespace.
This is a pre-existing inventory-expectation failure, not a demonstrated client
permission leak or P7-A02 regression. No grant was relaxed and the unrelated test
was not rewritten to force green. A separate inventory-test correction or owner
disposition is required before claiming the entire regression suite is green.

Baseline reproduction used `docker exec -i <new-container> psql -h /tmp -U postgres`
with `ON_ERROR_STOP=1`, the existing `r06_x2_bootstrap.sql`, sorted migrations
excluding `20261104082240_p7_a02_driver_availability_safeguards.sql`, and expanded
013 SQL. pgTAP failure is in TAP output even though psql exits 0; the new runner
explicitly validates TAP plans and failures.

## Verified contracts and concurrency

Catalog inspection confirmed all three replacement signatures, row return types,
SECURITY DEFINER, and empty search paths. Focused catalog tests passed authenticated,
anonymous and service-role execution boundaries. Existing RLS/direct-write tests passed.

The new concurrency tests observed a real lock waiter, committed the winner,
and verified stale contender SQLSTATE `40001`, one version increment and preserved
winning state. Separate canonical Admin block/reject races observed Driver lock
waits followed by `42501` and offline availability. These are real PostgreSQL sessions.
Reservation and active-Trip clearing/type-change attempts were rejected in 015.
Existing reservation/recovery behavior passed, including the extended R06 suite.

No SQL implementation or authored assertion required correction after execution.
Heartbeat enforcement remains deferred because no canonical heartbeat writer exists.
P6-R06/R08 Card restrictions, P6-R08 Cash integration gate, and P6-R09 exit gate
are unchanged; this local verification does not satisfy hosted integration gates.

## Disposition

P7-A02's scoped database implementation is verified locally. Overall handoff:
**NEEDS FIXES** solely for the independently reproduced pre-existing 013 inventory
test failure or an explicit owner disposition. No commit, push, PR, merge, hosted
operation, or P7-A03 work was performed.


## Final regression resolution ? 2026-11-04

### Proven root cause and security boundary

The complete 21-signature inventory is now explicitly recorded in
`supabase/tests/database/013_phase3_rls_rpc_hardening.test.sql`.
Migration-by-migration replay in the new disposable database
`p7_regression_baseline` proved **20 before / 21 after** migration
`20261028140221_phase6_r06_x2_guarded_reserved_recovery.sql`, with exactly one added
signature and no removed signature:
`public.backend_record_stripe_test_preparation_fenced(uuid,uuid,text)`.
The introducing commit is `14335f5` (an ancestor of current HEAD).
The count assertion's last update, `a7e2ae7`, changed 17 to 20 but did not account
for this additional wrapper. It was not a P7-A02 production privilege change.

The wrapper is an intentional existing recovery contract: it requires service-role
JWT context; uses fixed empty search_path and SECURITY DEFINER; validates the
original dispatch token and evidence format for recovered attempts; quarantines
late observations; otherwise delegates to the guarded existing recorder.
The existing server adapter in
`supabase/functions/_shared/payments/test_intent_reservation.ts` invokes it.
Its introducing migration revokes every API role then explicitly grants service
role. This merged implementation is not an approval to activate Stripe.
`supabase/functions/stripe-test-intent/index.ts` still sets
`providerDispatchEnabled: false`; that file was not changed.

Effective catalog inspection in both the 31-migration baseline and 32-migration
P7-A02 database found identical 21 signatures: owner postgres, SECURITY DEFINER,
empty search_path, PUBLIC/anon/authenticated EXECUTE false, service_role true.
Private original claim/record/complete and lock helpers have EXECUTE false for
all four API roles, including service_role. No security issue was found in this
additional RPC's reviewed boundaries.

The test correction replaces its filtered hard-coded count with exact signature
set equality over all public `backend_` names, followed by an independent effective
privilege assertion. Missing, extra and overloaded signatures cannot be masked by
a matching count or by permission filtering. Existing RLS/search_path/anonymous
checks remain. No production SQL or grant was changed by this correction.

### Final execution

Fresh container: `ridex-r06-x2-83dbff8ec4ca`, PostgreSQL 17.11 using the same
repository helper, network none, no mounts or published ports. Old test containers
and the original Supabase stack were untouched.

```powershell
python supabase/tests/ops/p7_a02_local_test.py
python supabase/tests/ops/r06_x2_local_test.py --existing-new-container ridex-r06-x2-83dbff8ec4ca
git diff --check
```

- Main suite: **1,143 PASS / 0 FAIL / 0 SKIP**, all 28 files complete, exit 0.
- Corrected 013: **45 PASS / 0 FAIL / 0 SKIP**, both with P7-A02 and in the
  separate 31-migration baseline. Baseline rerun is outside suite totals.
- All **56 P7-A02-authored assertions PASS** (41 focused, 11 concurrency,
  four additions inside the 31-assertion 015 regression).
- All 32 migrations applied with exact history and zero provisioned approvals;
  the R06 command performs two further complete successful replays.

- Additional Phase 6 suite: **252 PASS / 0 FAIL / 0 SKIP**, all 14 files,
  plus **16 PASS / 0 FAIL independent-session races**, exit 0.
- Across the complete 40-file available pgTAP suite, deduplicating the 39 Cash
  assertions run in both commands: **1,356 PASS / 0 FAIL / 0 SKIP**.
- Final `git diff --check`: PASS. No runtime correction to P7-A02 was necessary.

**Final disposition: READY TO COMMIT**, as two independently reviewable changes.
Local verification is complete; hosted/service integration and Phase 6 exit
approval remain outside this checkpoint. No hosted mutation, provider activation,
financial production change, commit, push, PR, merge or P7-A03 work occurred.

### Commit separation

Keep the baseline regression correction as a focused independent change:
`supabase/tests/database/013_phase3_rls_rpc_hardening.test.sql` only.
It passes on the pre-P7 baseline and does not depend on the new migration.
Keep the P7-A02 migration, 015 extension, two dedicated tests, fixture, runner and
this checkpoint evidence together in the separate implementation change.
No files are staged and no commit has been made.
