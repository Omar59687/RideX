# RideX Current Status

## Git Checkpoint

- Active branch: `yousuf/supabase-env-audit`
- Final 4D audit baseline: `18a6c77`, aligned with `origin/main` before the
  uncommitted audit corrections.
- Checkpoint 4D Driver Home UI correction: `31bc7c9`; documentation for this
  correction is being committed separately.
- Checkpoint 4D final review correction: `0e0a9e6`; documentation for this
  correction is being committed separately.
- Checkpoint 4D Driver Home UI implementation: `ab5ce59`; documentation for
  this slice is being committed separately.
- Checkpoint 4D reconnection review correction: `b7e74f7`; documentation updated
  in the separate commit following it.
- Checkpoint 4D reconnection signal wiring implementation: `610835f`;
  documentation updated in the separate commit following it.
- Checkpoint 4D network recovery implementation: `7ddc3f3`; documentation
  updated in the separate commit following it.
- Checkpoint 4D slice 2B2A implementation: `1a2bad3`; documentation updated in
  the separate commit following it.
- Checkpoint 4D slice 2B1 implementation: `c3e85ee`; review correction:
  `49d7702`; documentation updated in the separate commit following it.
- Checkpoint 4D slice 2A implementation: `3669a4d`; documentation:
  `8a2dcf0`. The worktree was clean after both commits.
- Checkpoint 4D slice 1 implementation: `4694a5e`; its documentation is
  committed as `2a37abe`. The worktree was clean after both commits.
- Current `origin/main` at the start of 4D: `300c8d5`
- Checkpoint 4A implementation: `d65a58a`, merged into `main`
- Checkpoint 4B implementation: `2359a81`, merged into `main`
- Checkpoint 4B unresolved map/GPS selection fix: `41dd2f5`, merged into `main`
- Checkpoint 4C routing implementation: `a3cdc1c`, merged into `main` through
  `300c8d5` and approved. Its verification is recorded below.

## Phase 4 Checkpoint Status

- Checkpoint 4A: **Approved.** Twenty-three focused automated cases passed, and
  the project owner reports that Omar completed every remaining physical Android,
  Maps/GPS, permission/fallback, and configuration check successfully.
- Checkpoint 4B: **Approved.** The final replacement-selection guard now blocks
  routing during map/GPS, prediction-details, and forward-geocode resolution.
  All 33 focused Flutter cases pass, and the project owner reports that Omar
  completed every remaining physical/live/configuration check successfully.
- Final full verification: `flutter analyze` found no issues;
  `flutter test --no-pub` passed 144 tests with 2 intentional skips and known
  non-failing SVG warnings.
- Checkpoint 4C: **Approved.** Focused verification passed 15 cases, the complete
  Deno Edge Function suite passed 23 cases, and the full Flutter suite passed
  144 cases with 2 intentional skips. The deployed authenticated Google route,
  physical Android polyline, service-backed distance/duration, selected
  endpoints, and endpoint-change recalculation are verified.
- Checkpoint 4D: **Approved on 2026-09-20.** Checkpoints 4E through 4G remain
  incomplete, so Phase 4 is not approved and Phase 5 must not begin.
- Checkpoint 4D slice 1: **Completed.** Commit `4694a5e` adds the Driver location
  provider-neutral availability, sample, and saved-location contracts; sanitized
  failure types; canonical Supabase availability/latest-location reads; RPC-only
  `driver_record_location` publishing; and deterministic Mock behavior. The exact
  implementation files are `lib/core/errors/driver_location_exception.dart`,
  `lib/core/models/driver_availability.dart`,
  `lib/core/models/driver_location.dart`,
  `lib/core/providers/repositories_providers.dart`,
  `lib/core/repositories/driver_location_repository.dart`,
  `lib/core/repositories/mock_driver_location_repository.dart`,
  `lib/core/services/driver_location/driver_location_service.dart`,
  `lib/core/services/driver_location/supabase_driver_location_service.dart`, and
  `test/driver_location_repository_test.dart`.
- Slice 1 verification: changed Dart files formatted; focused Driver location suite
  passed 6 tests; `flutter analyze` reported no issues; `git diff --check` and
  staged `git diff --cached --check` passed before commit.
