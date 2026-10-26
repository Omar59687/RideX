# P6-R07 Cash and Recovery test fixture preparation

Date: 2026-10-25. Repository base: `49e5281dfef04ad9eb0e02d5303a344d425d6ac3`.
Status: **TRIP EXECUTION STOPPED FOR LIFECYCLE CORRECTION; HOSTED FINANCIAL ACCEPTANCE NOT RUN**.

## Canonical lifecycle correction - 2026-10-26

The original #64 Trip execution path skipped directly from `accepted` to
`inProgress`. Repository migration 008 and the hosted
`private.enforce_trip_transition()` trigger both reject that transition with
`55000: Invalid Trip status transition.` The earlier read-only preflight verifies
data prerequisites, not transition compatibility; it cannot establish that this
execution path is safe. The defect was caught before creating an offer or Trip.

This correction uses the existing authenticated `driver_transition_trip` RPC for
`accepted -> driverArriving -> driverArrived -> inProgress`. Each staging response
must match the original Trip, then a canonical Driver-authorized reread must prove
the expected status, next version, original booking/Rider/Driver/vehicle identities
and Cash method before any further command. Errors, uncertain responses, foreign
identities or stale rereads stop the sequence without retry. No backend contract,
schema, migration, financial workflow or app activation flag is changed.

Local verification: **11 Deno tests PASS / 0 FAIL**, including the five existing
fixture guard tests and six lifecycle regressions. Type-check, lint, formatting
and diff consistency checks passed. These are local tests, not hosted
fixture acceptance. No new authenticated preflight or hosted mutation was run
during this corrective work.

Read-only inspection at this checkpoint found the designated Rider's confirmed
Cash Economy booking at version 3 with locked quote version 1, the approved
Driver's active owned vehicle at version 2, and availability `available` at version
2. No offer or Trip exists for the booking. Exact identities remain in restricted
operator evidence rather than this document.

**Execution remains stopped.** The current owner request enumerates only offer
creation, acceptance and `inProgress`. Obtain authorization explicitly covering
the required intermediate `driverArriving` and `driverArrived` test transitions,
merge/review this correction, then authenticate both accounts and run a fresh
read-only preflight before one operator execution. Do not run the original #64
sequence merely to reproduce a known partial failure. No approval for completion,
settlement, receipt issuance, replay, cleanup or Phase 6 exit is implied.

## Original preparation scope (historical snapshot)

This record prepares one isolated, non-production Cash Trip acceptance scenario.
During the original preparation, no hosted Trip, Payment, Receipt, booking,
vehicle, profile or role was created or changed. No RPC was invoked, and no
migration or Edge Function was deployed. The
future acceptance must not involve exchange of real cash; fixture execution remains
a separately authorized mutation of designated test-backend records.

## Approved test scope and observed environment

The owner approved this graduation-project test backend identity:

- Endpoint: `https://ykasivejjchupswqyxpm.supabase.co`
- Driver journal namespace: `ridex-grad-ykasivejjchupswqyxpm-v1`
- Account labels: `yousufadmin@gmail.com` (Admin),
  `yousufdriver@gmail.com` (approved Driver), and
  `yousufrider@gmail.com` (Rider). These are identifiers only; this record has
  no credentials.

Connected Supabase management metadata identifies project ref
`ykasivejjchupswqyxpm`, status `ACTIVE_HEALTHY`, PostgreSQL 17, region
`ap-south-1`. The owner's approval classifies this identity for the graduation
project test backend. This record does not independently classify any other
endpoint or authorize financial fixture execution.

Read-only catalog inspection reports migrations **001–027**, including
`027_phase6_admin_payment_read_rpc`. Public `users`, `trips`, `payments`,
`payment_attempts`, and `receipts` exist with RLS enabled. The account-scoped
read-only profile/count query returned:

| Account label | Profile result | Availability | Existing associated bookings / Trips / Payments / Receipts |
|---|---|---|---|
| `yousufadmin@gmail.com` | Admin, unblocked | n/a | 0 / 0 / 0 / 0 |
| `yousufdriver@gmail.com` | Driver, approved, unblocked | Offline; no active Trip | 0 / 0 / 0 / 0 |
| `yousufrider@gmail.com` | Rider, unblocked | n/a | 0 / 0 / 0 / 0 |

The hosted catalog reports zero `vehicles` rows. No account has a canonical
booking or financial fixture yet. These results establish profile/catalog
configuration only. They do not establish successful sign-in, authenticated RPC
authorization, live application behavior, or a role-matrix pass. No UUIDs,
tokens, passwords or provider data were collected for this record.

