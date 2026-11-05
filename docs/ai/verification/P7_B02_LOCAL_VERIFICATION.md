# P7-B02 local verification and P2 remediation

Date: 2026-11-04. Owner: Moath. Issue #107.
Branch: `feature/p7-b-driver-flow`.
Base/unchanged HEAD: `0be40db6f78ee80c11bb0cde074e1750a6074f6b`.

## Scope and source identity

The remediation started with the existing uncommitted B02 slice: one modified
tracked Driver Home file and six untracked files. It was not a clean worktree.
The earlier three-defect remediation edited five B02 working files. This final
scope-retirement fix edits only the controller, controller test and two B02
documents; the widget tests are preserved from that earlier remediation:

- `lib/features/driver_flow/presentation/providers/driver_availability_controller.dart`
- `test/driver_availability_controller_test.dart`
- `test/driver_availability_screen_test.dart`
- `docs/ai/plans/P7_B02_DRIVER_AVAILABILITY.md`
- `docs/ai/verification/P7_B02_LOCAL_VERIFICATION.md`

The B02 screen and pre-existing Driver Home import/preview action were preserved
without remediation edits. The total pending B02 slice remains seven paths.
All eight committed B01 files are unchanged from HEAD, including contract, provider,
fake and tests. No shared router/session/GPS/financial/backend file was edited.

Final five-file Dart source SHA-256:
`de1900a42217c5445ef2991a43b5a0008fc00f061572a4c7625f2e1de89dee70`.
Recipe: sorted relative paths (controller, screen, Driver Home, two B02 test files),
each UTF-8 path + NUL + exact file bytes + NUL. This identifies the uncommitted
verified source; the baseline SHA alone does not identify B02.

## Defects reproduced before correction

Five added controller regressions ran against the original implementation:

```powershell
flutter test --no-pub test/driver_availability_controller_test.dart --name 'survives|high-water|wins over' --reporter expanded
```

**0 PASS / 5 FAIL; exit 1.** Pending and unknown attempts became writable after
listener removal/remount; loading/null and unavailable/null erased the v8 barrier
and accepted v7; unauthorized v7 after reserved v8 became stale instead of terminal
unauthorized. These were reproduced new failures, not pre-existing failures.
An initial filter invocation used --plain-name with a regex and selected no tests;
the corrected --name command above produced the five actual regression failures.

## Remediation and regression mapping

1. Persistent NotifierProvider ownership shares the command lock and uncertain
   attempt across screen lifetimes in one container/scope. Scope/repository change
   or container disposal retires subscriptions and asynchronous work by epoch.
   Controller and widget tests cover pending/unknown removal/remount, callbacks
   captured by an old screen, no duplicate dispatch, unchanged reads, unrelated
   version advancement, revoked scope, late reads/replies and independent containers.
2. A highest-accepted availability version is separate from optional display data.
   Tests cover reserved v8 -> loading/null or unavailable/null -> ready v7, read
   failure plus missing data, onTrip v8 -> missing data -> equivalent v8/new v9,
   and fresh session/repository baselines at v1.
3. Ordered same-session/source unauthorized events latch before version checks.
   Tests cover reserved v8 -> unauthorized v7, later ready v9, disabled refresh
   and writes, pending write plus late success across remount, fresh authorized
   scopes and retired repository events that cannot affect the replacement.

B01 has no authoritative availability reconciliation API. No such API is invented.
Unknown outcomes stay blocked until explicit scope retirement, even after a newer
simulated observation. Only a still-pending command's correlated simulated reply
can resolve that pending attempt (validated session/state/vehicle/version/revision).
This is local fixture evidence, never canonical availability. Original tests that
allowed unrelated version advancement to restore writes were tightened. Tests that
assumed widget autoDispose were changed to test actual scope retirement instead.

## Final scope-retirement regression and correction

Root cause confirmed in installed Riverpod 2.6.1: Notifier.state invokes
_element.flush(), which may rebuild derived dependencies and then build() on
the same notifier. A callback's pre-getter epoch check could pass before that
rebuild; the remainder then used its old captured scope against the new state.

Added nine deterministic no-flush regressions before correcting the controller:

```powershell
flutter test --no-pub test/driver_availability_controller_test.dart --name 'no-flush' --reporter expanded
```

**Before correction: 2 PASS / 7 FAIL; exit 1.** All six ready/unauthorized event
cases (scope replacement, scope clearance, repository replacement) failed, plus
the delayed simulated command case published old version-99 data. Unauthorized
and unknown command outcomes without a snapshot already passed those assertions.
**Immediately after correction: 9 PASS / 0 FAIL; exit 0.** Same nine tests.

The new _AvailabilityLifetime record captures epoch, scope identity and repository
identity. _viewFor rejects an already-retired epoch before touching state, reads
state to flush dependencies, then rechecks the epoch and both identities before
returning a local view. Every state getter in the controller uses this helper.
All synchronous observations/errors and async read/command outcomes, failures and
finally cleanup carry that lifetime. Old work cannot change new-scope version,
authorization, publication or attempt state. Operations use the captured repository.
The persistent provider, high-water version, unknown protection and authorization
latch remain in place; no retry/replay or B01 API change was added.

Ten further cases bring this fix to **19 new controller tests**: scope-only
replacement on the same repository (ready/unauthorized), retired stream error,
six reply-only read/command success/unauthorized/exception cases, and an old finally
running while the replacement command remains pending then unknown. Reply-only
responses publish no event before completion, so the async guard is exercised
independently. No-pump/no-flush intervals are explicit. New cases use synchronous
controlled streams, Completers, container.pump and microtask turns, not arbitrary
sleep durations. Assertions cover visible state/publications, version-1 recovery,
Driver generation/identity, selected vehicle, expected version and command counts.
Existing remount, single-flight and independent-container cases remain unchanged.

