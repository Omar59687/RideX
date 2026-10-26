# P6-R06 Card Fixture Operator

**Status: operator implemented; hosted fixture creation not executed. R06 remains partial.**

This operator prepares one isolated, test-only Card authorization context for
later R06 reservation concurrency acceptance. Its default mode is read-only
preflight. This implementation has not created a hosted Booking, Trip, Payment,
Attempt, reservation, or Stripe object.

## Fixed test boundary

The operator accepts only project `ykasivejjchupswqyxpm`, namespace
`ridex-grad-ykasivejjchupswqyxpm-v1`, Rider `yousufrider@gmail.com`, approved
Driver `yousufdriver@gmail.com`, and the previously approved synthetic Economy
vehicle `48d007ab-c13c-4ff8-93f3-1dc7f1e6975d`. It verifies both SDK access
tokens against Auth and the current profile/Driver approval before use. A
per-run UUID labels the route and derives the confirmation, acceptance and
authorization operation keys. The fare is obtained from the existing fare
function; no client amount is accepted.

## Canonical workflow

An explicitly approved future execution uses these existing operations in
order:

1. `rider_create_booking_draft` creates a Rider-owned Economy/Card draft with
   the unique `RIDEX_R06_CARD_TEST_<fixture UUID>` route label.
2. The existing `/functions/v1/fare` operation calculates the quote from
   canonical pricing and route data. `rider_lock_fare_quote` locks it and
   `rider_confirm_booking` confirms the draft using the derived operation key.
3. `backend_create_driver_match_offer` creates the canonical offer for the
   approved Driver and fixed test vehicle. The authenticated Driver accepts it
   through `driver_transition_trip`; this creates the canonical Trip and
   pending Card Payment through existing backend behavior.
4. `backend_record_payment_attempt` records the first pending
   `initialAuthorization` Attempt using the derived original operation key.
   This operator never calls the R06 reservation claim RPC.

After each mutation, the operator reads back and checks the canonical owner,
identities, versions, locked JOD fare, amount, Card method, pending Payment and
Attempt, Driver availability and absence of a Receipt. It halts on an ambiguous
request and never retries automatically. It performs no direct table writes.
The service-role key is used only by this local operator for read-only profile
and row reads and the existing backend-only RPCs; it is never logged or sent to
the Flutter client. Supabase documents service/secret keys as server-side only
([API keys](https://supabase.com/docs/guides/getting-started/api-keys)).

## Local commands

Run from the repository root with Deno and environment variables supplied by a
secure local secret manager or process environment. Do not put credentials in
the command line or commit a `.env` file. Keep the state file outside the
repository, at `%LOCALAPPDATA%\RideX\R06\card-fixture-state.json`.

```powershell
$fixtureId = [guid]::NewGuid().ToString()
$stateDir = "$env:LOCALAPPDATA\RideX\R06"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$env:SUPABASE_URL = 'https://ykasivejjchupswqyxpm.supabase.co'
$env:RIDEX_BACKEND_NAMESPACE = 'ridex-grad-ykasivejjchupswqyxpm-v1'
$env:R06_FIXTURE_STATE_FILE = "$stateDir\card-fixture-state.json"
deno run --allow-net=ykasivejjchupswqyxpm.supabase.co --allow-env=LOCALAPPDATA,SUPABASE_URL,RIDEX_BACKEND_NAMESPACE,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY,R06_RIDER_ACCESS_TOKEN,R06_DRIVER_ACCESS_TOKEN,R06_FIXTURE_STATE_FILE,R06_EXECUTION_APPROVAL_REF --allow-read="$stateDir" --allow-write="$stateDir" supabase/ops/r06_prepare_card_fixture.ts --fixture-id $fixtureId
```

`--fixture-id` is required. Omitting `--execute` performs only preflight. The
operator requires both approved test identities, active Driver availability,
no active Trip for either actor, no existing R06-labelled fixture, and the
expected synthetic vehicle state.

Hosted creation is a separate action and is **not authorized by this PR**. Only
after separate owner approval for that exact fixture may the operator be run
once by adding `--execute` to the same command and setting
`R06_EXECUTION_APPROVAL_REF=owner-approved-r06-card-fixture-<same UUID>`. Use
one designated operator machine and the same fixed absolute state-file path
(not a per-fixture path); the atomic create-new file blocks repeats/restarts on
that machine. A partial or
uncertain result requires read-only reconciliation before any further action.
Because `rider_create_booking_draft` has no caller idempotency key and there is
no global fixture-claim RPC, this local guard does not provide a cross-machine
atomic claim. Do not run concurrent operators or treat this tool as globally
race-safe; a backend-owned atomic fixture claim would be needed to remove that
limitation.

## Verification and remaining gates

Focused local tests mock every HTTP call and verify default read-only behavior,
fixed environment/actors, duplicate labels and operation keys, canonical
identity/version/amount guards, Attempt freshness, restart protection, and an
allowlist of existing RPCs. They assert that no direct table mutation, Stripe
request, Payment transition, or Receipt operation occurs. No hosted fixture
creation is evidence from these tests. The focused existing pgTAP reservation
test was attempted locally but could not run because the local database lacked
`backend_claim_stripe_test_preparation`; no local database reset was performed.

The operator leaves the Payment and authorization Attempt pending and creates
no reservation row. R06 still requires separate authorization and execution of
one isolated Card fixture, followed by hosted reservation concurrency and
reconnect acceptance. Stripe Test Mode account/JOD approval and independent
sandbox acceptance remain separate gates; provider dispatch stays disabled.
