# Phase 8 — Yousuf (Developer 1)

**Owner:** Yousuf / يوسف  
**Division:** Supabase and trusted financial backend  
**Workstream:** P8-A — Backend, Payment Completion, RLS, Webhooks  
**GitHub:** https://github.com/Omar59687/RideX/issues/151  
**First branch:** `feature/p8-a01-payment-contracts`  
**Status:** READY FOR INDEPENDENT LOCAL DEVELOPMENT; no P8 work is asserted complete.

## Mission
Implement the canonical server-side payment lifecycle and share stable interfaces early. The Master Plan's Phase 8 includes Card authorization only after a real Driver match, capture only after a trusted Trip completion, void/refund, verified webhooks, receipts and payment history. Reuse the Phase 3/6 foundation, preserve Cash, and keep Stripe Test Mode disabled pending separately approved financial rollout.

## Start here
1. Inspect actual migrations 009, 010, 017, 018, 022, 027, R06 reservation, the canonical Trip/Payment/Attempt/Receipt relations and `supabase/functions/_shared/payments/`.
2. Inspect `supabase/functions/stripe-test-intent/index.ts`: provider dispatch is intentionally OFF. PR #150 introduced publishable/secret API-key migration; follow current source, not legacy key assumptions.
3. Post a concise draft financial interface in issue #151 first: exact IDs, states, versions, auth, idempotency, errors and redacted fake response fixtures. Other developers may start on those fakes without waiting for deployment.
4. Do not run hosted SQL, enable Cron/Realtime, activate Stripe, or alter existing Trips/payments.

## File ownership
**Yousuf alone:** `supabase/migrations/**`, payment-specific `supabase/functions/**`, financial SQL RPCs/grants/RLS, webhook verification, backend tests and payment contract docs.  
**Do not edit:** Rider checkout and History UI, Driver Trip UI, central Flutter router or shared provider wiring.

## Independent checkpoints

### [ ] P8-A01 — Inventory and contract-first handoff
- Inventory the canonical financial state machine, existing authorization helpers, durable reservation records and read-only APIs; avoid duplicating any existing RPC.
- Define post-match authorization and post-completion capture conditions, Money/JOD precision, Payment/Attempt/Receipt identity, expected versions, idempotency, error/UNKNOWN outcomes, and actor boundaries.
- Deliver mock-ready documented request/response examples to Omar, Moath and Sanad.
- **Done:** reviewed contract draft and test fixtures. No server deployment needed.

### [ ] P8-A02 — Backend Card authorization and trusted capture
- Implement only missing backend transitions behind explicit gates and server authorization. Never authorize from a Booking alone or capture from a UI status.
- One financial effect per canonical intent under race/retry; no double capture, duplicate Payment, cross-user access, or stale-version overwrite.
- Preserve existing Cash completion/cancellation behavior and existing R06 financial fences.
- **Done:** local pgTAP, PostgreSQL concurrency and negative actor tests pass.

### [ ] P8-A03 — Stripe Test Mode, webhook and recovery boundary
- Provider-neutral secure server adapter; no secrets or raw card data sent to Flutter.
- Verify webhook signatures, event identity, replay protection, out-of-order delivery and durable UNKNOWN reconciliation; handle void/refund safely.
- Provider dispatch stays OFF until independently approved Test Mode/JOD settings, backed-up target and explicit owner authorization.
- **Done:** Deno tests with fake provider, replay/race/invalid-signature cases, and documented rollback.

### [ ] P8-A04 — Receipts and financial history read APIs
- Expose only bounded authorized reads for Rider-owned Trip → backend-issued Payment ID → independently verified Receipt; apply RLS/role checks.
- Do not synthesize payment identifiers from bookings, or treat Trip completion as receipt proof.
- Publish a typed read contract for Omar and Sanad.
- **Done:** pgTAP and Deno tests for owned/foreign/blocked/missing records.

### [ ] P8-A05 — Full backend verification
- Clean disposable database migrations, ACL/RLS, webhook races, duplicate command/replay, failed capture, cancellation/refund and Cash regressions.
- Record exact Deno/pgTAP/check results. Investigate rather than suppress failing assertions.
- **Done:** independent reproducible local evidence; no hosted claims.

### [ ] P8-A06 — Safe deployment-readiness handoff
- Review issue #149 (R06/X2 migration present in source but absent from hosted catalog); do not replay it blindly.
- Establish a separately approved off-project backup and restore proof before any live DDL. Prepare staged deployment and rollback documentation.
- Keep all hosted financial/Stripe activation BLOCKED until authorization and nonproduction actor-level acceptance.
- **Done:** source/hosted parity matrix and exact owner-approval gates documented.

## Minimal coordination
| Consumer | Early handoff | Never required for their local start |
|---|---|---|
| Omar | Typed Card status/error and checkout read-back contract | Live Stripe calls |
| Moath | Canonical Trip completion response, no financial writes | Any server Card capture during UI tests |
| Sanad | Owned Trip/payment/receipt read fields and pagination | Hosted database access |

## Definition of Done
- [ ] Contracts reviewed, versioned and shared early.
- [ ] Payment/RLS/Edge implementation isolated to backend files.
- [ ] Auth, version, idempotency, webhook signature/replay and financial race tests passed.
- [ ] No hosted writes, Card activation or financial success claimed prematurely.
- [ ] Handoff to integration owner recorded with blockers and exact evidence.

## Rules shared by all developers
- One checkpoint = one short-lived feature branch and separate worktree from latest origin/main. Preserve everyone else's files.
- Do not edit app/router/**, core/providers/repositories_providers.dart, core/repositories/trips_repository.dart, shared payment models, or another person's feature folder. Omar alone coordinates shared runtime wiring AFTER reviewed feature work.
- One backend owner: Yousuf. Changes to Supabase migrations, RPCs, RLS, payment Edge Functions and webhook contracts must go through him.
- Each checkpoint: report branch, commit, changed files, actual tests, evidence, known limits and the one interface needed from another developer.
- No PR, merge, hosted deployment, migration, credentials, Stripe dispatch, capture/refund, or financial data mutation without owner permission. Each PR needs an independent reviewer.
- Do not label mock tests, local pgTAP or CI success as hosted financial acceptance. Default Card execution remains disabled.
- Phase 7 source integration is merged, but hosted Realtime/Cron and live actor/device acceptance remain unproven. R06/X2 hosted migration discrepancy is tracked in issue #149. Do not bypass these gates.
