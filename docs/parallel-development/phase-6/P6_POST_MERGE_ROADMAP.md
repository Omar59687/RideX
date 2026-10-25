# Phase 6 post-merge audit and remaining execution roadmap

## R01/R02 implementation update - 2026-10-25

The original audit/specifications below are preserved. The canonical source,
journal gateway, application-support storage, existing-owner provider and bounded
canonical-screen panel merged via PR #54 at main `f9e6807`, originally on
`feature/p6-r01-r02-driver-cash-integration` from `fc3224c`.
R01/R02 remain PARTIAL because the approved deployment namespace and production
activation/canonical mounting are still open. The mock screen is unchanged.
See [SPRINT_TRACKER.md](SPRINT_TRACKER.md) for status and
[P6_R01_R02_IMPLEMENTATION.md](P6_R01_R02_IMPLEMENTATION.md) for files, owner decision,
319 historical focused local test results and limitations. R03 local composition
merged via #55 at `34801bc`; its aggregate review correction remains pending
in a follow-up PR. Runtime gates remain open.

Audit date: 2026-10-25. Audited main: `59be9b7712894c695e9c8efa580a1ffc2013bec7`.
The [sprint tracker](SPRINT_TRACKER.md) is the sole task-status authority and contains
the requested Implemented / Integrated / Verified / Remaining workstream table.
This roadmap describes implementation and acceptance work still needed; it does
not authorize that work or approve Phase 6. Task IDs R01-R09 below are prefixed
`P6-` and refine existing P6-02/04/06/07/08/09 scope, rather than a new architecture.

## Repository and cleanup evidence

- Fetched origin/main and checked GitHub PR metadata: #52 is MERGED, merged at
  `2026-10-25T15:45:40Z`, merge SHA matches the expected full SHA above.
- Original checkout was clean on `feature/p6-driver-lifecycle-b1b` at `6e8b316`.
  It was left on that branch. Documentation uses a separate clean worktree based
  on origin/main and branch `docs/p6-post-merge-reconciliation`. No other worktree,
  uncommitted or untracked file was reset, removed, overwritten or staged.
- Compared every changed path from #47 (`af594273`) and #51 (`180b0cc`) with main.
  Cash composition, Stripe modules/tests and closeout compatibility tests from
  #47 are identical. Canonical repository/tests were deliberately changed to RPC
  transport. Main's guarded Admin UI is retained; #47's legacy Admin wrapper,
  stale closeout/tracker text and optional list-caption difference are superseded.
  #51's provider is identical; its reader has stronger exact Session pinning and
  additional regressions. Architecture entries retain both infrastructure adapters.
  No unique necessary implementation was found. Both PRs were commented and
  CLOSED without merge as superseded by #52; no source branch was deleted.
- Migration 027 came from merged #50 (`b1f74c4`), before #52. Competing #48 is
  CLOSED without merge. No schema file or hosted environment was changed here.

## Code evidence and boundaries

Paths in this section are repository-relative, and exist in the audited tree.

| Component | Evidence in merged main | Limit |
|---|---|---|
| Canonical reader | `lib/core/repositories/canonical_payment_repository.dart`: `user_canonical_payment_record`, `admin_recent_canonical_payments`, persisted identity/version parsing, actor/session checks | No direct payment SELECT; no authority to settle or infer receipt issuance |
| Server authorization | `supabase/migrations/027_phase6_admin_payment_read_rpc.sql`: current nonblocked profile/ownership checks, explicit grants, bounded list | Checked as source only; hosted deployment/role behavior not reverified |
| Admin production integration | `lib/core/repositories/supabase_admin_payment_reader.dart`; `lib/features/auth/presentation/providers/admin_payment_providers.dart`; existing Admin screen/panel/mapper | App/SDK identity match plus initial Session object pinning; sanitized display; no mutation |
| Driver composition | `lib/core/repositories/supabase_driver_cash_completion_composition.dart`; `lib/core/repositories/supabase_driver_trip_completion_repository.dart` | Existing verified SDK/backend/B1-B owner required; original command only; trusted `driver_transition_trip` plus canonical Trip/receipt rereads; not production-activated |
| Durable completion/recovery | `lib/features/trips/application/driver_completion_coordinator.dart`; `lib/features/trips/application/driver_completion_recovery_coordinator.dart`; `lib/core/services/trips/file_driver_completion_command_store.dart` | Staging gateway and canonical source are interfaces, not production composition; recovery is read-only, no dispatch/retirement; receipt absence is not payment failure |
| Rider reads | `lib/features/history/presentation/providers/rider_payment_providers.dart` | Cash/Card providers bind the app client and exact canonical RPC reader for the current Rider; no trusted production Payment ID source or Trip-to-Payment lookup |
| Trip UI source | `lib/core/providers/repositories_providers.dart`; `lib/features/trips/presentation/screens/driver_active_trip_screen.dart` | `tripsRepositoryProvider` still uses `MockTripsRepository`; do not turn mock completion into financial authority |
| Stripe preparation | `supabase/functions/_shared/payments/test_intent_provider.ts`, `test_intent_fake.ts`, `test_intent_provider_test.ts` | Injected canonical context and account approval required; accepted Card Trip only; manual modes, confirm=false, no payment method/client secret/financial success |

