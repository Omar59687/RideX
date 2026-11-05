# P7-A05 — Confirmed Cash Booking to Trip local integration

## Scope and provenance

Issue #93. Worktree `RideX-Phase7-Yousuf`, branch
`feature/p7-a-matching-backend`, source HEAD `73e0f8e`. Initial status was clean.
A01–A04 source and verification evidence, `Phase 7/Yousuf.md`, Issue #93,
Phase 6 tracker/roadmap and Phase 5 owner acceptance were inspected. No teammate
branch or worktree was used. Results below apply to this uncommitted A05 diff.

**READY TO COMMIT for local contract/adapter work. Hosted A05 acceptance BLOCKED.**
Neither new adapter is mounted in an application provider, HTTP endpoint,
Realtime subscription or scheduler. This checkpoint does not activate live matching.

## Existing architecture and missing connection

The canonical database path already exists:

1. Rider `rider_create_booking_draft(jsonb,jsonb,vehicle_type_code,payment_method,jsonb)`.
2. Trusted `backend_calculate_fare_quote(uuid,integer,integer,integer,text)` and
   `backend_lock_fare_quote(uuid,integer,integer)`.
3. Rider `rider_confirm_booking(uuid,integer,text)`; Cash only for new confirmation.
4. Service-only `backend_find_nearby_driver_candidates(uuid,integer,integer,integer)`.
5. Service-only `backend_create_driver_match_offer(uuid,uuid,uuid,integer,integer)`.
6. Actual authenticated Driver `driver_transition_trip(uuid,trip_status,integer,text)`.
7. Participant RLS reads of the resulting canonical Trip.

A04 already protects offer-time eligibility/GPS/quote/version checks and atomic
acceptance, plus reservation/release and expiry. No new migration, table, RPC,
assignment path, RLS policy, grant or payment transition is necessary for A05.
All 34 historical/additive migrations remain unchanged.

The missing local connection was an independently testable trusted composition
boundary and a Rider read boundary that resolves the existing confirmed handoff
to the actual assigned Trip without treating a notification or mock Trip as authority.

## Implemented contracts

### Trusted server composition

`supabase/functions/_shared/matching/cash_matching_adapter.ts` exports:

- `CashMatchingAdapter.request(bookingId: string, quoteId: string,
  expectedVersion: number): Promise<MatchingResult>`.
- `CashMatchingPort.owner/read/candidates/offer` for deterministic isolated tests.
- `SupabaseCashMatchingPort(url, publicKey, riderBearer, serviceKey, send?)`:
  explicit trusted-server-only REST implementation; no environment reads or entrypoint.
- Result: canonical booking/quote IDs, `awaitingDriver | noCandidates | assigned`,
  with actual Trip ID only for validated assignment. No credentials or Payment ID.
- Sanitized errors: `unauthorized | invalid_request | invalid_state | conflict | unknown`.

The adapter authenticates the Rider with Auth and checks the nonblocked Rider
profile. It reads the booking aggregate using that Rider bearer/RLS. Booking
and quote locators are validated against server owner/linkage, confirmed/searching
Cash state and locked quote. It requests the existing deterministic 3 km/top-three
candidate RPC and creates offers through A04 with freshly read booking versions.
No caller coordinates, amount, payment state or chosen Driver is accepted by
`request`. Service credentials occur only in the two backend RPC requests.

Repeated requests first recover existing assignment or offered records, without
resending a mutation or extending a deadline. Unknown transport/5xx responses cause
read-only reconciliation; absence of evidence remains `unknown`, never automatic
replay. Each real REST operation has a 15-second abort deadline. Actual assignment
requires a matched booking, exactly one Trip and exactly one accepted linked offer.
The adapter never impersonates the Driver or calls acceptance/completion/payment RPCs.

Composition is a bounded initial dispatch, not a background matching scheduler or
radius-expansion/retry engine. Separate RPC calls are not one transaction; earlier
successful offers survive a later conflict and are recovered on the next request.
`awaitingDriver` reports a canonical `offered` record, not a guarantee its deadline
has not elapsed. A04 remains the sole expiry/acceptance authority; authorized cleanup
must reconcile overdue records. `noCandidates` describes that bounded search snapshot.

The constructor's URL/keys/bearer must come from trusted, reviewed server request
composition, never request JSON. Future endpoint wiring must add its own approved
registry, request validation, operational limits and authorization review. Auth/profile
checks do not claim instantaneous JWT revocation or knowledge of a device logout
after dispatch. No such endpoint was implemented or deployed in this checkpoint.

### Rider assignment read

`lib/core/repositories/cash_booking_assignment_repository.dart` exports:

- `CashBookingAssignmentRepository.read(ConfirmedBookingReference)`
  returning `Future<AssignedCashTrip?>`.
- `CashAssignmentReadTransport` and `SupabaseCashAssignmentReadTransport(client,
  namespace, epochReader)`.