## Registry and activation gate

PR #62 records the exact owner-approved endpoint/namespace pair in
`approvedDriverCompletionBackendsProvider`. Its compile-time gate is
`RIDEX_ENABLE_TEST_DRIVER_CASH`, with `defaultValue: false`. The source mapping
is present on this base; **the flag remains disabled and must not be passed as a
`dart-define`** for this preparation task. The canonical Cash panel is still not
mounted in the live Driver experience. This PR does not change the flag, provider,
or screen wiring.

## Canonical fixture path and authority

The minimum future fixture is one Rider-owned Cash booking, one locked fare quote,
one server-authorized match offer to the designated approved Driver and that
Driver's owned active vehicle, one canonical assigned Trip, its canonical Payment,
and (only after an authorized completion) its backend-issued Receipt.

The fixture must use RideX's authenticated application and trusted backend path:

1. Sign in as the designated Rider and create a draft with
   `rider_create_booking_draft`, setting `requested_payment_method` to `cash`.
   Use the existing fare calculation/lock path, then
   `rider_confirm_booking`. The payment method is immutable after confirmation.
   Use only a route supported by the configured test fare service; do not
   hand-author fare values.
2. Establish the designated Driver's owned vehicle and availability through the
   authenticated `driver_create_vehicle`, `driver_set_vehicle_active` and
   `driver_set_availability` RPCs. A proposed unmistakably synthetic configuration
   is type `economy`, make `RideX Test Fixture`, model `QA Economy`, color
   `Blue (Test)`, registration `RIDEX-TEST-ONLY`, four seats, no year/photo. The
   tool's `--prepare-vehicle` mode checks for an empty Driver vehicle inventory and
   offline availability, then uses only authenticated Driver RPCs to create,
   activate and make the vehicle available. It fails closed if the Driver already
   has a vehicle or is not offline. Use it only after separate operator
   authorization; this PR did not create it. Match the type to the Rider booking.
3. The narrow operator tool
   [`supabase/ops/p6_r07_prepare_cash_trip.ts`](../../../supabase/ops/p6_r07_prepare_cash_trip.ts)
   accepts only the fixed test endpoint and namespace, and authenticates the exact
   dedicated Rider and approved Driver. Its default mode is read-only. It requires
   a canonical confirmed Cash booking with locked FareQuote, the Driver's owned
   active compatible vehicle and `available` state, and no prior Trip/offer for
   that booking. With `--execute` plus `R07_EXECUTION_APPROVAL_REF`, it calls only
   `backend_create_driver_match_offer` followed immediately by the authenticated
   Driver `driver_transition_trip` acceptance, then the required `driverArriving`,
   `driverArrived` and `inProgress` transitions. This is
   an operator-triggered test assignment through canonical contracts; it is not a
   real matching algorithm or evidence of Phase 7 matching. The operator holds
   the service-role key locally; the key is never part of Flutter/application code,
   command arguments, logs or responses. The script has no endpoint override,
   direct table write, cleanup, completion, settlement, receipt, retry or replay.
   An unknown mutation response stops the run and requires authorized read-only
   reconciliation before any further action.
4. `driver_transition_trip(..., 'accepted', expected_version, key)` validates the
   Driver, offer and assignment; the server creates the canonical Trip and ensures
   its Payment from the locked FareQuote and Trip. The tool then uses that same
   authenticated RPC for each required lifecycle stage, preserving backend versions
   and checking returned canonical identity/state/version after every response.
5. Once R01/R02 are mounted and separately authorized for hosted acceptance,
   complete that same `inProgress` Trip exactly once using its persisted version
   and original idempotency key.
   Migration 017's `driver_transition_trip` path completes the Cash Trip, settles
   the canonical Payment and issues the Receipt in the same database transaction.
6. Verify through authorized canonical reads: Trip is completed; its Payment is
   linked to the same Trip/Rider, method Cash and status paid; exactly one Receipt
   is linked to the same Trip/Payment, with matching amount/currency and backend
   source versions. Read the Driver-safe receipt summary; never infer issuance
   from Trip or Payment state alone.
7. Restart/resume the canonical Driver app and run R03 read-only recovery. Confirm
   the original journal evidence is retained, canonical Trip evidence is read,
   and the receipt result is reported separately. No recovery action dispatches,
   retries, repairs or retires a command.