## Verification provenance

The owner supplied PR #52 results: focused Flutter **45 PASS / 0 FAIL**; full
Flutter **1,489 PASS / 0 FAIL / 2 SKIP**; Flutter Analyze **No issues found** on
the preceding implementation commit. These are historical owner-provided results,
not newly executed tests. Exact per-run SHAs/logs were not supplied in this request;
no attribution to the final merge SHA is invented. Historical #47/#51 numbers in
older records are branch-specific, not replacement evidence for #52.

This documentation-only audit uses GitHub state, Git comparisons, source review,
Markdown link/path checks and `git diff --check`. It does not rerun Flutter, Node,
TypeScript or database suites, contact hosted Supabase, inspect credentials, invoke
Stripe, execute a financial operation or establish real-device acceptance.
Historical migration catalog reports do not prove the authenticated role matrix.

## Remaining task specifications

### P6-R01 - Approve backend registry and canonical completion context (P6-02/P6-07)

- Current implementation: `DriverBackendRegistry`, verified initialization access,
  `AuthService.driverBinding` and B1-B lifecycle exist. No approved default backend
  mapping or production `CanonicalDriverCompletionSource` is installed.
- Files/components: `lib/core/models/driver_authority.dart`,
  `lib/core/services/supabase/supabase_initialization_provenance.dart`,
  `lib/core/services/supabase/auth_service.dart`, `lib/app/bootstrap.dart`,
  `lib/features/trips/application/driver_completion_coordinator.dart`.
- Required work: owner records the exact trusted endpoint-to-stable-namespace mapping
  and canonical active-Trip source/ownership contract. Implement the smallest source
  using authenticated canonical Trip identity/version and current Driver eligibility;
  do not derive authority from `MockTrip`, booking version or a UUID-shaped value.
- Acceptance: unknown/ambiguous endpoints fail closed; same verified SDK/client,
  backend, Driver and epoch across every await; stale/foreign/non-Cash/non-inProgress
  context rejected; tests cover logout, A-to-B-to-A and namespace mismatch.
- Dependencies: explicit deployment registry approval and a canonical assigned Trip
  source. Phase 7 matching is not implemented here. An owner-authorized isolated
  canonical test fixture can validate the seam without claiming real matching.
- Physical device: **not required** for implementation/local acceptance. This audit
  supplies no registry approval or financial runtime authorization.

### P6-R02 - Wire bounded Driver Cash completion (P6-02/P6-07, B1-C)

- Current implementation: composition/adapter/coordinator and file journal exist;
  `DriverCompletionStagingGateway` remains an injection interface. No production
  provider/Driver UI consumer is installed.
- Files/components: the composition/adapter above;
  `lib/features/trips/application/driver_completion_coordinator.dart`,
  `lib/core/services/trips/driver_completion_command_store.dart`,
  `lib/core/services/trips/file_driver_completion_command_store.dart`,
  `lib/core/providers/repositories_providers.dart`,
  `lib/features/trips/presentation/screens/driver_active_trip_screen.dart`,
  `test/driver_cash_composition_test.dart`, `test/driver_completion_coordinator_test.dart`.
