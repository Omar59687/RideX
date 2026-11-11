# P7-B09: inactive authenticated Driver offer discovery

Base: `427850558f79ad53339593be3670f80439ba9c85`. B01-B08 are retained.
B09A acceptance-harness worktree is untouched. This slice is SELECT-only polling,
not Realtime, a deployed integration, or approval to activate canonical runtime.

## Contract verification

Migration 007 (`007_phase3_booking_fare_matching_foundation.sql`, lines 223-249,
525-552, 1096, 1121-1145) defines the offer columns, positive integer version,
exact `expires_at = offered_at + interval '15 seconds'`, and index
`(driver_id, status, expires_at)`. Authenticated gets SELECT; public/anon have no
access and authenticated has no direct write grant. RLS calls
`private.can_read_match_offer(booking_request_id, driver_id)`: active/nonblocked
Driver can read their own offers; Rider/Admin participant visibility is broader.
Therefore B09 explicitly filters Driver identity and independently revalidates
Driver role/approval using the existing eligibility reader. No migration overrides
that offer predicate/grant were found in the committed migration set.

A04's backend creation path reserves one Driver and rejects an existing live
Driver offer. Multiple eligible rows are treated as an ambiguous contract breach.
These are repository contract checks, not proof of hosted catalog parity.

The actual SDK loopback test checks a normal-user authenticated GET, selected
columns, `driver_id=eq.<owner>`, `status=eq.offered`, `expires_at=gt.<UTC now>`,
`order=expires_at.asc.nullslast,id.asc.nullslast` and `limit=2`. It neither creates
an SDK client nor introduces an RPC. All SDK access remains in B07's existing
`SupabaseCanonicalDriverPort`, constructed from verified initialization provenance
and AuthService's single-client/epoch binding.

SDK docs checked: https://supabase.com/docs/reference/dart/select and
https://supabase.com/docs/reference/dart/limit. The current changelog describes
v3 breaking changes; this repository retains its reviewed v2 SDK and overrides.
No package upgrades or backend configuration changes are part of B09.

## Design and behavior

A polling delivery instance is owned by a pinned UI SessionState, SDK session,
Driver identity/backend/epoch and explicit authority-invalidation source. It is
single-subscription, session-lifetime scoped and default-disabled. No production
provider, screen, route or flag is mounted/enabled by this slice.

On subscription, if enabled and owned, it rereads Driver eligibility, then reads
at most two candidate rows. Polls run two seconds after the previous poll settles,
with no overlapping requests. The four-second read deadline hides old presentation
and suppresses late results. The SDK GET cannot be physically aborted: a hanging
request stays disconnected and occupies the sole read slot until completion or
owner disposal. Cancellation suppresses publication immediately and stops timers.

Candidate IDs, owner, booking/quote/vehicle lineage, status, integer version,
timezone-aware offered/expiry timestamps and exact 15-second lifetime are checked.
Future, expired, malformed, foreign, duplicate or ambiguous batches cannot expose
an offer. Equal observations suppress repeated offer hints. Versions cannot go
backwards and immutable identity/deadline changes are rejected. Terminal/deadline
observations cannot resurrect an offer. Rollback history has a 64-ID lifetime
bound; exceeding it retires the instance instead of evicting safety evidence.

One valid offer emits an increasing-revision connected hint and then an
`CanonicalDriverOfferHint` containing only its ID. B08 passes it to B07's existing
exact authenticated offer/availability/eligibility rereads. Discovered row data
never becomes presentation or command evidence. B07 verifies commands and canonical
Trip assignment independently. An RPC response, hint or connection alone cannot
prove acceptance or Trip assignment.

Invalid/ambiguous/network observations emit disconnected hints. A successful
empty SELECT remains connected without an offer hint: accepted offers leave this
query, and B08 must retain explicit UNKNOWN reconciliation and verified Trips.
Empty polls allow B08 to refresh existing references only through B07; they are
not evidence of assignment, cancellation or a resolved command. Duplicate healthy
empty observations suppress redundant connection signals so they cannot starve
a slower canonical Trip read or invalidate explicit recovery. Recovery
repeats eligibility/discovery and emits a fresh connection plus a locator
when an eligible offer is present; B08 retains
pending/UNKNOWN guards and never automatically reconciles/replays commands.
B07 retains the original idempotency intent across controller replacement.
A widget remount must preserve its owning B08 controller/repository; B09 does not
provide durable restart recovery or reconstruct UNKNOWN UI from identifiers.

## Future explicit composition (not mounted)

Construct one `SupabaseCanonicalDriverPort` through existing verified access and
AuthService. Borrow that same object for `CanonicalDriverRepository` and
`PollingCanonicalDriverOfferDelivery`. Pass the same approved session notifier,
authority-invalidation source and clock into B08 and B09. Supply this delivery to
`CanonicalDriverPresentationController`. Host owns disposal and must invalidate
before logout/session replacement, backend/role changes and unsupported lifecycle
transitions. Do not dispose B07/B08 on panel/widget removal or replace an unresolved
intent. Stream pause retires polling; do not replay buffered signals as authority.

All three layers remain explicitly opt-in and production defaults stay disabled.
A02 availability/GPS, Trip Realtime composition and UI mounting are separate
integration work. No payment/completion/settlement/receipt command exists in the
new discovery port or adapter; existing B06 completion stop remains unconditional.

## Verification and acceptance limits

