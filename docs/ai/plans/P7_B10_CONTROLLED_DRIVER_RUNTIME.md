# B10 controlled Driver canonical runtime

This slice composes B07, B08 and B09 in a read-only test entry at
`/driver/canonical-discovery`. It does not replace them or change their backend
contracts. Driver Home shows the entry only with the test flag enabled. The
existing GoRouter session/role guard protects the route; direct navigation while
disabled still displays BLOCKED and cannot construct an SDK port.

## Gates and authority

- `RIDEX_ENABLE_TEST_DRIVER_CANONICAL` defaults false. Both composition providers
  independently deny `kReleaseMode`; release cannot opt in with this define.
- `approvedCanonicalDriverTargetProvider` defaults null. A flag, URL, JWT claim,
  route parameter or UI session does not approve an environment. Owners must
  supply a separately reviewed **nonproduction** target, exact Driver UUID and
  vehicle UUID through trusted root composition before any configured build.
  There is deliberately no inferred production/graduation-project approval.
- Existing application Supabase initialization provenance and AuthService epoch
  binding create the normal-user SDK port. No new SDK client, login, credentials,
  service key, RPC or RLS bypass is added.
- The wrapper pins backend object identity, Driver, SDK session, epoch and active
  owner around reads. Every B07/B09 profile authorization also rereads the exact
  owned active `vehicles` row. Availability, offers and Trips must reference that
  approved vehicle. Vehicle SELECT reuses migration 006's columns, migration 008's
  participant RLS and existing authenticated grants. No schema change is needed;
  actual hosted deployment/grants/acceptance remain unverified.
- B09 retains its two-second/two-row bounded SELECT polling and four-second
  publication deadline. It is not Realtime. B07 independently rereads hinted
  offers and any Trip identity obtained from canonical availability. B08 presents
  only verified identifiers/version/status; unavailable fare, route and Rider
  details remain explicitly unavailable. No fake offer enters runtime composition.

## Lifetime and commands

One auto-disposed provider owns B07/B08/B09 and one polling subscription. The
panel borrows that controller; its one-second display clock grants no authority.
Existing session replacement/logout invalidates captured views immediately.
An auth observation checks the captured SDK session and epoch; replay of the
unchanged initial observation cannot stop a new owner. Changed authority, auth
errors/completion and UI session replacement permanently stop the captured owner.
Session refresh cannot reconstruct it; SDK token refresh changes authority and
requires explicit reentry rather than silently moving authority.
Backgrounding or covering/leaving the route also stops polling. Resume does not
restart it; explicitly leave/reenter the entry for a fresh canonical read owner.
Cancellation suppresses late results and cannot abort an in-flight SDK HTTP read.

Accept/decline stay disabled at the port, B07 and B08 levels. This B10 has **no
command enable define**, even when all read gates pass. A later separately
approved command composition requires review of authorization, durable UNKNOWN
intent ownership across remount/relaunch and idempotency before enabling writes.
This read-only route can safely dispose its repository because it cannot create
a pending command. B07/B08 UNKNOWN/no-replay behavior remains unchanged and is
covered by existing regressions. Completion, settlement, receipts, Stripe/Card
and tracking writes are not connected. No successful hint or RPC is promoted to
Trip assignment authority.

## Local verification and device scope

`test/controlled_driver_runtime_test.dart` uses real providers, B07 repository,
B08 controller/panel and B09 polling with deterministic fake SDK-boundary inputs.
It covers default/release gates, existing sign-in/session/role guards, no/active/
expired offers, backend-blocked/foreign Driver and vehicle rejection, stale and
duplicate observations, network recovery, logout/replacement, auth errors,
background/resume, Navigator Back/reentry, covering routes, remount/disposal,
late reads, independently reread canonical Trips and zero command dispatch.
These are local widget/composition tests, not hosted sign-in or Cash E2E.

