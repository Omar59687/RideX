# P8-C02 - Canonical Driver completion interaction

Owner: Moath / Developer 3. Issue #153. Local implementation and review only.

## Branch and dependency

Branch: `feature/p8-c02-canonical-driver-completion` in a separate worktree.
Fetched origin/main is `3be1aa6`. This branch deliberately stacks on reviewed C01
`30a27aaa31eddfd6ece4ea6736d30582e54fcba6` (two unpublished C01 commits above main).
C01's original worktree is clean and unchanged. No merge/rebase/cherry-pick was
performed. C02 reuses C01's canonical read-only preflight and its mock completion
stop gate; it must not be integrated without that reviewed dependency.

## Design and resulting behavior

Extend the existing DriverCashCompletionController and DriverCompletionCoordinator.
Do not create another completion owner or journal. A Driver-owned interaction
interface adds read checks only; it never generates keys, dispatches or writes.
The default Driver-owned interaction provider is null. No target/actor/vehicle,
SDK client, connected state or hosted execution approval is supplied by C02.

CanonicalDriverCompletionInteraction requires all of:

- Nonrelease build, explicit enabled and reviewed-nonproduction configuration.
- Identical approved backend identity, pinned SDK Session and Driver authority epoch.
- Real connection state and a current owning application session.
- Existing source's canonical Cash context, exact Trip and expected version.
- C01's inProgress-to-completed preflight, active availability and assigned vehicle.
- A current active vehicle row assigned to the configured Driver.

The controller binds one gate before preparation and defaults to no submission.
Preparation only verifies reads. An explicit tap consumes the one attempt before
any awaited validation; duplicate/reentrant taps cannot submit again. The original
source supplies its original Trip/version/key; the controller never synthesizes
or rotates them. The coordinator stages through the existing durable gateway,
then calls an optional final interaction check and revalidates its session before
the existing repository dispatch. Failure/throw/UNKNOWN preserves the original
journal evidence and leaves submission blocked. Existing evidence never reaches
this new callback or grants dispatch. No journal or recovery algorithm was changed.

After the existing adapter's canonical Trip/receipt reads, the interaction performs
an additional authenticated canonical Trip read for this exact command. Success
requires the configured assigned Driver/vehicle, completed status and a version
newer than the original command. An RPC acknowledgement alone is insufficient.
Receipt verification stays separate; completion never implies paid. A lost RPC
response remains UNKNOWN until the existing explicit read-only recovery path.
There are no Payment/Receipt writes or Stripe calls.

Connection/config/authority loss and route retirement invalidate the command
owner without clearing its journal. Covering the screen or backgrounding it does
not rearm completion on pop/resume. When invalidation occurs in route build,
rights are revoked synchronously and notifier publication is deferred so Riverpod
is not mutated during widget build. Gate/controller disposal leaves evidence intact.

## Owned files changed

- `lib/features/driver_flow/application/driver_completion_interaction.dart`
- `lib/features/driver_flow/presentation/providers/driver_completion_interaction_provider.dart`
- `lib/features/trips/application/driver_cash_completion_controller.dart`
- `lib/features/trips/application/driver_completion_coordinator.dart`
- `lib/features/trips/presentation/screens/driver_canonical_trip_screen.dart`
- `lib/features/trips/presentation/widgets/driver_cash_completion_panel.dart`
- `test/driver_completion_interaction_test.dart`
- `test/driver_cash_production_integration_test.dart`
- This evidence document and `docs/ai/ops/CURRENT_STATUS.md`.

## Verification and independent review

Fake canonical-port tests and local loopback SDK fixtures only; no hosted calls.
The existing composition suite binds an explicit test-only FixtureInteraction to
retain its prior adapter/journal assertions. New C02 cases use the real canonical
interaction with fake/loopback reads, not that permissive fixture.

Coverage includes default-off/no approved gate, eligibility, exact command,
assigned active vehicle, invalid transitions, blocked/unapproved/non-Driver actors,
stale versions, session/epoch changes, connection loss, duplicate widget taps,
UNKNOWN/lost responses, canonical read failure, receipt absence, and route cover/pop.
A version change during journal acquisition proves the post-staging guard blocks
RPC and retains the exact original command. Existing coordinator/store/recovery
and C01 stop-gate suites are included in the focused regression run.

- Final focused regression: 429 passed, 0 failed (ten test files).
  The full 2,869-test suite was not repeated.
- Changed-file analyzer: no issues in all eight Dart files.
- Android `flutter build apk --debug --no-pub`: passed after the route fix.
  Existing AGP/Kotlin/SDK XML/Java compatibility warnings remain; no platform edits.
- Full `flutter analyze --no-pub`: 21 inherited diagnostics (3 warnings,
  18 infos), all in ten source files unchanged from C01; exit 1.
- Fresh independent reviewer: APPROVED after one medium route-build notification
  finding was fixed and a push/pop regression passed. No remaining concrete
  critical/high/medium findings. No C03 work was started.

Toolchain: Flutter 3.41.2 / Dart 3.11.0, matching existing CI. Tests/build use the
SDK's temporary resolved dependencies. The committed parent lockfile remains
byte-identical: `bb6148d20da9613013f01aa25dfefe82566360f1`. Exact-lockfile resolution
on this SDK remains incompatible: characters 1.4.0 -> 1.4.1, matcher 0.12.17 ->
0.12.18, material_color_utilities 0.11.1 -> 0.13.0, meta 1.16.0 -> 1.17.0,
test_api 0.7.6 -> 0.7.9. The lockfile already requires Dart >=3.8, despite the
older 3.27.3/3.6.1 guide. No dependency, lockfile, generated plugin or machine
configuration change belongs to this commit. Exact-lockfile/older-SDK acceptance
is not claimed.

## Exact Omar integration request and remaining limits

Keep shared router/providers unchanged in this branch. At the existing canonical
Driver route, Omar must provide `driverCompletionInteractionGateProvider` with a
route/session-owned CanonicalDriverCompletionInteraction using the SAME verified
normal-user client/backend/epoch as driverCashCompletionProvider. Use that
controller's existing recovery.source.load for loadContext; borrow the matching
canonical port and authenticated vehicle SELECT; supply actual connection
invalidations and the application's synchronous session-lifetime predicate.
Require explicit reviewed nonproduction Driver/backend/vehicle configuration;
never take this authority from route parameters, user metadata or MockTrip.
Host composition owns gate/connection/port disposal via ref.onDispose. Config,
auth and connection changes must retire the old binding, never reuse its intent.
The existing runtime flag remains additionally required by the canonical screen.
No gate is supplied by default, including release builds. No hosted activation
is authorized by these Dart seams or local tests.

Also gate direct `/driver/completed` navigation and the Driver branch of shared
TripCompletionScreen on current canonical completed evidence for the exact Driver
Trip. Remove hard-coded Driver success/fare and keep payment/receipt claims
independently verified. C01 removed the owned mock navigation; the inherited
shared direct-navigation gap remains Omar-owned. C02 shows inline canonical
success and does not navigate to that shared legacy success screen.

Yousuf still owns trusted backend/payment consequences. Card remains unsupported
by this Cash slice. Live actor/device acceptance, hosted migration discrepancy
#149 and power-loss durability acceptance remain unproven. C03 may audit existing
restart/recovery only after this checkpoint is reviewed and authorized.

Status: local C02 implemented, independently reviewed; awaiting owner approval.
No push, PR, merge, deployment, hosted mutation or accepted Phase 7 Trip change.
