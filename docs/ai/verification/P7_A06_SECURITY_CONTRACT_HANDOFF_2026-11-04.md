# RideX Phase 7 A01–A06 Security and Integration Handoff

**Contract revision:** 1.0.0 (database/RPC contracts at source commit `aa868023d18c56b2875dc4718f2370f4f84391c9`)
**Review:** P7-A06 local independent security assessment. No hosted acceptance, approval, or production matching activation is implied.

## Baseline and exact cause of the prior BLOCKED report

Worktree `RideX-Phase7-Yousuf`; branch `feature/p7-a-matching-backend`; HEAD `aa868023d18c56b2875dc4718f2370f4f84391c9`; initial worktree clean, no merge/rebase operation. Issue #94 and `Phase 7/Yousuf.md`, A04/A05 verification, current Phase 6 roadmap/tracker, migrations, RPC inventory tests, RLS tests, adapters, and race harnesses were reviewed. Only the assigned branch was used.

The prior BLOCKED verdict was an execution omission: the previous response stopped before starting A06. Repository files, permissions, and disposable DB infrastructure are available. Missing P6 hosted evidence gates the live integration portion only, as Issue #94 explicitly directs. No critical local security finding required stopping review.

## Security assessment

**Critical: none found in the reviewed local implementation.** No local finding currently blocks commit. The adapters are unwired, and the hosted gate matrix below is still open.

- **RPC boundary — VERIFIED locally.** `013_phase3_rls_rpc_hardening.test.sql` enumerates expected backend signatures, compares the exact catalog inventory, asserts backend RPC execute privilege is service-role-only, and asserts API clients cannot invoke private helpers. A03 discovery checks service role in its security-definer body; A04 creation/expiry also have server-role boundaries. A04 Driver decline and `driver_transition_trip` are authenticated-only and still validate `auth.uid()` as the approved, nonblocked offer owner. A02 availability/vehicle changes are authenticated-only and validate actor/eligibility. The local bootstrap is not hosted PostgREST evidence.
- **RLS and identity — VERIFIED locally; hosted NOT RUN.** `002_enable_rls_and_policies.sql`, later security hardening, participant-table RLS, A04 offer tests, and A05 embedded-aggregate tests cover own/foreign Rider visibility and foreign Driver decline. A05 SDK transport checks a nonblocked Rider profile, reads using SDK session with owner filters, pins namespace/epoch/session identity across asynchronous completion, and sanitizes read failures. The caller must advance epoch on every account/session lifecycle change and recheck ownership before publishing later state. JWT revocation after an in-flight request and GoTrue/PostgREST behavior were not independently tested here.
- **Eligibility and stale observations — VERIFIED locally.** A02 approved/nonblocked Driver, active owned vehicle, availability state and optimistic versions feed A03/A04. A03 sorts latest location sequence before quality checks and fails closed for stale, inaccurate, future or Trip-associated GPS. A04 recomputes the current location at offer creation and checks Driver, Rider, booking, locked Cash quote, vehicle/category, current booking version, radius, search/offer limits and existing Trip/reservation under locks. Candidate discovery itself is read-only.
- **Assignment and retries — VERIFIED locally.** A04 uses one authenticated Driver acceptance RPC and the existing Phase 6 assignment/payment wrapper. A unique partial index prevents multiple nonterminal Trips per Driver; booking/offer/availability locks serialize competing claims. The transaction rollback pgTAP fault injection verifies no partial Trip/reservation/offer/idempotency state. Idempotent retry and lost-response paths reread canonical state. The A05 composition adapter does not accept for a Driver and does not replay an unknown write; it rereads and returns unknown if no canonical effect is visible.
- **Input/errors/audit — VERIFIED for the tested RPC paths.** Search radius/result limit, versions, IDs, status, deadline and caller ownership have database guards; SQL error messages are sanitized and audit transition records omit precise GPS. A05 verifies linked IDs, locked quote, route/stops and accepted offer before returning actual Trip ID. The server REST adapter takes identifiers only, has request timeouts and has no entrypoint. Its URL, Rider bearer, and service credential must only be supplied by a separately reviewed trusted composition; request JSON must never set credentials. Do not wire the adapter directly to Flutter or expose it publicly without authentication, registry and abuse-limit review.
- **Money and Card — VERIFIED locally.** New matching path accepts Cash only; no A05 Payment/Receipt join or ID inference exists. The existing acceptance wrapper creates its existing Cash-selected Payment row; tests assert no duplicate attempt or receipt. No settlement/provider operation is added. Card/Stripe is disabled and remains a hard block.