Use Flutter 3.41.2 / Dart 3.11.0. Run focused B10 and B07/B08/B09 tests, B09A,
architecture checks, scoped analysis, formatting and `flutter test --concurrency=1`.
Full analysis has an inherited non-green baseline (3 warnings, 17 infos).
Flutter's SDK-pinned dependency resolution differs from the committed older lock
in five transitive package versions; no dependency change is part of this slice.
Retain the actual resolved-version log with external verification evidence.

At read-only inspection both emulators were booted. Rider emulator-5554 has no
`com.ridex.app`; Driver emulator-5556 has 1.0.0 (4001). Existing APKs are from the
older isolated Mock worktree at 5cc55d7, with no approved nonproduction build
attestation. Only the environment template was found in the inspected worktrees;
it is not approval or valid configuration. No Rider build/install is authorized
by that evidence. Do not reuse the old APK as a configured B10 acceptance build.
No device has been installed, wiped, reset or modified by B10.

Run the existing B09A CLI into a **new external directory** after the local commit.
Record its exact SHA, package hash/version and blocked prerequisites. Installed
Driver package identity does not establish source/environment/gate identity.
No trusted environment identity is available; runtime gate is OFF with no target.
All connected S01–S14 actions remain BLOCKED / NOT RUN.

## Remaining owners and safe order

1. Environment owner/all owners: approve nonproduction deployment, operation
   scope, distinct actors and build attestations. Never send credentials in chat
   or put keys into source/Git.
2. Moath: supply reviewed target/Driver/active vehicle, approved Rider build and
   explicit runtime mounting evidence. Command activation and durable recovery
   remain separately reviewed work, not an implied effect of B10.
3. Yousuf: matching deployment/grants/eligibility, expiry scheduler and canonical
   matching/acceptance evidence; no hosted writes are performed by this slice.
4. Sanad: Rider Cash confirmation/matching/exact assignment/tracking entry.
5. Omar/backend owner: server-compatible fresh GPS cadence/quality and safe real
   Realtime delivery, publication, reconnect/disposal and actor isolation proof.
6. Moath/payment owner: independently attest intended-build financial stop gates.
   Completion remains forbidden throughout eventual controlled Cash acceptance.

Owner approval is required before push/PR. This is a local read-only runtime
foundation, not genuine connected acceptance and not production activation.


## Final local verification ? 2026-11-12

- 33 new B10 tests pass; focused B10/B07/B08/B09/B09A/architecture/P6 run:
  **304 passed, zero failures, zero skips**.
- Full `flutter test --concurrency=1 --reporter expanded`: **2766 passed,
  zero failures, four intentional skips**, 4 min 31 s. The two unconfigured live
  Supabase Auth/role and two opt-in real-Realtime tests remain skipped.
- Seven changed Dart files: scoped analyzer clean; formatting zero changes;
  Git whitespace checks passed. Full analyzer remains non-green with exactly
  **3 inherited warnings and 17 infos, zero errors**, exit 1.
- Astra High final static review: **APPROVE**, no blocking findings. Review
  found and rechecked two fixed lifecycle defects: replayed initial auth events
  incorrectly revoked new owners, and watched session refresh recreated stopped
  owners. Deterministic regressions failed before the corresponding fixes and
  now pass. Static review does not certify test execution, devices or hosted E2E.
- SDK-driven lock resolution and generated registrant line endings are retained
  only in external evidence, excluded from the local source commit. No dependency
  upgrade, hosted operation, device mutation or feature activation is included.
- Final clean-commit B09A reports and build/provenance investigation are external
  operator evidence; connected S01?S14 remain BLOCKED / NOT RUN.

## Final local integration follow-up

The original read-only B10 verification above is historical. The separate
`main_acceptance.dart` entry now provides explicit nonproduction target and
independent command opt-in, with a native exclusive persistent decision barrier.
See `docs/ai/verification/P7_FINAL_LOCAL_INTEGRATION.md` for current gates,
limitations, verification and blocked hosted acceptance. Default startup and
release Driver commands remain disabled.
