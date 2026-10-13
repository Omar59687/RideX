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

## P6-02 — Cash settlement backend wiring | Status: TODO

- Goal: Flutter-visible Cash settlement wiring against the existing trusted
  Phase 3 path; unblock P6-07 semantics. No new settlement logic.
- Prerequisites: P6-01 (merged); V5-01/V5-04 hosted evidence (both TODO).
- P6-02-S1 validated settlement chain (docs only; verified against latest SQL):
  - Trusted completion: Flutter calls only
    `public.driver_transition_trip(target_id uuid, requested_status
    public.trip_status, expected_version integer, idempotency_key text)`
    (`017:204-210`, SECURITY DEFINER, approved non-blocked Driver only).
    With `requested_status = 'completed'` and a Cash-method Trip, the backend
    invokes `private.settle_cash_trip_and_issue_receipt` (`017:263-264`),
    which requires a completed Cash Trip (`017:159-163`), refuses completion
    while an approved fare adjustment is unapplied (`017:164-170`), moves the
    payment `cashSelected` → `paid` at the current fare, and issues the receipt
    via `backend_issue_receipt` (`017:172-189`). Direct Flutter invocation of
    any `private.*payment*` / `private.settle_*` function is forbidden; these
    are revoked from client roles (`017:444-447`, `009:376` pattern).
  - Cancellation/reconciliation: `public.rider_cancel_trip` (`017:272-287`),
    driver `cancelledByDriver` via `driver_transition_trip` (`017:265-266`),
    and `public.admin_terminate_trip` (`017:289-307`) all reconcile through
    trusted `reconcile_cancelled_trip_payment` (latest: `022:612-670`), which
    requires a terminal-cancelled Trip, moves Cash `cashSelected` →
    `cancelled`, and never cancels settled `paid` (`022:632-642`).
  - Read-only access: `payments`, `payment_attempts`, `refunds`, `receipts`,
    and `processed_webhook_events` expose SELECT-only RLS to authenticated
    callers (`009:361-369`). `private.can_read_payment` admits admins and the
    owning rider only — Drivers cannot read payment rows (`009:198-205`).
    `private.can_read_receipt` admits admins, the owning rider, and the trip
    Driver (`009:207-216`). Sanitized projections (`019`/`020`,
    `user_payment_summary` and receipt views) carry brand/last4 only.
  - Known gap (P6-02-S2 prerequisite): `user_payment_summary` omits
    `bookingRequestId` and Payment `version` required by `CashPayment`.
    Resolve the authorized read projection before production wiring; Flutter
    must never fabricate missing identifiers or versions.
- Security/verification gates: settlement authority stays entirely backend-side;
  no new migration or RPC is required for the existing path unless a verified
  gap is later discovered (any such migration is additive, Dev 1-numbered, and
  separately authorized). V5-01/V5-04 hosted evidence remains pending: no claim
  of real financial execution until those gates and the sprint-boundary full
  non-live suite pass.
- Handoff for Dev 3 / P6-07 (prepared; receipt not confirmed): the Driver hook
  calls the existing trusted completion path only and presents the canonical
  result; it never sets `paid` client-side. Execution claims wait on V-evidence.
- Sprint 3+ sequencing: S1 (this validation) → S2 wiring draft (blocked until
  V-evidence) → S3 settlement claim (blocked until evidence + boundary suite).
  Re-plan S2/S3 from latest `main` when unblocked.
## P6-04 — Stripe Test Mode intent interface | Status: TODO

- Goal: reviewed design mapping Stripe PaymentIntent manual-capture concepts
  onto the existing trusted Phase 3 attempt lifecycle. Design only in Phase 6;
  execution belongs to a separately authorized future phase (Phase 8 scope).
- Prerequisites: P6-03 (merged); Phase 2 card rules; this design slice is
  unblocked contract work, while any execution claim stays blocked behind
  Sprint 3 authorization, Test Mode key infrastructure, and V5-01/V5-04 hosted
  evidence (all TODO).
