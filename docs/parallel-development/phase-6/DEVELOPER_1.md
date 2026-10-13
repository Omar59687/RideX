# Developer 1 — Backend / Supabase Coordinator (Phase 6)

Role: PostgreSQL/Supabase architecture, RLS/RPC/Edge contracts, payment/matching
backend, shared-contract ownership. Status authority: `SPRINT_TRACKER.md`.

## P6-01 — Cash payment domain contract

- Goal: provider-neutral Cash contract reusing Phase 3 foundations; unblock P6-05/P6-07/P6-08.
- Prerequisites: Phase 3 `008`/`009`/`017`/`022` semantics; P5 fare-lock/confirm flow.
- Implementation: `payment_method.dart` defines `cash`/`card` separately from
  `cash_payment.dart` statuses (`cashSelected`, `paid`, `cancelled`, matching
  the backend camelCase strings). `cashSelected` is unpaid. The existing
  `FareRepository.createBookingDraft` / `updateBookingDraft` selects Cash on
  the booking draft; the latter uses the **booking** expected version. Only
  trusted Trip-linked backend operations create persisted Payments and settle
  Cash atomically or reconcile cancellation after Trip cancellation.
- `PaymentRepository` exposes only
  `Future<CashPayment> readCashPayment({required String paymentId})` for an
  already persisted Payment. `FakePaymentRepository` accepts canonical
  test/demo fixtures for read-only presentation; it is not payment authority.
  Neither interface nor fake creates, cancels, or settles Cash client-side.
  Persisted Payment version is distinct from booking version; there is no
  client payment mutation or payment-command idempotency key to test here.
- Owned files: new model/contract/test files only.
- Shared/coordination: `repositories_providers.dart`, `fare_repository.dart`,
  `booking/trip` models — read-only in Sprint 1; wiring deferred to P6-09.
- Acceptance: S1/S2/S3 independently approved; read-only interface and fake
  cover canonical payment identities, typed read failures, and fixture
  uniqueness. `test/payment_cash_contract_test.dart`: 16/16 passed for exact
  mappings, lifecycle, model invariants, typed reads, and fake fixture safety;
  scoped Flutter analysis clean. No client-side payment mutation, settlement,
  or cancellation. Fake mutation version/idempotency tests from the initial
  plan are obsolete; backend/booking version and idempotency protections remain
  in their existing trusted contracts.
- Handoff for Dev 2 / P6-05: use `FareRepository.createBookingDraft` or
  `updateBookingDraft(paymentMethod: 'cash')`; never assume `paymentId` before
  trusted Trip-linked payment creation. No production provider/router change.
- Handoff for Dev 3 / P6-08: use the read-only `PaymentRepository` interface
  and test/demo-only `FakePaymentRepository` fixtures for Cash presentation;
  never treat fixture values as real payments or invent absent RPC fields.
- Future integration: `user_payment_summary` omits `bookingRequestId` and
  Payment `version` required by `CashPayment`. Resolve the authorized read
  projection before production wiring; do not fabricate these fields.
- Complexity: M. Task status, teammate receipt, and integration gates remain
  authoritative in `SPRINT_TRACKER.md`.

## P6-03 — Card payment domain contract | Status: TODO

- Goal: provider-neutral Card contract + Stripe-adapter boundary (Stripe Test Mode only).
- Prerequisites: P6-01; Phase 2 card rules (auth post-match, capture post-completion,
  one active fare, attempt limits as contract constants, not execution).
- Implementation: `card_payment.dart` defines the seven canonical statuses
  (`cardPaymentPending`, `cardPaymentAuthorized`, `cardPaymentSucceeded`,
  `cardPaymentFailed`, `paymentCancelled`, `refundPending`, `refunded`, matching
  the backend camelCase strings) as statuses only; `CardPayment` carries integer
  fils in JOD plus sanitized brand/last4 metadata only. `canTransitionCard` is a
  pure lifecycle-possibility predicate (refund edges occur only via trusted refund
  operations); `CardAttemptLimits` mirrors server-enforced caps (2 authorizations,
  3 captures, 3 attempts per refund, 2-minute attempt-completion timeout) as
  metadata, not enforcement. Raw card data prohibited.
- `CardPaymentRepository` exposes only
  `Future<CardPayment> readCardPayment({required String paymentId})` for an
  already persisted Payment. `FakeCardPaymentRepository` accepts canonical
  test/demo fixtures for read-only presentation; it is not payment authority.
  Neither interface nor fake creates, authorizes, captures, voids, refunds,
  cancels, or settles Card client-side.
- Adapter-boundary decision (independently reviewed): no executable
  `PaymentAdapter` was created in P6-03. Defining client-callable
  authorization/capture operations would grant Flutter financial authority and
  repeat the client-mutation failure mode rejected in P6-01 review. No Stripe
  SDK, provider credential, or provider-specific type exists anywhere in the
  Card contract; provider metadata is confined to brand/last4 in the domain
  model. The executable payment-provider adapter and payment-intent operations
  are deferred to the authorized P6-04/P8 scope behind a trusted server-side
  boundary, never in UI-facing models.
- Owned: new card contract/test files only:
  `lib/core/models/card_payment.dart`,
  `lib/core/repositories/card_payment_repository.dart`,
  `test/payment_card_contract_test.dart`.
- Shared: same as P6-01; no Edge/migration change in Sprint 2.
- Acceptance: S1/S2/S3 independently approved; read-only interface and fake
  cover canonical payment identities, typed read failures, and fixture
  uniqueness. `test/payment_card_contract_test.dart`: 20/20 passed for exact
  mappings, the exhaustive 49-pair lifecycle matrix, model invariants, attempt
  metadata, and fake fixture safety; scoped Flutter analysis clean. No
  client-side payment execution. The original "adapter interface" wording is
  reconciled above: the P6-03 boundary is the read contract plus documented
  deferral, reviewed and accepted at the S2/S3 gates.
- Handoff for Dev 2 / P6-06: use the read-only `CardPaymentRepository`
  interface and test/demo-only `FakeCardPaymentRepository` fixtures for Card
  state and receipt presentation; present status text, fils amounts, and
  brand/last4 only. Never assume `paymentId` before trusted Trip-linked payment
  creation; never treat fixture values as real payments or invent absent RPC
  fields. No production provider/router change.
- Future integration: `user_payment_summary` omits `bookingRequestId` and
  Payment `version` required by `CardPayment`. Resolve the authorized read
  projection before production wiring; do not fabricate these fields.
- Tests: `test/payment_card_contract_test.dart`. Complexity: M. Task status,
  teammate receipt, and integration gates remain authoritative in
  `SPRINT_TRACKER.md`.

## Sprint 3+ (outline, re-plan from latest main)

- P6-02 cash settlement wiring (RPC/RLS validation vs Phase 3; additive migration
  only if separately authorized, Dev 1-numbered). Blocked-claim: trusted settlement
  needs V5-01/V5-04 evidence.
- P6-04 Stripe Test Mode intent interface (PaymentIntent manual-capture design,
  webhook-ID dedup design; no deploy). Secrets server-side only.
- P6-09 compatibility harness (contract + fake parity, version/idempotency matrix).

## Cross-phase independent work

- Review V5-01/V5-04 backend evidence when available; no P7/P8 implementation in Phase 6.
- Deliverable per task: reviewed contract + fake + tests; integration via P6-09.
