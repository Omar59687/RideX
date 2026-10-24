# Phase 6 — Sprint Tracker (authoritative status)

This file is the ONLY Phase 6 task-status authority. Other docs reference it; do not duplicate
status elsewhere. Historical planning rows initially used `TODO`; update only from evidence.

Status reconciliation 2026-10-19: merged GitHub PRs verified for P6-01/03/05/06 and partial P6-07; hosted V5-01 PASS and V5-02 PARTIAL. A subsequent clean-workspace integration audit at `2eccf03` (owner-supplied T3 report) found P6-08 standalone redaction/card foundation PARTIAL rather than TODO; P6-02/P6-07/P6-09 remain partial and P6-04 remains design-only. Audit reported Flutter analyze PASS, 732 focused tests in 24 files PASS, and full Flutter suite 1,293 PASS / 2 live tests skipped. P6-05/06 may be closed for their approved presentation scope after integration-owner sign-off; their deferred production readers/payments/history are NOT closed. Phase 6 NOT READY for final approval. The dated Phase 5 owner acceptance is recorded separately; uncompleted Phase 4/5 full-exit gates remain open.

Implementation checkpoint 2026-10-24 (task branches, not merged main): guarded Admin UI and complete RLS payment reader implemented (#41/#43); server-only unconfirmed Stripe Test Mode interface implemented (#42); verified Cash completion/recovery composition implemented (#44). Combined acceptance: analyze clean, 807 focused PASS, final full suite 1,405 PASS / 0 FAIL / 2 live skipped, Stripe 32 PASS plus strict TypeScript check. B1-B lifecycle/UI activation, hosted Cash/receipt acceptance, provider configuration and independent review remain open. Full Phase 6 NOT COMPLETE / NOT READY. See P6_FOUNDATION_INTEGRATION_ACCEPTANCE.md for exact scope and evidence.

Owner rotation: Sprint 1 Dev 1 → Sprint 2 Dev 2 → Sprint 3 Dev 3 → Sprint 4 Dev 1…

## Sprint 1 (48h) — Integration Owner: Dev 1

| Task | Dev | Branch (suggested) | Depends | Status | PR | Gate / outcome |
|---|---|---|---|---|---|---|
| P6-01 cash domain contract | Dev 1 | `feature/p6-cash-contract` | none | DONE (merged) | [#14](https://github.com/Omar59687/RideX/pull/14) | Read-only Cash contract + fake and 16 focused tests merged 2026-10-13; no Cash settlement execution claim. Historical handoff text below records pre-merge state. |
| P6-05 rider selection + handoff (mock) | Dev 2 | `feature/p6-rider-payment-ui` | P6-01 draft | DONE (merged) | [#18](https://github.com/Omar59687/RideX/pull/18), [#25](https://github.com/Omar59687/RideX/pull/25) | Cash/Card method selection and canonical booking/fare handoff merged 2026-10-17; no Stripe charge claim. |
| P6-08 admin sanitized visibility | Dev 3 | `feature/p6-admin-payment-visibility` | P6-01 draft (cash scope) | IMPLEMENTED (review pending) | [#41](https://github.com/Omar59687/RideX/pull/41), [#43](https://github.com/Omar59687/RideX/pull/43) | Guarded Admin surface and existing sanitizer connected to bounded canonical RLS reads. Loading/empty/error/unavailable/role/account/disposal coverage passes. No fake production payments, migrations or financial writes. Independent review/merge pending. |
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
| P6-07 driver cash-completion hook | Dev 3 | `feature/p6-driver-cash-completion` | P6-01 (+P6-02 draft) | PARTIAL (composition tested) | [#23](https://github.com/Omar59687/RideX/pull/23), [#33](https://github.com/Omar59687/RideX/pull/33), [#44](https://github.com/Omar59687/RideX/pull/44) | Existing journal/coordinator and B1-A SDK authority composed with trusted Cash RPC and read-only recovery; 202 combined tests PASS. B1-B lifecycle/active-Trip/UI activation and separately authorized hosted settlement/receipt acceptance remain open. |
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

## Integration closeout — 2026-10-24 (independent review pending)

| Task | Owner | Verified state | Evidence / remaining gate |
|---|---|---|---|
| P6-02 Cash settlement wiring | Dev 1 | PARTIAL — composed boundary | #44 plus existing foundations: canonical Driver/Trip preflight, stable key/version, trusted RPC, Trip/receipt rereads and read-only recovery tested. No runtime UI activation or live settlement claim; B1-B and hosted acceptance remain required. |
| P6-04 Stripe Test Mode interface | Dev 1 | IMPLEMENTED interface / external verification blocked | #42: 32 transport tests and strict TypeScript PASS; unconfirmed preparation only. No configured Test Mode secret/account approval or deployed actor/attempt owner; no real provider request. P8 execution remains separate. |
| P6-09 compatibility acceptance | Dev 1 / Integration Owner | LOCAL ACCEPTANCE PASS / approval open | Integration branch: 807 focused PASS; corrected final full suite 1,405 PASS / 2 live skipped; analyze clean; 32 Stripe tests PASS. Independent review/merge and bounded external gates remain open; see P6_FOUNDATION_INTEGRATION_ACCEPTANCE.md. |

The canonical reader gap is resolved in code (#43) without changing the reduced
summary RPC or deployed migrations. Existing complete, RLS-protected payment
columns supply booking identity and Payment version; no missing field is fabricated.
This read contract is not proof of issued receipts, completed-Trip linkage or
permission to enable Rider financial success/history, which remain deferred.

P6-01/P6-03/P6-05/P6-06 remain DONE within their approved scope. P6-08 has code
and test completion but is not labeled merged. P6-02/P6-07 runtime activation and
financial acceptance are not labeled DONE. No Phase 6 approval is asserted.
V4-01/V4-02 and V5-02/V5-03/V5-04 evidence tails remain separate; no Phase 5 Android
or hosted tests were repeated during this implementation.
V5-03 multi-stop physical verification remains OPEN; V5-04 recovery/negative-case
testing remains PARTIAL (full live fault injection not established).

Concurrent B1-B ownership work is now open in [#45](https://github.com/Omar59687/RideX/pull/45) at `6e8b316`. It is outside this tested integration tree and remains review/merge pending; B1-C approved backend mappings and activation acceptance are still open. No teammate branch or source was changed.
