# P6-R07 Cash and Recovery test fixture preparation

Date: 2026-10-25. Repository base: `49e5281dfef04ad9eb0e02d5303a344d425d6ac3`.
Status: **PREPARATION COMPLETE; HOSTED ACCEPTANCE NOT RUN**.

This record prepares one isolated, non-production Cash Trip acceptance scenario.
No hosted Trip, Payment, Receipt, booking, profile or role was created or changed.
No financial RPC was invoked, and no migration or Edge Function was deployed. The
future acceptance must not involve exchange of real cash; it remains a separately
authorized mutation of designated test-backend records.

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
   authorized Driver flow. The current Driver is offline and the hosted catalog
   has no vehicle, so these prerequisites are presently absent.
3. A trusted matching service must create the offer. Migration 007 exposes
   `backend_create_driver_match_offer` to `service_role` only. Current hosted Edge
   Function inventory contains `places` and `fare`, but no matching/fixture
   function. Do not call the service-role RPC from a client or invent a Trip/offer.
4. The assigned Driver accepts the actual offer through the authenticated Driver
   flow. `driver_transition_trip(..., 'accepted', expected_version, key)` validates
   the caller, offer and assignment; the server creates the canonical Trip and
   ensures its Payment from the locked FareQuote and Trip.
5. Once R01/R02 are mounted and separately authorized for hosted acceptance, move
   that same Trip through its canonical Driver transitions to `inProgress`, then
   complete exactly once using its persisted version and original idempotency key.
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

No dedicated fixture seeder or authorized hosted matching setup endpoint was
found. Although `supabase/config.toml` references `supabase/seed.sql`, that file
does not exist in the inspected tree. Existing local tests use synthetic models,
fakes and loopback HTTP fixtures; they do not seed hosted canonical data. Direct
table inserts, service-role RPC calls outside an approved server
setup, mock Trip IDs, SQL role impersonation and fabricated Payment/Receipt
records are not valid substitutes. A canonical Driver UI/matching path is a
blocking integration dependency; the current MockTrips screen cannot be used.

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

## Current blockers and status

- No owned vehicle for the designated Driver.
- No active canonical Driver screen: current Driver Trip screen remains mock-backed.
- No deployed trusted matching/offer setup function; the only canonical offer
  creation RPC is service-role-only.
- No hosted booking/Trip/Payment/Receipt fixture exists for the three accounts.
- No dedicated blocked/demoted Admin or foreign Rider identities for the full R04
  negative matrix.
- The activation flag remains off; no hosted JWT/RPC role tests or financial
  operations were run for this preparation.

R07 is **PREPARED, NOT ACCEPTED**. Phase 6 remains **NOT APPROVED**. Next, finish
the canonical Driver screen/matching integration and obtain separate explicit
operator authorization for one isolated hosted completion. Then run R04/R07
checks with designated role fixtures and record each result without treating
catalog inspection as authenticated acceptance.
