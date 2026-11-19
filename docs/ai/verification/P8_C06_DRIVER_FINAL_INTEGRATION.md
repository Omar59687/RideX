# P8-C06 — final Driver verification and integration package

Moath / Developer 3, issue #153. 2026-11-19.

**Verdict: APPROVED for local owner integration review.** The cumulative P8-C
workstream is READY FOR OWNER INTEGRATION REVIEW, with activation prerequisites
below. This is not approval to enable hosted completion, dispatch financial work,
push, open a PR, merge or deploy. Completion remains default-OFF.

## Reviewable package and ancestry

Dedicated branch: `feature/p8-c06-driver-final-integration`. Created clean directly
on approved C05; no merges, rebases or cherry-picks. Latest fetched origin/main is
`3be1aa67eecb49ce95ea77077b63964eb3cbc62c` and has not moved from the earlier baseline.
Assignment reread from `Phase 8/Moath.md` on
`origin/docs/phase-8-parallel-assignments-20261118`.

| Dependency order | Commit |
|---|---|
| C01 implementation | `2c52bc35708dd719168db051107113c7a9e87916` |
| C01 reviewed fix | `30a27aaa31eddfd6ece4ea6736d30582e54fcba6` |
| C02 approved | `1bd8a9659e04a0ca88f2fcee20bee6b00432d3fa` |
| C03 approved | `c152f44acc7372deb3d3928f06a0f6f671f265c3` |
| C04 approved | `c630ecc7f592f4b58063bff3a8514583b4fac881` |
| C05 approved / C06 parent | `27cfad61b67ad80233754fa13c7844e592a9c43c` |
| C06 | Commit containing this package; obtain full SHA with `git rev-parse HEAD`. |

`git merge-base --is-ancestor` verified each successive approved checkpoint.
The C01–C05 worktrees retain their approved HEADs and clean status; final clean-tree
checks are recorded with the local commit handoff. The original workspace branch
was not switched or edited. C06 changes only one Driver-owned file's formatting,
this verification package and current-status documentation; no semantic fixes or
new features were required.

- [Complete cumulative changed-file manifest](P8_C06_CUMULATIVE_MANIFEST.md)
- [Exact Omar/Yousuf/Sanad integration instructions](P8_C06_OMAR_INTEGRATION_HANDOFF.md)
- [Machine-readable verification, skipped tests and evidence hashes](P8_C06_VERIFICATION_RESULTS.json)
- Previous evidence: [C01](P8_C01_DRIVER_LIFECYCLE_AUDIT.md),
  [C02](P8_C02_DRIVER_COMPLETION_INTERACTION.md),
  [C03](P8_C03_DURABLE_UNKNOWN_RECOVERY.md),
  [C04](P8_C04_DRIVER_ACTIVE_TRIP_RESTORATION.md),
  [C05](P8_C05_DRIVER_COMPLETION_HANDOFF.md).

## End-to-end source trace

| Boundary | Actual implementation / verification |
|---|---|
| Acceptance creates canonical Trip | Existing `SupabaseCanonicalDriverPort.acceptOffer` calls `driver_transition_trip` with OFFER ID/version and original key. Canonical repository rereads assignment/Trip; an acknowledgement does not assign the UI. |
| accepted → driverArriving → driverArrived → inProgress | `DriverTripTransitionPolicy` is the intersection of 008's transition trigger and 014's Driver allowlist. 016/017 and P7 A04 wrappers preserve the backend contract. Arrival/progress target the TRIP ID/version. C01 `inspectTransition` checks eligibility, exact Trip/version and matching unchanged availability/vehicle around reads; it is a read-only preflight, not a new intermediate-action dispatcher. |
| Authorized completion intent | Existing `SupabaseDriverCompletionSource` pins normal-user SDK Session/backend/Driver/epoch and canonical active Cash Trip/version/key. `CanonicalDriverCompletionInteraction.verify` checks reviewed nonproduction configuration, connection, exact command, eligibility, assignment and active owned vehicle. Legacy MockTrip completion is disabled. |
| Durable stage then dispatch | `DriverCompletionCoordinator` accepts only `StagingNewlyCreated` with exact original command. Existing `JournalDriverCompletionStagingGateway` and native store append, flush, close, read back and release synchronization before acknowledgement. Existing evidence, write/flush/readback/lock uncertainty or failed final verification cannot dispatch. |
| Original backend command | Existing `SupabaseDriverCashCompletionComposition` rechecks eligibility/Trip/version just before the adapter's `driver_transition_trip(target_id, requested_status: completed, expected_version, idempotency_key)`. No new key/RPC, direct Trip/Payment/Receipt update or financial command was added. |
| Confirm completion | Existing authenticated adapter rereads exact canonical Trip. C02 adds current assigned Driver/vehicle and strictly newer completed-version confirmation before UI success. Receipt verification is a separate fact. RPC callback alone is insufficient. |
| Lost response / UNKNOWN | Original command and durable evidence survive. C03 recovery uses authenticated read-only exact Trip rereads; no auto-replay, replacement key or journal retirement. Late/wrong-session callbacks cannot publish. Terminal observations cannot resurrect an active Trip. |
| Restart / restore | C04 discovers current assignment from authenticated availability and rereads/rechecks eligibility and exact Trip. Cache/journal IDs are locators only. Foreign/stale/replaced evidence is rejected. Terminal state is separate from active assignment. |
| Connectivity / GPS / lifecycle | Generation and ownership guards suppress obsolete replies; disconnect hides evidence, reconnect rereads. Background/auth replacement retires old owners; resume constructs fresh ones. GPS health requires exact authority/SDK/Trip and age 0..45 seconds. |
| Financial handoff | C05 `DriverCompletionHandoffReader` and revocable event verify Trip, Payment and Receipt independently. Driver finance adapter/provider remains unconfigured until the reviewed backend contract exists; fake Card examples do not enable Card completion. |

