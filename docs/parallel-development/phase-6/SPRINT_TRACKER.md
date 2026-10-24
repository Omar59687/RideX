# Phase 6 — Sprint Tracker (authoritative status)

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
| P6-08 admin sanitized visibility | Dev 3 | `feature/p6-admin-reader-recovery` | P6-01/03; approved Admin read contract required | PARTIAL (guarded UI on recovery branch; canonical reader blocked) | Recovery PR pending | Existing mapper/card remain on main. This branch adds Admin-only UI states and fake-backed tests, but production data stays unavailable: migration 019 drops authenticated SELECT policies on `payments`, and merged RPCs provide neither Admin listing nor the identity/version projection. No migration/RLS change is authorized in this task; no hosted acceptance is claimed. |
| V4-02 blank-map diagnosis | Dev 3 | n/a (evidence) | device/logs | OPEN | — | 2026-10-19 hosted Android test used GOOGLE_MAPS_ENABLED=false with fallback routing; native Google map tiles/route geometry still unverified. |
| V5-01 hosted RLS checks | Dev 2 | n/a (evidence) | hosted access | PASS (scoped) | [Phase 5 owner record](../../ai/verification/PHASE_5_OWNER_ACCEPTANCE_2026-10-19.md) | Two distinct hosted Riders: own vs foreign booking/stop/quote RLS positive/negative checks and canonical lock/confirmation passed; hosted draft-update/quote-invalidation still open in Phase 5 exit. |

### P6-08 recovery audit — 2026-10-24

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

- Sprint 3 (Owner Dev 3): P6-02 Cash backend/completion integration has multiple merged foundation PRs (#19–#23, #26, #31) but still needs end-to-end trusted settlement verification; P6-04 is design-only in merged #17 (no executable Stripe adapter); V5-03 multi-stop physical remains OPEN and V5-04 recovery/negative-case testing is PARTIAL (automated and Android cold-start PASS, full live fault-injection not shown).
- Sprint 4 (Owner Dev 1): P6-09 foundation harness merged via #27; finish integration acceptance and P6→P8 readiness review. P6-08 Admin sanitized visibility has a tested standalone mapper/card/redaction foundation but guarded Admin-screen integration remains PARTIAL (no confirming end-to-end integration PR).
- Phase 6 exit: contracts + mock-backed UI + harness green; hosted/device tails
  still tracked above; no P4/P5 APPROVED claim.