- Slice 1 limitations: no GPS stream, tracking controller, Driver Home UI, Realtime
  subscription, matching, background behavior, lifecycle/reconnect recovery, or
  live Supabase verification. Slice 2A addressed the GPS stream boundary below;
  Slice 2B follows with the Riverpod tracking controller, ordering, lifecycle,
  reconnect, and recovery tests.
- Checkpoint 4D slice 2A: **Completed.** Commit `3669a4d` adds the separate
  provider-neutral foreground `DriverGpsStreamService`, `DriverLocationFix`
  model, and `GeolocatorDriverGpsStreamService` adapter. The adapter maps point,
  device timestamp, and available accuracy, heading, and speed; drops invalid
  coordinates; omits invalid optional measurements; sanitizes provider stream
  errors; and propagates cancellation. The existing one-shot Rider location
  service is unchanged. No Riverpod controller, backend publishing, Driver Home
  UI, Realtime, background permissions, or matching was added.
- Slice 2A verification: changed Dart files formatted; focused test
  `test/driver_gps_stream_service_test.dart` passed 4 tests covering mapping,
  invalid fixes, stream errors, and cancellation; `flutter analyze` reported no
  issues; staged diff check passed before commit.
- Slice 2A limitation: no tracking controller, ordering, lifecycle, reconnect,
  canonical recovery, UI, or live Supabase verification. Slice 2B1 and 2B2A
  addressed the controller and foreground lifecycle foundations below; network
  and Realtime reconnect/recovery entry point is recorded below.
- Checkpoint 4D slice 2B1: **Completed.** Commit `c3e85ee` adds the Riverpod
  Driver tracking controller with explicit start/stop, canonical availability
  and latest-location reads before owning one foreground stream, ordered
  sequential publication, sequence values above the saved maximum, and
  missing-accuracy/older-timestamp filtering. It allows one publish at a time
   and stops on publish failure without blindly retrying a rejected sequence.
   No UI, app lifecycle, reconnect, Realtime, background tracking, or matching
   was added. Review correction commit `49d7702` carries the canonical active
   Trip ID into `onTrip` samples and invalidates unfinished starts and queued
   work across Stop, disposal, and later tracking sessions.
- Slice 2B1 verification: changed Dart files formatted; focused test
  `test/driver_tracking_controller_test.dart` passed 9 tests covering
  eligibility, start/stop, `onTrip` publishing, pending-start invalidation,
  duplicate starts, sequence ordering, invalid/stale fixes, publish failure,
  and queued-work invalidation across restart; `flutter analyze` reported no
  issues; staged diff check passed before the correction commit.
- Slice 2B1 limitation: lifecycle handling, reconnect, canonical recovery, UI,
  and live Supabase verification remain unimplemented. Slice 2B2A addressed
  lifecycle handling below; network and Realtime recovery is recorded below.
- Checkpoint 4D slice 2B2A: **Completed.** Commit `1a2bad3` adds the testable
  lifecycle boundary and foreground background/resume handling. Background
  entry cancels the GPS stream and invalidates pending work while preserving
  deliberate tracking intent; foreground return re-reads canonical
  availability/latest location before resuming one stream. Explicit Stop and
  sign-out clear intent, and repeated resumes do not duplicate streams. Session
  sign-out now stops tracking before authentication sign-out. No UI, network or
  Realtime reconnect, background permission, or matching was added.
- Slice 2B2A verification: changed Dart files formatted; focused test
  `test/driver_tracking_controller_test.dart` passed 13 tests, including
  background/resume, repeated resume, Stop while backgrounded, and sign-out;
  `flutter analyze` reported no issues; staged diff check passed before commit.
- Slice 2B2A limitation: network and Realtime reconnect/recovery, UI, live
  Supabase verification, background permissions, and matching remain
  unimplemented. Network recovery and reconnection signal wiring are addressed
  below; Driver Home UI remains next.
