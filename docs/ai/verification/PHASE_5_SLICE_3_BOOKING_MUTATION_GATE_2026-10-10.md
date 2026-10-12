# Phase 5 Slice 3: Booking Mutation Safety Gate

Status: implemented and verified; ready for independent review. Phase 5 is not
complete. Booking Confirmation Handoff and subsequent work were not started.

Branch verified before implementation and at final verification:
`codex/phase-4f-evidence-hardening`.
HEAD: `a421bf89101446a93ddae135d2ff441271af7085` (`a421bf8`).
Existing uncommitted Phase 5, Slice 1, Slice 2, and Software Factory files were
preserved. No commit, push, merge, reset, rebase, branch switch, Software Factory
execution, dependency installation, hosted configuration change, or backend
operation occurred. Tests used deterministic doubles and local loopback HTTP.

## Mutation paths and shared boundary

Targeted symbol searches covered all client uses of `createBookingDraft`,
`updateBookingDraft`, `rider_create_booking_draft`, and
`rider_update_booking_draft` under `lib`.

- `FareEstimateScreen._refresh` creates a server draft on first entry and updates
  its existing server draft on route/selection changes and retries.
- Both dispatch through `SupabaseFareRepository.createBookingDraft` and
  `SupabaseFareRepository.updateBookingDraft`, then the shared RPC adapter in
  `fareRepositoryProvider`. No other direct client RPC call sites were found.
- Rider Home's `_startNewBooking` invalidates local place/booking state. Other
  booking controls change the local `BookingController` draft; their subsequent
  server persistence reaches the same fare repository boundary. Local reset,
  navigation, redirects, and widget recreation cannot erase the pending owner.
- `FakeFareRepository`, `UnavailableFareRepository`, and the mock booking
  repository retain their deterministic/demo contracts.

`SupabaseFareRepository` now requires a provider-neutral `BookingMutationGate`
and wraps the actual create/update dispatch in it. Production wiring calls
`PendingFareLockController.runBookingMutation`; no second state controller or
persisted source of truth was added. The client provider owns backend readiness;
a null client still selects the existing demo fare path.

## Safety and concurrency contract

The existing pending owner's operation queue serializes restore, staging,
canonical recovery, and the entire draft RPC dispatch. Every mutation inspects
the authenticated Rider's persisted slot afresh. Until that inspection finishes,
no RPC is sent. Only an explicitly absent, readable slot with no in-memory
command permits dispatch. Valid commands, corrupt/foreign evidence, read
failures, unauthenticated/non-Rider sessions, disposal, and changed ownership
block dispatch with `FareFailure.mutationBlocked`.

The gate captures the session snapshot and controller generation before queueing
and checks them before/after storage and after the RPC. A same-Rider session
refresh also invalidates a stale attempt. Production wiring checks SDK user
identity immediately before dispatch and after its response: a JWT belonging to
another Rider cannot use the slot that was inspected. Evidence is namespaced;
another Rider can use their own safely restored empty slot without clearing or
reusing the original Rider's evidence. Concurrent calls recheck storage when they
reach the queue; staging cannot interleave the protected dispatch.

## Recovery and lifecycle integration

Slice 2's canonical SELECT and classification remain unchanged. Missing server
records, timeouts, ambiguous states, and advanced versions never authorize
replacement. Recovery now verifies and RETAINS the exact durable command after
canonical confirmation instead of deleting it. Original/replayed definitive
lock responses also retain the staged command. This deliberately supersedes
Slice 2's cleanup behavior: lock confirmation proves commitment, not permission
to abandon the original booking or begin a replacement.

The retained evidence protects cold restart, same-Rider reauthentication,
cross-route entry, GoRouter redirects, and widget disposal/recreation. The fare
screen displays the original locked fare, warns when current selections differ,
and explains that replacement is paused until booking handoff is available.
Unreadable storage exposes Check fare status even without an in-memory command;
retry uses the existing restore/recovery operation. Repaired readable absence
can retry the ordinary flow, subject to another repository gate check. There is
no automatic replacement loop or blanket unblock from a missing server row.