Source transition authority inspected: `008_phase3_trip_cash_change_foundation.sql`,
`014_phase3_driver_lifecycle_reconciliation.sql`,
`016_phase3_driver_lifecycle_concurrency_correction.sql`,
`017_phase3_trip_payment_concurrency.sql`, and
`20261104100311_p7_a04_offer_lifecycle_atomic_acceptance.sql` under
`supabase/migrations/`. These were read only. Drivers can cancel only before
inProgress. Same-status acknowledgement is not a new authorized transition.
Skipped canonical observations are allowed; skipped command edges are not.

## Actual verification

All checks used Flutter **3.41.2 / Dart 3.11.0**, matching the existing Android CI.

| Check | Exact result |
|---|---|
| Full default Flutter suite | **3,037 passed, 0 failed, 6 skipped**, 163 test files; exit 0, JSON reporter completion 122.561 seconds. |
| Driver-focused subset inside that full run | **1,518 passed, 0 failed, 0 skipped**, 44 files; not an additional test run or added to the full total. Selection and per-file counts are in the results JSON. Session, Rider/Driver shared contract and finance boundary tests also ran in the full suite. |
| C05 handoff regression within full suite | 52 passed; C04 restoration 38, C03 recovery 21, C02 interaction 27, C01 lifecycle 32. Existing native journal/coordinator/controller/repository/widget regressions also passed. |
| Cumulative changed-file analysis | **31 Dart files, no issues**, exit 0. |
| Full Flutter analyzer | **21 inherited diagnostics: 3 warnings, 18 info**, exit 1. All ten diagnostic-bearing files have identical blobs to origin/main. Zero new diagnostics. Whole-repository analysis is not reported green. |
| Formatter | All 31 cumulative changed Dart files pass `--output=none --set-exit-if-changed`. One initial C01 policy formatting discrepancy was corrected without changing behavior. |
| Standard Android debug APK | `flutter build apk --debug --no-pub`: passed, exit 0. |
| Gated acceptance Android APK | Existing CI's `main_acceptance.dart` build with integration compilation flags true but nonproduction approval and offer-command approval false: passed, exit 0. Build only; not installed/launched. |
| Exact committed lock enforcement | `flutter pub get --offline --enforce-lockfile`: expected failure, **exit 65**. Original lockfile preserved. |

Full tests explicitly supplied empty `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` Dart defines. Six skips are two existing default-OFF
Rider router tests, two unconfigured live Supabase auth tests, and two opt-in
local real-Realtime acceptance tests. No skipped case is claimed as passed. The
JSON reporter's 169 hidden harness/setup completions are excluded from test totals.
No device integration runner, hosted fixture or financial execution was invoked.

Reproducible commands and SHA-256 hashes of raw test/analyzer/build/lock-check logs
are in the results JSON. Raw logs are local temporary verification artifacts, not
committed caches or a substitute for hosted acceptance. Build output contains
existing AGP/Kotlin, Android SDK XML and Java compatibility warnings; no platform
configuration change was made.

