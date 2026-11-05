# P7-B05 - Accepted Driver Trip presentation

Owner: Moath. Issue: #110. Approved bounded implementation, 2026-11-05.
Branch: feature/p7-b04-driver-offer-actions.
Base: 1fb20e36f1d4ca3a0399b54983d09c4174bd7580 (local B04).

## Scope and ownership

One persistent DriverTripPresentationController owns simulated Trip observations
and progression attempts. It reuses DriverFlowRepository, DriverFlowTrip,
DriverFlowProgressTrip and DriverAvailabilityScope without changing B01 public
interfaces. It never writes shared mock/canonical Trip or financial state.

B04 alone owns offer acceptance/decline. B05 listens to its pending/UNKNOWN and
authorization barriers without watching/rebuilding its own command owner. A
simulated B04 acceptance is not an assignment; opening B05 reads the repository.
There is no automatic navigation from B04 and no Trip invented from button state.

Approved ownership is six new files and one modified file:

- lib/features/driver_flow/presentation/providers/driver_trip_presentation_controller.dart
- lib/features/driver_flow/presentation/screens/driver_trip_preview_screen.dart
- test/driver_trip_presentation_controller_test.dart
- test/driver_trip_preview_screen_test.dart
- docs/ai/plans/P7_B05_ACCEPTED_DRIVER_TRIP.md
- docs/ai/verification/P7_B05_LOCAL_VERIFICATION.md
- lib/features/driver_home/presentation/screens/driver_home_screen.dart (bounded entry only)

No Rider, shared router, existing mock/canonical Trip, SQL, production adapter,
session implementation or other owner files are modified. Existing fake support
is reused unchanged; the new tests additionally use an unfiltered repository.

## Presentation and observations

The summary shows repository pickup, ordered stops, destination, vehicle, Trip
ID/version, current lifecycle status and exact integer-fils locked Cash fare.
Recorded distance/duration are labelled non-live metrics. No Rider contacts,
invented assignment, Driver GPS, financial success or receipt are presented.

Observation phases reuse loading, ready, pending, unavailable, unauthorized,
stale, unknown and completionBlocked. A missing Trip has no accepted fallback.
Terminal statuses are read-only; reported completion does not prove payment.

The first observed Trip ID is pinned for the lifetime. Entity versions and event
revisions are independent barriers. Older observations are ignored; a higher
revision cannot regress a Trip version, including after missing observations.
Same-version status or complete-journey conflicts latch stale. Reconstructed
equivalent payloads are accepted. Different IDs, vehicle-scope mismatches,
incompatible journeys and terminal resurrection fail closed.

Reconnect can observe forward lifecycle jumps after missed events, including a
reported terminal state. This does not permit commands to skip lifecycle edges.
External UNKNOWN remains latched after ordinary ready observations/reads.

## Simulated commands

driverTripSimulationEnabledProvider defaults FALSE. The real application has no
override and the existing repository/scope remain unavailable/null. The only
commands admitted through deliberate test/demo overrides are:

1. accepted -> driverArriving
2. driverArriving -> driverArrived
3. driverArrived -> inProgress

No cancel, completion, settlement, payment or receipt command is introduced.

Admission installs synchronous single-flight ownership. Each attempt captures
one immutable command/token, original full Trip, Trip ID/version, session/scope,
repository lifetime and observation revision. The UI callback also captures its
presentation lifetime; an equivalent Trip in a newer lifetime cannot authorize
an old callback. Reads, rebuilds, remounts and resume never regenerate tokens.

After publishing pending and setting up the injectable 15-second response
scheduler, final validation flushes dependencies and independently checks current
observation readiness, simulated source, identity/version/payload, legal next
status, application authorization, original scope/repository lifetime, simulation
gate, B04 barrier and attempt ownership. Own pending is distinct from an external
pending observation. No publication, await or host callback occurs between the
final pure validation and execute invocation.

