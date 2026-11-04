# P7-A03 nearby Driver candidates - contract and local verification

Source baseline: `8b32560` on `feature/p7-a-matching-backend`.
Assigned worktree was clean before implementation. No other worktree was accessed.
P7-A01 findings from the checkpoint discussion were independently checked against
migrations 006, 007, 011, 014-017, 024, the P7-A02 migration and its verification.

## Implemented contract

```sql
public.backend_find_nearby_driver_candidates(
  target_booking_request_id uuid,
  expected_booking_version integer,
  requested_radius_meters integer default 3000,
  requested_limit integer default 3
) returns table (
  driver_id uuid,
  vehicle_id uuid,
  availability_version integer,
  vehicle_version integer,
  location_sequence bigint,
  distance_meters double precision
)
```

Service-role-only EXECUTE, explicit service-role context validation, SECURITY
DEFINER with empty search_path. No anonymous/authenticated access, no changed table
RLS or grants. The existing explicit backend RPC inventory is extended by exactly
this signature (22 total). No client-facing coordinates or profile data are returned.

Canonical pickup JSON (`latitude`, `longitude`), vehicle type, Rider identity,
payment method and booking version come from `booking_requests`. A confirmed or
searching, unmatched Cash booking must retain its own locked quote with matching
Rider, pickup and vehicle category. Searching bookings retain the existing
90-second window. Missing/stale/ineligible bookings fail with P0002/40001/55000;
blocked/non-Rider ownership fails with 42501. Invalid/null inputs use 22023.

The eligibility predicates reuse the same canonical users/driver_profiles,
vehicles and driver_availability as the existing offer RPC: approved, nonblocked
Driver role, owned active category-compatible vehicle, available state, no
reservation/active Trip references. A real nonterminal Trip excludes a Driver even
if an inconsistent aggregate says available. No independent vehicle approval.
Driver eligibility is not inferred from JWT metadata or legacy profile flags.
Existing authenticated `driver_record_location` remains the client upload boundary;
there is no new requirement to inspect mutable Auth sessions or duplicate its RPC.

Latest GPS is selected by descending per-Driver sequence using the existing index,
BEFORE filtering. Invalid latest evidence does not fall back to an older good fix.
Locations associated with a Trip are excluded. Drivers previously offered this
booking are excluded because the existing booking/Driver unique constraint allows
only one offer for that pair. No offer lifecycle semantics were changed.

## Discovery policy and rationale

- Recorded fix age <= 60 seconds, inclusive.
- Server receipt age <= 60 seconds, inclusive; no future server receipt.
- Device future skew <= 5 seconds relative to both statement time and server receipt.
- Accuracy <= 50 metres, inclusive.
- Radii: exactly 3000, 5000 or 8000 metres, preserving existing offer inputs.
- Result limit: 1 through 3, preserving the offer-capacity upper bound.

These are conservative NEW discovery thresholds, not claims about pre-existing
upload policy. Upload tolerance remains 15 minutes old / 5 minutes future.
The shorter age avoids using many-minutes-old positions for immediate matching;
receipt age prevents delayed/replayed fixes being treated as live, and the 5-second
clock allowance avoids accepting upload's much larger future tolerance. Fifty
metres limits positional uncertainty without pretending GPS measurements prove
physical location. These values are fixed server policy, not caller override fields.
`last_heartbeat_at` remains unused: there is no canonical writer.

Known integration condition: Flutter `DriverGpsTrackingConfig.available` permits a
two-minute maximum publish interval with low accuracy. The 60-second/50-metre
policy intentionally fails closed when that evidence is insufficient. Before live
integration, the GPS owner must demonstrate sufficiently frequent/accurate fixes
or agree on a separately reviewed policy change. No Flutter/GPS code was edited.

## Geometry, ordering and concurrency