- `AssignedCashTrip`: exact Trip, Offer, Booking, Quote, Driver and Vehicle IDs,
  Trip version/status, locked fare and captured `RiderAssignmentOwner`.

This consumes the existing BookingHandoff locator, PendingFareLock versions,
FareQuote parser/equality, locked-snapshot validator, canonical UUID validator and
DriverTripLifecycleStatus. It does not add a parallel booking model/provider.
The original lock command version + two establishes the minimum confirmed booking
version; subsequent search/match versions are allowed. The typed locked FareQuote
must equal the original reference. Raw database snapshots additionally verify
pickup/destination/category, route distance/duration/geometry and ordered stops.
Original fare is immutable lineage; later legitimate current-fare changes are not
misrepresented as a new quote or a Payment result.

Confirmed/searching returns null (pending), never a fabricated Trip. Matched must
resolve exactly one linked Trip and accepted offer, with matching Rider, Driver,
vehicle, quote, Cash method, JOD, original fare and route/stops. Wrong/missing IDs,
foreign ownership, malformed aggregates and Card fail closed. Errors are sanitized.
No Payment/Receipt is queried or inferred from a Booking/Trip ID.

The SDK transport performs GETs only: profile, one embedded booking aggregate,
profile again. Explicit FK relationships are `fare_quotes_booking_rider_fk`,
`trips_booking_request_id_fkey`, `driver_match_offers_booking_request_id_fkey`.
The SQL test checks these constraints exist. SDK tests assert actual request paths,
Rider bearer and owner filters. Wildcard columns are read only within those existing
RLS aggregates; no financial table joins occur. Actual PostgREST relationship
resolution remains NOT RUN against a Supabase runtime.

Namespace, owner, application epoch and SDK Session identity are pinned across
asynchronous reads, including errors. The future caller must advance epoch on every
logout/account/lifecycle replacement, including A-B-A, and recheck the returned owner
before retaining/publishing it later. The repository bounds reads to 15 seconds and
owns no long-lived UI state. SDK tests cover real Session replacement during response.

## Security and unchanged financial contracts

No SQL privileges or actor checks change. Flutter cannot call privileged matching
RPCs through this adapter. Only the server port accepts a service credential.
No new payment transitions, Stripe calls, Card activation or financial operations
were added. In the disposable SQL fixture only, existing Driver acceptance invokes
the existing Phase 6 compatibility wrapper: one `cashSelected` Payment, zero
provider Attempts, zero Receipts. The tests do not settle or collect Cash.

## Actual local verification

Commands, from the assigned worktree:

```powershell
python supabase/tests/ops/p7_a02_local_test.py
python supabase/tests/ops/p7_a04_concurrency_test.py
python supabase/tests/ops/r06_x2_local_test.py --existing-new-container ridex-r06-x2-939216bd3454
deno test --no-config supabase/functions/_shared/matching/cash_matching_adapter_test.ts
deno check --no-config supabase/functions/_shared/matching/cash_matching_adapter.ts
deno fmt --check supabase/functions/_shared/matching/
dart format lib/core/repositories/cash_booking_assignment_repository.dart test/cash_booking_assignment_repository_test.dart test/architecture_boundary_test.dart
flutter test --no-pub test/cash_booking_assignment_repository_test.dart test/architecture_boundary_test.dart
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
git diff --check
```

Fresh PostgreSQL 17.11 image `public.ecr.aws/supabase/postgres:17.11.0.006`:
main/Phase 6 cluster `ridex-r06-x2-939216bd3454`; independent A04 races cluster
`ridex-r06-x2-b2da98fcde5c`. Network none, no ports/mounts; each file/scenario gets
a fresh database clone. Four final full 34-migration replays (main, A04 runner,
two Phase 6 bases) completed with exact migration history and zero recovery approvals.
The original Supabase stack and hosted databases were not touched. New disposable
resources remain for review; no existing container or volume was stopped/removed.

| Verification | Passed | Failed | Skipped |
|---|---:|---:|---:|
| Main database suite, 31 complete files | 1,317 | 0 | 0 |
| Included new A05 SQL assertions | 55 | 0 | 0 |
| Additional Phase 6, 14 files | 252 | 0 | 0 |
| Deduplicated SQL, subtract 39 repeated Cash checks, 43 files | 1,530 | 0 | 0 |
| Real A04 independent-session scenarios | 19 | 0 | 0 |
| Real Phase 6 independent-session scenarios | 16 | 0 | 0 |
| Deno server composition/REST-port tests | 32 | 0 | 0 |
| Focused Flutter: 47 new + 5 architecture assertions | 52 | 0 | 0 |
| Complete Flutter suite | 1,711 | 0 | 2 |

The two intentional live skips are `live_supabase_auth_test.dart` and
`live_supabase_role_state_test.dart`; no hosted environment was intentionally
configured. Analyzer: zero issues. Deno type/format checks and Git whitespace: PASS.

