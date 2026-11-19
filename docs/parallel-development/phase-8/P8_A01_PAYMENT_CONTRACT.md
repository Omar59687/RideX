# P8-A01 canonical payment contract v1 (draft)

Status: PROPOSED handoff, 2026-11-19. No new endpoint or runtime behavior is introduced. Fixtures in `p8-a01-fixtures.json` are synthetic proposed envelopes, not RPC responses or real identifiers. Review by backend and consumers remains required. Card dispatch remains BLOCKED pending separate owner authorization and financial rollout gates.

## Inventory and identity

EXISTING: `supabase/migrations/009_phase3_payment_receipt_foundation.sql` defines Payment uniquely linked to a Booking and optionally one Trip, Attempts linked to Payment, Refunds linked to Payment, and immutable Receipt uniquely linked to Trip and Payment (optionally Refund). IDs are server-issued UUIDs; a Booking ID is never a Payment ID. Payment and Refund have positive versions; attempts have a unique idempotency key (hardened globally by migration 022), with unique active authorization and successful capture fences. Webhook event identity is unique per provider. `005_phase3_core_security_foundation.sql` defines actual statuses: Card `cardPaymentPending`, `cardPaymentAuthorized`, `cardPaymentSucceeded`, `cardPaymentFailed`, `paymentCancelled`, `refundPending`, `refunded`; Attempt `pending`, `succeeded`, `failed`, `cancelled`. UNKNOWN below is a proposed outcome, not a database enum.

EXISTING: migrations 010, 017, 018, 021 and 022 harden service-owned attempts, optimistic transitions, Trip locking, authorization evidence and cancellation reconciliation. Migration 019 denies direct finance-row reads through RLS; 020 narrows reader roles; 027 provides `user_canonical_payment_record(target_payment_id)` for the owning Rider or unblocked admin, returning no row for unauthorized or missing IDs. `user_trip_payment_summary` and `user_trip_receipt_summary` already exist (019/020); the latter exposes a limited participant receipt summary, not a Payment ID. Their error semantics are not identical to 027. See `lib/core/repositories/canonical_payment_repository.dart` and `rider_canonical_trip_detail_repository.dart`: existing exact Trip detail is Cash-specific and independently checks links and receipt evidence.

EXISTING: `supabase/functions/_shared/payments/` contains test-intent provider and durable reservation seams and fake tests; `stripe-test-intent/index.ts` hard-disables dispatch. No webhook handler was found there. Reservation is not authorization, capture or receipt evidence. Preserve R06/X2 recovery fences.

Money is nonnegative integer fils with currency `JOD` (1 JOD = 1000 fils); never use floating point or client-supplied authoritative fare. Stored amounts and server fare snapshots are authoritative. No raw card data, secret keys, provider credentials or sensitive provider payloads in clients, fixtures or logs.

## Proposed v1 operation matrix

These are logical operations, not names of existing RPCs. All mutations require a verified actor, exact server-issued IDs and current versions under transaction/lock; server validates ownership, state, amount and linkage again at execution. No client claims financial success.

