# P7-A04 - Offer lifecycle and atomic acceptance

## Baseline and scope

Issue #92. Assigned branch `feature/p7-a-matching-backend`, worktree
`RideX-Phase7-Yousuf`. Started clean at `201830c`, preserving the owner's existing
merge of current main (`c9ebffa`, PR #118) and the earlier feature commits.
No branch switching, reset, rebase, merge, commit, push or hosted operation.
Issue #92 and `Phase 7/Yousuf.md` were read; source migrations 005-017, 024,
P7-A02/P7-A03 and their recorded evidence were the contract authority.

Existing architecture reused: booking_requests, fare_quotes, driver_match_offers,
driver_availability, vehicles, driver_locations, trips, command_idempotency_keys,
existing reservation/release triggers, audit records and the existing Phase 6
Trip/payment wrapper. No new matching tables or duplicate acceptance RPC.

## Public contracts

New:

- `driver_decline_match_offer(target_offer_id uuid, expected_offer_version integer,
  idempotency_key text) returns driver_match_offers`: authenticated only; actor is
  auth.uid(), must be approved/nonblocked Driver and own the offer. Reuses command
  idempotency with a distinct decline fingerprint. Conflicting keys fail 23505.
- `backend_expire_booking_match_offers(target_booking_request_id uuid,
  expected_booking_version integer) returns booking_requests`: service-role only,
  positive/current booking version; an already-expired booking is safe recovery.

Existing signatures retained:

- `backend_create_driver_match_offer(uuid,uuid,uuid,integer,integer)`.
- `driver_transition_trip(uuid,trip_status,integer,text)`.
- `service_reserve_driver_for_booking(uuid,uuid,uuid,integer)`.
- `service_release_driver_reservation(uuid,uuid,integer)`.
- `backend_find_nearby_driver_candidates(uuid,integer,integer,integer)`.
- `admin_reject_driver(uuid,text)` and `admin_set_user_blocked(uuid,boolean,text)`.

All new privileged implementations have fixed empty search_path. Catalog tests
and inspection verified no anon access, authenticated decline/Trip-only access,
service-only expiry/creation, and no API-role EXECUTE on private helpers or the
preserved Phase 6 wrapper. No RLS policy/table grant was broadened. The explicit
backend inventory gains only the new expiry signature (23 backend signatures).

## Offer creation and retry

Creation pins Driver eligibility, Rider eligibility, booking, existing offers,
availability and vehicle. It checks current approved/nonblocked Driver, owned
active category-compatible vehicle, available or same-booking reserved state,
no active Trip, confirmed/searching unmatched Cash booking with its own locked
quote, matching Rider/pickup/category, current booking version, supported radius,
three-offer limit and search window.

A03 GPS math/filtering is factored into private.current_matching_gps; discovery
and creation share the exact policy: latest sequence first, unassociated with a
Trip, recorded and received age <=60 seconds, device skew <=5 seconds relative
to current time AND receipt, no future receipt, accuracy <=50 metres. Haversine
uses the same mean-Earth radius and one-micrometre comparison tolerance.
Creation obtains current clock_timestamp and newest GPS after availability locks
(the canonical GPS writer uses that same row). A stale candidate list is never
assignment authority; a newer valid fix is recomputed and its sequence audited.
No caller coordinates, fare, Payment status or application Driver identity are used.

The existing unique booking/Driver pair is the creation retry identity. Same pair,
vehicle and radius returns the same canonical offer even after booking version
advances. Changed vehicle/radius conflicts. Recovery may return a terminal or
past-deadline offer; it never resurrects it, extends its deadline, reserves again,
or asserts it is still live. A Driver is not offered twice for one booking.

New offers retain exactly 15-second expiry; search begins on first offer and
retains the 90-second window. Timings use wall clock after lock waits rather than
transaction-start now().

## Lifecycle and liveness

- Creation: no offer -> offered; availability available -> reserved.
- Owner rejection: offered -> declined; exact reservation released to available.
- Deadline cleanup: offered -> expired; exact reservation released.
- Search timeout: searching booking -> expired, all open offers -> expired,
  all matching reservations released.
- Rider cancellation: existing cancelled transition cancels offers and releases.
- Acceptance: winner offered -> accepted, other open offers -> cancelled,
  booking -> matched, winner -> onTrip, other reservations released.
- Service reservation release now cancels its outstanding live offers before
  releasing, so it cannot leave an apparently live offer holding no reservation.

Decline and creation lost-response retries return canonical state without new
transitions. A decline crossing its deadline returns expired and stores that
actual canonical result; repeating it remains safe. Terminal recovery intentionally
permits the original positive stale version; new state-changing requests still
require current versions. Audit transitions occur once and contain IDs/status/
sequence only, never precise GPS or route data. Failed statements roll back.

The expiry RPC is an explicit service operation, NOT an installed scheduler.
No cron/worker/provider is deployed or activated. A future authorized service must
invoke it to materialize idle expiry and release reservations. Until then,
deadlines are enforced by commands but cleanup liveness is not autonomous.

## Acceptance, locking and rollback

A new public prelude delegates to the unchanged preserved Phase 6 implementation.
Non-accept transitions delegate directly. Acceptance checks owner/current
eligibility, offer version/deadline, current search window and Rider state, and
existing nonterminal Trip. The original assignment still creates Trip/stops,
sets matched identity, updates availability and writes idempotency/status events.
The existing ensure_trip_payment behavior is preserved; no new financial
transition, settlement or provider call is introduced. Historical Card Trip
compatibility is retained, while ALL new offer creation is Cash-only.

Normal lock order: Driver users/profile NO KEY UPDATE -> Rider eligibility where
needed -> booking -> all booking offers ordered by UUID -> availability ordered
by Driver UUID -> vehicle. Reservation functions no longer acquire availability
before booking. Competing acceptance does not lock its offer before waiting for
the booking. Existing Rider cancellation already starts with the booking.

Blocking/rejection now use NO KEY UPDATE for non-key user/profile changes; this
still serializes eligibility but avoids a cycle with audit/location FK key-share
reads of a losing Driver. Accepted-offer retry does NOT pin availability before
Trip recovery, avoiding an inversion with concurrent Trip cancellation/completion.
Both hazards have controlled, independent-session regressions.

`trips_one_nonterminal_per_driver_idx` enforces one nonterminal Trip per Driver
for every write path, complementing the existing one-Trip-per-booking uniqueness
and RPC locks. Migration fails closed if an eventual target has pre-existing
conflicting assignments. Authorized deployment must preflight that data; no
implicit cleanup or hosted inspection was performed.

## Changed files

Production: only the new additive migration
`supabase/migrations/20261104100311_p7_a04_offer_lifecycle_atomic_acceptance.sql`.
Historical applied migrations were not edited.

New tests/support:

- `supabase/tests/database/20261104100311_p7_a04_offer_lifecycle.test.sql`
- `supabase/tests/fixtures/p7_a04_matching.sql`
- `supabase/tests/fixtures/p7_matching_fixture_drivers.sql`
- `supabase/tests/ops/p7_a04_concurrency_test.py`

Existing regressions:

- `007_phase3_booking_fare_matching_foundation.test.sql`: fresh GPS fixture and
  same-pair recovery expectation; uniqueness/capacity assertions preserved.
- `013_phase3_rls_rpc_hardening.test.sql`: add explicit expiry RPC inventory.
- `010_phase3_payment_state_verification_hardening.test.sql`,
  `021_phase3_post_merge_hardening.test.sql`,
  `022_phase3_final_payment_lifecycle_remediation.test.sql`: independent synthetic
  Drivers/owned vehicles for simultaneous Trip scenarios; original financial
  assertions retained. The 022 rollback actor follows its new fixture owner.
- `fixtures/r06_card_context.sql`, `fixtures/r06_retirement_target.sql`, and
  `20261027192343_r06_retirement_guard.test.sql`: same fixture-only correction;
  the retirement target has its own Driver and the availability check follows it.
  No financial expectations/provider behavior were relaxed or changed.

This document is the checkpoint evidence; no Flutter/GPS/Realtime files changed.

## Final local execution

```powershell
python supabase/tests/ops/p7_a02_local_test.py
python supabase/tests/ops/p7_a04_concurrency_test.py
python supabase/tests/ops/r06_x2_local_test.py --existing-new-container ridex-r06-x2-005002e74801
git diff --check
```

Fresh network-none/no-port/no-mount PostgreSQL 17.11 clusters:
main/Phase 6 `ridex-r06-x2-005002e74801`, A04 races
`ridex-r06-x2-2d203b5352b4`. Each suite file/scenario gets a fresh database clone;
all 34 migrations replayed with exact history and no provisioned recovery approvals.
The Phase 6 runner performs two further full canonical replays.
Original Supabase containers, hosted projects and other worktrees were untouched.
Synthetic finance regression rows exist only in disposable databases; no provider
requests or real financial operations occurred. Resources remain for review.

Main suite: **1,262 PASS / 0 FAIL / 0 SKIP**, 30 complete files, exit 0.
Includes **50 A04 pgTAP**, **56 A02 authored assertions**, **69 A03 assertions**,
security/RLS, Driver lifecycle and existing real dblink regressions.
A04 runner: **19 PASS / 0 FAIL independent-session races**, exit 0. Every case
observes actual pg_blocking_pids/lock waits before releasing the winner; no sleeps
or mocks substitute for concurrency. No 40P01 deadlock/timeout was accepted as PASS.

Cases: two Drivers/one booking; duplicate acceptance/lost response; first winner
rollback; accept vs expiry (both orders); decline vs accept (both orders); booking
cancel vs accept (both orders); offer vs Driver block (both orders); offer vs Rider
block (both orders); offer vs category change (both orders); real GPS upload after
discovery/before offer; one Driver/two bookings with injected legacy conflicting
offers; competing-Driver blocking vs acceptance audit FK; accepted retry vs Trip
cancellation. Separate pgTAP fault injection proves rollback of Trip, reservation,
offer and command-key state. Canonical create itself cannot make the injected
conflicting-offer state; only the disposable fixture bypasses that trigger.

Development failures were corrected: missing legacy GPS; restored expected-version
validation precedence; stale expiry fixture version; independent actor fixtures
required by the new unique index; declined-at-expiry retry canonical state. Earlier
incomplete/failing runs are not counted as final acceptance.

## Remaining integration conditions

The minimal Auth bootstrap is not GoTrue/PostgREST/Realtime/device/hosted evidence.
No claim of deployed matching, scheduler liveness, scale latency or phase approval.
A03's 60-second freshness versus Flutter available-mode's up-to-120-second publishing
remains unchanged; stale/low-accuracy Drivers fail closed. A GPS cadence contract
review is required before live integration. No separate heartbeat writer is invented.

P6-R08 Cash booking handoff remains an integration gate; P6-R06/R08 Card activation
is blocked; P6-R09 is an exit gate. P7-A05 integration is not started. Preserve
existing Payment identities and the Phase 6 compatibility wrapper in future work.

## Final outcome

Additional Phase 6 suite: **252 PASS / 0 FAIL / 0 SKIP**, 14 files, exit 0;
**16 PASS / 0 FAIL independent-session races**, and two full 34-migration replays.
Across both pgTAP commands, deduplicating the 39 repeated Cash assertions:
**1,475 PASS / 0 FAIL / 0 SKIP across 42 distinct test files**.
The Python runners additionally verified **35 real independent-session scenarios**
(19 A04 + 16 Phase 6), with no accepted deadlock or timeout outcomes.
No required local database scenario was marked NOT RUN. Hosted/service/device
integration remains NOT RUN and outside this checkpoint.

Final whitespace and new-file checks: PASS. Git scope: eight modified regression/
fixture files and six new implementation/test/evidence files; nothing staged.
Historical migration files, production finance functions, Flutter UI, GPS and
Realtime ownership files are unchanged. Only the new additive migration changes
production SQL. Existing local merge history is preserved.

**READY TO COMMIT** for independently verified local P7-A04 backend work.
No commit, push, PR, merge, issue closure, hosted deployment, provider activation,
or P7-A05 implementation was performed. Deployment preflight, expiry-service
invocation/liveness and the retained integration gates require later review.