An intermediate expanded run passed 176 and failed one new cleanup test: the test
assumed B's initial read had completed. It now explicitly refreshes and asserts B
is writable before starting B's delayed command. The targeted corrected test passes.
Initial scoped analysis found five new braces infos; all were fixed before final
focused/full verification. These resolved development findings are not pre-existing.

## Independently executed final verification

The results below were executed during this remediation, not copied from the
initial developer-reported evidence. Runtime: Flutter 3.41.2 / Dart 3.11.0.
The guide's Flutter 3.27.3 / Dart 3.6.1 was not executed. Existing package
configuration was reused with --no-pub; no dependency resolution was run.

```powershell
flutter test --no-pub test/driver_availability_controller_test.dart test/driver_availability_screen_test.dart test/driver_flow_contract_test.dart test/fake_driver_flow_repository_test.dart test/driver_flow_repository_provider_test.dart --reporter expanded
```

**180 PASS / 0 FAIL / 0 SKIP; exit 0.** 102 unchanged B01 tests plus 78 B02 tests
(60 controller / 18 widget). This final fix adds 19 cases to the preceding 59-case
B02 suite. All earlier remount/unknown/single-flight/isolation tests remain green.

```powershell
flutter test --no-pub test/driver_accept_trip_test.dart test/driver_cash_completion_hook_test.dart test/session_route_guards_test.dart test/driver_home_location_sharing_test.dart test/driver_cash_production_integration_test.dart test/active_trip_creation_lifecycle_test.dart test/trip_status_transition_test.dart --reporter expanded
```

**123 PASS / 0 FAIL / 0 SKIP; exit 0.** Existing mock Trip, routing/session,
GPS-sharing and canonical Cash boundaries remain green.

```powershell
flutter test --no-pub --reporter expanded
```

**1,844 PASS / 0 FAIL / 2 SKIP; exit 0.** Credential-gated live Supabase auth
and role-state tests skipped; no live configuration was supplied.

No live credentials or backend Dart defines were supplied. Credential-gated live
Supabase auth/role tests remain unconfigured. Counts overlap and must not be added.

```powershell
flutter analyze --no-pub lib/features/driver_flow/presentation lib/features/driver_home/presentation/screens/driver_home_screen.dart test/driver_availability_controller_test.dart test/driver_availability_screen_test.dart
flutter analyze --no-pub
```

Scoped analysis: **No issues found; exit 0**. Full analysis: **0 errors,
0 warnings, 2 pre-existing infos; exit 1**. Both containsSemantics deprecations
remain in unchanged `test/rider_v2_adaptive_accessibility_test.dart:145` and `:342`.
This is not complete analyzer success. No unrelated Rider fix was made.

```powershell
dart format --output=none --set-exit-if-changed lib/features/driver_flow/presentation/providers/driver_availability_controller.dart lib/features/driver_flow/presentation/screens/driver_availability_screen.dart lib/features/driver_home/presentation/screens/driver_home_screen.dart test/driver_availability_controller_test.dart test/driver_availability_screen_test.dart
git diff --check
```

**5 Dart files, 0 format changes; exit 0**. Tracked whitespace check passes.
Direct untracked content checks pass for trailing whitespace, conflict markers
and final newlines. All final tests/analyzers use the final formatted Dart source.

## Limits, preservation and Git

This is an in-memory local fake preview. Real authenticated scope/vehicle mapping,
canonical reconciliation, process-death recovery, physical devices and actual
screen-reader verification remain integration work. The host must explicitly
retire scope on logout/account/approval changes; production scope remains null.
Persistent controller/subscription ownership lasts until scope/repository retirement
or container disposal. A screen remount is deliberately not a retirement boundary.

P6-R01/R02/R03/R07 Cash completion/settlement/receipt gates remain unchanged;
P6-R06 Card stays disabled. The plan retains the P6-R08 Stripe foundation versus
Phase 7 Cash-handoff wording reconciliation. No hosted Supabase, GPS, financial,
Card/Stripe or B03 work was performed. No fake response grants backend authority.

Git remains one modified tracked file plus six untracked B02 files; nothing staged.
HEAD remains the B01 commit. Local main remains
`c9ebffae323bd4b621cdd5f8edfba5a33bf91667`; cached origin/main remains
`2856c13fa7f0cbc82616a7b286b69593691c3f61` (10 upstream-only commits, one
branch-only B01 commit). No upstream integration was performed. No direct path
overlap was identified in the earlier review; semantic integration remains separate.

All eight B01 files match their committed Git blobs with normal CRLF filters;
raw SHA-256 snapshots are also compared during this fix to detect byte changes.
The B02 screen, widget tests and Driver Home remain untouched by this final fix.

No commit, push, merge, rebase, PR, issue closure, branch switch or hosted operation
was performed. The initial developer-reported record was 143 focused / 123 Driver /
1,807 full-suite passes with two live skips; the final independently executed
remediation results above supersede it for the new fingerprint. The preceding
three-defect remediation passed 161 focused / 123 Driver / 1,825 full-suite tests
with two live skips at fingerprint
`b18d007b0a01d2f265262e7a392feabfb316feeb64dbe6441d87756c1912bb59`;
those earlier results do not substitute for this final scope-retirement verification.