A dispatched flag separates definitely unsent local cancellation (stale, no
lost-response UNKNOWN publication) from uncertain dispatched work. Timeout,
transport error, lost reply, conflicting observation or ambiguous result latches
UNKNOWN. Reads, higher revisions/versions, remount and reconnect never unlock it.
No automatic retry/replay or reconciliation is implemented. A future separately
reviewed reconciliation contract is required. Definitively rejected commands
cannot be repeated against the same target version.

Simulated success requires a matching result source/session, original Trip ID,
advanced Trip version, requested status and unchanged journey. A compatible
publication before the command Future completes remains pending until a valid
correlated response. Notification alone is not success. Old timers/Futures and
finally blocks can settle only their original operation.

## Session and recovery

The controller observes the existing application session for authenticated,
approved, unblocked Driver role and matching local Driver ID. This is a local
preview guard, not SDK provenance or backend authorization. It listens rather
than rebuilding on routine session/offer notifications.

Logout, role/account/approval loss or unauthorized observations hide Trip details
and latch access loss. Returning to the same account cannot revive that lifetime.
Scope/repository replacement retires old work and ignores late results. Reusing
a retired Driver ID/generation, including A -> B -> A, fails closed. Repository
replacement requires a fresh local generation rather than clearing uncertain
work in a reused scope. Retirement is not proof that a command failed.

Initial loading, Check status and resume/reconnect perform reads only. Stream
errors disable actions; newer valid reads can restore observation presentation,
but cannot reconcile UNKNOWN. Reads started before a newer event cannot overwrite
it. No canonical durable command journal or process-death recovery is claimed.

Screen exit only disposes view/lifecycle listeners. The persistent provider keeps
pending/UNKNOWN ownership; back navigation never mutates or cancels a Trip.

## Passive route handoff

View route preview opens a sheet bound to captured session, controller lifetime,
Trip ID/version and full payload. It validates at open and render, invalidating on
logout/replacement/version change. The sheet consumes the same owner.

RouteRequest is constructed directly from the Trip journey, not a Rider draft.
RouteTimeline and idle MapPlaceholder show labelled schematic connections, no
cars/live position and no road-routing promise. Coincident coordinate spans are
handled safely. No GPS, Routes API, map SDK or external navigation is invoked.

Existing Driver arrival/active-trip mock screens and their completion controls
are not reused. The Rider-draft-bound route controller is not reused. Actual
Driver-to-pickup navigation needs trusted location and geometry integration.

## Backend and Phase 6 boundaries

Source-inspected A04 contract:

    driver_transition_trip(target_id uuid, requested_status public.trip_status,
      expected_version integer, idempotency_key text) returns jsonb

Acceptance uses offer ID/version; subsequent progression uses Trip ID/version.
Non-accept transitions delegate to the preserved lifecycle/authorization path.
Authenticated, approved/unblocked Driver and ownership/version/idempotency checks
remain backend-owned. A04 also defines:

    driver_decline_match_offer(target_offer_id uuid,
      expected_offer_version integer, idempotency_key text)
      returns public.driver_match_offers

Neither RPC is wired by B05. A05 Rider assignment readers are not Driver
authorization. A06 notifications are observation triggers, not assignment proof.
GPS freshness alignment, canonical Driver ownership/booking/quote/route lineage,
delivery and hosted acceptance remain integration dependencies. DriverFlowTrip
does not provide all metadata needed for canonical assignment/route changes.

Phase 6 tracker overrides retain R01/R02/R03 partial evidence and R07 acceptance
gates for Cash completion/recovery. R05 bounded Rider Cash read acceptance is not
Driver financial approval. R06 remains partial with Stripe dispatch disabled;
R08 is the authoritative secure Stripe UI scope, despite older Moath wording.
Phase 6 remains NOT APPROVED. These gates do not block this isolated preview.

## Issue #110 acceptance mapping

