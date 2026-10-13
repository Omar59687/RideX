# Phase 6 — Sprint Tracker (authoritative status)

This file is the ONLY status authority. Other docs reference it; do not duplicate
status elsewhere. Initial status for all rows: `TODO`. Never mark future work complete.

Owner rotation: Sprint 1 Dev 1 → Sprint 2 Dev 2 → Sprint 3 Dev 3 → Sprint 4 Dev 1…

## Sprint 1 (48h) — Integration Owner: Dev 1

| Task | Dev | Branch (suggested) | Depends | Status | PR | Gate / outcome |
|---|---|---|---|---|---|---|
| P6-01 cash domain contract | Dev 1 | `feature/p6-cash-contract` | none | TODO | — | S1/S2/S3 independently approved; 16/16 focused tests, scoped analyze clean. Contract handoff prepared below; Dev 2/3 receipt, integration review, sprint-boundary suite and merge confirmation pending. |
| P6-05 rider selection + handoff (mock) | Dev 2 | `feature/p6-rider-payment-ui` | P6-01 draft | TODO | — | widget + fake tests; no router change; no success claim |
| P6-08 admin sanitized visibility | Dev 3 | `feature/p6-admin-payment-visibility` | P6-01 draft (cash scope) | TODO | — | redaction + guard tests; TO VERIFY admin surface first |
| V4-02 blank-map diagnosis | Dev 3 | n/a (evidence) | device/logs | TODO | — | redacted evidence note |
| V5-01 hosted RLS checks | Dev 2 | n/a (evidence) | hosted access | TODO | — | redacted evidence note |

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
| P6-03 card domain contract | Dev 1 | `feature/p6-card-contract` | P6-01 | TODO | — | S1/S2/S3 independently approved; 20/20 focused tests, scoped analyze clean. Contract handoff prepared below; adapter-boundary deferral reviewed and accepted (executable adapter → P6-04/P8). Dev 2 receipt, integration review, sprint-boundary suite and merge confirmation pending. |
| P6-06 rider states + receipts | Dev 2 | `feature/p6-rider-payment-states` | P6-01, P6-03, P6-05 | TODO | — | state/receipt widget tests; no history rewrite |
| P6-07 driver cash-completion hook | Dev 3 | `feature/p6-driver-cash-completion` | P6-01 (+P6-02 draft) | TODO | — | hook tests; execution claim waits on V-evidence |
| V4-01 two-device (4.38) | Dev 3 | n/a (evidence) | devices | TODO | — | dated evidence or remains open |
| V5-02 confirm + B1/B2 | Dev 2 | n/a (evidence) | hosted+device | TODO | — | dated evidence or remains open |

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

## Later (high-level; re-plan from latest main when Phase 6 S1–S2 merge)

- Sprint 3 (Owner Dev 3): P6-02 cash backend wiring, P6-04 Stripe intent interface,
  V5-03/V5-04 evidence.
- Sprint 4 (Owner Dev 1): P6-09 compatibility harness, P6→P8 readiness review.
- Phase 6 exit: contracts + mock-backed UI + harness green; hosted/device tails
  still tracked above; no P4/P5 APPROVED claim.
