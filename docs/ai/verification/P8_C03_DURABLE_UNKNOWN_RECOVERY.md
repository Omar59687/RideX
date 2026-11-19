# P8-C03 - Durable journal and UNKNOWN recovery

Moath / Developer 3, issue #153. Local checkpoint only; C04 is not started.

## Baseline and stack

Fetched origin/main: `3be1aa6`. Separate branch/worktree:
`feature/p8-c03-durable-completion-recovery`.
Full required stack above main: C01 implementation `2c52bc35708dd719168db051107113c7a9e87916`,
reviewed C01 fix `30a27aaa31eddfd6ece4ea6736d30582e54fcba6`, then approved C02
`1bd8a9659e04a0ca88f2fcee20bee6b00432d3fa`, then this C03 checkpoint.
C03 was created directly from approved C02. No merge/rebase/cherry-pick was used;
the earlier worktrees and reviewed heads remain clean and unchanged.

## Existing infrastructure retained

C02 interaction/source validates the owning Driver, pinned SDK session/epoch,
assigned active vehicle, exact active Cash Trip and original version before
submission. DriverCompletionCoordinator stages the source's original command
through JournalDriverCompletionStagingGateway and FileDriverCompletionCommandStore.
The native store appends, flushes, closes, reads back exact bytes and releases
its exclusive lock before returning CompletionCreated. C02 then rechecks
interaction/session eligibility before the existing completion repository can
invoke driver_transition_trip. Existing records never grant dispatch to a new
coordinator. Pending/failed/UNKNOWN attempts do not retry or rotate keys.

Recovery uses captured Driver/backend partitions and the existing authenticated
read-only canonical Trip repository. It never calls completion, stages a command,
clears evidence, repairs a tail or removes a stale lock. Terminal canonical state
is an observation, not proof of which historical command executed. Completion
and receipt/payment verification remain separate. C01/C02 default-OFF and exact
Omar integration requirements remain unchanged.

No journal, gateway, completion repository, dispatch coordinator, interaction gate,
global provider/router, backend or financial implementation was replaced or edited.

## Confirmed gaps and minimal fixes

1. Recovery's cached current getter exposed the prior outcome after authority
   replacement until another recovery call. It now validates the captured
   authority on every getter access and invalidates stale cached ownership.
2. Recovery accepted completed at the original command's inProgress version.
   It now rejects that impossible status/version pair as conflicting evidence,
   matching C02's requirement for a newer canonical completion version.
3. Only completed was protected against later status changes. All terminal states
   now remain terminal, both within one coordinator and across the aggregate
   controller's separate recovery passes. A conflicting newer observation cannot
   replace a previously accepted cancellation/failure with completion.
4. Independent review found that aggregate recovery retained observedTrip before
   checking whether the coordinator accepted it. The aggregate now retains only
   strongestTrip. A regression proves rejected completed@4 cannot poison the
   cache or block valid cancellation@5. Existing UNKNOWN classification for weaker
   rereads of accepted evidence remains intact; journal faults remain blocked.

Fourteen focused assertions/cases exposed these issues before their fixes.
The final implementation changes are confined to the two Driver recovery owners.

## Deterministic verification

New native-store/gateway/coordinator tests verify this exact event sequence:
read -> write -> flush -> close -> readback -> release -> dispatch.
Concurrent calls share one dispatch. Injected write, flush, close, readback and
release-acknowledgement failures each prevent dispatch through the real gateway.

The crash worker is a test-only Dart child process with no SDK/network capability.
It deliberately calls exit(), bypassing Dart cleanup, in three scenarios:

| Child exit point | Restart behavior verified |
|---|---|
| After native flush, before acknowledgement/lock release | Stale lock blocks staging and recovery; no replay, no lock deletion, unchanged journal bytes |
| After verified staging, before dispatch | Existing original command remains; new completion owner cannot dispatch; canonical inProgress reread stays nonterminal |
| Fake backend dispatch committed, response lost | One local dispatch marker; fresh owner cannot replay; authenticated canonical completed reread is required |

The marker simulates an external backend event only. It never substitutes for
the separate canonical reader in recovery. Across restart, no prior client result,
attempt, receipt or success callback is reconstructed from journal bytes.

Native-store tests also combine an in-flight completion with A -> B and A -> B -> A:
B sees no A journal record; A's new epoch can recover read-only, while the old late
success cannot publish or replace newer recovered truth. The original key/version
remain unchanged, and a replacement completion coordinator still cannot dispatch.

The focused regression also includes existing journal corruption/partial-tail,
namespace/key conflicts, duplicate staging, bounded persistence, lost responses,
late success/error, disconnected/UNKNOWN state, stale versions, foreign Driver/Trip,
revoked/expired SDK authentication, original R01/R02/R03 safeguards, and C01/C02
controller/widget guards. No new recovery engine or broad audit was added.

- Final focused suite: 527 passed, 0 failed across twelve test files; full
  project suite was not repeated.
- Changed-file analyzer: no issues in five Dart files.
- Android debug APK build: passed; existing toolchain warnings remain.
- Full analyzer run: 21 inherited diagnostics (3 warnings, 18 infos); no passing
  whole-repository analysis is claimed. Final owned-file analysis is clean.
- Fresh independent reviewer: APPROVED after the rejected-observation retention
  fix and compatibility re-check; no remaining critical/high/medium findings.

## Files

- lib/features/trips/application/driver_completion_recovery_coordinator.dart
- lib/features/trips/application/driver_cash_recovery_controller.dart
- test/driver_completion_c03_recovery_test.dart
- test/helpers/driver_completion_crash_worker.dart
- test/driver_cash_production_integration_test.dart
- This report and docs/ai/ops/CURRENT_STATUS.md.

## Toolchain, integration and limits

Flutter 3.41.2 / Dart 3.11.0 matches existing CI. Tests/build use temporary SDK
resolution. The committed lockfile is unchanged (blob
`bb6148d20da9613013f01aa25dfefe82566360f1`); exact-lockfile resolution still fails
on this SDK. Its five SDK-pinned differences are characters 1.4.0 -> 1.4.1,
matcher 0.12.17 -> 0.12.18, material_color_utilities 0.11.1 -> 0.13.0,
meta 1.16.0 -> 1.17.0 and test_api 0.7.6 -> 0.7.9. The original lockfile already
requires Dart >=3.8 despite the guide's older 3.27.3/3.6.1 claim. No dependency,
generated platform file or machine-specific configuration is committed.

Process-exit tests establish bounded local persistence, not device power-loss,
directory-fsync, backup rollback or cross-device durability. Stale writer locks
remain fail-closed pending a separately authorized recovery procedure; C03 does
not invent automatic cleanup. Journal partitioning is not local encryption or
a substitute for authenticated canonical authorization.

Omar must still provide C02's reviewed nonproduction same-client gate, actual
connection/session invalidations, and shared success-route protection for
/driver/completed. No approved target is supplied here. Yousuf owns trusted
completion/payment consequences. Hosted migration discrepancy #149 and live
actor/device acceptance remain unproven.

No hosted Trip/financial writes, Stripe, migrations, Edge Functions, push, PR,
merge or deployment. No emulator/ADB/session operations or accepted Phase 7
Trip changes. C03 is ready for owner review after final local verification;
C04 requires separate authorization.
