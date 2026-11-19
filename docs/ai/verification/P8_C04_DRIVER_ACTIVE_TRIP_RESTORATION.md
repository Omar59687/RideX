# P8-C04 - Driver active Trip restoration and presentation

Moath / Developer 3, issue #153. Local checkpoint only. C05 has not started.

## Isolated stack

Branch: `feature/p8-c04-driver-active-trip-restoration`, created directly from
approved C03 `c152f44acc7372deb3d3928f06a0f6f671f265c3` in a separate worktree.
Fetched origin/main is `3be1aa6`. Full dependency chain above main:
C01 `2c52bc35708dd719168db051107113c7a9e87916` -> reviewed C01
`30a27aaa31eddfd6ece4ea6736d30582e54fcba6` -> C02
`1bd8a9659e04a0ca88f2fcee20bee6b00432d3fa` -> C03 -> this checkpoint.
No merge, rebase or cherry-pick. The three earlier worktrees remain unchanged.

## Existing owners extended

C04 extends CanonicalDriverRepository and CanonicalDriverPresentationController;
it does not introduce another Trip/booking state owner. The new restoration mode
is opt-in (`restorationEnabled` defaults false), retaining existing offer/discovery
behavior. C01-C03 completion/coordinator/journal/recovery implementations are
unchanged. The existing controlled B10 runtime/screens are unchanged.

The new DriverActiveTripRestorationScreen is a read-only integration entry. Its
Driver-owned provider defaults null, with no SDK client, backend target or source
invented here. It accepts only a restoration-enabled controller with offer actions
disabled. The existing completion stop gate remains unconditional; the screen
never mounts completion, generates a key, calls a command, or navigates to shared
legacy success. It is compiled/tested as a widget and remains unmounted in the
shared global router until Omar integrates it.

## Canonical restoration protocol

1. Reuse backend eligibility checks for approved, non-blocked Driver and the
   captured SDK Session/backend/authority epoch.
2. Read authenticated Driver availability to discover the actual active Trip.
3. Reread the exact owned Cash Trip and positive canonical version.
4. Recheck availability and eligibility after the Trip read. Nonterminal Trip
   publication requires matching onTrip state, exact active ID, assigned vehicle
   and unchanged availability version. Empty assignment is also rechecked.
5. Retain immutable verified Trip identity and monotonic versions/progression
   within the owner. Outdated responses, replacement assignments and backward
   canonical progression fail closed; missed intermediate observations are allowed.

A previously verified ID or a single C03 recovery ID is only an exact reread hint.
It cannot assign a nonterminal Trip without matching canonical availability. A
terminal owned Trip is shown separately as a known ended Trip, never active or
proof of payment/receipt success. If a pinned Trip becomes terminal while another
assignment appears, the old owner reports that terminal observation; a fresh owner
must discover any new active assignment. No replacement is silently admitted.

DriverCompletionRestorationHints listens to the existing C03 recovery controller,
without reading/staging/deleting the journal or interpreting callbacks as success.
It hides IDs after authorization revocation and does not arbitrarily choose among
multiple historical records. UNKNOWN/recovery-required information blocks action
presentation, while all displayed Trip fields still come from a fresh canonical
read. The host must provide the recovery owner for this same account/backend/session.

## Presentation and lifecycle

The panel reports loading, verified active Trip, no assigned active Trip,
disconnected source, recovery required, terminal canonical status, stale evidence
and unauthorized session. GPS is health-only: a sample must match the exact
Driver/backend/epoch, opaque SDK Session and verified Trip, with age 0..45 seconds.
Missing, foreign, old or future samples are unavailable/stale. No location
coordinates, map movement, fare, payment or receipt are fabricated. This freshness
window is presentation policy; backend GPS acceptance rules are unchanged.

Disconnect immediately hides references and retires optional C02 completion
eligibility. Reconnect rereads canonically; it cannot replay or synthesize progress.
Auth/UI-session/epoch changes permanently retire the old presentation owner and
cancel its delivery subscription. Late reads cannot publish into a replacement.

The read-only screen retires on background or route coverage. Foreground replaces
the owner through its provider factory, so only fresh authenticated reads restore
state. Replacement owners while paused/covered are retired synchronously. The
provider listener tracks the current owner before lifecycle callbacks, handling
both pause->replacement and replacement->pause orderings before any screen rebuild.
Initial non-foreground mounting is guarded too. Notification deferral is forwarded
to optional C02 retirement on build/disposal. Route pop does not revive a retired
owner; explicit reload creates a fresh read owner.