- Checkpoint 4D network recovery: **Completed.** Commit `7ddc3f3` adds the
  testable `recoverAfterConnectivity()` entry point. After publish/network
  failure it cancels the old stream while preserving deliberate tracking intent,
  re-fetches canonical availability/latest location, derives the next sequence,
  and opens one replacement foreground stream without replaying failed samples.
  Repeated recovery and recovery after Stop, sign-out, backgrounding, or
  disposal are ignored. No connectivity package, Realtime subscription, UI,
  background tracking, or matching was added.
- Network recovery verification: changed Dart files formatted; focused test
  `test/driver_tracking_controller_test.dart` passed 16 tests, including higher
  canonical sequence recovery, repeated recovery signals, and Stop during
  recovery; `flutter analyze` reported no issues; staged diff check passed
  before commit.
- Network recovery limitation: Driver Home UI and live Supabase verification
  remain unimplemented. Reconnection signal wiring is addressed below;
  background permissions and matching remain unimplemented.
- Checkpoint 4D reconnection signal wiring: **Completed.** Commit `610835f`
  adds a disposable, testable connection-status boundary, a no-op Mock
  implementation, and a Supabase adapter that owns one lightweight Realtime
  channel while tracking is requested. Initial subscription is not recovery;
  disconnect/error followed by successful resubscription invokes
  `recoverAfterConnectivity()` once. Stop, sign-out, backgrounding, and
  disposal remove the channel. No `driver_locations` changes subscription,
  dependency, UI, background permission, or matching was added.
- Reconnection wiring verification: changed Dart files formatted; focused test
  `test/driver_tracking_controller_test.dart` passed 21 tests, including
  disconnect/reconnect, repeated status events, Stop while disconnected,
  background/resume, cleanup, canonical recovery, and duplicate-stream guards;
  `flutter analyze` reported no issues; staged diff check passed before commit.
- Reconnection wiring review correction: **Completed.** Commit `b7e74f7` makes
  connection events generation-bearing, clears pending recovery on intentional
  disconnects, and ignores late callbacks from removed channels or old tracking
  sessions. A new session's initial subscription cannot trigger recovery.
- Reconnection correction verification: the focused
  `test/driver_tracking_controller_test.dart` suite passed 22 tests, including
  Stop/restart, background/resume, late removed-channel status, and genuine
  disconnect/reconnect; `flutter analyze` reported no issues; staged diff check
  passed before commit.
- Reconnection wiring limitation: live Supabase verification, background
  permissions, and matching remain unimplemented. The Driver Home tracking UI
  slice is completed below; reconnection behavior was not reworked or
  re-verified as part of that UI slice.
- Checkpoint 4D Slice 3: **Completed.** Commit `ab5ce59` adds a separate Driver
  location-sharing card to `DriverHomeScreen` with Start and Stop controls. The
  existing foreground permission flow runs only after Start is tapped. The card
  presents stopped, starting, sharing, and unavailable states, sanitized
  permission/backend messages, and the age of the last server-confirmed
  location from the controller's canonical `received_at` value. The existing
  session-local online switch remains explicitly Mock presence and independent
  from real location sharing. Focused widget coverage is in
  `test/driver_home_location_sharing_test.dart`.
- Slice 3 verification: changed Dart files formatted; focused
  `test/driver_home_location_sharing_test.dart` passed 4 tests; `flutter analyze`
  reported no issues; `git diff --check` passed. The completed reconnection
  suite was intentionally not rerun for this UI-only slice.
- Slice 3 next step: Checkpoint 4D final security/architecture review, full
  non-live regression verification, and supported physical/authenticated Driver
  tracking verification. Checkpoint 4E must not start from this slice.
- Slice 3 correction: **Completed.** Commit `31bc7c9` adds the lifecycle-derived
  `Paused` status when requested tracking is stopped for app backgrounding. Stop
  now publishes its stopped state before asynchronous cleanup and captures the
  connection before awaiting cancellation, fixing the provider-disposal race.
  The widget test taps Stop, waits for the controller to reach `stopped`, checks
  that demo presence is unchanged, and covers the paused background state.
- Slice 3 correction verification: focused
  `test/driver_home_location_sharing_test.dart` passed 5 tests; `flutter analyze`
  reported no issues; formatting and `git diff --check` passed. The reconnection
  suite was not rerun.