| Operation | Preconditions and effect | Result / unresolved boundary |
| --- | --- | --- |
| Authorize | Trusted backend verifies confirmed match and canonical assigned Trip, matching Payment and locked fare; Booking alone is insufficient. One current authorization per canonical intent. | Return server IDs, version and pending/verified outcome. Existing attempts/guards are foundations; post-match Card execution is MISSING and BLOCKED by dispatch gate. |
| Capture | Trusted backend verifies canonical Trip completion and current verified authorization, amount and exact links. Driver UI completion or callback is not evidence. | One capture effect per intent; remain pending or UNKNOWN until verified. End-to-end trusted provider capture is MISSING. |
| Cancel / void | Trusted cancellation reconciles payment; if no authorization exists, cancel without provider effect. A live authorization requires verified void before treating it as released; races with capture require reconciliation. | Existing cancellation reconciliation is not proof of an executed provider void. Provider void is MISSING. |
| Refund | Authorized admin requests against verified captured Payment; backend validates remaining refundable amount, reason, version and policy, and uses a distinct refund intent/key. | Existing admin refund/attempt primitives are not end-to-end provider refund. Partial-refund policy requires owner decision; do not assume support. |
| Webhook | Trusted server verifies signature over raw body, timestamp tolerance, provider/account/environment and event identity before processing. Persist event identity and transition atomically; deduplicate, handle out-of-order events and reconcile ambiguous effects. | Event table exists; signature-verifying handler, replay and recovery flow are MISSING. Invalid signatures fail closed. |
| Receipt | Only trusted backend issues after verified eligible settlement, with immutable snapshots and exact Trip/Payment links. Completion alone is insufficient. | `backend_issue_receipt` exists; end-to-end Card issuance and consumer verification remain MISSING. |
| Read | Scoped server read returns only actor-authorized fields, server IDs, states, integer amounts and version. Receipt is independent evidence, not derived from Payment status. | Existing summaries above are available; a bounded, reviewed Card/history read contract and pagination are PROPOSED for A04. |

## Request, response and security rules

PROPOSED mutation request: `contract_version`, `trip_id`, `payment_id`, `expected_trip_version`, `expected_payment_version`, and a stable `idempotency_key`; include operation-specific fields such as refund amount and reason only when applicable. Server derives actor, currency and authoritative amount; it validates any submitted amount against canonical data. Attempts and refund IDs are returned only after server creation. Idempotency key is bound to actor, operation, IDs and immutable payload: exact retry returns the original result; reuse with different payload fails `IDEMPOTENCY_CONFLICT`. Persist the provider key before dispatch and never issue a fresh effect merely because a response was lost.

PROPOSED response: `contract_version`, server-issued IDs, authoritative versions and `outcome` (`PENDING`, `VERIFIED`, `FAILED`, `UNKNOWN`), plus sanitized error when applicable. `VERIFIED` means server-verified operation evidence, not automatically receipt issuance. UNKNOWN means a provider effect may have occurred; preserve intent and reconcile server-side before retry or another financial effect. Pending is not success. Suggested errors: `UNAUTHORIZED`, `NOT_FOUND_OR_FORBIDDEN`, `INVALID_STATE`, `STALE_VERSION`, `IDEMPOTENCY_CONFLICT`, `AMOUNT_MISMATCH`, `DISABLED`, `UNAVAILABLE`, `UNKNOWN_OUTCOME`. These are proposed categories, not current SQL error codes. Avoid disclosing foreign record existence. Fail closed on missing identity, stale session, mismatched link, unsupported state or malformed response.

Rider reads only their own permitted financial data; an assigned Driver receives only authorized limited receipt/Trip information, never payment mutation authority. Admin operations require verified unblocked admin authorization; service-only transitions and verified webhook processing remain server-side. Existing grants and role checks are authoritative, not user-editable metadata. Maintain session/role checks and revalidate at the privileged boundary; never expose service credentials. No provider callback or client state is authoritative.

## Next checkpoints (not implemented)

- A02: reuse existing transitions and evidence; implement missing gated post-match authorization and trusted-completion capture with races, versions, idempotency and Cash regression tests.
- A03: implement server adapter, signature/replay protection, durable unknown recovery, void/refund and fake-provider tests; keep dispatch OFF.
- A04: review bounded actor-authorized Card/payment/receipt/history reads and pagination, preserving existing RPCs and independent receipt verification.
- A05: run disposable local migration, ACL/RLS, concurrency, replay, negative actor, unknown and Cash regression tests.
- A06: resolve issue #149 parity, establish separately approved backup/restore proof and deployment/rollback gates. No hosted execution is implied.

Consumer handoff: Omar uses `omar_card_pending` for gated checkout and canonical reread; Moath uses `moath_trip_completed` to keep completion separate from capture; Sanad uses `sanad_payment_receipt` to model exact linked reads. Values are fake and proposed, not current wire DTOs. Contract and fixtures require independent review before consumers treat them as stable. No issue comment was posted.