- P6-04-S1 intent mapping (docs only; verified against latest SQL). In every
  case the provider occurrence is conceptual only: canonical state changes only
  when the trusted backend records and verifies a `payment_attempts` row through
  the service_role-only RPCs (`backend_record_payment_attempt` at `022:240`,
  `backend_complete_payment_attempt` at `022:435`; client roles revoked at
  `009:376-378`). A provider-side success that the backend has not verified and
  committed changes nothing.
  - Initial authorization: provider authorize-and-hold maps to recording an
    `initialAuthorization` attempt (first authorization cycle, Pending Card
    payment on an accepted Trip; `022:329-339`), completed only when the
    verified attempt matches the current cycle, amount, and currency
    (`022:482-495`) within the 2-minute attempt-completion timeout.
  - Replacement authorization: exactly one follow-up hold maps to a
    `replacementAuthorization` attempt, permitted only after a failed
    authorization or a verified release, with at most two authorization
    attempts per payment (`022:340-366`).
  - Capture: provider capture maps to recording a single `capture` attempt and
    only for a completed Trip on a currently authorized payment with a
    verified current-cycle authorization (`022:367-380`); one initial capture
    only.
  - Capture retry: provider retry maps to `captureRetry`, permitted only while
    the latest current-cycle capture has failed, at most three capture attempts
    total (`022:381-401`).
  - Authorization void/release: provider release maps to a `voidAuthorization`
    attempt on the current pre-start authorized payment (`022:402-421`); verified
    voids gate new authorization cycles and cancellation.
  - Refund attempts: provider refunds map to `refund`-type attempts recorded
    per Refund row through the canonical refund operations
    (`022:539-610`; completion at `021:308-378` semantics), at most three
    attempts per refund, moving `refundPending` → `refunded` only on verified
    completion. No `refundFailed` card state exists by design.
  - Provider-status verification not used: `providerStatusVerification` (and
    `adjustmentAuthorization`) attempts cannot be recorded through the attempt
    operation (`022:322-327`); the design must not rely on provider polling.
  - No new RPCs, columns, or enums are introduced by this mapping.
- Webhook deduplication design: provider events deduplicate through
  `processed_webhook_events` on `(provider_name, provider_event_id)`
  (`009:144-151`), recorded server-side via
  `backend_record_processed_webhook_event` (`009:350-359`, upsert
  `on conflict do nothing`, 90-day retention). This is provider-event
  deduplication, distinct from per-operation payment-attempt idempotency keys
  (`payment_attempts_payment_idempotency_unique`, `009:61`) and per-cycle
  accounting. No webhook handler, endpoint, or signature-verification code is
  designed or authorized here.
- Security boundary: Stripe secret credentials must remain server-side; no key
  material, test keys, tokens, or secrets may enter the repository, config, or
  Flutter code. No Stripe SDK installation is authorized for Flutter. Flutter
  cannot directly perform authorization, capture, void, or refund, and S1
  introduces no client-callable financial-execution API. The existing trusted
  backend payment lifecycle remains exclusively authoritative.
- Explicit non-goals: no Stripe SDK/dependency setup; no PaymentIntent
  creation; no Edge Function implementation; no webhook endpoint or signature
  code; no Test Mode payment execution; no hosted Supabase operations; no
  financial settlement verification claims.
- Handoff implications (prepared; receipt not confirmed): Dev 2 / P6-06 keeps
  building mock-backed Card states against the P6-03 fake — this design changes
  nothing UI-facing. Dev 1 / P6-09 will consume this mapping for the contract
  compatibility harness. Future Phase 8 trusted execution implements this
  design behind the service-role boundary; re-validate against latest `main`
  before any execution slice.
- Sprint sequencing: S1 (this design) → S2 interface scaffold → S3 Test Mode
  verification, each blocked until Sprint 3 authorization, key infrastructure,
  V-evidence, and integration verification clear. Re-plan S2/S3 from latest
  `main` when unblocked.
- P6-09 compatibility harness (contract + fake parity, version/idempotency matrix).

## Cross-phase independent work

- Review V5-01/V5-04 backend evidence when available; no P7/P8 implementation in Phase 6.
- Deliverable per task: reviewed contract + fake + tests; integration via P6-09.