- Checkpoint 4D final approval review on 2026-09-17: **Automated blockers
  corrected; physical/live approval was still pending at that time.** The review began on the clean
  `codex/phase-4d-driver-location` worktree and confirmed the intended
  authorization/RPC boundary, canonical availability checks, sequence recovery,
  single-stream/publisher ownership, Stop/sign-out/background cleanup,
  reconnect recovery, and separate Driver Home sharing status. No 4E or later
  scope was added or reviewed. The controller now rejects a fix unless its
  `recordedAt` is strictly after `_latestRecordedAt`; equal-timestamp coverage
  was added. The obsolete background expectation now checks `paused`, and the
  Driver Home map test scrolls its `ListView` to the shared map before checking
  the overridden `fake-google-map`; production map code was not changed because
  the map path is intact.
- Final review correction verification: the three affected suites passed 35
  tests; `dart format --output=none --set-exit-if-changed lib test` passed with
  183 files checked and 0 changed; `flutter analyze` passed with no issues; and
  full non-live `flutter test` passed 180 tests with 2 intentional live-Supabase
  skips. Known non-failing `flutter_svg` unsupported `<filter>` warnings
  appeared.
- That 2026-09-17 review left physical-device and authenticated Supabase checks
  outstanding. They were completed later and are recorded in the final approval
  entry below.
- Verification attempt on 2026-09-17 found the Android toolchain installed, but
  `flutter devices` listed only Windows, Chrome, and Edge; no physical Android
  device or emulator was available. `adb devices -l` could not run because `adb`
  is not on PATH. `flutter doctor -v` otherwise reported a healthy Android
  toolchain. No device permission, Start/Stop, physical background/resume,
  canonical-write, reconnect, or unauthorized-write check was performed.
- The same attempt found no `SUPABASE`, `RIDEX`, `ANDROID`, or `ADB` environment
  variables. No credential values were displayed. The live command
  `flutter test --no-pub test/live_supabase_auth_test.dart
  test/live_supabase_role_state_test.dart` completed with both tests skipped
  because `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` were absent. No
  authenticated Supabase 4D check was performed.
- The Android manifest currently declares coarse/fine foreground location only;
  it does not declare background-location permission. App background/resume can
  therefore be checked only as foreground-stream cancellation and resume, not as
  continuous OS-background tracking.
- Required next prerequisites are an authorized Android device visible as
  `device` through `adb`/`flutter devices`, a hosted Supabase project with
  migrations `001` through `022`, local uncommitted publishable URL/key
  `--dart-define` values, an approved non-blocked Driver with vehicle and
  availability, and a separate Rider or pending/blocked account for rejection.
  The manual sequence is documented in the 4D verification-attempt section of
  `Plan.md`: permission then Start/Stop, canonical sequence/timestamp inspection,
  app background/resume, connectivity recovery, and negative RPC/no-row checks.
- Checkpoint 4D final approval on 2026-09-20: **Approved.** The project owner
  reported that all physical/live checks passed: Android startup/login,
  permission timing, real GPS sharing with canonical sequence/timestamp growth,
  hosted persistence, Stop, foreground lifecycle recovery, network/reconnection
  recovery, and Rider rejection with HTTP 403 / SQLSTATE 42501 and no inserted
  row. The final audit also corrected connection-start stream cleanup and made a
  stale-sequence rejection automatically re-fetch canonical state before
  restarting one stream.
- Final 4D verification: 69 focused 4D/Driver/location/session tests passed;
  full non-live `flutter test --no-pub` passed 184 tests with 2 intentional live
  skips; `flutter analyze --no-pub` found no issues; Dart formatting checked 183
  files with 0 changes; and `git diff --check` passed apart from line-ending
  warnings on pre-existing generated desktop plugin files. Known non-failing
  `flutter_svg` `<filter>` warnings appeared.
- Scope remains narrow: 4D provides foreground Driver location sharing and
  recovery. Tasks 4.24 through 4.27 are complete as recorded below; tasks 4.28
  through 4.30, matching, Rider live-trip tracking, and continuous OS-background
  location remain later work.
