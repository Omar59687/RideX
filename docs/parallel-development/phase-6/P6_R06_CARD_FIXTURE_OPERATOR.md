# P6-R06 Card Fixture Operator

**Status: Card fixture operator and coordinated reservation acceptance harness implemented; hosted concurrency acceptance still requires separate owner authorization. R06 remains partial.**

This operator prepares one isolated, test-only Card authorization context for
later R06 reservation concurrency acceptance. Its default mode is read-only
preflight. PR #73 itself made no hosted mutations. A later separately authorized
operator execution created one canonical Booking, Trip, Payment, and Attempt;
the resulting Attempt expired before any reservation claim was attempted. No
reservation or Stripe object was created. The one-time local state marker is
preserved at `%LOCALAPPDATA%\RideX\R06\card-fixture-state.json` with status
`started_do_not_retry`; do not rerun this fixture operator or reuse its Attempt.

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
no reservation row. The authorized fixture was reconciled read-only as follows:

- Fixture UUID: `3657b9e5-f614-4ef2-9986-fa7355a18bbd`.
- Booking `faec387e…aadbab3e`: matched, version 5; locked Economy quote
  `6754c0b1…8ed988f`, JOD 2,150 fils.
- Accepted Trip `ceff7eb6…d80d550b`: version 1, owned by the approved Driver
  and fixed test vehicle.
- Payment `9c4558e0…b389eb837d4c`: Card, `cardPaymentPending`, version 1;
  initial authorization Attempt `2a2e4369…b19f3629939a`: pending, cycle 1,
  sequence 1, original operation key retained, no provider reference.
- At read-only reconciliation the Attempt was 150,825 ms old, beyond the
  120-second claim eligibility window. The read-only preparation RPC returned
  no reservation evidence; reservation count was zero. **No claim RPC was
  called**, so concurrency and reconnect acceptance are untested/blocked.
- No Receipt was created. Driver state is `onTrip` for the accepted Trip.
- Existing Cash fixture remains completed (Trip version 5), paid JOD 16.00
  (Payment version 2), with exactly one Receipt.

No provider request, financial mutation, claim, cleanup, or retry was made
during reconciliation. Preserve the local state marker and all hosted evidence.
The expired Attempt must not be reused. Any new fixture strategy or new fixture
execution requires separate owner authorization. Stripe Test Mode account/JOD
approval and independent sandbox acceptance remain separate gates; provider
dispatch stays disabled and R06 is **PARTIAL**.

## Coordinated concurrency acceptance harness

`supabase/ops/r06_accept_card_concurrency.ts` composes the canonical Card fixture
workflow with the reservation claim RPCs. Its read-only preflight still rejects
any active Trip for the fixed Rider or Driver, requires the approved Driver's
vehicle to be available, uses a new per-run fixture UUID, confirms the accepted
Trip/Card Payment before the first authorization Attempt exists, and confirms
there are no prior Attempts for the fresh Payment. The fixture marker lookup is
exact to that UUID, so the old fixture's retained Booking does not collide with
a distinct run. Existing active Trip conflicts are never bypassed.

Immediately after `backend_record_payment_attempt` returns the fresh Attempt ID,
the harness starts two separate PostgREST requests to
`backend_claim_stripe_test_preparation` concurrently, with no intervening read.
It requires exactly one `claimed` response with a token and one `existing`
response without a token. It then calls only the read RPC
`backend_read_stripe_test_preparation` to verify reconnection, retained context,
and no token replay. The fixture operator's final canonical reads require the
Trip to remain accepted, the Card Payment and authorization Attempt pending,
and zero receipts. The harness does not read or write the private reservation
table directly and does not invoke Stripe.

For a newly authorized run, configure the same test project, approved actor
tokens, and service-role secret listed above. Use the separate fixed local
state file `$stateDir\concurrency-acceptance-state.json` (the previous
`card-fixture-state.json` records the expired attempt and must remain preserved),
set a new fixture UUID, and run:

```powershell
$env:R06_FIXTURE_STATE_FILE = "$stateDir\concurrency-acceptance-state.json"
deno run --allow-net=ykasivejjchupswqyxpm.supabase.co --allow-env=LOCALAPPDATA,SUPABASE_URL,RIDEX_BACKEND_NAMESPACE,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY,R06_RIDER_ACCESS_TOKEN,R06_DRIVER_ACCESS_TOKEN,R06_FIXTURE_STATE_FILE,R06_CONCURRENCY_APPROVAL_REF --allow-read="$stateDir" --allow-write="$stateDir" supabase/ops/r06_accept_card_concurrency.ts --fixture-id $fixtureId
```

The operator requires `R06_CONCURRENCY_APPROVAL_REF=owner-approved-r06-card-concurrency-<same UUID>` and reserves this create-new state file before any write. Do not repeat an execution after a timeout or partial result; reconcile using read-only canonical and reservation RPCs.

### Existing fixture retirement decision

The historical fixture can be retired without falsifying financial evidence,
but only through an owner-authorized canonical Rider cancellation before the new
run. First re-read the exact Trip, Payment, Attempt, and reservation state. If it
still matches the recorded facts (accepted Trip, `cardPaymentPending` Payment,
pending expired initial Attempt, no provider reference, and no reservation), call
`rider_cancel_trip(target_trip_id, expected_trip_version, reason_code)` as its
owning Rider. The canonical workflow terminally cancels the Trip, records
`paymentCancelled`, preserves the original pending Attempt and its expired
timestamp, and sets Driver availability to `offline` with no active Trip. Do not
call Driver availability setters while the Trip is active. After verifying
cancellation, the approved Driver must make a separate authenticated
`driver_set_availability('available', <existing vehicle UUID>, <current
availability version>)` call. Verify the resulting available state, vehicle,
empty reservation/active Trip references, terminal Trip, cancelled Payment,
unchanged Attempt, and zero reservations. Any mismatch or
successful/provider-backed authorization means stop; a replacement
authorization or manual row edit is not permitted. The acceptance harness will
not perform this retirement implicitly.

Hosted owner authorization must separately name (1) the exact historical Trip
cancellation and owning Rider identity, (2) the Driver availability transition
using the existing vehicle and freshly read availability version, and (3) the
new fixture UUID and one-time concurrency acceptance run using both approved
test actors. This authorization does not authorize Stripe, payment advancement,
retries, or provider dispatch. The existing recorded fixture-create approval
does not by itself approve these later hosted operations.
