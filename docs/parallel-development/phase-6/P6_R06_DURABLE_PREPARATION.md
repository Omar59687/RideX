# R06 durable Stripe Test Mode preparation — 2026-10-26

Base: main `b740c16180609b466e1bdbeb984077605a6ae355` (PR #68).
Status: **PARTIAL; locally verified durable foundation; production dispatch OFF**.
No PaymentIntent was created and no hosted financial record was changed.

## Design and canonical authority

The proposed migration
`20261026163720_phase6_stripe_test_dispatch_reservation.sql` adds a private
preparation-evidence table and three service-role-only RPCs. It does not alter
the Payment/Attempt state machine or grant clients financial writes. No existing
migration is rewritten. The migration was generated with Supabase CLI 2.122.0,
applied only to an isolated local schema snapshot, and is **not deployed**.

The claim RPC locks Trip, Payment and Attempt in the existing backend lock order,
then checks the current nonblocked Rider. It requires exact ownership/identity,
accepted Card Trip, pending Card Payment, pending initialAuthorization cycle 1
with provider stripe and no provider transaction reference, original operation
key, equal canonical fares/attempt amount, supported JOD precision and exact Trip/
Payment versions. The original attempt must also remain inside the existing
two-minute initial-authorization window. Amounts/statuses are never taken from client input. The attempt
has no independent version; its immutable identity/type/cycle/key/pending state
remain the existing contract. Initial Card fixture creation is not implemented
by this slice.

The reservation has unique Attempt, Payment and operation key constraints. A
random original claim token is returned **only** to the newly committed winner.
Duplicate calls with a still-eligible, unchanged context receive existing evidence
without a token; expired or changed contexts are rejected. The separate read RPC
can reconcile retained evidence after the eligibility window. Locks/uniqueness span
database connections and Edge instances. Reservation contents preserve the full
canonical snapshot and original key. No TTL, lease reclaim, retry reset, delete
or retirement operation exists. Anonymous/authenticated/service-role direct
table access is revoked; RLS is enabled without client policies.

The Edge handler now requires a reservation store and an explicit provider
readiness check in addition to its enable flag. The existing process-local map
remains a convenience only. A positive durable claim acknowledgement is required
before one provider call. Lost claim acknowledgement prevents dispatch. A crash
before dispatch can strand a reservation; that liveness cost is deliberate.
The design guarantees at-most-once **automatic dispatch permission**, not
exactly-once provider creation/delivery or an atomic database/Stripe transaction.

Every failure after claiming is unresolved, including timeout, rejected/malformed
provider response or lost evidence-write acknowledgement. A best-effort unknown
record cannot erase a previously stored prepared reference. An existing claim
never permits another provider POST, including after restart or a configuration
change. Known pre-dispatch database ownership/version failures are sanitized and
rejected without invoking the provider. Claims do not substitute for user-facing
financial authorization.

## Stripe and reconciliation boundaries

The existing adapter still requires an explicit account/JOD Test Mode approval
configuration and a test-only key. Live/missing keys are rejected. Canonical JOD
fils must be divisible by ten for the existing supported conversion; no rounding
is introduced. This arithmetic is not approval of account presentment support.
Preparation is manual/unconfirmed, with no payment method supplied; amount
received/capturable must be zero and latest_charge null. Provider responses also
must match server-supplied Payment/Attempt/Trip metadata before their ID is saved.
Client secrets and raw provider fields are discarded. Server keys are private
class fields and are not serializable.

Stripe may prune idempotency keys after at least 24 hours, so a key is not a
permanent recovery journal. This implementation never uses an uncertain POST as
a lookup. See [Stripe idempotency](https://docs.stripe.com/api/idempotent_requests).

`reconcileReservedTestIntent` is a **server-only internal seam**, not a newly
deployed or Rider-callable endpoint. The backend read RPC checks the current
Rider and persisted ownership. Only an exact provider ID saved from a validated
preparation response can drive a Stripe GET. The response must match that ID,
original canonical metadata, amount/currency and unconfirmed/manual state.
Reconciliation performs no reservation write, claim, provider POST, financial
transition, deletion or retirement. It returns only preparation_verified or
unresolved, with canonical verification still required. See
[Stripe exact PaymentIntent retrieval](https://docs.stripe.com/api/payment_intents/retrieve).

If the process loses a provider ID before durable storage, reconciliation makes
**no Stripe call** and remains unresolved. Missing/404 evidence, timeouts, live
objects, mismatches and provider authorization/capture states also stay unresolved.
No fabricated ID, search-by-untrusted-metadata, blind retry, definitive payment
failure or financial success is inferred. Operator/provider evidence recovery
for ID-less outcomes requires a separately approved contract. A positive read
does not itself mutate or authorize the canonical Payment/Attempt.

## Local verification

- **83 Deno tests PASS / 0 FAIL** across provider, handler and reservation tests;
  tests ran without network permission. Covers concurrent owners, duplicate keys,
  restarted handlers, crash/unknown/lost acknowledgements, stale versions,
  foreign/blocked actors, configuration, live-key rejection, JOD precision,
  provider validation, read-only reconciliation and secret/error redaction.
- `deno check` production entrypoint/reservation module: passed. `deno fmt --check`
  on the eight touched TypeScript files and `git diff --check`: passed.
- **31 pgTAP assertions PASS** on isolated local PostgreSQL 17: grants/RLS,
  ownership/block/version/key rejection, one winner/no duplicate token, retained
  unknown/stronger evidence, immutable original key, unchanged Attempt bytes,
  pending Payment state and zero receipts. Fixture transaction rolled back.
- A real **two-connection PostgreSQL test PASS**: one claimed, one existing;
  a third independent connection after restart simulation also returned existing.
  Exactly one reserved row, pending Attempt/Payment, zero receipts/provider calls.

Local SQL used a newly created database `ridex_r06_safety_2026102602` copied from the
existing schema-only migration-027 test snapshot, not the application database.
This is not a fresh full migration-chain or hosted rollout verification. The
concurrency test deliberately commits and retains synthetic local fixtures and
reservation evidence. It refuses a nonempty database and has no cleanup/reset.
The existing developer database, R04 snapshot and hosted target were unchanged.

Reproduction: use a fresh empty **local Docker** database with the compatible
auth/public/private schema and proposed migration. Run
`supabase/tests/database/20261026163720_stripe_test_reservation.test.sql` with psql
(its fixture is included relative to the file), then:

```powershell
python supabase/tests/ops/r06_dispatch_concurrency_test.py --database ridex_r06_safety_YYYYMMDD
```

The script permits only the named local Docker container and an isolated database
name prefix. Never send these synthetic SQL fixtures to a hosted project. Do not
rerun against the retained nonempty database; create a fresh isolated test DB.
No full Flutter suite was run because no Flutter code changed.

## Exact activation prerequisites and remaining blockers

1. Review/merge the reservation design and migration; separately authorize and
   perform deployment with migration history, grants/RLS and hosted concurrency/
   restart/unknown-outcome acceptance. Local success is not deployment approval.
2. Approve the exact Stripe Test Mode account/credential selection, API contract,
   JOD presentment and precision rules. Supply credentials only through server
   secret management. No Stripe key was obtained or used here.
3. Authorize an isolated accepted canonical Card Trip, linked pending Card
   Payment and pending stripe initialAuthorization attempt/cycle 1 with the exact
   original key. The completed Cash fixture is incompatible and must not be reused.
   Real matching/payment-attempt fixture provenance remains an upstream P7/P8
   dependency; no hosted fixture was created here.
4. Approve ID-less unknown-outcome operator resolution and journal retention.
   Reservations cannot be reclaimed/deleted as a convenience retry mechanism.
5. Separately authorize a bounded Test Mode preparation run. A later reviewed
   activation change must bind the real adapter/readiness check; the production
   entrypoint still uses a throwing provider/readiness stub and a literal false
   dispatch gate. No environment flag can silently enable it in this PR.
6. Define/review the authenticated reconciliation entrypoint before exposing the
   internal read seam to an application. R08 UI/client-secret handling and P8
   authorization/capture/refund/receipt execution remain out of scope.

R06 is **not approved**, and Phase 6 remains NOT APPROVED. No hosted query/test,
financial mutation, Stripe request, PaymentIntent creation, schema/function
deployment or external-dispatch activation occurred in this implementation.