- Checkpoint 4E task 4.24: **Completed and verified on 2026-09-22.** The existing
  4D architecture and canonical Driver-location state are preserved. It adds
  movement filtering; the controller suppresses unchanged location content and
  coalesces queued callbacks to the latest pending meaningful fix while
  retaining one ordered publisher; and the Driver Home tracking watch is
  isolated to the sharing card so confirmed writes do not rebuild the whole
  screen/map. Focused fakes assert a maximum of one active GPS subscription
  across duplicate starts and reconnect recovery.
- Task 4.24 verification: the GPS service/controller suites passed 32 tests,
  the Driver Home sharing suite passed 5 tests, and `flutter analyze --no-pub`
  found no issues. At that task boundary, state-dependent cadence and tasks 4.25
  through 4.30 remained incomplete.
- Checkpoint 4E task 4.25: **Completed and verified on 2026-09-22.** A centralized
  provider-neutral policy maps canonical `DriverAvailabilityState`: `onTrip`
  selects high accuracy, a 10-meter movement filter, and a 5-second minimum
  accepted-update interval; `available` and `reserved` select medium accuracy,
  a 25-meter movement filter, and a 20-second minimum interval. Start, resume,
  and recovery use existing canonical reads. Explicit canonical synchronization
  coalesces concurrent requests into at most one trailing read, retains an
  unchanged profile, and cancels a changed stream before opening one replacement
  without reconnecting or duplicating subscriptions. Reconnect recovery is
  deferred until synchronization completes, and sync requests arriving during
  start/recovery run after that canonical setup finishes. Explicit sync ignores
  ineligible states, leaving automatic offline-state stopping to task 4.26.
- Task 4.25 verification: the GPS service/controller suites passed 47 tests, the
  Driver Home sharing suite passed 5 tests, and `flutter analyze --no-pub` found
  no issues. At that task boundary, tasks 4.26 through 4.30 and the Checkpoint 4E
  approval gate remained incomplete. No polling, Realtime availability
  subscription, automatic offline-state monitoring, state-based stopping,
  broader resource policy, accuracy-resilience, UI-state, or error-policy work
  was implemented.
- Checkpoint 4E task 4.26: **Completed and verified on 2026-09-24.** Explicit
  canonical synchronization now stops all owned tracking resources for
  `offline`, missing, or otherwise ineligible availability. It invalidates
  queued location work, cancels GPS, disconnects the tracking channel, and
  reports a sanitized ineligible state while preserving explicit sharing intent
  and latest canonical location metadata. A later explicit eligible sync
  re-reads canonical sequence state, reconnects, and starts the existing
  state-appropriate profile. Lifecycle, explicit Stop/sign-out, recovery
  ordering, write coalescing, and the one-active-subscription invariant remain
  intact. No polling or Realtime availability subscription was added.
- Task 4.26 verification: the GPS service/controller and Driver Home sharing
  suites passed 58 tests; `flutter analyze --no-pub` found no issues; the full
  `flutter test --no-pub` suite passed 208 tests with 2 intentional live-test
  skips; and `git diff --check` passed. At that task boundary, tasks 4.27 through
  4.30 and the Checkpoint 4E approval gate remained incomplete.
- Checkpoint 4E task 4.27: **Completed and verified on 2026-09-24.** The
  provider-neutral tracking configuration now owns the complete device/write
  resource policy. `available` uses low accuracy, a 50-meter device/write
  threshold, a 30-second minimum cadence, and a two-minute maximum silence;
  `reserved` uses medium accuracy, 25 meters, 20 seconds, and one minute;
  `onTrip` preserves high accuracy, 10 meters, and five seconds, with a
  15-second maximum silence. The controller suppresses sub-threshold movement
  and measurement-only jitter using provider-neutral great-circle distance.
  Maximum-silence updates consume only fixes emitted by the existing stream, so
  no timer, polling, extra canonical read, or additional subscription was added.
  Existing write coalescing, ordering, recovery, and shutdown behavior remains
  intact.
- Task 4.27 verification: the GPS service/controller and Driver Home sharing
  suites passed 62 tests; `flutter analyze --no-pub` found no issues; the full
  `flutter test --no-pub` suite passed 212 tests with 2 intentional live-test
  skips; and `git diff --check` passed. Tasks 4.28 through 4.30 and the Checkpoint
  4E approval gate remain incomplete.