## Exact files changed in Slice 3

- `lib/core/models/fare_quote.dart`
- `lib/core/repositories/fare_repository.dart`
- `lib/core/providers/repositories_providers.dart`
- `lib/core/providers/session_providers.dart`
- `lib/features/booking/presentation/screens/fare_estimate_screen.dart`
- `test/booking_mutation_gate_test.dart` (new)
- `test/fare_repository_test.dart`
- `test/fare_lock_recovery_test.dart`
- `test/fare_estimate_screen_test.dart`
- This verification record (new)

The pending model/store, canonical model/reader, architecture allowlist, test-app
helper, migrations 001-026, RPCs, Edge Functions, RLS, and dependency files were
not changed by Slice 3. Existing uncommitted changes remain present in git status.

## Exact final verification

Focused command:

```powershell
flutter test --no-pub test/booking_mutation_gate_test.dart test/pending_fare_lock_test.dart test/fare_lock_recovery_test.dart test/fare_repository_test.dart test/fare_estimate_screen_test.dart test/rider_booking_provider_test.dart test/rider_booking_flow_test.dart test/booking_progression_guard_test.dart test/booking_stops_management_test.dart test/booking_stops_flow_test.dart test/booking_location_validation_test.dart test/session_route_guards_test.dart test/architecture_boundary_test.dart --reporter expanded
```

Result: `00:31 +187: All tests passed!`, exit 0. This includes 22 new mutation
gate tests (including production-provider/SDK loopback tests), 36 recovery tests,
pending/fare tests, booking flows, session route guards, and architecture checks.
Tests exercise actual create/update repository dispatch, readiness, corrupt/read
failure evidence, same/different Rider sessions, queued concurrent mutations and
staging, cold-start/recreated owners, delayed RPC/recovery results, protected
confirmed locks, storage retry UX, and legitimate/mock booking behavior.

| Command | Result | Exit |
| --- | --- | --- |
| `flutter analyze --no-pub` | `No issues found! (ran in 19.5s)` | 0 |
| `dart format --output=none --set-exit-if-changed lib test` | `Formatted 212 files (0 changed)` | 0 |
| `git diff --check` | No whitespace errors | 0 |
| `git diff --quiet HEAD -- supabase pubspec.yaml pubspec.lock` | No backend/dependency differences | 0 |
| `git status --short --untracked-files=all -- supabase pubspec.yaml pubspec.lock` | No tracked/untracked backend/dependency changes | 0 |
| `flutter test --no-pub --reporter expanded` | `01:24 +431 ~2: All tests passed!` | 0 |

The full suite was run once at the final checkpoint, including Driver regression
tests. Two live Supabase tests intentionally skipped without configured live
credentials. Existing non-failing SVG diagnostics remain present.

Earlier focused runs failed readiness fixture initialization and superseded
post-lock replacement expectations, then one offscreen button assertion. Those
were corrected before the final focused/full runs. Initial analysis reported two
style infos; both were fixed before the clean final analysis. No failing run is
represented as passing evidence.

## Remaining limits

- No safe handoff/abandonment contract exists yet. A confirmed lock therefore
  remains durably protected and blocks new/updated server drafts for that Rider.
  This is intentional; no Booking Confirmation Handoff was implemented.
- SharedPreferences is still best-effort evidence. Lost app data, other devices,
  and other processes cannot be coordinated by this in-process queue.
- An RPC already dispatched cannot be cancelled by a later session change;
  late results are withheld and server authorization/version checks still apply.
- Hosted SELECT/RLS execution, physical-device restart, and multi-device behavior
  were not tested. No Phase 5 completion or independent-review approval is claimed.

Stop at Slice 3. No subsequent task is authorized by this checkpoint.