- Required work: bind the existing journal to the staging gateway; choose an app-owned
  durable directory and storage-failure handling; compose one session-scoped owner,
  canonical source and Cash repository; add bounded UI states using existing owners.
  Dispatch only a newly staged original command, never an inspected old command.
- Acceptance: durable acknowledgement precedes the one original dispatch; concurrent
  taps are single-flight; existing/conflicting/corrupt/uncertain evidence blocks;
  no new key/version on retry; session revocation suppresses late results; only
  canonical completion and Driver-safe receipt evidence affect success wording.
- Dependencies: R01, separately authorized B1-C scope/review, existing B1-B and trusted
  RPCs. Do not replace the global Mock Trip repository just to enable this slice.
- Physical device: **not required** for local SDK/widget/integration tests; hosted
  acceptance remains R07. Native journal lifecycle acceptance needs a native app
  runtime (emulator/desktop where supported can supply evidence).

### P6-R03 - Wire read-only Cash recovery and unresolved UI (P6-02/P6-07)

- Original PR #55 merged at `34801bc` after #54/main `f9e6807`.
  The follow-up branch reconciles both and corrects the reviewed aggregate issue:
  per-Driver read-only journal discovery,
  startup-on-provider-creation/resume/explicit triggers, canonical Cash Trip checks,
  receipt-summary reads and bounded panel states are composed locally. See
  [P6_R03_IMPLEMENTATION.md](P6_R03_IMPLEMENTATION.md). R03 remains PARTIAL:
  the approved backend registry is empty; the canonical panel is not
  mounted; hosted/runtime and journal/operator policy acceptance remain open.
- Receipt reuse: `user_trip_receipt_summary(target_trip_id)` is already authorized
  for authenticated participants by migration 019/020. R03 calls only that RPC;
  its P0002 result means receipt absent and never means payment failure.
- Files/components: `lib/features/trips/application/driver_completion_recovery_coordinator.dart`,
  `lib/features/trips/application/driver_cash_recovery_controller.dart`,
  `lib/core/repositories/canonical_trip_reconciliation_repository.dart`,
  `lib/core/repositories/supabase_driver_cash_completion_composition.dart`,
  `lib/core/services/trips/file_driver_completion_command_store.dart`, the R02
  session-scoped provider/panel; focused recovery, canonical reader and production
  composition tests.
- Required remaining work: independent follow-up re-review and namespace owner approval before
  activation; mount the canonical panel in a non-mock Driver Trip screen; establish
  owner-approved journal retention/export and operator-resolution policy; collect
  hosted role/session/restart evidence under R07. The read-only local composition
  already preserves exact command evidence and surfaces completed-but-receipt-
  unverified, not-visible and unknown outcomes. No automatic replay, clear or retirement.
- Acceptance: local tests cover restart discovery, evidence preservation, no write,
  missing receipt, stale version, and no dispatch. Full R03 acceptance still requires
  hosted runtime/role/session/restart evidence, canonical UI activation after the
  approved registry, and a policy for operator resolution; weaker reads never
  erase per-Trip canonical/receipt facts. Separate latest outcomes keep unresolved,
  failed and not-yet-checked commands visible in the aggregate; one verified Trip
  cannot hide another Trip. Focused correction tests: 210 PASS / 0 FAIL plus 5 architecture cases (215 total).
- Dependencies: R01 and R02's production storage/lifecycle binding; an independently
  approved receipt/retention policy where needed, without inventing journal deletion.
- Physical device: **not required** for local/restart-simulation acceptance; native
  storage/process lifecycle evidence may use a supported emulator/runtime. R07 covers hosted behavior.

### P6-R04 - Accept Admin and canonical RPC reads on hosted runtime (P6-08/read integration)

- Verification update, 2026-10-25 on main `34801bc`: **PARTIAL**, with hosted
  authenticated acceptance **BLOCKED**. Project identity, migration 027 matching
  bodies/grants/RLS and estimated plans were inspected read-only; no hosted actor
  RPC or financial-row reads were executed. Local evidence: 117 focused Flutter
  tests, 103 SQL assertions PASS; clean Analyze. See the
  [R04 evidence record](P6_R04_HOSTED_RPC_VERIFICATION.md) for the role matrix,
  environment/identity blockers and findings. A passing local characterization
  test is not acceptance of unobserved remote revocation or nullable-Trip rendering.