- Accepted summary: complete simulated route, vehicle, locked Cash and status.
- Map/navigation handoff: passive, identity-bound schematic route sheet only.
- Pickup/arrival/start: three gated adjacent nonfinancial transitions.
- Logout/reconnect: hidden unauthorized data, scoped retirement, read-only reads.
- Safe exit: no mutation/replay; persistent pending and UNKNOWN protection.
- Authority: default-off production, no canonical/financial state promotion.

The hosted issue was not fetched or changed; mapping uses the owner's supplied
criteria and Phase 7/Moath.md. B06 is not implemented.

## Verification

### Three P2 corrections

P2-1: a watch error set UNKNOWN before an unauthorized command reply, and the
UNKNOWN early return suppressed access retirement. Matching operation/lifetime
authorization loss now precedes ordinary settlement. A guarded response handler also processes a late denial after timeout, only for its still-current operation/lifetime. Revocation hides Trip and
route details while retaining UNKNOWN and the original command/token for a
dispatched uncertain attempt. It does not infer command failure or success.

P2-2: source filtering previously discarded same-session unconfigured unauthorized
snapshots before handling the denial. Current lifetime and session identity are
checked first; a matching unauthorized snapshot revokes regardless of source.
Foreign/retired sessions cannot revoke the replacement lifetime, and subsequent
ready observations cannot revive revoked access.

P2-3: duplicate-revision suppression also prevented valid read recovery after
transport failure. Only an explicit observed read may restore transport-unavailable
presentation from an equivalent same-revision simulated ready snapshot. The full
publication and pinned Trip payload/version must match retained memory. Watch
duplicates do not recover transport availability. Authorization, conflict,
identity/version high-water, external UNKNOWN and dispatched UNKNOWN barriers
remain intact. B04 pending/UNKNOWN still disables progression even if read-only
presentation recovers. Recovery never executes or replays commands.

Deterministic initial P2 reproduction: 15 PASS / 6 FAIL across 21 cases. The same
defect regressions pass after correction. The B04 recovery negative was further
strengthened to fail only B05's read, asserting that B04 truly remains pending
rather than becoming UNKNOWN through a shared stream error. Controller/widget
tests include data hiding in an already-open route sheet and late denial isolation.

The final remediation results in the verification record supersede initial B05
counts/hashes below. No B04 ownership, public B01 interface, final dispatch guard,
production adapter, simulation default or command correlation was changed.

Implementation and final-source command evidence, exact test counts, SDK,
inherited analyzer/formatting findings and remaining limits are recorded in
../verification/P7_B05_LOCAL_VERIFICATION.md. No historical exception authorizes
new failures. Counts from overlapping test selections must not be added.

Independent Astra review is required before any commit. No stage, commit, push,
PR, issue update, branch change, hosted mutation or live activation is authorized
by this implementation checkpoint.

Historical initial B05 results (superseded): B05 99 PASS (84 controller, 15 widget), B01-B04
318 PASS, integration-sensitive 280 PASS, full suite 2170 PASS / 2 intentional
live SKIP / 0 FAIL. Counts overlap. Scoped analysis and formatting pass. Full
analysis exits 1 for the two unchanged containsSemantics infos; repository-wide
formatting exits 1 for 15 unchanged baseline files. Tracked and untracked
whitespace checks pass. Flutter 3.41.2 / Dart 3.11.0 was used; the guide's older
SDK was not tested. Exact commands and final-source hashes are in the verification
record. These are local implementation-agent results, not independent review or
hosted/CI acceptance.

Final P2 verification after final Dart edits: B05 121 PASS (104 controller,
17 widget), B01-B04 318 PASS, integration-sensitive 280 PASS, full suite
2192 PASS / 0 FAIL / 2 intentional live SKIP. Counts overlap. Scoped analysis
and five-file formatting pass. Full analysis exits 1 with the same two inherited
infos; global formatting exits 1 with the same 15 inherited findings. Tracked and
untracked whitespace checks pass. Source hashes and execution correspondence are
recorded in the verification document. All original 99 B05 tests are preserved;
22 P2 regressions now pass, including the late-denial-after-timeout extension.
Fresh independent Astra review remains required; no staging or commit occurred.
