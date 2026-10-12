# Developer 1 — Backend / Supabase Coordinator (Phase 6)

Role: PostgreSQL/Supabase architecture, RLS/RPC/Edge contracts, payment/matching
backend, shared-contract ownership. Status authority: `SPRINT_TRACKER.md`.

## P6-01 — Cash payment domain contract | Status: TODO

- Goal: provider-neutral Cash contract reusing Phase 3 foundations; unblock P6-05/P6-07/P6-08.
- Prerequisites: Phase 3 `008`/`009`/`017`/`022` semantics; P5 fare-lock/confirm flow.
- Implementation: new `lib/core/models/payment*.dart` (method vs status separate;
  `cash_selected` unpaid until trusted completion; `payment_cancelled` on cancel),
  new `lib/core/repositories/payment_repository.dart` interface + fake; no secrets;
  integer minor units + currency; idempotency/expected-version fields.
- Owned files: new model/contract/test files only.
- Shared/coordination: `repositories_providers.dart`, `fare_repository.dart`,
  `booking/trip` models — read-only in Sprint 1; wiring deferred to P6-09.
- Acceptance: interface reviewed; fake passes version/idempotency cases; Dev 2/3
  build P6-05/P6-08 against it with no production-provider change.
- Tests: `test/payment_cash_contract_test.dart` (states, transitions, fake).
  Complexity: M. Integration: publish draft Day 1 Sprint 1.

## P6-03 — Card payment domain contract | Status: TODO

- Goal: provider-neutral Card contract + Stripe-adapter boundary (Stripe Test Mode only).
- Prerequisites: P6-01; Phase 2 card rules (auth post-match, capture post-completion,
  one active fare, attempt limits as contract constants, not execution).
- Implementation: card states (`card_payment_pending/authorized/succeeded/failed`,
  `payment_cancelled`, `refund_pending/refunded` as statuses only); adapter interface
  returning provider refs/metadata (brand/last4 only); raw card data prohibited.
- Owned: new card contract/test files.
- Shared: same as P6-01; no Edge/migration change in Sprint 2.
- Acceptance: Stripe types isolated behind adapter; UI contracts carry no secrets;
  P6-06 builds against fake.
- Tests: `test/payment_card_contract_test.dart`. Complexity: M.

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