No database seeder or deployed matching/fixture Edge Function exists. Although
`supabase/config.toml` references `supabase/seed.sql`, that file does not exist.
The new local operator tool is a bounded setup path over existing server
contracts, not a production app integration or deployed service. It does not
create the Rider booking/fare; those must come from the authenticated Rider flow.
It cannot test R02's app journal/UI because the activation flag and canonical
Driver panel remain disabled/unmounted. The current MockTrips screen cannot be
used. Direct table writes, Trip/Payment/Receipt fabrication, SQL role
impersonation and unconstrained service-role calls remain prohibited.

## Prepared R04 role matrix

| Actor | Expected check | Fixture/evidence status |
|---|---|---|
| Active nonblocked Admin (`yousufadmin@gmail.com`) | `admin_recent_canonical_payments()` returns sanitized rows, capped at 50 | Profile exists; no representative payment; authenticated RPC not run |
| Blocked Admin | Admin RPC denied | No dedicated blocked Admin identity; do not block the active Admin |
| Demoted Admin | Admin RPC denied after demotion is observed | No separate demoted Admin identity; do not change the active Admin |
| Owning Rider (`yousufrider@gmail.com`) | `user_canonical_payment_record(id)` returns only own canonical Payment | Profile exists; no Payment fixture; authenticated RPC not run |
| Foreign Rider | Cannot read another Rider's Payment | No separate foreign Rider fixture/account supplied |
| Approved Driver (`yousufdriver@gmail.com`) | Cannot access unauthorized financial records; can only read the Driver-safe receipt summary for an assigned Trip | Profile approved; no vehicle/Trip; authenticated RPC not run |
| Anonymous | RPC denied; direct financial-table reads denied | Not run |

Direct `payments`, `payment_attempts`, `refunds` or `receipts` table SELECT is
not an acceptance substitute for the authorized RPCs. Keep permission denial
distinct from an authorized empty result. Obtain separate dedicated identities
for blocked/demoted Admin and foreign Rider cases before the hosted matrix; never
change the three designated accounts' roles for negative tests.

## R07 Cash/Receipt and recovery checklist

All boxes below are future hosted acceptance scenarios, not evidence of execution.
The new preflight tool covers only fixture scope/prerequisites. Local regression
commands for the existing completion/recovery implementation are
`flutter test test/driver_completion_coordinator_test.dart`,
`flutter test test/driver_readonly_recovery_test.dart`,
`flutter test test/canonical_trip_reconciliation_test.dart`, and
`flutter test test/supabase_driver_completion_adapter_test.dart`; they were not
rerun for this fixture tooling change. Run the focused local fixture guard with
`deno test --no-lock supabase/tests/p6_r07_fixture_contract_test.ts`.

- [ ] Driver can complete the one authorized Cash Trip through the original
  durable command; verify exactly one canonical Trip completion, one settlement
  record and one linked issued receipt through trusted reads.
- [ ] Reuse of the original idempotency key is safe; a stale Trip version,
  foreign/blocked/revoked Driver and namespace mismatch are rejected.
- [ ] Lost completion response remains unresolved until read-only recovery;
  missing receipt is unverified; no automatic replay, retry, journal deletion or
  retirement occurs.
- [ ] Rider/Admin canonical visibility is checked through authorized RPCs only;
  a missing/unauthorized record is distinguished from a permission error.

- [ ] Confirm the approved endpoint and namespace match the compiled app; confirm
  `RIDEX_ENABLE_TEST_DRIVER_CASH` remains absent/default false until explicit
  hosted acceptance authorization and canonical UI readiness.
- [ ] Confirm the Rider, approved Driver, owned active vehicle and matching service
  are the designated isolated test actors; confirm no pre-existing active booking
  or Trip is being reused.
- [ ] Create the booking, fare quote, match offer, Trip and Payment only through
  their authorized actor/server flows. Record evidence after each canonical result.
- [ ] Reject foreign Driver, non-Cash Trip, stale Trip version, duplicate tap
  and namespace mismatch without settlement. Verify session revocation through
  logout on the designated Driver; a blocked Driver role test requires a separate
  negative-test identity rather than changing the designated Driver.
- [ ] On the one authorized completion, record the original Trip ID/version and
  idempotency key in the restricted evidence record; verify one completed Trip,
  one paid Cash Payment and one linked issued Receipt.
- [ ] Verify replay with the same key does not create a second settlement/Receipt.
  Any uncertain RPC response is unresolved: do not re-dispatch; use R03 read-only
  canonical Trip and receipt reconciliation.
- [ ] Restart/resume the canonical app and verify recovery retains journal
  evidence, performs reads only, and presents Trip completion separately from
  receipt verification. Missing receipt is unverified, never “payment failed.”
- [ ] Run the authorized R04 role matrix separately and capture only sanitized
  outcomes, request labels and timings; do not include credentials, raw payloads,
  full private snapshots or secrets in PR evidence.

