# P7-B02 Driver availability UI and controller

Owner: Moath. Issue: #107. Branch: `feature/p7-b-driver-flow`.
Base: `0be40db6f78ee80c11bb0cde074e1750a6074f6b` (approved B01).
Scope: isolated local availability presentation, no backend wiring.

## Ownership and reuse

- New `lib/features/driver_flow/presentation/providers/driver_availability_controller.dart`:
  immutable view state, scope-owned Riverpod controller and local fixture scope seam.
- New `lib/features/driver_flow/presentation/screens/driver_availability_screen.dart`:
  accessible availability screen, observed status, explanations, switch and read action.
- Modified `lib/features/driver_home/presentation/screens/driver_home_screen.dart`:
  only a tooltip-labelled app-bar action and import to open the preview. The B01
  ownership map identifies this as Moath's future Driver presentation area. Its
  existing presence switch, mock metrics, GPS tracking and Cash gate are preserved.
- New `test/driver_availability_controller_test.dart` and
  `test/driver_availability_screen_test.dart`; these reuse the B01 test-only fake.
- This plan and `docs/ai/verification/P7_B02_LOCAL_VERIFICATION.md` record the slice.

No shared router, session provider, tracking provider, financial contract, B01
contract/fake or other owner's source is edited. Native Navigator entry from Driver
Home avoids a shared GoRouter change. Existing Driver route guards are unchanged.

## Interface and behavior

The controller watches the B01 `driverFlowRepositoryProvider` and the new
`driverAvailabilityScopeProvider`. Scope carries a local DriverFlowSession and
selected fixture vehicle ID; it is NOT authenticated identity or eligibility.
Default scope is null and B01's default repository is unavailable: production
entry opens an explanatory disabled preview. Tests/isolated hosts explicitly
supply scope and fake repository. Test fakes are never imported into production.

The local host must replace/clear scope on logout, authorization/approval loss,
account or lifecycle replacement, including A-B-A with increasing generation.
Actual authenticated session/vehicle mapping is deferred to the integration owner;
this checkpoint does not install real session wiring. The ordinary (non-autoDispose)
NotifierProvider owns one controller per ProviderContainer. Screen removal/remount
and overlapping screens share the same controller and command lock. The controller
and subscription stay alive until scope/repository replacement or container disposal;
those boundaries advance its lifetime guard and retire old reads/commands/events.
Repository ownership/disposal remains with the host. Check status calls refresh,
never provider invalidation. A new scope is explicit retirement, not a retry tool.

The screen displays local demonstration provenance prominently. Its switch
reflects the last observed availability; pending writes never flip it optimistically.
Loading, unavailable, unauthorized, stale, unknown and blocked states disable writes.
Reserved/onTrip are observed read-only values owned by matching/trip services.
All four existing availability values and entity versions are reused, not duplicated.

Commands use B01 DriverFlowSetAvailability with captured Driver ID, expected
availability version, selected vehicle and a unique local correlation token.
Availability's existing RPC has no idempotency parameter; this token is not a
claim of backend idempotency. No RPC is called or invented by this slice.

Only one command can be in flight. Every reply checks controller lifetime, current
authorization, publication sequence, snapshot session/source/revision and entity
version. Newer events retire older reads/replies. A simulated successful reply
can resolve only its still-pending command, with matching session, requested state,
selected vehicle, increasing entity version and current/newer observation revision.
The fake may emit the identical observation before replying; equal-revision replies
must match all current availability fields. A newer reserved/onTrip observation
cannot be overwritten by an older reply.

An independent highest-accepted availability version survives data-less loading,
unavailable/missing-data observations, read failures and screen removal. Lower
versions fail closed despite higher observation revisions. Equivalent versions and
higher versions remain observable. Only scope retirement resets the baseline.
After session/source and event ordering validation, unauthorized observations latch
before entity-version checks, clear visible availability and disable reads/writes.
Later ready observations/replies cannot recover that scope, even across remount.

