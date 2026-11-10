# P7-B08 — inactive canonical Driver presentation/delivery composition

Owner: Moath. Base main: `ef45428f4f8791cbf5c450e3f8abff036d098c3d`
(B07 merged via PR #132). This is a local integration foundation, not production
activation or connected Rider-to-Driver acceptance.

## Design and exact file ownership

Add a separate canonical reference view/controller and unmounted panel. Extending
DriverFlowSource.simulated or constructing a DriverFlowJourney from incomplete B07
references would manufacture authority or display data. Activating existing routes
would cross the delivery and shared integration gates. Both alternatives are
rejected. Existing B04–B07 code, providers, controllers and screens stay unchanged.

New files only:

- `lib/features/driver_flow/domain/canonical_driver_delivery.dart`
- `lib/features/driver_flow/presentation/providers/canonical_driver_presentation_controller.dart`
- `lib/features/driver_flow/presentation/widgets/canonical_driver_reference_panel.dart`
- `test/canonical_driver_presentation_controller_test.dart`
- `test/canonical_driver_reference_panel_test.dart`
- `test/helpers/canonical_driver_presentation_harness.dart`
- This design/verification/handoff document.

The ChangeNotifier controller is consumed through a session-owned Riverpod
ChangeNotifierProvider. The provider defaults null. Controller admission and offer
actions both default off. No router, Driver Home entry, SDK client, backend
registry, migration, matching endpoint, Realtime channel or production factory is
added. Removing/remounting the panel does not dispose the provider/controller or
regenerate an intent/key. Provider/session disposal is an authority boundary;
the borrowed B07 repository is not disposed by the presentation controller.

## Contracts and data flow

`CanonicalDriverDelivery` exposes a stream of advisory connection, exact offer-ID
and exact Trip-ID hints. Each has a source-local increasing observation revision,
not an offer/Trip/database version. Duplicate/older revisions are ignored.
Signals contain no coordinates, fare, route, status, vehicle description, Rider
display identity, row payload or authorization assertion. No production delivery
adapter is implemented. Missing delivery, unready connection, errors and stream
closure leave references hidden and actions unavailable.

A ready signal permits an authenticated read through B07, not a command. An
offer locator causes `CanonicalDriverRepository.observe(offerId: ...)`; returned
offer identity and Driver ownership must agree. Actionable offer presentation
also requires the canonical reservation's booking and vehicle references.
B07's high-water/correlation/eligibility protections are retained. Newer reads
retire older asynchronous publications; a higher signal revision cannot grant
authority to a stale row.

Current Trip discovery comes only from source-verified canonical availability or
B07's command-correlated reconciliation. A Trip hint cannot discover or replace
the Trip identity. The controller calls `readTrip` for the pinned ID, checks
booking/quote/Driver/Rider/vehicle correlations and version ordering, and rejects
terminal resurrection. Acceptance receives an additional canonical Trip reread
before presentation. This is not a second backend or active-Trip state machine:
B07 owns authenticated reads/commands; B08 owns only their view/uncertainty.

`CanonicalDriverPresentationView` is distinct from all simulated snapshots.
It exposes only currently valid B07 offer/Trip references and action availability.
Previously captured views are revoked on publication/lifetime replacement.
The panel displays verified IDs, versions and Trip lifecycle vocabulary. It
explicitly says fare/route/Rider details/vehicle details are unavailable.
Vehicle ID is labelled an identifier, not a vehicle description. It shows no
invented journey, fare, name, rating, ETA, receipt or payment success. The local
action override is reference-only testing, not approval of a live commercial UI
with incomplete journey evidence.

## Identity, attempts and UNKNOWN

The injected UI `ValueListenable<SessionState>` may suppress access but cannot
authorize backend operations. B07 independently checks authenticated SDK
provenance, exact session/epoch, approved/nonblocked Driver and normal-user RLS.
B08 pins the exact UI SessionState; logout, same-user session replacement, role,
approval, account or block replacement permanently retires the composition.
A required shared authority-invalidation Listenable supplies SDK/lifecycle
revocation signals. All references are hidden on invalidation; stale callbacks
cannot use an old view to dispatch.

One decision captures the exact displayed offer, original key and repository
lifetime. Synchronous attempt ownership and post-publication checks block
duplicate/reentrant callbacks before handoff. New source identities or
disconnection hide references and retire stale observations. Once handed to
B07, a disconnect, response uncertainty or inclusive deadline crossing is
UNKNOWN; a later response must not silently restore acceptance. No automatic
retry, replay, new key, navigation or financial action is triggered by reads,
reconnect, timers, events, build or remount.

Ordinary reads/events cannot clear UNKNOWN. Only the explicit read-only
`reconcile()` action invokes B07's original-intent recovery and may display a
freshly reread exact canonical Trip or authoritative decline. Missing/RLS-filtered
rows and expiry never prove non-assignment. A repository/controller instance
supports one intent; a new offer or key cannot release its uncertainty. Do not
recreate the composition to bypass the original attempt. Durable process-restart
intent/recovery composition remains a separate integration prerequisite.

Decision ownership remains pending through the final presentation Trip reread.
The initial operation checks its captured generation, authority, original deadline
and uncertainty again before publication, so expiry or a disconnect/reconnect
during that reread cannot expose even a transient accepted Trip. Explicit recovery
pins a new generation before notifying listeners, rechecks admission before its
first read and after every awaited read, and retains UNKNOWN until the entire
command-correlated verification succeeds. A retired recovery cannot be revived by
connectivity becoming ready; a new explicit recovery is required. Recovery may
resolve canonical evidence after the original offer deadline without replaying it.

The panel's one-second clock projection calls `tick()` only; it performs no
repository read or write. Timers are canceled on panel removal. Expiry that was
observed by tick stays expired even after a backwards clock change.

## B06 financial stop

Views reuse `DriverTripCompletionGate.blocked`: `canComplete` is unconditionally
false. `requestCompletion()` returns `DriverFlowOutcome.unsupported` without
reading a repository, changing view/UNKNOWN state, generating a key or dispatching.
The panel's completion control is always disabled. B08 adds no progression,
completion, payment, settlement, receipt or Stripe/Card command. Existing B07
Cash-only pre-dispatch validation and automatic backend Cash-selected record
side-effect documentation remain unchanged; no real command was executed here.

## Integration dependencies and acceptance limits

- **Yousuf:** reviewed matching application endpoint, canonical offers and safe
  offer delivery/discovery/expiry operations. B08 consumes only an exact locator;
  it does not define an HTTP endpoint or create offers/Trips.
- **Omar:** actual source readiness, monotonic advisory signals, shared
  authorization/lifecycle invalidations, disconnect/reconnect handling and GPS
  freshness/Trip synchronization. PR #127 remains untouched and unmerged by this
  work. Reuse the existing GPS and Realtime infrastructure after review.
- **Sanad:** Rider confirmed-booking/assignment discovery and authorized exact-Trip
  tracking composition. Driver references do not authorize Rider reads.
- **Moath/shared integration:** approve the canonical UI projection and supported
  journeys, durable attempt lifetime, foreground/background policy and runtime
  entry before any activation. Add richer display fields only through a reviewed
  authorized canonical read contract; never fill them from demo data.

The injected invalidation seam is not proof that silent SDK replacement,
instant remote blocking, real channels or device lifecycle have been accepted.
A host must provide reviewed invalidations and clear copied display data.
Current point-in-time reads are not a multi-table transaction or authorization
lease. A reset delivery revision requires a new reviewed source lifetime while
preserving unresolved intent; it must not silently reset the attempt.

Independent Mock UI, synthetic local composition tests, and genuine shared-backend
device acceptance remain distinct. A/B tests here do not establish C.

## Verification record

Focused controller/widget tests cover positive exact references; missing evidence;
unauthorized/foreign data; missing/unready delivery; duplicates, expiry, revisions
and delayed reads; pending/reentrant decisions; UNKNOWN and explicit recovery;
logout/role/SDK replacement; canonical Trip reads; terminal/version protection;
remount/disposal; no replay; and unconditional B06 completion blocking.

Run serially:

```sh
flutter test --no-pub --concurrency=1 test/canonical_driver_presentation_controller_test.dart test/canonical_driver_reference_panel_test.dart test/canonical_driver_repository_test.dart test/driver_cash_completion_gate_test.dart test/driver_cash_completion_gate_screen_test.dart test/architecture_boundary_test.dart
flutter test --no-pub --concurrency=1
flutter analyze --no-pub
```

Focused serial verification: **162 passed**, including **58 new B08 tests** and
the existing B07/B06/architecture suites. Scoped analysis: **no issues**.
Final full Flutter suite with `--concurrency=1`: **2,551 passed, 0 failed,
2 intentional credential-gated live skips**.
Full analysis: **zero errors, zero warnings, eight existing baseline infos**
(exit 1). These are three prefer_initializing_formals infos in Rider map/card
code and five deprecations in canonical Rider searching, cancellation tests and
adaptive accessibility tests. No clean full-analysis claim is made.

Verification uses Flutter 3.41.2 / Dart 3.11.0, matching current offline CI.
Generated lockfile/desktop registrant refresh is excluded; committed dependencies
and platform files are unchanged.

Independent Astra High read-only re-review: **APPROVE for inactive B08** with no
remaining blocking correctness/security findings. Both initial P2 race findings
were reproduced by gated tests, fixed, and explicitly verified in re-review:
pending ownership includes the final Trip reread; recovery is fenced to its
starting generation across notification and asynchronous reads. The reviewer
performed static review only; the parent owns executed verification.

No hosted mutation, provider activation, financial operation, PR #127 change or
other-owner branch modification is part of this phase.

Next safe step: review this inactive composition with the delivery, shared
authority and Rider owners; verify the integrated natural booking→offer→acceptance
chain in isolated infrastructure, then separately approve nonproduction actors,
fixtures and operations before two-emulator shared-backend acceptance.