- Hardening update based on main `a637f5e` (after PR #57): F01/F02 are locally remediated.
  The production Admin reader rechecks the pinned SDK session and live Admin
  profile before/after its RPC; nullable `trip_id` is supported by the Admin and
  canonical readers with strict checks retained for missing/malformed fields.
  51 focused tests pass and Analyze is clean. This bounded client revalidation
  cannot promise instantaneous remote revocation; no hosted acceptance is claimed.
- Current implementation: production Admin RPC composition is merged; exact canonical
  RPC and strict parsing/session guards exist. Authenticated hosted acceptance is open.
- Files/components: both payment reader adapters, Admin providers/panel/mapper,
  `test/admin_payment_live_reader_test.dart`, `test/admin_payment_integration_test.dart`,
  `test/canonical_payment_reader_test.dart`; migration 027 and its SQL test file are
  read-only contract references, not files to redeploy in this task.
- Required work: with separately authorized dedicated test accounts/data, record hosted
  nonblocked Admin, owning/foreign Rider, Driver, blocked/demoted Admin and anonymous
  reads; verify app logout, role changes, SDK A-to-B-to-A and redacted error/display behavior.
  Inspect representative listing plans/latency; the earlier synthetic top-N scan is
  a scale risk, not proof that a new index is required for this deployment.
- Required follow-through before acceptance: run approved hosted profile-revocation
  and nullable-Trip read cases, then verify bounded UI/session publication behavior.
  No migration was changed. Runtime latency is still unmeasured;
  the hosted estimated listing plan scans/sorts, while the exact read uses the
  primary-key index with an authorization filter.
- Acceptance: exact read returns only authorized persisted identity/version; foreign
  and nonexistent IDs are indistinguishable; only nonblocked Admin lists up to 50;
  direct finance SELECT remains denied; no raw IDs/provider payloads reach UI; no
  stale account publishes data; reads change no rows. Record target, revision and logs.
- Dependencies: authorized hosted access/test identities and migration 027 confirmed in
  the target. Any index/schema remediation is a separate approval and PR.
- Physical device: **not required** for hosted role tests and browser/emulator UI checks.
  A native repeat can remain a separately tracked release gate.

### P6-R05 - Finish approved Rider canonical read consumer integration (P6-06 follow-through)
**Implementation update - 2026-10-25:** provider wiring and focused local guards
are implemented on `feature/p6-r05-rider-payment-reader` from main `3c83c78`.
The shared production repository is available only to an authenticated,
unblocked Rider whose profile identity matches the exact SDK Session. Rider
exact reads reject non-Rider roles, pin session identity, and accept valid null
Trip linkage; presentation reports "Trip not yet linked" without asserting
payment success. Local tests cover loopback RPC-only reads, SDK/app mismatch,
Admin role rejection, A-B-A session change, foreign Rider rows, and nullable
Trip presentation. No hosted reads were made. **R05 remains PARTIAL.**

- Trusted identity today: Rider identity is from the application SessionController
  and server profile. No trusted persisted Payment ID is exposed by booking,
  history, or current Trip UI. Migration 027 only reads by exact
  `target_payment_id`; booking IDs and Trip IDs are not interchangeable. Do not
  activate the demo-backed history screen.
- Remaining dependency: a backend-issued Payment ID scoped to the Rider and
  linked to its canonical Trip. Assigned canonical Trip identity belongs to the
  Phase 7 boundary; payment creation and durable history/receipt restoration
  belong to Phase 8. The exact backend source/contract must be provided before
  wiring a production UI consumer. R04 hosted authorization acceptance also
  remains blocked by missing approved environment provenance and fixtures.

- Current implementation: canonical Cash/Card adapter and app-client provider
  integration exist. The production history surface has no trusted Payment ID,
  so no screen consumer is activated. Display guards reject caller-built success.
- Files/components: `lib/features/history/presentation/providers/rider_payment_providers.dart`,
  `lib/features/history/presentation/models/rider_payment_presentation.dart`,
  `lib/features/history/presentation/widgets/rider_payment_status_card.dart`, canonical
  reader and existing `test/rider_payment_provider_test.dart` / state-mapping tests.
- Required work: establish the trusted backend-issued Payment ID and canonical
  Trip association; then connect the authorized exact-ID reader to the canonical
  Rider Trip/history surface. Keep persistent History/receipt restoration in P8.
- Acceptance: missing identity/configuration fails closed; no mock ID inference;
  foreign/stale session responses rejected; amounts/status are canonical; paid status
  alone cannot produce an issued receipt or trusted completion/capture success.
- Dependencies: owner scope decision, R04 role evidence and a trusted backend-issued
  payment-ID/Trip source (possibly Phase 7/P8). If deferred, record the exact P8 task
  and retained unavailable UI; do not call this production integration completed.
- Physical device: **not required** for implementation/local and hosted read acceptance.

### P6-R06 - Compose trusted Stripe Test Mode preparation endpoint (P6-04)

- Implementation update - 2026-10-25 from `552b0f7`: an authenticated
  `stripe-test-intent` Edge Function, server-side Rider/profile validation, and
  filtered canonical Payment/Trip/attempt reader are implemented. Exact Payment,
  Trip and attempt IDs, both current versions, pending initial-authorization status,
  amount/currency consistency and the persisted idempotency key are checked before
  any provider seam. The handler rejects client financial fields and stale authority.
- Production provider dispatch remains hard-disabled in `supabase/functions/stripe-test-intent/index.ts`.
  No Stripe secret is read and no outbound provider request is possible from the
  production entrypoint. The existing Stripe adapter is only reachable in injected
  local tests. Its in-memory replay/unknown guard is not a durable cross-instance
  claim; durable attempt reservation and reconciliation are still missing.
- JOD is stored in 1/1000-dinar fils. The adapter now rejects nonmultiples of 10 and
  converts exact hundredths to Stripe's documented currency minor unit without
  rounding. This does not establish RideX account support or JOD Test Mode approval.
  The historical 2026-07-29 decision approves Test Mode only for the Graduation MVP demonstration; it does not approve this account/JOD endpoint configuration. Server-managed test credentials are not configured.
- Focused local Deno tests: **55 PASS / 0 FAIL**; Deno type check and format
  pass. No hosted calls, credentials, Stripe requests, DB mutations, migrations or
  deployment were performed. See [R06 implementation record](P6_R06_IMPLEMENTATION.md).
  R06 remains **PARTIAL**, and R08/Phase 6 remain open.
- Remaining work: approve the Test Mode account and JOD/currency precision; provide
  an isolated accepted Card Trip, its persisted Payment and pending initial
  authorization attempt; approve a durable reservation/unknown-outcome reconciliation
  contract; only then enable dispatch behind the same approval checks and collect
  sandbox-only evidence. The current request carries IDs and versions only, never
  amount/status. R08 secure UI/session contract and Phase 8 authorization/capture stay
  outside this slice.
- Physical device: **not required** for server work or injected tests. Hosted
  acceptance/deployment requires separate authorization.
### P6-R07 - Collect controlled hosted Cash completion/recovery evidence (P6-02/P6-07)

- Current implementation: trusted completion/receipt backend foundations and local
  adapters exist; the complete authenticated production consumer flow is unverified.
- Files/components: existing Driver composition/coordinator/recovery/journal, Driver
  UI, trusted Trip RPC and Driver receipt RPC; acceptance records in this directory.
- Required work: after separate authorization, run only an isolated nonproduction Cash
  test scenario with approved Driver/canonical Trip and counterpart test accounts.
  Record exact Trip/Payment/Receipt invariants with sanitized evidence. No real Cash
  collection or production financial transaction is needed or authorized by this audit.
- Acceptance: one trusted completion atomically completes Trip, settles Cash and issues
  one receipt; same original key does not duplicate; stale version, foreign/blocked
  Driver, concurrent requests, lost response, receipt-read failure and revoked session
  retain safe evidence; read-only recovery performs no mutation/replay. Separate
  canonical completed Trip from verified issued receipt in UI and logs.
- Dependencies: R01-R03, hosted test authorization/data and existing backend contract;
  R04 supports cross-role read evidence. Real matching may await Phase 7; isolated
  fixture validation does not establish an end-to-end matched ride.
- Physical device: **not required** for hosted SDK/emulator acceptance. Native restart
  storage checks and broader Rider/Driver real-device release tails remain separately open.

### P6-R08 - Resolve and complete secure Stripe UI foundation scope (P6-04/P6-05)

- Current implementation: Cash/Card selection exists; no Stripe PaymentSheet/Checkout
  or approved hosted card-entry integration exists. Preparation deliberately returns
  no client secret and cannot itself back a card-entry/authorization flow.
- Files/components: `lib/features/booking/presentation/providers/rider_payment_selection_provider.dart`,
  existing fare/booking screens, Rider payment states and the server preparation module.
- Required work: owner selects approved hosted card-entry approach and records which
  secure UI foundation is required for Phase 6. Implement only that bounded UI/backend
  handoff or explicitly defer the matched-Trip/provider-dependent part to Phase 7/P8.
  A usable payment session/client-secret contract needs separate secure design/review;
  do not bypass the current no-secret preparation interface or authorize early.
- Acceptance: no PAN/CVV or server secret enters RideX forms/storage; cancellation,
  unavailable and unknown states are explicit; no authorization before matching and
  no client-declared success. Preserve Phase 8 ownership of authorization/capture,
  webhooks/refunds/history. Scope disposition must not falsely check an unfinished UI.
- Dependencies: owner UI/scope decision, R06 and accepted matched Trip/session contract
  for a real sandbox flow; Phase 7 supplies real matching. This dependency must be
  explicitly recorded to avoid a circular unconditional Phase 6 exit gate.
- Physical device: **not required** for scope, widget and supported hosted-checkout
  browser work; native PaymentSheet acceptance needs a supported mobile runtime and
  any provider-specific device checks remain separately tracked, not assumed passed.

### P6-R09 - Integration acceptance and Phase 7 gate disposition (P6-09)

- Current implementation: contract/closeout fixture harness is merged. Fixture mapping
  and historical local green runs do not establish complete financial workflow approval.
- Files/components: `test/p6_closeout_acceptance_test.dart`, existing contract harness,
  [foundation acceptance](P6_FOUNDATION_INTEGRATION_ACCEPTANCE.md),
  [tracker](SPRINT_TRACKER.md), `Plan.md`, `docs/ai/ops/CURRENT_STATUS.md`.
- Required work: independent financial/security/integration review; associate final
  implementation revisions with focused/analysis/full non-live evidence when code
  changes warrant it; record hosted results, remaining device tails and explicit
  dispositions for every R task. Do not rerun a full suite merely for this docs PR.
- Acceptance: each exit requirement is passed or explicitly owner-deferred with a
  named follow-up/dependency; evidence distinguishes implementation, integration,
  local, hosted/runtime and approval. Only the owner can record Phase 6 approval or
  bounded Phase 7 continuation. Release requires its later gates independently.
- Dependencies: R01-R08 completion or explicit scope disposition, independent review,
  prior Phase 4/5 gate disposition (not silently closed), account/runtime access where
  applicable. Capture exact run SHAs/logs when available; do not fabricate missing ones.
- Physical device: **not required** for this reconciliation and decision record. Any
  retained physical-device gate stays unchecked until its own evidence or disposition.

## Recommended order and owner decisions

1. Start with **P6-R01**, then a focused **P6-R02 B1-C** implementation. Reuse existing
   journal/coordinator/session/composition seams; keep unresolved evidence fail-closed.
2. Wire R03; obtain R04 hosted read acceptance independently when access is authorized.
3. Resolve R05/R06/R08 scope and the accepted-Trip dependency before declaring a strict
   Phase 6-to-7 order. R06 local handler work need not wait for physical hardware.
4. Collect R07 isolated hosted evidence, then complete R09 review and explicit gate decision.

Owner decisions/access still needed: approved endpoint/namespace registry and canonical
Trip source; B1-C implementation/hosted test authorization; retention/receipt resolution;
Rider consumer P6/P8 scope; Stripe account/JOD precision/credentials and secure UI scope;
Phase 7 dependency/Phase 4/5 carry-over dispositions; final Phase 6 acceptance. None is
needed to review or merge this documentation-only PR, and no approval is invented here.

Phase 8 still owns Card authorization/capture/cancellation/refunds/webhooks and persistent
history/restoration. Phase 7 owns matching/Realtime. Phase 10 release/device verification
is not silently pulled into this cleanup or marked complete.
