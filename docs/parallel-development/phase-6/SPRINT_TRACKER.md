# Phase 6 — Sprint Tracker (authoritative status)

## R06 durable Test Mode preparation — 2026-10-26

**R06 PARTIAL; external provider dispatch OFF.** A proposed private reservation
migration and server adapter now provide one atomic original-attempt dispatch
claim, durable duplicate/restart protection and retained uncertain evidence.
Read-only reconciliation uses only a previously validated/stored provider ID;
an ID-less outcome stays unresolved. Payment/Attempt financial states are not
advanced. Local checks: **83 Deno PASS**, **31 pgTAP PASS**, and real PostgreSQL
concurrent/restarted claim PASS; type/format checks pass. Migration is local-only,
not deployed. Account/JOD approvals, canonical Card fixture, migration/hosted
safety acceptance, operator unknown-outcome policy and explicit activation remain
required. R05 bounded Cash acceptance is unchanged; Phase 6 NOT APPROVED.
See [durable design and exact gates](P6_R06_DURABLE_PREPARATION.md).

## R04/R05 security closeout — 2026-10-26 (current acceptance override)

Main `86e67cb` includes PR #67. **R05 ACCEPTED for the bounded canonical Cash
Trip/payment/receipt read UI**: prior owning-Rider SDK evidence and owner-attested
device display/refresh/logout/login/isolation are supplemented by fresh real
Rider-B SDK exact-ID rejection (HTTP 200/empty) and foreign Trip payment/receipt
denials (403/42501). No completed device/owning-Rider acceptance was repeated.

**R04 remains PARTIAL**: fresh Admin list bounds/redaction passed for one known
record, deployed LIMIT 50/order/field allowlist is confirmed, and previous role
denial/RLS/device evidence is retained. Blocked Admin count is zero; no approved
demoted-Admin fixture exists. These hosted cases remain BLOCKED without role or
account mutation. Hosted over-limit datasets and deliberately delayed/session
race tests were not run. New focused tests: **88 PASS**, Analyze clean.

Phase 6 remains **NOT APPROVED**. R05 acceptance is not Card/Stripe/history or
global financial release approval. Prior partial/missing-foreign-case entries
below are historical. See [evidence matrix and limits](P6_R04_R05_SECURITY_CLOSEOUT.md).

## R05 canonical Rider Cash detail UI — 2026-10-26

The existing participant-scoped `trips` SELECT policy supports a bounded latest
completed Cash Trip lookup; R05 now composes it with `user_trip_payment_summary`,
the existing exact-ID canonical reader and an independent Trip receipt RPC.
A distinct Rider-home entry and `/rider/canonical-payment` surface display the
result. Mock history remains separate. The former application discovery gap is
closed for this single-detail Cash scope without adding matching/history/schema
infrastructure. Session/provenance/version checks and stale-response tests apply.
Prior hosted exact payment/receipt reads passed; integrated UI hosted acceptance
and authorized foreign-Rider acceptance remain open. **R05 remains PARTIAL** and
Phase 6 NOT APPROVED. See [implementation and remaining gates](P6_R05_CANONICAL_TRIP_UI.md).

## Canonical Driver Cash UI integration — 2026-10-26

The R01/R02/R03 composition is now mounted on a distinct Driver-protected
`/driver/canonical-trip` surface, with a test-only Driver-home entry and independent
recovery notifications. Both entry and backend allowlist retain the default-off
`RIDEX_ENABLE_TEST_DRIVER_CASH` gate. The mock route remains separate. Readiness
uses the existing canonical active-Trip source; durable staging, session pinning,
B1-B epochs and read-only startup/resume/explicit recovery are reused.

The prior operator fixture execution reached `inProgress` version 4; this is
setup evidence, not completion/settlement/receipt acceptance. This code slice
performs no hosted operations and does not enable the flag. R01/R02/R03 runtime
wiring is implemented locally; R07 acceptance and R04 hosted role acceptance
remain pending. Phase 6 is NOT APPROVED. Older unmounted/no-fixture statements
below describe their historical checkpoints. See
[runtime wiring, activation command and remaining gates](P6_CANONICAL_DRIVER_CASH_UI.md).

## P6-R07 operator lifecycle correction - 2026-10-26