Deterministic fake-backed tests and normal-user SDK loopback tests cover discovery,
RLS query shape, malformed/foreign/expired/cancelled evidence, multiplicity,
duplicates/rollback, timeouts/network recovery, precise expiry, session/epoch/UI
replacement, disposal, cancellation, bounded memory, B07 reread and UNKNOWN/no replay.
Verification uses Flutter 3.41.2 / Dart 3.11.0. Final counts are recorded below.
Scoped analysis and five-file formatting are clean. Full analysis retains **20
inherited diagnostics: 3 warnings, 17 infos, zero errors**, exit 1. These are
outside B09: three initializing-formal infos; five Rider radio/semantics
deprecations; nine Rider matching/search/confirmation control-flow infos; and
three unused imports in Rider cancellation/matching tests. It is not green.

Independent Astra High final read-only review: **APPROVE inactive B09**, no
remaining blocking findings. Review was static plus supplied execution evidence,
not an independent test rerun or hosted acceptance. Two prior P2 recovery issues
were reproduced in failing tests and fixed before approval:

1. Empty successful discovery had disabled explicit UNKNOWN reconciliation and
   hidden accepted Trips. Healthy empty now preserves connectivity without an
   offer locator; explicit B07 recovery is still mandatory for UNKNOWN.
2. Repeated empty connection signals restarted canonical Trip refreshes faster
   than a valid delayed read could complete. Empty-state transitions are now
   coalesced. A three-second canonical-read regression fails before the fix and
   passes afterward with repeated two-second discovery polls.

A further passing regression covers authority invalidation inside a connection
listener and verifies that expiry/poll timers and offer publication are cancelled.
Earlier logs contain corrected test-authoring compilation/timer failures; they
are not counted as final passes. An intermediate complete suite passed 2667
with four skips before that last coverage-only case was added. The final run
includes all cases.

### Final local execution

- `flutter test --concurrency=1`: **2668 passed, 0 failed, 4 intentional skips**,
  4:20 elapsed (`final-complete-suite.log`). Skips are the two existing Supabase
  live Auth/role tests and two environment-gated D05 local Realtime tests.
- Combined focused B09/SDK/B07/B08/B06/architecture suite: **224 passed**
  (`complete-focused.log`): 51 new discovery/schema tests, 11 SDK tests (two new),
  and 162 existing regression/boundary tests. B09 adds 53 tests in total.
- Scoped analysis: **no issues**, five changed Dart files (exit 0).
- Changed-file format check: **5 files, 0 changes** (exit 0).
- Git whitespace check: **pass**. Full analysis: **20 inherited findings**
  (3 warnings, 17 infos, 0 errors); exit 1, explicitly non-green.
- Local slice is ready for owner PR approval after this verified checkpoint;
  branch remains unpublished. No CI, hosted or device acceptance is claimed.

Commands:

```sh
flutter test --concurrency=1
flutter test --no-pub --concurrency=1 test/canonical_driver_offer_discovery_test.dart test/supabase_canonical_driver_port_test.dart test/canonical_driver_repository_test.dart test/canonical_driver_presentation_controller_test.dart test/canonical_driver_reference_panel_test.dart test/driver_cash_completion_gate_test.dart test/driver_cash_completion_gate_screen_test.dart test/architecture_boundary_test.dart
flutter analyze --no-pub lib/features/driver_flow/data/canonical_driver_offer_discovery_port.dart lib/features/driver_flow/data/polling_canonical_driver_offer_delivery.dart lib/features/driver_flow/data/supabase_canonical_driver_port.dart test/canonical_driver_offer_discovery_test.dart test/supabase_canonical_driver_port_test.dart
```

Evidence is stored outside Git in the system Temp directory
`ridex-b09-evidence-20261111`: complete-suite/focused/analyzer/format logs, and
`astra-blocker-before.log` / `astra-starvation-before.log` for the reproduced P2s.
No credentials or machine-specific paths are committed. SDK-induced lockfile and
desktop registrant refreshes are excluded, as in previous local validation.
No push, PR or merge is part of this local deliverable.

Hosted schema parity, real RLS actors, device clock skew, latency versus the
15-second deadline, backend offer/expiry scheduling, availability/GPS eligibility,
production lifecycle wiring, two-device assignment and transport acceptance remain
unverified. No hosted data was read/mutated, no migrations/deployment occurred and
no activation or financial operation was performed. This is local B09 readiness,
not a claim that a real Rider-to-Driver ride succeeded.

## Remaining integration owners and exact next step

- Yousuf/backend: confirm deployed table grants/RLS/schema parity, single-Driver
  reservation and offer/expiry scheduling under approved nonproduction fixtures.
- Moath/runtime owner: review explicit session-owned composition and invalidation,
  retained B07/B08 intent across remount, richer presentation contracts and durable
  restart recovery before mounting. This class alone does not discover/restore an
  existing Trip on process restart or provide Trip lifecycle delivery.
- Omar: integrate reviewed lifecycle/SDK invalidation and foreground GPS/availability
  eligibility; no second GPS publisher or offer Realtime subscription is created.
- Sanad: verify Rider discovery of the same canonically assigned Trip and participant
  tracking in the separately approved two-device path.

Next step is owner PR approval of this inactive code. After review/merge, separately
approve a nonproduction composition/environment, accounts, fixtures and operations
for controlled shared-backend acceptance. Existing B07 real accept can have the
backend Cash-selected Payment-row side effect; future hosted write approval must
cover it. B09 itself performs only SELECTs. Financial collection, completion,
settlement, receipts and Stripe/Card remain outside this slice and gated off.