## Cleanup, evidence and authorization boundary

This preparation performed no setup or cleanup mutations. After a separately
authorized hosted run, cancel only an unstarted Rider booking through its
authorized cancellation flow if cancellation is valid. Never delete or directly
edit canonical Trips, Payments, Attempts, Receipts, audit/idempotency evidence or
another user's rows. Completed fixtures and receipts are retained as financial
test evidence; record them as retired from further use in the restricted run
ledger. Do not reuse a completed Trip to simulate another completion.

Keep exact correlation identifiers in access-controlled test evidence only;
the public report should contain masked identifiers and status assertions. No
credentials, service-role key, session token, raw receipt snapshots or payment
payload belongs in repository documentation.

## Historical preparation blockers and status

The lifecycle correction checkpoint above supersedes the absent vehicle/booking
items in this original preparation snapshot. The canonical app activation and
hosted financial acceptance gates remain open.

- No owned vehicle for the designated Driver; the synthetic vehicle fields and
  authorized registration/activation RPCs are now specified, but not executed.
- No active canonical Driver screen: current Driver Trip screen remains mock-backed.
- No production matching service. A local operator-only tool now calls the existing
  service-role-only match-offer RPC and Driver-owned transition RPCs under a fixed
  test-only allowlist; it does not claim natural matching behavior.
- No hosted booking/Trip/Payment/Receipt fixture exists for the three accounts.
- No dedicated blocked/demoted Admin or foreign Rider identities for the full R04
  negative matrix.
- The activation flag remains off; no hosted JWT/RPC role tests or financial
  operations were run for this preparation.

R07 is **PREPARED, NOT ACCEPTED**. Phase 6 remains **NOT APPROVED**. Next, finish
canonical Driver screen integration and obtain a separate explicit execution
authorization before running either vehicle/Trip setup or any completion. Then
run R04/R07 checks with designated role fixtures and record each result without
treating prepared checks as executed acceptance evidence.

## Operator tool preflight and execution

Run from the repository root with Deno 2. The operator must load secrets into the
process environment through a private secret manager/shell, never a command-line
argument or checked-in file: `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`, `R07_DRIVER_ACCESS_TOKEN`, `R07_RIDER_ACCESS_TOKEN`,
and `RIDEX_BACKEND_NAMESPACE=ridex-grad-ykasivejjchupswqyxpm-v1`. The script
pins the URL to the approved project and checks both auth tokens against the exact
account labels plus live unblocked profiles/Driver approval.

First run the read-only vehicle preflight:

```powershell
deno run --allow-env=RIDEX_BACKEND_NAMESPACE,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY,R07_DRIVER_ACCESS_TOKEN,R07_RIDER_ACCESS_TOKEN,R07_EXECUTION_APPROVAL_REF --allow-net=ykasivejjchupswqyxpm.supabase.co supabase/ops/p6_r07_prepare_cash_trip.ts `
  --prepare-vehicle
```

After separate authorization specifically covering the test Driver vehicle, set
`R07_EXECUTION_APPROVAL_REF` to its record and append `--execute` to that command.
Capture the returned vehicle UUID in the restricted acceptance ledger. All vehicle
and availability mutations use the authenticated Driver token, not service role.
The tool never deletes or deactivates this vehicle.

After the Rider has created and locked a Cash booking through the canonical app
flow and the Driver vehicle is ready, run its read-only Trip preflight:

```powershell
deno run --allow-env=RIDEX_BACKEND_NAMESPACE,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY,R07_DRIVER_ACCESS_TOKEN,R07_RIDER_ACCESS_TOKEN,R07_EXECUTION_APPROVAL_REF --allow-net=ykasivejjchupswqyxpm.supabase.co supabase/ops/p6_r07_prepare_cash_trip.ts `
  --booking-id <canonical-booking-uuid> --vehicle-id <owned-vehicle-uuid>
```

Only after a separately recorded operator execution authorization, set
`R07_EXECUTION_APPROVAL_REF` to that approval record and append `--execute`. This
creates a canonical offer and advances the same canonical Trip to `inProgress`;
authorization must cover acceptance plus `driverArriving`, `driverArrived`, and
`inProgress`. It does not complete the Trip. Never use the Admin account to execute this tool. Do not
run concurrent setup processes. On any timeout or uncertain response, stop; do not
rerun. Verify booking, offer, Trip and Payment through authorized read paths and
preserve evidence. A prepared Trip is not an accepted Cash completion fixture
until the separately approved R01/R02 application path has been activated and
the completion/recovery scenarios below have actual evidence.