A hosted/source contract inspection caught a genuine #64 tool defect before any
offer or Trip was created: `accepted -> inProgress` is rejected by the existing
Trip transition trigger. The corrected operator sequence uses the same Driver
RPC through `driverArriving`, `driverArrived`, then `inProgress`, with canonical
identity/status/version rereads after each response. Six new lifecycle regressions
plus five existing fixture guards pass locally (11 total). No hosted fixture
execution was performed during this correction. The previous passing read-only
preflight remains data-prerequisite evidence only. Current execution is stopped
until the correction is reviewed/merged and the owner explicitly includes the two
intermediate test transitions in the execution scope. See
[R07 fixture preparation](P6_R07_TEST_FIXTURE_PREPARATION.md). R07 remains
**PREPARED, NOT ACCEPTED**; completion, settlement, receipt issuance and app
activation are not authorized here.

## P6-R07 isolated fixture tooling update - 2026-10-26

From PR #63 merge base `e41b7eb`, this change adds a Deno operator tool pinned to
the approved project/namespace and two dedicated actor identities. Read-only
preflight verifies canonical Cash booking + locked quote, approved Driver, owned
active compatible vehicle, availability and absence of existing Trip/offer. Its
explicit execution mode calls the existing service-role match-offer RPC and the
Driver-authenticated acceptance/start RPCs only; it stops at `inProgress` and
never completes, settles, issues a receipt, retries, or cleans up. Synthetic
vehicle values and authenticated vehicle RPCs are documented; no vehicle/Trip or
other hosted record was created. Focused Deno contract tests characterize the
allowlist and fail-closed guards. R07 remains **PREPARED, NOT ACCEPTED**; the app
flag stays off, R02 UI remains inactive, and hosted setup/financial acceptance
still requires separate operator authorization.

## P6-R07 test fixture preparation update - 2026-10-25