## Stable shared contracts (implemented unless marked PROPOSED)

**Database actors and operations:**

| Operation / exact signature | Permitted actor and inputs | Result / meaning |
|---|---|---|
| `driver_set_availability(public.driver_availability_state, uuid, integer)` | Authenticated approved Driver; requested state/vehicle/version | Versioned `offline`/`available`; cannot self-assign `reserved` or `onTrip` |
| `driver_record_location(uuid, bigint, double precision, double precision, double precision, double precision, double precision, timestamptz)` | Authenticated Driver; own Trip association, increasing sequence, coordinates/quality/time | Server-recorded observation; canonical database observation sequence is authoritative |
| `backend_find_nearby_driver_candidates(uuid, integer, integer default 3000, integer default 3)` | service role; booking ID, expected booking version, allowed radius `3000/5000/8000`, limit `1..3` | Rows: `driver_id, vehicle_id, availability_version, vehicle_version, location_sequence, distance_meters`; discovery does not reserve or create offer |
| `backend_create_driver_match_offer(uuid, uuid, uuid, integer, integer)` | service role; booking, Driver, vehicle, radius, current expected booking version | Canonical `driver_match_offers` row; revalidates current eligibility/GPS/quote/version; offer lifetime 15 seconds; search window 90 seconds; A04 limit applies |
| `driver_decline_match_offer(uuid, integer, text)` | Authenticated owner Driver; offer ID, expected offer version, idempotency key | Canonical offer row; stale/foreign/conflicting retry errors; eligible decline releases reservation |
| `driver_transition_trip(uuid, public.trip_status, integer, text)` | Authenticated owner Driver; existing offer/Trip ID, transition, version, idempotency key | Existing result JSON; `accepted` creates/assigns canonical Trip atomically; idempotent retry returns canonical result |
| `backend_expire_booking_match_offers(uuid, integer)` | service role/scheduler only; booking ID/current version | Booking row after expiry cleanup; no scheduler is installed by these commits |
| `rider_create_booking_draft(jsonb,jsonb,public.vehicle_type_code,public.payment_method,jsonb)`; `backend_calculate_fare_quote(uuid,integer,integer,integer,text)`; `backend_lock_fare_quote(uuid,integer,integer)`; `rider_confirm_booking(uuid,integer,text)` | Rider draft/confirmation, trusted pricing/lock services; IDs, versions, and idempotency key | Canonical Booking and locked FareQuote; current confirmation policy is Cash-only |

Database enums/states are canonical: availability `offline`, `available`, `reserved`, `onTrip`; Trip `accepted`, `driverArriving`, `driverArrived`, `inProgress`, `completed`, `cancelledByRider`, `cancelledByDriver`, `cancelledByAdmin`, `failed`; offer states include `offered`, `accepted`, `declined`, `expired`, `cancelled`. Do not substitute mock UI states for these values.

**Trusted composition (implemented, unwired):**

`CashMatchingAdapter.request(bookingId: string, quoteId: string, expectedVersion: number): Promise<MatchingResult>` in `supabase/functions/_shared/matching/cash_matching_adapter.ts`. `MatchingResult` contains `bookingId`, `fareQuoteId`, `state: awaitingDriver | noCandidates | assigned`, and only for `assigned` a validated `tripId`. `awaitingDriver` means a canonical offered row exists; it does not promise the deadline remains live. `noCandidates` means this bounded search snapshot produced no candidates. Errors are sanitized as `unauthorized | invalid_request | invalid_state | conflict | unknown`. `CashMatchingPort` is the fakeable seam. The concrete REST port accepts trusted server URL/public key/Rider bearer/service key and calls only A03 discovery and A04 offer-creation service RPCs. It does not call Driver acceptance. Never expose service credentials or this service-only port in Flutter.