- Detailed evidence:
  `docs/ai/verification/PHASE_4AB_FINAL_VERIFICATION_2026-09-14.md`
  and `docs/ai/verification/PHASE_4C_IMPLEMENTATION_VERIFICATION_2026-09-16.md`

The Rider V2 sections below describe the accepted historical UI scope. Their
original exclusions do not override the newer Phase 4 status above.

## Completed Phases

| Commit | Completed phase |
|---|---|
| `781b437` | Urban Aurora theme, semantic tokens, dark mode, and motion |
| `a015caa` | Shared RideX V2 components, SVG runtime assets, and native map painter |
| `eed7155` | Rider authentication, real email flow, and mock-only phone/OTP |
| `5327cb7` | Rider home and destination-first booking flow |
| `b31ec2f` | Rider search, trip lifecycle, cancellation, completion, and rating |
| `9021f6a` | Rider trip history, repository-backed details, filters, and rebooking |
| `f3a35aa` | Repository-backed rider profile, disabled previews, and real sign-out |
| `96d7db9` | Rider notifications, session-local preferences, settings, and driver preservation |
| `a39aeee` | Responsive, accessibility, route, provider, theme, and driver regression pass |
| `f4e0371` | Official Plus Jakarta Sans static fonts, license, weight mappings, and asset verification |
| `b5dc11c` | Final Rider V2 documentation reconciliation, visual audit, and cleanup |
| `33a882e` | Pre-merge Phase 1: database authorization boundary |
| `687bcd2` | Pre-merge Phase 2: three-role Flutter domain and trusted session |
| `3331e70` | Pre-merge Phase 3: public Rider authentication flow and router guards |
| `10c4a30` | Pre-merge Phase 4: light-first visual correction |
| `51c5a5d` | Pre-merge Phase 5: responsive and accessibility hardening |
| `67b2b74` | Pre-merge Phase 6: final verification, documentation, and handoff assessment |

**Do not redo, replace, or restart these completed phases.** Rider V2 has no remaining implementation checkpoint.

## Verification Status

Final Phase 6 verification on July 28, 2026:

- `dart format lib test`: 119 files checked, 0 changed.
- Focused authentication, public-role, route-guard, light-first theme, responsive/accessibility, Driver-regression, and migration-contract command: 40 tests passed.
- `flutter analyze`: no issues found.
- Full non-live `flutter test`: 67 tests passed with 2 intentional live Supabase skips.
- The test suite logs non-failing `flutter_svg` warnings for unsupported SVG `<filter>` elements.
- Local Supabase verification passed: `npx supabase@latest db reset --local` completed, and all 29 assertions in `supabase/tests/database/004_role_authorization_boundary.test.sql` passed with `npx supabase@latest test db`.
- `flutter analyze`: no issues found.
- Full non-live `flutter test`: 67 tests passed with 2 intentional live Supabase skips.
- The local Supabase stack was stopped after verification. No Supabase linking, remote query, remote SQL, migration application, `db push`, deployment, or service-role operation was performed.

## Rider V2 Final Handoff

Rider V2 implementation, documentation, visual comparison, verification, and cleanup are complete. No Rider V2 implementation checkpoints remain. The branch has not been pushed or merged and no Pull Request has been opened; those actions require explicit approval.

The complete `origin/main...HEAD` diff was reviewed across 120 tracked files, including the final documentation changes. It adds no HTML embedding, WebView, map SDK, generated Open Design metadata, credentials, machine-specific paths, reference edits, or unrelated product changes. The only Driver-specific product diff is regression coverage. Ignored local Flutter/build metadata contains machine paths but is not part of the feature diff and remains untracked. Existing tracked files under `supabase/.temp/` predate this branch, contain project linkage metadata but no discovered secret, and were preserved as unrelated baseline state.

`git diff --check origin/main...HEAD` reports the official `assets/fonts/OFL.txt` trailing space at line 21. That source formatting is intentionally preserved because changing it would invalidate the verified official license-file hash.

