# P7-B03 Incoming Requests UX

Owner: Moath. Issue: #108. Branch: feature/p7-b-driver-flow.
Local baseline: B01 0be40db; B02 22f6776. Clean worktree and both commits were
verified before editing. Phase 7/Moath.md, AGENTS.md and GitHub Issue #108 read.
No current-main integration, fetch, merge or branch switch was performed.

## Ownership and design

Seven paths comprise this checkpoint:
- lib/features/driver_flow/presentation/providers/driver_incoming_offer_controller.dart
- lib/features/driver_flow/presentation/screens/driver_incoming_offer_screen.dart
- lib/features/driver_home/presentation/screens/driver_home_screen.dart (import/action only)
- test/driver_incoming_offer_controller_test.dart
- test/driver_incoming_offer_screen_test.dart
- docs/ai/plans/P7_B03_INCOMING_REQUESTS.md
- docs/ai/verification/P7_B03_LOCAL_VERIFICATION.md

B01/B02 source and contracts are preserved. The existing Driver mock request
screen still uses its original demo flow; this preview is reached through a
labelled Native Navigator action from guarded Driver Home, following B02's entry
pattern. No shared routing/session edit is required. AppScaffold and the project
theme are reused. A route sequence card presents ordered pickup/stops/destination,
with the locked Cash amount prominent. No invented map or Rider identity is shown.

The existing money utility formats floating JOD to two decimals. B03 formats
integer fils directly with quotient/remainder and exactly three decimal digits,
so 1001 fils is JOD 1.001 without rounding. No shared utility change is necessary.

## State and lifetime

B01 DriverFlowRepository, DriverFlowSession, DriverFlowOffer and DriverFlowJourney
are reused. B02's local fixture scope supplies Driver/session generation and vehicle
context; it remains null by default and is not authenticated eligibility evidence.
B03 owns only a presentation projection and per-offer memory; it owns no booking,
Trip, matching connection or command. Availability retains its separate B02 owner.
Test fakes remain in test code. No execute call exists in the B03 controller.

A persistent NotifierProvider retains per-session logical identity and expiry
memory across screen removal. The host must retire/clear scope on logout, approval
loss and account replacement, with increasing generations for A-B-A. Captured
epoch/scope/repository guards validate AFTER reading state because Riverpod may
flush derived dependencies during that getter. Replacement retires subscriptions,
reads and old callbacks. Read publication sequence prevents older reads replacing
new observations. Unauthorized is terminal within a scope and hides offer details.

Offer identity is (ID, version), with full payload comparison: Booking/quote IDs,
original expiry, pickup/destination, ordered stops, vehicle, Cash/fare/route values.
Reconstructed equivalent observations retain the original offer object and expiry.
Incompatible payloads latch stale. Replaced/no-longer-offered identities cannot
return as valid within the same scope. A separate per-offer-ID highest-version
map rejects lower entity versions even at higher observation revisions, before
selecting their payload. It survives expiry and missing/empty/transient events.
Different IDs have independent baselines; valid upgrades follow replacement rules.
Session/repository retirement resets it behind the existing post-flush guard.
The injected clock function is captured per scope without watching clock-provider
replacement, so changing a clock fixture cannot reset version/uncertainty memory. Pending/unknown/stale observations latch
even if their payload is absent. Equivalent ready events cannot clear uncertainty;
expired pending observations become unknown, never assignment confirmation.

## Time and presentation

An injectable absolute clock drives ceiling-to-second countdowns, with inclusive
expiry (now >= deadline). Expiry latches per logical offer; clock rollback cannot
revive it. A widget-owned one-second timer requests recomputation, is cancelled
outside resumed lifecycle and on disposal, and restarts after resume. Resume
recomputes immediately from the clock rather than counting missed timer ticks.
On entry, build uses a pure viewAtCurrentTime projection of the observed view,
so the first rendered frame already has the inclusive expiry state and zero
countdown when due. This calculation mutates no provider state. A mounted-guarded
post-frame callback latches expiry outside the widget build lifecycle, preserving
rollback protection even if the screen closes again before a timer tick. The
controller has no background timer and does not dispatch on resume/reconnect.

B01 requires positive integer distanceMeters and durationSeconds, nonempty vehicle
identity/label, and locked integer Cash fare; it cannot represent missing route
metrics. Empty stops and empty addresses are omitted. Contract changes to make
other fields optional are deferred. Status covers loading, empty, valid/replaced,
stale, expired, pending/unknown, unauthorized and unavailable observations.

All screens label local demonstration provenance and deny confirmed assignment
or payment. Accept/decline are visibly disabled. No Rider name, phone, rating,
contact or private detail is derived from unrelated mock/draft state.

## Gates and limitations

P6-R01/R02/R03/R07 remain hard gates for actual Cash completion, settlement and
receipts. P6-R06 keeps Card disabled. B01/B02 already document the inconsistent
Phase 7 Cash-handoff label for P6-R08; the Phase 6 roadmap identifies R08 as Stripe
UI foundation. Neither interpretation authorizes activation here. Canonical Cash
handoff and authoritative reconciliation remain separate integration work.
No Supabase, migrations, GPS, Realtime, finance, Stripe or hosted/live operation
is added. B04 accept/reject/claim work is not started. Persistent memory is local
and in-memory; new process/session recovery needs reviewed authoritative evidence.
Physical-device and real screen-reader verification remain outstanding.

A separate read-only offer projection avoids coupling countdown updates to B02
availability command ownership. A shared general Driver-flow store would require
a broader refactor and coordinated contracts; it is unnecessary for this slice.

## P2 remediation verification

Two findings were reproduced with four deterministic pre-fix failures: same-ID
v2 -> v1 before/after expiry, and first-frame remount at/exceeding the deadline.
The same four tests pass after correction. Sixteen new cases bring B03 to 49
cases (30 controller / 19 widget). An unfiltered test repository delivers events
verbatim so offer-version, duplicate and event-order checks exercise the controller.
Additional tests cover equivalent v2, conflicting v2, v1 -> v2, independent IDs,
missing data, no-flush scope/repository replacement, just-before expiry, rapid
remount timer ownership, rollback after remount, and closed-screen authorization
or session replacement. Exact command/count evidence and the final source
fingerprint are in P7_B03_LOCAL_VERIFICATION.md. No B01/B02, Driver Home, backend,
GPS, finance, routing or B04 changes are part of this remediation.