Unrelated offer hints are ignored in restoration mode. Completion remains default
OFF; no durable UNKNOWN evidence is cleared on reload, logout, pause or reconnect.

## Verification and review

- Final focused suite: 732 passed, 0 failed across nineteen test files.
  The full project test suite was not repeated.
- Changed-file analyzer: clean in eight Dart files.
- Full analyzer run: 21 inherited diagnostics (3 warnings, 18 infos), in unchanged
  files outside this patch. Whole-repository analysis is not claimed green.
- Android `flutter build apk --debug --no-pub`: passed. Existing platform/toolchain
  warnings remain. The newly unmounted screen is exercised by Flutter widget tests.
- Fresh independent review: APPROVED after fixing the medium paused-owner replacement
  race in both event orderings. Regressions reproduced the unsafe live Trip before
  the fixes. The malformed offer-hint robustness edge was also fixed/tested.

Coverage includes cold start without local IDs; loading and empty assignment;
foreign Driver/Trip, blocked/unapproved/non-Driver and expired sessions; assignment
replacement during reads; stale version/progression; terminal states after restart;
network disconnect/reconnect and canonical completion; A logout/B login and A-B-A;
late callbacks; scoped GPS age/identity; C03 UNKNOWN hints and revocation; and native
journal/process-exit plus C01-C03 regression suites. No hosted reads/writes were
used: deterministic fakes and existing loopback SDK fixtures only.

## Changed files

- lib/features/driver_flow/data/canonical_driver_repository.dart
- lib/features/driver_flow/domain/driver_restoration_hints.dart
- lib/features/driver_flow/presentation/providers/canonical_driver_presentation_controller.dart
- lib/features/driver_flow/presentation/providers/driver_active_trip_restoration_provider.dart
- lib/features/driver_flow/presentation/screens/driver_active_trip_restoration_screen.dart
- lib/features/driver_flow/presentation/widgets/canonical_driver_reference_panel.dart
- test/driver_active_trip_restoration_test.dart
- test/driver_cash_production_integration_test.dart
- docs/ai/ops/CURRENT_STATUS.md
- This verification report.

## Exact integration request and remaining limits

Omar must mount DriverActiveTripRestorationScreen at the approved Driver entry and
override driverActiveTripRestorationProvider with a fresh session-owned existing
CanonicalDriverPresentationController (restorationEnabled true, offerActionsEnabled
false). Use CanonicalDriverRepository over the same verified normal-user SDK port,
application SessionState source and synchronous authority invalidations, plus the
existing approved delivery/connection adapter. Dispose borrowed repository, delivery,
port and hint adapters with ref.onDispose; the provider owns controller disposal.
Watch auth/session/config dependencies so login produces a new owner. The screen
handles resume by invalidating that provider. Do not reuse a retired factory result.

Supply DriverCompletionRestorationHints from the existing same-session C03 Cash
recovery controller, and health hints from the already scoped Driver GPS source.
Forward retireCompletion as `(defer) => completion.invalidateInteraction(
  deferNotification: defer)` to retire any separately mounted C02 owner safely.
These hints never grant dispatch authority or substitute for authenticated reads.
Retain the reviewed nonproduction configuration for any live composition. No
approved target or runtime activation is supplied in this branch.

C02's nonproduction completion gate, shared /driver/completed protection and
removal of shared hard-coded Driver success/fare remain Omar-owned. Yousuf owns
trusted payment/receipt consequences. Cash-only support, stale journal locks,
power-loss durability limits, hosted discrepancy #149 and live actor/device
acceptance remain as previously documented.

Toolchain: Flutter 3.41.2 / Dart 3.11.0, matching existing CI. Tests/build use temporary
SDK resolution. The committed lockfile is unchanged (blob
bb6148d20da9613013f01aa25dfefe82566360f1); exact enforcement still fails due to five
SDK-pinned differences: characters 1.4.0->1.4.1, matcher 0.12.17->0.12.18,
material_color_utilities 0.11.1->0.13.0, meta 1.16.0->1.17.0 and test_api
0.7.6->0.7.9. The original lockfile already requires Dart >=3.8 despite the guide's
older Flutter 3.27.3/Dart 3.6.1. No lockfile/platform/generated changes are committed.

No migrations, Edge Functions, financial logic, shared router/providers, Rider UI,
Stripe, accepted Phase 7 Trip changes, emulator operations, push, PR, merge or
deployment. C04 is ready for owner approval after final verification; C05 requires
separate authorization.