Role and route audit confirms that public signup, phone OTP, and demo entry are Rider-only; trusted profile data determines Rider, Driver, or Admin routing; blocked and malformed profile states fail closed; and Rider, Driver, and Admin route policies remain separated. `RideXApp` is light-first while the explicit dark theme remains available.

Migration deployment order is `001_create_users_and_profiles.sql`, then `002_enable_rls_and_policies.sql`, then `003_create_auth_signup_trigger.sql`, then `004_enforce_role_authorization_boundary.sql`. Migration `004` must not be deployed until its local pgTAP suite passes. Remote deployment remains outside this checkpoint.

## Visual Comparison

The final audit compared the native Flutter screens with `RIDEX-V2-DESIGN.md`, the rider gallery, brand board, system CSS, JavaScript screen definitions, structural token JSON, and identity assets under `references/UI/`. The implementation preserves the Urban Aurora palette and semantics, bundled typography, light/dark themes, identity, destination-first flow, provider-owned state, responsive foundations, and native component strategy.

Accepted implementation deviations from the conceptual gallery:

- The native `CustomPainter` map is intentionally illustrative and less geographically detailed than the gallery; no live map, GPS, routing, geocoding, or tracking was introduced.
- Authentication, searching, map markers, vehicle cards, navigation, and completion surfaces use simplified native compositions rather than pixel-identical HTML/CSS layouts.
- Deterministic demo controls and limitation messages remain visible where production integrations do not exist.
- Completion and rating remain separate approved routes, and driver screens retain their existing visual presentation.
- Launcher and platform resource branding remains deferred by approved decision.

These deviations do not replace provider, repository, routing, session, authentication, sign-out, or driver behavior and do not fabricate backend capabilities.

## Pre-Merge Correction Sequence

A new six-checkpoint pre-merge correction sequence is active under `docs/ai/plans/PRE_MERGE_ROLE_THEME_CORRECTIONS.md`. It corrects the production role boundary, three-role Flutter architecture, public authentication flow, light-first presentation, and responsive/accessibility coverage without reopening completed Rider V2 scope or deferred integrations.

### Completed Pre-Merge Checkpoints

- Phase 1, database authorization boundary: `33a882e`.
- Migration `004_enforce_role_authorization_boundary.sql` makes public signup Rider-only, safely backfills missing role profiles, reasserts least-privilege client grants, and adds guarded Admin Driver-promotion and approval RPCs.
- The migration preserves existing roles, blocked values, Driver approval values, and existing profile rows. Missing Driver profiles are added as pending.
- A 29-assertion local pgTAP suite covers malicious signup metadata, direct mutation denial, Admin and blocked-Admin behavior, Driver promotion/approval/rejection, grants, and function hardening.
- Phase 2, three-role Flutter domain and session: `687bcd2`.
- `RideRole` now strictly parses Rider, Driver, and Admin. Missing or malformed user and Driver profile data produces a fail-closed `profileError` session instead of defaulting to Rider or pending Driver.
- Sign-in no longer accepts a caller-selected role. Public signup, phone OTP, and demo contracts are Rider-only, while exact mock Rider, Driver, and Admin credentials remain isolated inside `MockAuthRepository` with no email-pattern inference.
- Driver approval parsing is strict, blocked users retain priority over role state, and existing approved/pending/rejected Driver and sign-out behavior remains preserved.
- Phase 3, public authentication flow and router guards: `3331e70`.
- The public Rider/Driver selector and its state are removed. Onboarding Continue and Skip open the shared sign-in flow, and public signup explicitly creates a Rider account.
- Explicit route policies protect public, Rider, Driver, Admin, shared, application-status, blocked, and profile-error destinations. Admin and profile-error states have honest protected placeholder behavior.
- Phase 4, light-first visual correction: `10c4a30`.
- `RideXApp` now defaults to `ThemeMode.light` regardless of device dark mode while preserving `AppTheme.dark()` for a future explicit preference.
- Ordinary application surfaces use the approved Urban Aurora light semantics. Intentional midnight branded panels use scoped `RideXTheme` roles rather than scattered colors, preserving Rider and Driver presentation.
- Phase 5, responsive and accessibility hardening: `51c5a5d`.
- Expanded Rider coverage validates 320x568, 360x800, 375x667, 390x844, 430x932, phone landscape, and 600/800px tablet layouts; 1.0, 1.3, and 2.0 text scales; reduced motion; keyboard-open sign-in; target sizes; semantics; focus; short-screen scrolling; and sensible tablet bounds.
- Home availability now wraps status text and gives its vehicle cards sufficient large-text height. Destination route fields gain sufficient large-text height without changing booking state or behavior.

