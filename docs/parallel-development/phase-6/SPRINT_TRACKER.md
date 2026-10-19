# Phase 6 — Sprint Tracker (authoritative status)

This file is the ONLY Phase 6 task-status authority. Other docs reference it; do not duplicate
status elsewhere. Historical planning rows initially used `TODO`; update only from evidence.

Status reconciliation 2026-10-19: merged GitHub PRs verified for P6-01/03/05/06 and partial P6-07; hosted V5-01 PASS and V5-02 PARTIAL. The dated Phase 5 owner acceptance is recorded separately; the uncompleted Phase 4/5 full-exit gates remain open.

Owner rotation: Sprint 1 Dev 1 → Sprint 2 Dev 2 → Sprint 3 Dev 3 → Sprint 4 Dev 1…

## Sprint 1 (48h) — Integration Owner: Dev 1

| Task | Dev | Branch (suggested) | Depends | Status | PR | Gate / outcome |
|---|---|---|---|---|---|---|
| P6-01 cash domain contract | Dev 1 | `feature/p6-cash-contract` | none | DONE (merged) | [#14](https://github.com/Omar59687/RideX/pull/14) | Read-only Cash contract + fake and 16 focused tests merged 2026-10-13; no Cash settlement execution claim. Historical handoff text below records pre-merge state. |
| P6-05 rider selection + handoff (mock) | Dev 2 | `feature/p6-rider-payment-ui` | P6-01 draft | DONE (merged) | [#18](https://github.com/Omar59687/RideX/pull/18), [#25](https://github.com/Omar59687/RideX/pull/25) | Cash/Card method selection and canonical booking/fare handoff merged 2026-10-17; no Stripe charge claim. |
| P6-08 admin sanitized visibility | Dev 3 | `feature/p6-admin-payment-visibility` | P6-01 draft (cash scope) | TODO | — | redaction + guard tests; TO VERIFY admin surface first |
| V4-02 blank-map diagnosis | Dev 3 | n/a (evidence) | device/logs | OPEN | — | 2026-10-19 hosted Android test used GOOGLE_MAPS_ENABLED=false with fallback routing; native Google map tiles/route geometry still unverified. |
| V5-01 hosted RLS checks | Dev 2 | n/a (evidence) | hosted access | PASS (scoped) | [Phase 5 owner record](../../ai/verification/PHASE_5_OWNER_ACCEPTANCE_2026-10-19.md) | Two distinct hosted Riders: own vs foreign booking/stop/quote RLS positive/negative checks and canonical lock/confirmation passed; hosted draft-update/quote-invalidation still open in Phase 5 exit. |

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
- Sprint 4 (Owner Dev 1): P6-09 foundation harness merged via #27; finish integration acceptance and P6→P8 readiness review. P6-08 Admin sanitized visibility remains TODO (no confirming merged PR).
- Phase 6 exit: contracts + mock-backed UI + harness green; hosted/device tails
  still tracked above; no P4/P5 APPROVED claim.
