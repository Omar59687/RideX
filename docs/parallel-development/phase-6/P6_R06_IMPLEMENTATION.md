# P6-R06 Stripe Test Mode preparation implementation

Date: 2026-10-25
Base: `552b0f78f3e72b84cc7d5b446968a0b5e519f765`
Branch: `feature/p6-r06-stripe-test-preparation`
Status: **PARTIAL; production provider dispatch disabled**

## Implemented boundary

`supabase/functions/stripe-test-intent/index.ts` exposes the bounded `POST`
handler with Supabase `verify_jwt = true`. The handler independently validates
an authenticated, nonblocked Rider profile through the existing users/RLS
boundary. The body allows only Payment ID, Trip ID, attempt ID, expected Payment
and Trip versions, and the operation's idempotency key. Client amount/status and
unknown fields fail closed.

The server-side reader performs bounded GET-only service-role queries, each
filtered by the verified Rider or exact Payment/Trip/attempt identity. It requires
an accepted Card Trip, matching rider/payment/trip ownership, matching JOD/fare,
a pending initial-authorization attempt in cycle 1, and exact original attempt
key. The attempt table has no independent version column; exact attempt UUID,
cycle, pending state and key are the existing identity/freshness contract. Both
Payment and Trip versions are supplied by the caller and compared with canonical
rows. No RPC or schema was added and no financial row is written.

## Provider safety

Production `index.ts` passes a provider stub and `providerDispatchEnabled: false`.
It does not read a Stripe secret and no request can reach Stripe from this entrypoint.
The existing injected adapter remains tested separately: only `sk_test_`/`rk_test_`
keys and explicit JOD approval are accepted; `confirm=false`, manual confirmation
and capture, only card method, and `requires_payment_method` with zero captured or
capturable amount are required. The client secret and other provider fields are
never returned. Timeout becomes unknown and the process-local test guard blocks a
second request for the same key; this in-memory guard is not durable across Edge
instances/restarts, so it does not authorize production dispatch.

RideX stores JOD in thousandth-dinar fils. Stripe API amounts use currency minor
units; the adapter now rejects values not divisible by ten and converts exactly
from fils to the two-decimal JOD minor unit without rounding. This arithmetic does
not prove JOD presentment or approve an account. Stripe's [supported currency
contract](https://docs.stripe.com/currencies) describes minor-unit input and
account-specific support. Supabase's current [Edge Function auth guidance](https://supabase.com/docs/guides/functions/auth)
and [JWT header guidance](https://supabase.com/docs/guides/functions/auth-headers)
confirm keeping platform JWT verification enabled for a user-facing function.

## Verification and limits

- Focused Deno tests: **55 PASS / 0 FAIL** across provider and handler tests.
- `deno check` for the handler and production entrypoint: passed.
- `deno fmt` on changed TypeScript: passed.
- No hosted Supabase operation, Stripe credentials/request, database mutation,
  migration, deployment, or real financial operation was performed.

The historical 2026-07-29 Plan.md decision approves Test Mode only for the Graduation MVP demonstration; it does not establish this endpoint account, JOD presentment/precision, or credential approval.

Remaining owner requirements: approve the Stripe Test Mode account and JOD
currency/precision; provide an isolated accepted canonical Card Trip, Payment and
pending authorization-attempt fixture; approve a durable dispatch claim and
unknown-outcome reconciliation contract; then collect authorized sandbox-only
runtime evidence. Phase 7 assigned Trip identity and Phase 8 payment/attempt
creation remain upstream dependencies. R08 UI and Phase 8 authorization/capture
are out of scope. Phase 6 remains NOT APPROVED.