**Rider read (implemented, unwired):**

`CashBookingAssignmentRepository.read(ConfirmedBookingReference): Future<AssignedCashTrip?>` and `SupabaseCashAssignmentReadTransport(client, namespace, epochReader)` in `lib/core/repositories/cash_booking_assignment_repository.dart`. Confirmed/searching returns null (pending); matched returns only the unique actual Trip after checking Booking, FareQuote, accepted Offer, Rider, Driver, vehicle, Cash/JOD, original fare, route, stops, Trip status/version and current owner. Failure enum: `unauthorized | invalidReference | invalidResponse | unavailable`. No matching initiation is exposed by this Rider repository.

**Owner handoff:**

- **Omar — Realtime/GPS:** `driver_locations.sequence`, server `received_at`, observation `recorded_at`, `trip_id`, and accuracy are evidence; use the newest sequence and never fall back to an older high-quality point. Backend requires recorded/received age <=60 seconds, accuracy <=50 m, future device skew <=5 seconds and no future server receipt. Flutter available publishing may be as slow as 120 seconds. Decide/review cadence jointly; do not loosen the SQL freshness bound in this handoff. A Realtime event should prompt an authenticated canonical reread. It is not an assignment/status authority. Session-owned location publication and UI implementation remain outside this branch.
- **Moath — Driver UI:** offers arrive through an approved trusted delivery integration (none is implemented here). Show the exact offer/booking ID and expiry from the database row. Driver can decline through `driver_decline_match_offer(offerId, expectedOfferVersion, idempotencyKey)` or accept through `driver_transition_trip(offerId, 'accepted', expectedOfferVersion, idempotencyKey)`. Re-read canonical offer/Trip on retry/unknown response; never create a Trip in UI. A04 offer is 15 seconds; search is 90 seconds. Exact decline/accept response is canonical row/result; stale version `40001`, expired/non-live `55000`, foreign/missing offer `P0002`, authorization `42501`, conflicting key `23505`. Driver screen remains unwired to this backend.
- **Sanad — Rider UI/Tracking:** begin from existing `ConfirmedBookingReference` (original booking ID, locked quote ID/version, original booking version, Rider ID plus typed locked FareQuote), not arbitrary fare/payment/driver input. Matching initiation through the trusted server adapter is **not available to the Flutter client**; an application-facing authenticated endpoint is **PROPOSED** and requires separate design/review. Resolve by `CashBookingAssignmentRepository.read(reference)`. Loading/pending => null; unauthorized/session changed => discard result and reauthenticate; invalid linked snapshot => fail closed and surface sanitized error; unavailable => retry read-only; no candidate => bounded no-match message/retry per product owner; assigned => use returned actual Trip ID/status/version and canonical Trip reader. For a later terminal Trip, preserve existing Rider payment/receipt readers and their genuine Payment ID source; never derive Payment ID. `cancelledBy*`, `failed`, or completed Trip is terminal according to the canonical enum. Rider UI/tracking remains unwired.

## Phase 6 and live integration gate matrix