Clamped spherical haversine with mean Earth radius 6,371,008.8 metres. Native
PostgreSQL math only; no PostGIS installation or schema dependency. Works at the
longitude seam and poles. This is great-circle distance on the documented sphere,
not road distance, ETA, or ellipsoidal survey precision. Radius comparison is
inclusive with a one-micrometre numerical roundoff tolerance; tests exercise each
radius exactly, 1 cm inside and 1 cm outside.

Order is unrounded distance ascending, then Driver UUID ascending. IDs, versions
and sequence are observations for subsequent revalidation. Search is STABLE and
uses one statement snapshot with statement_timestamp(), not an old transaction's
now(). It takes no row locks, reserves nobody, creates no offers or Trips, and
performs no writes/audit/financial operation. Discovery is not assignment authority.
P7-A04 must atomically revalidate mutable eligibility, versions and capacity;
existing backend_create_driver_match_offer and driver_transition_trip are retained.

## Files

- `supabase/migrations/20261104090127_p7_a03_nearby_driver_candidates.sql`
  (CLI-created additive migration, one RPC).
- `supabase/tests/database/20261104090127_p7_a03_nearby_driver_candidates.test.sql`
  (69 focused assertions, reuses P7-A02 synthetic actor fixture).
- `supabase/tests/database/013_phase3_rls_rpc_hardening.test.sql`
  (one expected signature added; no assertion/grant relaxation).
- This contract/evidence document.

## Local execution

```powershell
python supabase/tests/ops/p7_a02_local_test.py
python supabase/tests/ops/r06_x2_local_test.py --existing-new-container ridex-r06-x2-c57bbc357d85
git diff --check
```

The existing runner includes the new dated test automatically. Final fresh cluster:
`ridex-r06-x2-c57bbc357d85`, image
`public.ecr.aws/supabase/postgres:17.11.0.006`. Network mode none, mounts [], published
ports {}; initdb in the new container's /tmp. Each file runs in a separate migrated
database clone. All SQL uses docker exec and that container's private Unix socket.
No existing Supabase container/data, hosted service, provider or other worktree was
modified. Resources retained. Minimal repository Auth bootstrap is not a full
GoTrue/PostgREST/Realtime or hosted integration test.

Main suite: **1,212 PASS / 0 FAIL / 0 SKIP**, 29 complete test files, exit 0.
Includes P7-A03 **69/69**, P7-A02 **56/56 authored assertions**, security inventory,
RLS, Driver lifecycle, fare/quote, Cash handoff, and real existing concurrency tests.
All **33 migrations** applied with exact history and zero provisioned approvals.

Development runs exposed two fixture errors (pgTAP VALUES query syntax and a Trip
fixture using the searched booking); both were corrected in the new test only.
An intermediate extended run had 67 successful TAP lines but an inconsistent final
plan after trailing savepoint rollback; a final independent catalog assertion now
records the final test counter and the runner verifies all 69 lines against plan.
No failing/incomplete development run is claimed as final acceptance.

## Remaining scope

No hosted acceptance or deployment. Existing P6-R08 Cash handoff gate and P6-R09
exit gate remain; Card provider activation stays blocked under R06/R08. No financial
production function was changed. No new spatial index or large-scale latency claim:
latest-location lookups reuse existing indexes, but discovery may inspect all
available Drivers; representative scale/EXPLAIN evidence remains an integration
performance task. Neither nearest-driver selection nor GPS authenticity guarantees
physical presence; downstream assignment must revalidate.

No commits, push, PR, merge, hosted operation or P7-A04 implementation performed.

## Final disposition

Additional Phase 6 run: **252 PASS / 0 FAIL / 0 SKIP**, 14 files, exit 0;
**16 PASS / 0 FAIL independent-session races**. Two further complete 33-migration
replays passed. Deduplicating 39 Cash assertions repeated by the two runners:
**1,425 PASS / 0 FAIL / 0 SKIP across 41 distinct database test files**.
`git diff --check` and new-file whitespace checks passed.

**READY TO COMMIT** for this independently verified local backend checkpoint.
The stated GPS cadence and performance integration conditions remain explicit;
this is not hosted or end-to-end matching acceptance. Nothing is staged or committed.