Phase 1 verification on July 24, 2026:

- `dart format test/supabase/role_authorization_migration_test.dart`: 1 file formatted.
- `flutter test test/supabase/role_authorization_migration_test.dart`: 4 tests passed.
- `flutter analyze`: no issues found.
- `git diff --cached --check`: passed before the implementation commit.
- The pgTAP suite could not execute locally because Supabase CLI is not installed and Docker Desktop's Linux engine remained stopped/unavailable with HTTP 500 responses. The suite must run against a local Supabase stack before migration deployment.
- No Supabase project linking, reset, remote query, remote SQL, migration application, `db push`, or service-role operation was performed.

Phase 2 verification on July 24, 2026:

- Targeted `dart format` completed for all 25 Phase 2 implementation and test files with no outstanding formatting changes.
- `flutter test test/auth_domain_session_test.dart test/auth_v2_test.dart test/role_selection_test.dart test/session_route_guards_test.dart`: 21 tests passed.
- `flutter test test/driver_accept_trip_test.dart`: 1 Driver regression test passed.
- `flutter analyze`: no issues found.
- `flutter test`: 59 tests passed with 2 intentional live Supabase skips.
- The suite retains the known non-failing `flutter_svg` warnings for unsupported SVG `<filter>` elements.
- `git diff --cached --check`: passed before the implementation commit.
- No Supabase project linking, reset, remote query, remote SQL, migration application, `db push`, or service-role operation was performed.

Phase 3 verification on July 24, 2026:

- `flutter test test/session_route_guards_test.dart test/onboarding_navigation_test.dart test/role_selection_test.dart test/auth_v2_test.dart test/driver_accept_trip_test.dart`: 20 tests passed.
- `flutter analyze`: no issues found.
- `flutter test`: 63 tests passed with 2 intentional live Supabase skips.
- The suite retains the known non-failing `flutter_svg` warnings for unsupported SVG `<filter>` elements.

Phase 5 verification on July 24, 2026:

- `flutter test test/rider_v2_adaptive_accessibility_test.dart test/driver_accept_trip_test.dart`: 10 tests passed.
- `flutter analyze`: no issues found.
- `flutter test`: 67 tests passed with 2 intentional live Supabase skips.
- The suite retains the known non-failing `flutter_svg` warnings for unsupported SVG `<filter>` elements.

## Final Pre-Merge Assessment

All six approved pre-merge phases are complete. Phase 6 completed the final diff audit, documentation reconciliation, formatting, focused verification, analysis, full non-live test run, and local pgTAP verification. The pgTAP merge blocker is resolved. The branch is ready for Pull Request review after explicit user approval to open one. No push, merge, deployment, or Pull Request was performed.

## Font Status

Plus Jakarta Sans Regular 400, Medium 500, SemiBold 600, Bold 700, and ExtraBold 800 are bundled under `assets/fonts/` with the official `OFL.txt`. Flutter declares each static weight under the `Plus Jakarta Sans` family, and focused tests verify the files load and representative theme styles use the intended family and weights. No substitute fonts or `google_fonts` dependency were added.

## Known Limitations

Phone OTP, Rider live-trip location, booking/history persistence,
card payments, promotions, rewards, calls/messages, safety services, saved-place
persistence, notification delivery/persistence, and rating persistence are not
production integrations. Google Maps/GPS, place search, and routing foundations
now exist, and Checkpoints 4A through 4D are approved. Trip History remains
Mock-backed with static sample endpoints; GPS optimization and Rider live-trip
tracking remain later Phase 4 work.
Notification read state, preferences, booking drafts, active trips, and driver
availability are session-local and reset on sign-out. Unsupported behavior must
remain explicit demo, session-local, disabled, or Coming soon behavior.