| Gate | Classification | Evidence and exact safe unblock action / owner |
|---|---|---|
| P6-R08 Cash handoff | **INTEGRATION GATE / BLOCKED for A05 hosted acceptance** | Cash-only confirmation source and local SQL tests pass; Phase 5 owner evidence contains scoped prior Cash confirmations, not this matched Booking-to-Trip flow. Integration owner: authorize named nonproduction namespace/actors/fixture mutations, then capture exact owned Booking/locked Quote/accepted Offer/Trip IDs, unchanged fare/route/stops, session and foreign-Rider denial. |
| P6-R07 | **BLOCKED** | Preparation/operator tooling is not natural matching or A05 hosted evidence. Owner: run the authorized isolated nonproduction fixture only after endpoint/namespace/actors and lifecycle are approved; record sanitized before/after evidence. |
| P6-R09 | **BLOCKED exit gate** | Phase 6 roadmap states NOT APPROVED. Integration/financial owner records disposition for R01–R08, evidence and remaining device tails; A06 does not approve Phase 6. |
| P6-R06/R08 Card/Stripe | **BLOCKED / hard stop** | No Card matching/authorization/dispatch/Stripe operations. Resume only under separate approved Phase 6/8 design and security gates; not an A06 action. |
| GPS 60 s vs up-to-120 s publisher | **BLOCKED live eligibility contract** | A03/A04 SQL and Flutter publisher contract; no local policy change. Omar/integration owner agrees supported cadence or separately reviews proposed policy; prove current fixes meet freshness on supported devices. |
| Offer expiry scheduler | **NOT RUN / liveness gap** | A04 service expiry RPC exists but no scheduler is installed. Operations/backend owner proposes and authorizes scheduler identity, cadence, least-privilege invocation and observable cleanup; demonstrate expiry releases reservation. Until then cleanup is command-driven, not autonomous. |
| Duplicate-active-Trip deployment preflight | **NOT RUN / deployment gate** | Before applying A04 migration, perform read-only query below on target, confirm zero conflicts, backup/rollback window and expected catalog/grant parity. Deployment owner captures sanitized result. Do not auto-repair rows. |
| Hosted GoTrue/PostgREST/RPC grants and embedded relationships | **NOT RUN** | Local PG/bootstrap and SDK loopback tests do not prove hosted JWT/RLS/catalog/PostgREST FK embedding. Authorized integration owner runs read-only catalog/grant/RLS and owned/foreign authenticated requests on approved nonproduction project. |
| Realtime wiring | **NOT RUN** | No endpoint/channel/subscription/consumer in A04/A05. Omar and endpoint owner review event schema/auth/filters, prove notification-only canonical reread and owner/session cleanup; do not claim event-based assignment. |
| Rider/Driver real-device E2E | **NOT RUN** | No device acceptance for matched ride. Sanad/Moath/owner run approved synthetic Cash scenario after cadence, expiry, endpoint and P6 gates; assert IDs, session changes, rejection and terminal tracking. |

### Required read-only A04 migration preflight

A04 creates `trips_one_nonterminal_per_driver_idx` and deliberately fails instead of repairing conflicting live rows. On the exact target database, before deployment, run and retain sanitized output:

```sql
select driver_id, count(*) as nonterminal_trip_count
from public.trips
where status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed')
group by driver_id
having count(*) > 1;
```

Expected zero rows. If any row appears, stop; the data owner investigates and authorizes an explicit repair plan. Do not run deployment/reset/mutations as part of preflight. Then compare all 34 expected migration versions, the exact unique-index predicate, RPC signatures/grants, RLS table access and empty search paths using read-only catalog queries. A local PASS cannot replace this target-specific evidence.

## Independent-session failure and race evidence

A04's real PostgreSQL runner uses separate sessions and observed `pg_blocking_pids` barriers, not timing sleeps/mocks. The 19 cases cover competing Drivers/one booking, duplicate acceptance/lost response, rollback then contender success, acceptance vs expiry in both orders, decline vs accept in both orders, cancellation vs acceptance in both orders, offer vs Driver/Rider blocking both orders, offer vs vehicle category both orders, GPS update after discovery before offer, one Driver/two Bookings, audit/FK lock race and accepted retry vs Trip cancellation. Latest fresh run completed all 19 with no deadlocks/timeouts. The A02 11 real version races and Phase 6 16 separate races are reported individually; do not aggregate them into A04's count.

## Reproduction commands and evidence boundaries

Run from `RideX-Phase7-Yousuf`; Python runners create new network-isolated PostgreSQL containers with no ports or mounted volumes and retain them for review. They do not reset the existing Supabase stack. Full commands:

```powershell
python supabase/tests/ops/p7_a02_local_test.py
python supabase/tests/ops/p7_a04_concurrency_test.py
python supabase/tests/ops/r06_x2_local_test.py --existing-new-container <fresh-p7-a06-container>
deno test --no-config supabase/functions/_shared/matching/cash_matching_adapter_test.ts
deno check --no-config supabase/functions/_shared/matching/cash_matching_adapter.ts
deno fmt --check supabase/functions/_shared/matching/
flutter test --no-pub test/cash_booking_assignment_repository_test.dart test/architecture_boundary_test.dart
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
git diff --check
```

`p7_a02_local_test.py` applies the lexical 34-migration sequence and executes Phase 3–6, A02–A05 pgTAP including explicit security grants/RLS. It includes 55 A05 assertions, and its final reported total is 1,317 (not an independent 1,317 + 55 sum). The R06-X2 runner reports an additional 252 pgTAP assertions and 16 real races. Deduplicated cross-run total: 1,530 = 1,317 + 252 - 39 repeated assertions. A04 concurrency is a separate 19 real races. Flutter test suite has two configured live Supabase skips when no live credentials are configured; never count them as PASS.

## Final A06 execution results

| Check | Passed | Failed | Skipped |
|---|---:|---:|---:|
| Main isolated database suite, 31 files | 1,317 | 0 | 0 |
| Dedicated A05 assertions included above | 55 | 0 | 0 |
| Additional Phase 6 suite | 252 | 0 | 0 |
| Deduplicated SQL total, 43 distinct files | 1,530 | 0 | 0 |
| A04 real independent-session race scenarios | 19 | 0 | 0 |
| R06 real independent-session races | 16 | 0 | 0 |
| Deno adapter tests | 32 | 0 | 0 |
| Focused Flutter repository/architecture tests | 52 | 0 | 0 |
| Full Flutter suite | 1,711 | 0 | 2 intentional live skips |
| Flutter analyzer | 0 issues | 0 | n/a |

All 34 migrations replayed. Main database runner used new network-none/no-port/no-mount PostgreSQL 17.11 container `ridex-r06-x2-d94589932740`; independent A04 concurrency and R06-X2 runners used isolated disposable clusters. R06-X2 replayed the full migration chain twice. The original Supabase stack was not touched. Deno type/format and `git diff --check` passed. Hosted GoTrue/PostgREST/Realtime/device tests are NOT RUN.

Security scope did not change source code or tests in A06: existing negative/grant/RLS regressions and observed independent-session races cover the identified local security questions. Hosted checks and Phase 6 acceptance remain NOT RUN/BLOCKED as classified above.

## Suggested PR text for A04–A06 (proposal only; no PR created)

**Title:** Phase 7 A04–A06: harden matching assignment and document integration contracts

**Description:** A04 adds mutation-time candidate revalidation, versioned offer rejection/expiry, atomic Driver acceptance, deterministic locking and one-nonterminal-Trip-per-Driver protection. A05 adds an unwired trusted A03/A04 composition adapter and a session-bound Rider reader for the canonical Cash Booking -> locked FareQuote -> Offer -> accepted Trip lineage. A06 independently reviews SQL grants/RLS, actor boundaries and 19 real A04 PostgreSQL race scenarios, then records the exact Omar/Moath/Sanad contract and deployment gates. Local database, adapter, Flutter and concurrency results should be copied from their checkpoint reports and tied to the PR head after final CI reruns. State clearly that hosted/PostgREST/Realtime/device acceptance and scheduler liveness remain NOT RUN, P6-R09 remains open, GPS cadence remains mismatched and no live matching/Card activation occurred. Reference Issues #92–#94 without closing keywords. This PR description is proposed and must not imply A01–A03 are unmerged; they are already merged by PR #118.

## Final A06 disposition

Local security and handoff review completed; no critical defect found in examined source. No additional safeguard/regression was necessary because the existing grant inventory, A04/A05 negative pgTAP, actor/RLS checks and independent-session races cover identified local risks. No SQL/test implementation was changed. Local suite results are recorded above. Hosted integration is a separate gate, not a reason to block local A06. No issue update, commit, push, merge, deployment or A06 activation was performed.