Temporary offline SDK resolution changed only characters 1.4.0→1.4.1, matcher
0.12.17→0.12.18, material_color_utilities 0.11.1→0.13.0, meta 1.16.0→1.17.0 and
test_api 0.7.6→0.7.9 for verification. `pubspec.lock` was restored to blob
`bb6148d20da9613013f01aa25dfefe82566360f1`; generated plugin changes were restored.
The guide's Flutter 3.27.3/Dart 3.6.1 is stale relative to the lockfile's existing
Dart >=3.8 constraint. Exact-lockfile and old-SDK reproducibility remain unresolved;
no committed dependency update was used to hide this limitation.

## Security/reliability scenarios exercised

- Wrong role, blocked/unapproved/revoked/expired or unassigned Driver; exact
  client/backend/SDK Session/epoch/Trip/version/vehicle checks.
- Duplicate/reentrant taps and callbacks; original command/key preserved;
  create-or-load prevents a new owner from dispatching existing evidence.
- Native journal write/flush/readback failure, uncertain persistence, stale lock,
  corruption, simulated process termination, restart and no automatic replay.
- Lost response/UNKNOWN, late callbacks, weaker reads and terminal regressions;
  no false completion from a callback or journal alone.
- Logout, A→B→A and delayed old responses at awaited boundaries; old scoped
  evidence never grants a new session dispatch rights.
- Active restoration, no assignment, foreign/stale IDs, disconnected source,
  reconnect, terminal reread, GPS age/identity and paused owner replacement.
- Independently completed Trip with pending Cash settlement, pending/failed Card,
  UNKNOWN financial outcome, missing/delayed receipt, receipt with unknown Payment,
  foreign Payment/Receipt/scope, version regression and no fabricated Paid/Receipt.
- Default-null/disabled provider gates and the legacy Driver completion stop gate;
  existing adapter/server permission boundaries remain unchanged.

## Independent cumulative review

A fresh reviewer context inspected **origin/main through approved C05**, including
adjacent existing completion source/composition/repository, durable staging/journal,
recovery, auth/session, router and backend contracts. It did not merely review C06
documentation or rely on earlier checkpoint approvals. Reviewer made no edits,
hosted calls, dependency operations or device actions; parent ran verification.

**APPROVED — zero critical, high or medium introduced findings.** Reviewer
confirmed transition/RPC alignment, exact identity/session/version safeguards,
new-stage-only dispatch, preserved UNKNOWN/no-replay, terminal/monotonic recovery,
scoped restoration/GPS and independent financial evidence. C06's only source
change is formatter output; no semantic reviewer fix was necessary.

Two nonblocking additional regression candidates were recorded, not hidden:
truly captured older repository responses arriving after newer overlapping reads
can leave an owner fail-closed/stale; retained aggregate recovery getters after
server eligibility denial require consumers to honor authorizationRevoked (the
C04 hint adapter already does). Neither is replay permission or a reason to
weaken checks. Fresh lifecycle owners/read-only reload and current revocable
consumer state remain required integration behavior.

## Remaining activation blockers and acceptance gaps

1. **Omar:** reviewed same-client/session/backend configuration, real delivery and
   connection inputs, synchronous invalidation, fresh foreground owners, read-only
   restoration entry, shared `/driver/completed` canonical guard and removal of
   inherited hard-coded Driver success/fare. Existing direct shared success route
   is not safe to activate as canonical completion presentation yet.
2. **Yousuf:** reviewed Driver-safe versioned Payment projection and fixtures.
   Current 020/027 deny Driver Payment reads; existing Driver receipt summary has
   no invented version/Payment ID. No unauthorized read workaround is supplied.
3. **Sanad:** consume the current revocable handoff read-only after integration;
   do not create a competing financial truth path or infer settlement from Trip.
4. **Acceptance:** issue #149 hosted discrepancy, real Realtime/Cron behavior,
   physical/emulator actor/session/lifecycle/GPS acceptance and hosted completion
   remain unproven. Neither fakes, loopback SDK fixtures nor APK compilation prove
   the deployed schema, financial consequences or device durability.
5. **Durability/toolchain:** native flush/readback is not directory fsync or a
   universal power-loss/cross-device guarantee. Stale locks fail closed and need
   a separately reviewed procedure; do not clear UNKNOWN evidence. Exact lockfile
   SDK compatibility remains a separate reproducibility decision.

The handoff document provides safe integration order, explicit owner requests and
rollback notes. Entire P8-C is ready for owner integration review with these
dependencies visible; hosted activation is not ready or authorized. No further
Moath Phase 8 checkpoint remains. No hosted mutations, financial/Stripe operations,
Supabase/backend edits, shared router/provider edits, other feature changes,
accepted Phase 7 Trip changes, emulator/session operations, push, PR, merge or
deployment were performed.