Uncertain writes retain their attempt barrier across screen lifetimes. Neither
unchanged reads nor unrelated newer simulated versions reconcile a lost outcome.
B01 exposes no correlated authoritative reconciliation API; this slice adds none.
An unknown attempt therefore stays blocked until explicit scope retirement. A
still-pending command may finish with a validated correlated simulated reply;
that remains local demonstration evidence, never canonical/backend authority.
Check status performs reads only; no automatic command replay, changed token retry
or optimistic backend Online claim occurs. Raw errors are not displayed. The nonce
prevents token reuse across controller lifetimes.

## P2 remediation design and scope

The smallest ownership change is a persistent NotifierProvider for the existing
controller. A separate persistent ledger or autoDispose keep-alive leases would
add coordination between owners without improving this local seam. No B01 contract,
fake, Driver Home, routing, GPS or financial changes are needed for remediation.
The existing B02 controller and two test files own the three fixes; this plan and
the B02 verification record document them. Safety state is in-memory per container,
not durable across process death; no real backend adapter is configured.

## Final scope-retirement correction

Installed Riverpod 2.6.1 Notifier.state calls its element's flush(); a derived
provider dependency can rebuild the same notifier during that getter. An epoch
check before the getter therefore did not establish validity after the getter.
An old subscription could pass the check, flush a new scope while reading state,
then publish with its captured old scope. Post-await handling had the same ordering.

Every operation now captures a private lifetime record: epoch, scope identity and
repository identity. _viewFor first rejects an already-retired epoch (avoiding a
state access after disposal), reads state to flush pending dependencies, then
checks epoch and both identities again. It returns a local immutable view only
when that captured lifetime is still current. All controller state getters go
through this helper. Observations, stream/read failures, refresh, writes, replies
and command cleanup use the captured lifetime and local view. Repository calls
use the captured repository. No old callback can clear a replacement attempt,
advance its version barrier or alter its authorization latch.

Nineteen new controller cases exercise no-pump/no-flush scope replacement,
clearance, repository replacement, old ready/unauthorized/error events, delayed
command outcomes and reply-only read/command continuations. Same-repository
scope replacement is tested separately from repository replacement. Old version
8/99 observations cannot poison a fresh version-1 scope; identity, selected
vehicle, command counts and new-scope authorization are asserted. A separate
case keeps B's command pending while A's finally runs, then confirms B's unknown
outcome remains blocked. Existing remount/single-flight/container-isolation tests
remain in the focused suite. The new tests use controlled synchronous streams,
Completers, container.pump and microtask turns, with no arbitrary sleep durations.
The B01 fake and contract remain unchanged; a reply-only B02 test repository
isolates asynchronous response checks from stream observation checks.

## Presentation and verification boundaries

Material switch semantics, labelled actions, disabled controls, a live status
region, progress and actionable explanations provide keyboard/screen-reader
access. The body scrolls at narrow widths. Existing project theme is inherited.
Physical devices and visual screenshots are not acceptance evidence in this slice.
The old Driver Home presence demo remains independent and explicitly labelled;
the new screen never writes driverOnlineProvider or canonical tracking availability.

## P6 gates and remaining integration

P6-R01/R02/R03/R07 still block actual Cash completion, settlement and receipts;
local UI verification does not supply their canonical runtime/ownership/hosted
acceptance. P6-R06 Card remains disabled. The Phase 6 roadmap defines P6-R08 as
secure Stripe UI foundation, despite the inconsistent Cash-handoff label in the
Phase 7 issue/brief. Neither interpretation authorizes activation here. Canonical
Cash matching handoff remains separate Phase 5/P7-A05 integration work.

The existing signatures driver_set_availability(requested_state,
requested_vehicle_id, expected_version) and driver_transition_trip(...) remain
unchanged. Future integration must reuse reviewed canonical eligibility/session
readers and coordinate shared-file ownership. No Supabase, migration, hosted,
Stripe, financial completion, receipt, GPS, matching or B03 behavior is added.