Base: latest inspected `origin/main` `49e5281dfef04ad9eb0e02d5303a344d425d6ac3`
(PR #62). The owner-approved graduation test endpoint and Driver journal
namespace are recorded in `approvedDriverCompletionBackendsProvider`; the
`RIDEX_ENABLE_TEST_DRIVER_CASH` compile-time flag remains default false and was
not enabled. Read-only management/catalog and account-scoped profile/count
inspection confirmed migration 027, the three provided profiles and zero
associated booking/Trip/Payment/Receipt rows. The approved Driver is offline and
has no vehicle; no active Trip or hosted matching/fixture setup function exists.
No hosted role RPC or financial operation was executed. Details and acceptance
steps: [P6-R07 fixture preparation](P6_R07_TEST_FIXTURE_PREPARATION.md).
R07 is **PREPARED, NOT ACCEPTED**; Phase 6 remains NOT APPROVED.

The prior R01 namespace-not-approved statements are superseded by PR #62. The
mapping is approved, but activation and canonical Driver UI acceptance remain
open. Older handoff sections below are historical evidence.

## Historical merge reconciliation baseline — `main` `552b0f7`

Verified GitHub `main` at `552b0f78f3e72b84cc7d5b446968a0b5e519f765`. Source and blockers: [Current Phase 6 closeout gates](P6_CURRENT_CLOSEOUT_GATES_2026-10-25.md). This is an implementation checkpoint, **not** acceptance of hosted financial operations.

- **R03 read-only recovery correction MERGED:** original #55 (`34801bc`), follow-up #56 (`8b1ee51`). Per-Trip canonical/receipt evidence and aggregate unresolved cases are preserved. Previous "awaiting #56 review" statements below are historical.
- **R04 local Admin F01/F02 hardening MERGED** via #58 (`3c83c78`); hosted authenticated role acceptance remains BLOCKED.
- **R05 Rider exact-ID reader integration MERGED** via #59 (`552b0f7`). SDK app/Rider identity and role guards are installed; **no trusted Payment ID** from booking/demo/Trip UI yet. R05 remains PARTIAL as a runtime feature.
- Canonical Driver screen mounting, R03 retention/operator policy, R04 hosted role matrix, R06 Stripe server/account activation, R07 hosted Cash/receipt acceptance, R08 card UI scope and R09 exit evidence remain OPEN. The R01 endpoint/namespace pair is approved in PR #62, while its activation flag remains default-off.
- Latest *reported* local tests are per-PR only (R03 #56 full 1,554 PASS/2 live skips; R04 #58 51 focused PASS; R05 #59 focused 5 files PASS with no number). They **cannot be combined** as a single current-main run. No tests performed in this documentation reconciliation.

## P6-R06 implementation update - 2026-10-25

Based on main `552b0f7`, implementation is on
`feature/p6-r06-stripe-test-preparation`. An authenticated `verify_jwt=true`
Edge handler, Rider/profile check, and server-side filtered canonical reader now
validate accepted Card Trip, exact Payment and pending initial-authorization
attempt, current Payment/Trip versions and persisted operation key. Caller amount
and status are rejected. The existing TestIntent provider rejects non-Test keys,
manual/unconfirmed intents and any response that implies confirmation/capture;
JOD conversion is exact only for multiples of 10 fils and never rounds.

**R06 PARTIAL.** Production function has provider dispatch hard-disabled and does
not read Stripe credentials. This is required because no account/JOD Test Mode
approval, isolated canonical attempt fixture, or durable cross-instance attempt
claim/unknown-outcome reconciliation contract is established. Local tests only use
injected providers. Focused Deno tests: 55 PASS / 0 FAIL; Deno type check and format
pass. No hosted operation, financial mutation, deployment or secret use occurred.
See [R06 implementation record](P6_R06_IMPLEMENTATION.md). Phase 6 remains NOT
APPROVED.

## R05 Rider canonical reader implementation update - 2026-10-25

Based on main `3c83c78`; implementation is on
`feature/p6-r05-rider-payment-reader`. R05 is **PARTIAL**. Cash/Card reader
providers now use the application-owned client and existing exact canonical RPC
repository when the authenticated application Rider matches the SDK session.
The repository rejects non-Rider exact reads; null Trip linkage is accepted and
shown as "Trip not yet linked" without implying success. Focused local coverage
includes app/SDK mismatch, A-B-A session replacement, foreign Rider response,
RPC-only access and nullable Trip presentation. No hosted operation is claimed.

The Rider identity is sourced from SessionController/profile. There is no trusted
Payment ID on the current booking/history/Trip UI path, and migration 027 accepts
only an exact Payment ID. Booking and Trip IDs are not substitutes. Keep the
demo-backed history unavailable until a backend-issued, Rider-scoped Payment ID
and canonical Trip association are exposed. Phase 7 assigned Trip identity and
Phase 8 payment/history restoration remain dependencies. R04 hosted acceptance
remains PARTIAL/BLOCKED; Phase 6 is NOT APPROVED.

## R04 Admin security hardening update - 2026-10-25

Based on main `a637f5e` (after PR #57). [Detailed evidence](P6_R04_HOSTED_RPC_VERIFICATION.md).

- F01 locally remediated: production Admin reader rechecks the exact live SDK
  session and current nonblocked Admin profile before and after the RPC. This
  catches revocation observed during the read, but cannot promise detection of a
  change immediately after the final profile check.
- F02 locally remediated: Admin and canonical readers accept a present, null
  `trip_id`; missing/invalid linkage and malformed financial fields still fail
  closed. Display rows do not expose Trip IDs.
- Three focused Flutter test files: **51 PASS / 0 FAIL**; Analyze **No issues**.
  No full suite or hosted role test was run.
- **R04 PARTIAL; hosted acceptance BLOCKED** pending environment classification,
  authorization and dedicated fixture availability. F01/F02 local fixes do not
  complete role/session runtime acceptance. R04 evidence and Phase 6 remain open.

## R04 read-only verification handoff - 2026-10-25 (historical baseline)

Base: main `34801bcb5b89607e79a2736e83b87d82d4447bb5`.
[Evidence, actor matrix and findings](P6_R04_HOSTED_RPC_VERIFICATION.md).

- **R04 PARTIAL; authenticated hosted acceptance BLOCKED.** The connected project
  matches the intended endpoint. Migration 027 history/function bodies, grants,
  financial RLS/no SELECT policies and estimated plans are verified as hosted
  configuration. No dedicated identity/record fixture or testing-environment
  classification was available; no hosted actor/financial-row reads were made.
- **117 focused Flutter PASS / 0 FAIL**, **103 isolated local SQL assertions
  PASS / 0 FAIL**, Analyze **No issues found**. Local fixtures are not hosted
  identity acceptance. Characterization tests document F01/F02 limitations.
- At that baseline, **open findings** included Medium F01, unobserved remote
  Admin demotion/blocking could publish an already-authorized delayed response;
  and Medium F02, nullable Trip linkage could reject the strict Admin list. F01/F02
  have since been locally remediated above. Low F03,
  listing scan/sort scale observation without representative latency. Low F04,
  raw adapter errors rely on the provider's sanitization boundary.
- Next: provide dedicated hosted identity/data authorization and finish R04
  runtime acceptance. F03/F04 and hosted readiness remain open. No hosted
  mutation/deployment or Phase 6 approval.

## Historical R01/R02 implementation handoff - 2026-10-25

PR #54 merged the R01/R02 branch at main `f9e6807` (original base `fc3224c`).
[Implementation/evidence record](P6_R01_R02_IMPLEMENTATION.md).

- **R01 PARTIAL:** canonical availability/Trip source and pinned application SDK /
  B1-B eligibility checks implemented and locally tested. Production registry remains
  empty pending explicit endpoint-to-stable-namespace approval.
- **R02 PARTIAL:** durable application-support journal gateway, existing coordinator /
  Cash composition, Riverpod binding and bounded canonical-screen panel implemented
  and locally tested. The mock Driver screen remains unchanged; canonical mounting
  and runtime activation are not completed. No automatic replay or journal cleanup.
- New verification: **319 focused PASS / 0 FAIL / 0 SKIP**, including **33 new tests**;
  Flutter Analyze **No issues found**; 10 changed/new Dart files format clean. These
  are local SDK/HTTP-fixture/widget/file tests, separate from historical #52 results.
  No full-suite rerun, physical device, hosted financial verification or deployment.
- Required decision: approve a stable unique journal namespace for the configured
  `https://ykasivejjchupswqyxpm.supabase.co` endpoint (or explicitly choose another
  target). No namespace was invented; default activation is disabled.
- R03 original composition merged externally via #55 at `34801bc`; its independent
  aggregate-state correction awaits follow-up review. Registry
  approval/canonical mounting precede activation, and R07 hosted Cash/receipt evidence
  remains separately authorized. Phase 6 remains NOT APPROVED.

## R03 read-only recovery implementation handoff - 2026-10-25

PR #54 is merged at `f9e6807`. The original #55 was externally merged at
`34801bc` during review correction, before these fixes were pushed. The existing
`feature/p6-r03-cash-recovery-integration` branch is reconciled with both main
commits; its correction requires independent review on
[follow-up #56](https://github.com/Omar59687/RideX/pull/56). See
[R03 implementation record](P6_R03_IMPLEMENTATION.md).

- **R03 PARTIAL:** recovery discovers immutable per-Driver journal entries on
  provider creation, app resume and explicit request. Each exact original
  Trip/version/key is reconciled through the same B1-B binding, verified SDK
  client and approved namespace. Only canonical completed Cash Trips permit the
  existing Driver-safe receipt RPC read. Recovery has no dispatch, retry, repair,
  journal delete or retirement path.
- **UI:** the optional canonical Cash panel shows bounded reconciliation states.
  The legacy mock Driver screen remains unchanged and the canonical panel is not
  mounted in the live app. PR #62 records the approved endpoint/namespace pair,
  while the compile-time activation flag remains default-off.
- Local focused verification: **215 PASS / 0 FAIL** across recovery, canonical
  reconciliation, Driver Cash production-composition and architecture tests (210
  in the original three-file selection plus 5 architecture cases). No hosted/runtime/
  device acceptance. Analyze: no issues. Final full suite: **1,555 PASS / 0 FAIL /
  2 live skips**. All 14 R03/architecture Dart files pass read-only formatting.
  The initial full sweep exposed a missing exact SDK-infrastructure allowlist
  entry; after correction the final sweep passed. See the R03 record.
- Journal retention/operator resolution policy remains unapproved. Existing
  records are retained by this work; no automatic cleanup or replay. Phase 6
  remains NOT APPROVED.

The current handoff supersedes the Driver-completion provider/source absence in the
older table below; its hosted acceptance and recovery gaps remain open.

## Current reconciliation - 2026-10-25, after PR #52

This section supersedes older current-status statements below. Historical handoffs,
test counts and restrictions remain dated evidence. This tracker remains the sole
Phase 6 task-status authority; the [execution roadmap](P6_POST_MERGE_ROADMAP.md)
details the remaining work without granting approval.

- Fetched `origin/main`: `59be9b7712894c695e9c8efa580a1ffc2013bec7` (`59be9b7`).
  [PR #52](https://github.com/Omar59687/RideX/pull/52) merged 2026-10-25.
- [PR #47](https://github.com/Omar59687/RideX/pull/47) and
  [PR #51](https://github.com/Omar59687/RideX/pull/51) were compared with that tree
  and closed without merge as superseded. No unique necessary implementation was
  found. The legacy Admin adapter/direct payment SELECT path was deliberately
  replaced; current-main Admin UI, session ownership and historical tracker were retained.
- Migration `027_phase6_admin_payment_read_rpc.sql` was already in main through
  PR #50 (`b1f74c4`); #52 integrates its Flutter readers, rather than introducing
  or deploying a migration. Conflicting PR #48 is already CLOSED without merge.
- **Historical owner-provided #52 verification:** focused Flutter **45 PASS / 0 FAIL**;
  full Flutter **1,489 PASS / 0 FAIL / 2 SKIP**; Flutter Analyze **No issues found**
  on the preceding implementation commit. These were not rerun in this documentation
  audit. The owner report does not identify an exact SHA for each run; do not assign
  these results to the merge SHA or claim a fresh combined-tree run here.
- No hosted Supabase, live payment execution, Stripe credentials, real-device
  acceptance, deployment or financial transaction was verified in this audit.
  Older local database/TypeScript and reported hosted-catalog evidence retain their
  original scopes; catalog existence does not establish authenticated role acceptance.

| Workstream | Implemented | Integrated | Verified | Remaining |
|---|---|---|---|---|
| Admin Payment Visibility (P6-08) | Sanitized UI, strict RPC parser, exact SDK Session identity pinning | Production provider uses `SupabaseAdminPaymentReader` and `admin_recent_canonical_payments`; guarded Admin screen | Local loopback/widget coverage exists; historical owner #52 results above; hosted/runtime acceptance unverified | Hosted role/blocked-account matrix, logout and A-to-B-to-A acceptance, UI redaction and performance review (R04) |
| Canonical Payment Reader (P6-01/03 read integration) | Cash/Card parser and authorized exact/list RPC adapter; persisted identity/version | Admin uses dedicated RPC reader; Rider providers use the shared app client and Rider-scoped exact reader; history remains unactivated without trusted Payment ID | Focused local provider/session/RPC/nullable-link tests; no hosted Rider reader verification | Backend-issued Rider Payment ID and canonical Trip association; hosted role acceptance (R04); Phase 7 Trip identity and Phase 8 payment/history source |
| Driver Cash Completion (P6-02/P6-07) | Journal, coordinator, trusted completion adapter, B1-B composition; approved endpoint/namespace mapping (#62) behind default-off compile-time flag | Provider remains inactive; no canonical Driver-screen mounting; Trips remain mock-backed | Local journal/coordinator/SDK loopback coverage; no hosted atomic completion/receipt acceptance | Mount canonical screen, prepare owned vehicle and authorized matching path; keep flag off until separately authorized hosted acceptance (R07) |
| Cash Recovery (P6-02/P6-07) | Read-only discovery, canonical Cash Trip and Driver-safe receipt reads; #55/#56 merged | Per-Trip evidence is separate from outcomes; unresolved/failed/unprocessed commands block aggregate success; bounded journal rotation | 215 focused local PASS / 0 FAIL across four files; no hosted/runtime/device acceptance | Canonical screen mounting, retention/operator policy and R07 hosted/session/restart evidence; never replay, dispatch or retire from recovery |
| R07 Hosted Cash/Receipt Acceptance | Test-only operator fixture tool and authenticated canonical vehicle/Trip contract procedure prepared; test project and three account profiles previously verified read-only | No hosted fixture created; Deno tool defaults read-only; execution is separately approval-gated; app activation flag remains off | New local Deno guard tests only; historical metadata/catalog/profile inspection; no authenticated role or financial acceptance | Separately authorize/create synthetic Driver vehicle and canonical Cash booking; run tool for an in-progress Trip; activate only the approved R01/R02 application path for a later authorized completion; run recovery/read/role matrix and retain evidence; obtain extra negative-test identities where needed |
| Stripe Test Mode (P6-04) | Server-only unconfirmed adapter, fake, authenticated handler, filtered canonical reader, exact JOD minor-unit conversion | Handler validates Rider, accepted Card Trip, exact Payment/pending authorization attempt, versions/key; production provider dispatch disabled | 55 focused local Deno tests PASS; type check/format clean; no hosted read or provider call | Owner Test Mode/JOD approval, isolated canonical attempt fixture, durable attempt claim/unknown-outcome reconciliation, then sandbox evidence (R06); secure UI scope (R08); no release approval |
| Phase 6 Acceptance (P6-09) | Compatibility harness and fixture mappings | Foundations merged through #52 | Historical owner local results; no final hosted/runtime/device acceptance | Resolve R01-R08, independent integration review, evidence ledger and explicit owner exit decision (R09); Phase 6 NOT APPROVED and NOT release-ready |

P6-01/P6-03/P6-05/P6-06 remain complete only for their previously approved
contract/presentation scope. This does not complete their deferred production
readers or financial workflows. Merged, locally tested, hosted verified and
approved for release are separate states. Phase 7 planning may use the contracts;
execution across the payment/matching boundary needs the explicit dependency
and gate disposition in R09. Phase 4/5 carry-over gates remain unchanged.

## B1-B session ownership handoff — 2026-10-24

Status: MERGED to `main` by PR #45 at
`fc1d28b27a6d6432031eb05e562e5bec61c133e4` on 2026-10-24. This is a B1-B
foundation handoff, not Phase 6 exit approval. PR-local verification is reported;
no post-merge GitHub CI status was recorded.
Base: `22d98c5a418effeba062ebea629fe20b6c9b70eb` (includes merged #39 and #40).

- One application auth-client owner supplies monotonic epochs. Logout and
  explicit account entry revoke before tracking cleanup or SDK authentication
  awaits. Repeated logout coalesces SDK cleanup; disposal remains closed.
- The B1-B binding seam accepts only the same B0-verified SDK client/backend.
  Existing strict eligibility checks and before/after-await ownership checks
  remain intact. Late profile/auth successes and failures cannot restore an old
  owner. Rejected SDK login sessions are signed out before another login can
  be accepted, including removal from default SDK session persistence.
- Startup recovery has a one-shot window bound to its original account.
  Expiry suspends an existing owner and advances its epoch; valid same-owner
  refresh resumes under a fresh epoch. Logout, identity loss, stream errors,
  and disposal cancel both restoration and refresh admission.
- SessionController rejects superseded/disposed async publication, keeps
  explicit startup refresh ordering, and retains Rider/Demo entry and durable
  Rider recovery evidence. Unknown authentication errors use fixed UI copy.
- Independent read-only security review found three issues during development
  (expired startup admission, stale SDK login persistence, and expiry refresh
  suspension). All were corrected and re-reviewed with no remaining concrete
  B1-B blocker before PR #45 was merged.
- Regression fixtures now use explicit post-logout authentication, await an
  entered persistence boundary for the logout race, and pin the completion-store
  fixture clock to its creation date. Explicit seven-day expiry checks remain;
  production completion/storage behavior was not changed.
- Focused verification across 12 security/session/Rider/recovery test files:
  **340 PASS / 0 FAIL / 0 SKIP**. Flutter analysis: no issues. Read-only format:
  **277 files / 0 changed**. `git diff --check`: clean.
- Full `flutter test --no-pub` verification: **1,396 PASS / 0 FAIL / 2 SKIP**.
  The two existing live Supabase tests skip without intentional configuration;
  no hosted authentication or financial mutation was performed. Verification
  used the installed Flutter 3.35.3 / Dart 3.9.2 toolchain.

B1-C prerequisites: reviewed/merged B1-B; an explicitly approved deployment
endpoint-to-namespace registry (no default mapping exists); separately authorized
B1-C provider/consumer wiring with identity/client/backend/epoch checks at every
async publication and dispatch boundary. Retain the existing no-execution gates
until that slice's own acceptance/review. This change does not activate Driver
completion RPCs, recovery replay, journal retirement, settlement, Stripe, Admin
UI, migrations/RLS, or production financial operations.

This file is the ONLY Phase 6 task-status authority. Other docs reference it; do not duplicate
status elsewhere. Historical planning rows initially used `TODO`; update only from evidence.

Status reconciliation 2026-10-19: merged GitHub PRs verified for P6-01/03/05/06 and partial P6-07; hosted V5-01 PASS and V5-02 PARTIAL. A subsequent clean-workspace integration audit at `2eccf03` (owner-supplied T3 report) found P6-08 standalone redaction/card foundation PARTIAL rather than TODO; P6-02/P6-07/P6-09 remain partial and P6-04 remains design-only. Audit reported Flutter analyze PASS, 732 focused tests in 24 files PASS, and full Flutter suite 1,293 PASS / 2 live tests skipped. P6-05/06 may be closed for their approved presentation scope after integration-owner sign-off; their deferred production readers/payments/history are NOT closed. Phase 6 NOT READY for final approval. The dated Phase 5 owner acceptance is recorded separately; uncompleted Phase 4/5 full-exit gates remain open.

Owner rotation: Sprint 1 Dev 1 → Sprint 2 Dev 2 → Sprint 3 Dev 3 → Sprint 4 Dev 1…

## Sprint 1 (48h) — Integration Owner: Dev 1

| Task | Dev | Branch (suggested) | Depends | Status | PR | Gate / outcome |
|---|---|---|---|---|---|---|
| P6-01 cash domain contract | Dev 1 | `feature/p6-cash-contract` | none | DONE (merged) | [#14](https://github.com/Omar59687/RideX/pull/14) | Read-only Cash contract + fake and 16 focused tests merged 2026-10-13; no Cash settlement execution claim. Historical handoff text below records pre-merge state. |
| P6-05 rider selection + handoff (mock) | Dev 2 | `feature/p6-rider-payment-ui` | P6-01 draft | DONE (merged) | [#18](https://github.com/Omar59687/RideX/pull/18), [#25](https://github.com/Omar59687/RideX/pull/25) | Cash/Card method selection and canonical booking/fare handoff merged 2026-10-17; no Stripe charge claim. |
| P6-08 admin sanitized visibility | Dev 3 | `feature/p6-admin-reader-recovery` | P6-01/03; approved Admin read contract required | IMPLEMENTED / INTEGRATED; runtime acceptance OPEN | [#50](https://github.com/Omar59687/RideX/pull/50), [#52](https://github.com/Omar59687/RideX/pull/52) | Migration 027 supplies authorized canonical reads; production Admin RPC reader/session protection and guarded sanitized UI merged. Hosted role/runtime acceptance remains open; see current reconciliation above. |
| V4-02 blank-map diagnosis | Dev 3 | n/a (evidence) | device/logs | OPEN | — | 2026-10-19 hosted Android test used GOOGLE_MAPS_ENABLED=false with fallback routing; native Google map tiles/route geometry still unverified. |
| V5-01 hosted RLS checks | Dev 2 | n/a (evidence) | hosted access | PASS (scoped) | [Phase 5 owner record](../../ai/verification/PHASE_5_OWNER_ACCEPTANCE_2026-10-19.md) | Two distinct hosted Riders: own vs foreign booking/stop/quote RLS positive/negative checks and canonical lock/confirmation passed; hosted draft-update/quote-invalidation still open in Phase 5 exit. |

### Historical P6-08 recovery audit - 2026-10-24 (superseded above)

- Selectively recovered the guarded Admin UI boundary from closed PR #41; the
  production reader provider intentionally remains unavailable until an approved
  server-side Admin list/read contract exists.
- Did not recover PR #43's direct `payments` table SELECT adapter: migration 019
  drops its authenticated SELECT policy. Existing per-payment summary RPCs do not
  provide an Admin list or the required booking identity and payment version.
- Deterministic test readers are test-only. Loopback/fake verification is not
  hosted RLS or production data acceptance. P6-08 remains PARTIAL and Phase 6
  remains NOT READY for approval.

Conflict check Sprint 1: production writers disjoint (new contract files / booking UI /
new admin widgets). `repositories_providers.dart`/`app_router.dart`: no production edits.

### P6-01 handoff record (prepared; receipt not yet confirmed)

- Dev 2 / P6-05: Cash method selection uses existing
  `FareRepository.createBookingDraft` / `updateBookingDraft` with
  `paymentMethod: 'cash'`; updating takes the booking's expected version.
  No persisted `paymentId` exists before trusted Trip-linked payment creation.
  Build mock-backed booking UI without production provider/router changes.
- Dev 3 / P6-08: `PaymentRepository` exposes only
  `readCashPayment({required String paymentId})`. Use canonical Cash
  `FakePaymentRepository` fixtures for read-only presentation; fixture seeding
  is test/demo-only, never payment authority. Do not invent missing backend
  fields or introduce provider/router/RLS changes. Verify the admin surface
  before implementation.
- Security boundary: trusted backend Trip completion settles Cash; trusted
  Trip cancellation reconciles payment cancellation. Flutter cannot create,
  settle, or cancel a persisted Cash Payment via this contract.
- Future production read gap: `user_payment_summary` omits
  `bookingRequestId` and Payment `version`, so it cannot alone populate the
  complete `CashPayment` model. Resolve at authorized integration; no fields
  may be fabricated. This does not block mock-backed P6-05/P6-08 work.
- Evidence: independent reviews approved P6-01-S1/S2/S3; focused
  `test/payment_cash_contract_test.dart` 16/16 passed and scoped Flutter
  analysis clean. The earlier fake mutation-version/idempotency test wording
  was reconciled in `DEVELOPER_1.md` to the approved read-only contract.
- Closure pending: record actual Dev 2/3 receipt; reconcile this work from
  the current planning branch onto the task branch per `TEAM_RULES.md`;
  obtain independent PR/integration review, run the full non-live suite at
  the sprint boundary, and verify merge and stable `main`. Integration Owner
  updates this row only after those gates.

## Sprint 2 (48h) — Integration Owner: Dev 2

| Task | Dev | Branch (suggested) | Depends | Status | PR | Gate / outcome |
|---|---|---|---|---|---|---|
| P6-03 card domain contract | Dev 1 | `feature/p6-card-contract` | P6-01 | DONE (merged) | [#15](https://github.com/Omar59687/RideX/pull/15) | Read-only Card contract + fake and 20 focused tests merged 2026-10-13; executable payment adapter still deferred. Historical handoff below reflects pre-merge state. |
| P6-06 rider states + receipts | Dev 2 | `feature/p6-rider-payment-states` | P6-01, P6-03, P6-05 | DONE (merged) | [#24](https://github.com/Omar59687/RideX/pull/24) | Payment state/receipt/history presentation (mock-backed read surface) merged 2026-10-17; persistent History remains Phase 8. |
| P6-07 driver cash-completion hook | Dev 3 | `feature/p6-driver-cash-completion` | P6-01 (+P6-02 draft) | PARTIAL (integrated foundation) | [#23](https://github.com/Omar59687/RideX/pull/23), [#33](https://github.com/Omar59687/RideX/pull/33) | Driver journal/coordinator and read-only completion recovery merged; no authenticated full trusted Cash settlement/device completion claim. |
| V4-01 two-device (4.38) | Dev 3 | n/a (evidence) | devices | OPEN | — | Two physical/equivalent Rider/Driver GPS-device evidence not established in this tracked verification; 4.38 and Phase 4 owner gate remain unchecked. |
| V5-02 confirm + B1/B2 | Dev 2 | n/a (evidence) | hosted+device | PARTIAL | [Phase 5 owner record](../../ai/verification/PHASE_5_OWNER_ACCEPTANCE_2026-10-19.md) | Hosted A/B confirmations + one Android UI confirmation PASS; exact sequential B1→B2 both from Android with original preserved still not shown. |

Conflict check Sprint 2: writers disjoint (new card files / history-trips UI /
driver UI). No shared production-file overlap. Full non-live suite at boundary.

### P6-03 handoff record (prepared; receipt not yet confirmed)

- Dev 2 / P6-06: `CardPaymentRepository` exposes only
  `readCardPayment({required String paymentId})`. Use canonical Card
  `FakeCardPaymentRepository` fixtures for read-only state and receipt
  presentation (status text, fils amounts, brand/last4 only); fixture seeding
  is test/demo-only, never payment authority. No persisted `paymentId` exists
  before trusted Trip-linked payment creation. Build mock-backed UI without
  production provider/router changes.
- Security boundary: trusted backend operations authorize (post-match),
  capture (post-completion), void, refund, and verify webhooks. Flutter cannot
  authorize, capture, void, settle, or refund a persisted Card Payment via this
  contract. No Stripe SDK, secret, PAN/CVV, or provider type enters UI-facing
  models; the executable provider adapter is deferred to P6-04/P8 behind a
  trusted server-side boundary.
- Future production read gap: `user_payment_summary` omits
  `bookingRequestId` and Payment `version`, so it cannot alone populate the
  complete `CardPayment` model. Resolve at authorized integration; no fields
  may be fabricated. This does not block mock-backed P6-06 work.
- Evidence: independent reviews approved P6-03-S1/S2/S3; focused
  `test/payment_card_contract_test.dart` 20/20 passed and scoped Flutter
  analysis clean. The original "adapter interface" wording was reconciled in
  `DEVELOPER_1.md` to the approved read contract plus documented P6-04/P8
  deferral.
- Closure pending: record actual Dev 2 receipt; obtain independent
  PR/integration review, run the full non-live suite at the sprint boundary,
  and verify merge and stable `main`. Integration Owner updates this row only
  after those gates.

## Later (high-level; reconcile from latest main after merged S1–S2 work)

- Sprint 3 (Owner Dev 3): P6-02 Cash backend/completion integration has multiple merged foundation PRs (#19–#23, #26, #31) but still needs end-to-end trusted settlement verification; P6-04 began design-only in #17; #52 now adds the unconfirmed server-only preparation interface/transport, without runtime activation; V5-03 multi-stop physical remains OPEN and V5-04 recovery/negative-case testing is PARTIAL (automated and Android cold-start PASS, full live fault-injection not shown).
- Sprint 4 (Owner Dev 1): P6-09 foundation harness merged via #27; finish integration acceptance and P6→P8 readiness review. P6-08 guarded UI and production RPC integration are now merged in #52; hosted/runtime acceptance remains open.
- Phase 6 exit: contracts + mock-backed UI + harness green; hosted/device tails
  still tracked above; no P4/P5 APPROVED claim.