New SQL follows genuine Rider draft/quote lock/Cash confirmation, A03 discovery,
A04 offer and authenticated Driver acceptance (not direct inserts of a matched Trip).
It proves immutable entire FareQuote, two ordered stops/note, initial fare, all IDs,
route/currency, idempotent confirmation/offer/accept retries, stale versions,
unauthorized privileged calls, foreign Rider aggregate RLS and no settlement/provider
side effects. A02/A03/A04, Phase 3 security/lifecycle, Phase 5 and Phase 6 regressions pass.

Real races reused unchanged A04/Phase 6 harnesses, with observed lock waiters and
no accepted deadlock/timeout outcomes, including cancellation vs acceptance,
expiry/rejection, two Drivers/one booking, one Driver/two bookings, rollback,
Driver/Rider blocking, vehicle changes and GPS movement. Mock tests are not counted
as PostgreSQL concurrency evidence.

Development failures are excluded from final results: the first A05 SQL run stopped
at a wrong Payment column (`status` instead of `cash_status`); a Dart fixture duplicate
used an incompatible inferred map type; initial analysis found a missing brace;
the first full Flutter run found the missing SDK infrastructure allowlist entry.
All were corrected narrowly and affected/full checks rerun successfully.

## Phase 6 and hosted stop/resume gates

- **P6-R05:** the latest roadmap/closeout accepts bounded completed-Cash Rider reads
  on prior owning-Rider SDK/device attestation and foreign-Rider denial. That is not
  hosted acceptance of this new assignment reader. Existing finance reader keeps
  its actual Trip-to-Payment-summary lookup; A05 does not replace it.
- **P6-R07:** fixture preparation/tooling and completion evidence scope do not prove
  natural matched-ride integration. No fixture operator or hosted completion was run.
- **P6-R08 Cash integration gate:** source Cash-only confirmation and local tests pass.
  Phase 5 owner acceptance records prior scoped owning-Rider hosted/API/Android
  confirmations; sequential Android and multi-stop device exit limitations remain.
  Neither that historical evidence nor R08's broader Stripe-UI scope proves A05
  hosted Booking-to-Trip acceptance. Stop hosted A05 until separately authorized.
- **P6-R06/R08 Card:** HARD BLOCK for provider/Card activation; remains disabled.
- **P6-R09:** Phase 6 NOT APPROVED; exit disposition belongs to owner/integration review.

Resume hosted acceptance only after owner authorization identifies approved
nonproduction project/namespace, allowed actors and fixture mutations; read-only
migration/catalog/RLS parity and A04 duplicate-active-Trip index preflight pass;
trusted endpoint/registry and consumer session epochs are reviewed; then execute
owned-Rider confirmed locked Cash -> eligible Driver -> offer -> authenticated
Driver acceptance, exact IDs/unchanged quote/route/stops, foreign-Rider denial,
lost response and session changes with sanitized evidence. No completion,
collection, provider dispatch or receipt issuance is implied by that authorization.
Hosted GoTrue/PostgREST/Realtime/device/end-to-end acceptance is **NOT RUN** here.

A03/A04 GPS remains <=60 seconds recorded/received age, <=50 m accuracy and <=5 s
future skew; Flutter available-mode may publish as slowly as 120 seconds. The mismatch
remains a live integration blocker: agree/review cadence separately; do not loosen
backend policy here. A04 offer expiry cleanup still needs an authorized scheduler
and liveness evidence; adapter reads do not substitute for cleanup. Fifteen-second
offers, ninety-second search and existing offer limits remain unchanged.

## Shared boundaries and final scope

- Omar: Realtime is a notification to reread canonical assignment, not Trip authority.
- Moath: Driver owns authenticated offer decline/acceptance via existing RPCs and
  versions/keys; server composition never accepts on the Driver's behalf.
- Sanad: tracking consumes only actual `AssignedCashTrip.tripId` and canonical Trip
  version/status; recheck owner, then use existing participant Trip readers. No
  Payment ID derivation or mock ID fallback.
- All: adapters remain unwired. No teammate feature/GPS/Realtime file changed or
  unmerged branch dependency introduced. No production activation is claimed.

Exact pending files (six new, one existing two-line allowlist addition):

1. `lib/core/repositories/cash_booking_assignment_repository.dart`
2. `supabase/functions/_shared/matching/cash_matching_adapter.ts`
3. `supabase/functions/_shared/matching/cash_matching_adapter_test.ts`
4. `supabase/tests/database/20261104140000_p7_a05_cash_booking_trip_integration.test.sql`
5. `test/cash_booking_assignment_repository_test.dart`
6. `test/architecture_boundary_test.dart` (modified)
7. `docs/ai/verification/P7_A05_LOCAL_INTEGRATION_VERIFICATION_2026-11-04.md`

No generated/config/credential/lockfile changes, no staging, commit, push, PR,
merge, issue closure, deployment, hosted mutation or A06 work. Source branch/HEAD
remain unchanged. Local A05 is ready for owner review; hosted acceptance stays blocked.

