# P6-07 production completion integration — Slice 1

Inspection baseline: `omar` at `d80b1fb`, 2026-10-16. This plan now includes
the authorized persistence-only slice; it is not a P6-07 status completion.
The user explicitly assigns `omar` and prohibits automatic commits.

## Decision and implementation gate

Preserve the existing mock completion controller, repository, UI, and tests.
Do not dispatch production completion from the UI in this slice.

Three approaches were considered:

1. Wire the existing controller to Supabase: unsafe because its `MockTrip`
   has no canonical version, and shared wiring is approval-gated.
2. Implement a separate coordinator against injected durable storage and
   canonical readers: the intended smallest implementation, once those
   interfaces and ownership are approved. An injection seam alone would
   not establish production durability or authorize a replay.
3. Independent review revision: persistence-only implementation is unblocked.
   Developer 3 owns an unwired append-only journal and its deterministic tests
   in the four explicitly authorized files. Recovery reads, adapter semantics,
   retirement, production dispatch and shared wiring remain blocked. Stored
   commands are evidence, never authority to execute a backend operation.

## Findings from actual code

- `tripsRepositoryProvider` always supplies `MockTripsRepository`.
  `ActiveTripController` owns `MockTrip?`, uses a local revision and
  single-flight future, and has no canonical Trip version. The driver
  screen invokes this mock path. A UUID-shaped value alone is not
  authorized canonical evidence; a booking/offer/payment version is invalid.
- `DriverCompleteTripCommand` requires the canonical Trip UUID, positive
  Trip version, and stable key. It explicitly requires persistence before
  dispatch. Neither completion repository owns key creation or storage.
  No driver completion command store or restoration owner was found in
  the inspected core code. Existing pending fare-lock storage belongs to
  Rider booking recovery, not driver completion, and its documented
  crash-durability limitations cannot be silently inherited as guarantees.
- `DriverTripCompletionRepository` exposes only `completeTrip`. It has no
  independent canonical recovery or receipt reread operation. The adapter's
  injected row/receipt readers are private implementation dependencies;
  timeout classification alone does not perform canonical recovery.
- The adapter parses a canonical RPC `trip_id` but never compares it with
  the command. Its canonical row reader validates status/version without
  validating `row['id']`. It then constructs the result with the command
  ID. Developer 1 must close both identity-validation gaps before wiring.
- The same typed exception can originate from the completion RPC, Trip
  reread, or receipt reread. A rejection of a subsequent read does not prove
  that completion failed. The interface loses the stage and confirmed-write
  evidence, so the coordinator must not retire an intent solely because it
  sees `unauthorized`, `tripNotFound`, or another rejection category.
- In migration `019`, `user_trip_receipt_summary` raises `P0002` when no
  receipt exists; it does not return an empty list. The adapter documents
  empty receipts as valid, including for Card, but maps thrown `P0002` to
  `tripNotFound`. Developer 1 must approve how receipt absence is represented
  separately from a missing Trip, including after confirmed completion.
- `008` allows participant Trip reads through `private.can_read_trip`;
  that policy includes Riders/admins as well as Drivers. A production
  eligibility read must additionally establish the current assigned Driver.
  `020` allows Driver receipt summaries but excludes Driver payment access.
  `017` performs Cash settlement on the trusted completion path. No client
  payment mutation or migration is needed or authorized here.

## Exact proposed files, dependencies, and ownership

Coordinator/provider files below remain proposals. The separately authorized
persistence-only implementation adds `driver_completion_command_store.dart`,
`file_driver_completion_command_store.dart` under `lib/core/services/trips/`,
and their two matching root-level test files. No shared production file changes.

| File | Responsibility and dependencies | Owner / approval |
|---|---|---|
| `lib/features/trips/application/driver_completion_coordinator.dart` | Separate orchestration using the approved completion repository, command/result/failure types, and approved recovery/storage interfaces | Developer 3, after contract handoff |
| `test/driver_completion_coordinator_test.dart` | Gated repository/storage/read doubles; state, race, recovery, and exact replay assertions | Developer 3 |
| `test/driver_completion_provider_lifecycle_test.dart` | Invalidation, disposal, account/session epoch changes, and cross-instance single-flight | Developer 3, after provider lifetime approval |
| `lib/core/services/trips/driver_completion_command_store.dart` | Account-scoped persistent staging/inspection contract; no retirement or dispatch capability | Developer 3; isolated implementation authorized, production binding remains gated |
| `lib/core/repositories/driver_trip_completion_repository.dart` | Approve canonical recovery/receipt capabilities and how post-write read failures preserve completion evidence; retain existing API compatibility | Developer 1 |
| `lib/core/repositories/supabase_driver_trip_completion_repository.dart` | Validate RPC/row identity; resolve absent receipt and read-stage error semantics; authenticated transport closures | Developer 1 |
| `test/supabase_driver_completion_adapter_test.dart` | Identity mismatch, missing receipt `P0002`, and post-write read failure compatibility cases | Developer 1 |
| `lib/core/providers/driver_completion_providers.dart` | Proposed separate, explicitly enabled production boundary consuming approved session epoch, authenticated client, journal and canonical context | Developer 3 only after Developer 1 + Integration Owner approve the dependency/lifetime boundary |
| `lib/core/providers/session_providers.dart` | Existing mock flow remains intact; any session/sign-out registration is separately reviewed | Shared production writer; explicit approval required |
| `lib/core/providers/repositories_providers.dart` | No silent replacement of `tripsRepositoryProvider`; production completion repository wiring deferred to approved P6-09 integration | Developer 1 + Integration Owner approval required |
| `lib/features/trips/presentation/screens/driver_active_trip_screen.dart` | No production dispatch until identity/version, journal and wiring gates pass | Developer 3, later slice |

Routing, existing Trip models/repositories, payment contracts, and migrations
remain read-only. A new provider file does not bypass shared runtime ownership.

## Required handoffs and orchestration design

1. **Canonical context — Developer 1 contract, Developer 3 consumer.** Identify
   the authorized source of the assigned active Trip locator. An authenticated
   read of that Trip must establish ID, `driver_id`, canonical status and
   `trips.version`. Eligibility also requires an approved, non-blocked Driver
   session matching the SDK user. No mock-ID conversion, newest-row heuristic,
   or assumption that matching/restoration already exists is allowed.
2. **Durable intent — Developer 3 persistence owner; production binding gated.** The
   application journal, outside screen/provider lifetime, owns the original
   command plus account ownership. Atomically create-or-load one unresolved
   intent before RPC dispatch. Generate a key once only for a genuinely new
   intent, persist the normalized triple, verify the write, then send it.
   Duplicate taps and recreated providers must load the same intent. Storage
   failure, corruption, conflict or uncertain writes block dispatch; preserve
   evidence. No in-memory fallback. Define process-death durability and whether
   multiple isolates/processes are supported before selecting storage.
3. **Session and lifecycle — Developer 3 with approved wiring.** Capture an
   account and monotonic session/lifecycle epoch; check it before dispatch and
   after every awaited store/RPC/read. Compare against SDK identity too. On
   logout, account replacement, loss of approval, invalidation or disposal,
   retire publication rights immediately; do not erase durable evidence or
   claim to cancel an already dispatched RPC. A→B→A must invalidate old work.
   Authenticated transport closures also check the epoch at each network step,
   since this adapter performs multiple internal reads in one `completeTrip`.
4. **Single-flight — Developer 3.** Share one future per account/intent for
   stage, dispatch and recovery. The lock owner must outlive disposable UI
   providers. Invalidation cannot permit a second live controller to dispatch
   beside the original. Clearing a screen's busy flag is not permission to
   release that lock; durable command identity alone does not ensure single-flight.
5. **Confirmed completion.** Accept only matching canonical completed Trip
   evidence. Preserve the version supplied by authorized rereads; never
   synthesize `expectedVersion + 1`. Receipt verification is separate. No
   `paid`, Card authorization/capture, or receipt value is inferred from Trip
   completion. Receipt failures preserve confirmed completion evidence once
   the approved repository contract makes it available.
6. **Rejection and stale version.** A confirmed RPC rejection stops blind
   retries. Stale version requires an authorized canonical reread and a new
   explicitly staged intent if still eligible, using a new key; changing the
   old command version is never an exact retry. Read-stage failures must be
   kept separate, per the outstanding Developer 1 contract decision.
7. **Unknown or malformed result.** Retain the original triple and uncertain
   state. Reread canonical Trip first. A completed Trip permits receipt
   verification; a terminal cancellation stays cancelled. Hidden/missing,
   malformed, or failed reads remain unresolved. Only if the approved recovery
   decision permits dispatch may the original triple be replayed byte-for-byte;
   never rotate its key or refresh its version. An in-progress reread alone
   does not prove the original server operation has finished. Do not synthesize
   success from a recovery classification or from absence of a receipt.
8. **Receipt and retirement.** Read only Driver-safe receipt summaries after
   confirmed completion, verify Trip identity, and retain unverified state when
   absent/unavailable. No Driver payment-row read. Decide journal retirement
   conditions with Developer 1; stale actors cannot clear a newer intent.
   Receipt verification and canonical payment status remain separate facts.

## Test gate for the eventual implementation

| Requirement | Required assertion |
|---|---|
| One command per intent | Repeated taps and recreation stage/load one triple; no RPC before durable confirmation |
| Concurrent taps | Identical shared future, one dispatch, including gated staging and recovery |
| Exact retry | Restart reloads the original triple; changed Trip/version/key rejected as replay |
| Successful completion | Matching completed result only; no invented version, payment status or receipt |
| Typed rejection / stale version | Preserve evidence, no blind retry; canonical reread before a separately authorized new intent |
| Unknown / malformed | Durable record retained, canonical reread precedes replay; failed/hidden reread stays unresolved |
| Session/account changes | Before and after each await; logout, A→B→A, blocked/unapproved Driver, SDK/provider identity mismatch |
| Invalidation/disposal | No stale publication/cleanup or cross-instance second dispatch; pending RPC is not assumed cancelled |
| Recovery/receipt | Completed Card without receipt, Cash without inferred paid state, receipt identity mismatch, no forbidden payment calls |
| Storage/repository boundaries | Corrupt/failed/ambiguous writes block RPC; wrong RPC/row identity and post-write reread errors fail safely |

Existing mock and contract tests remain required regressions; they do not prove
production journal durability, account isolation, or provider integration.
Hosted V5-01/V5-04 evidence remains a separate financial-execution gate.

## Inspection inventory

- `AGENTS.md`; `docs/ai/ops/WORKFLOW.md`; current override in
  `docs/ai/ops/CURRENT_STATUS.md`.
- `docs/parallel-development/TEAM_RULES.md`, `MASTER_PLAN.md`;
  `phase-6/PHASE_PLAN.md`, `DEVELOPER_1.md`, `DEVELOPER_3.md`,
  `SPRINT_TRACKER.md` under that directory.
- `lib/core/models/driver_trip_completion.dart`,
  `driver_completion_recovery.dart`, `mock_trip.dart`.
- `lib/core/repositories/driver_trip_completion_repository.dart`,
  `supabase_driver_trip_completion_repository.dart`, `trips_repository.dart`.
- `lib/core/providers/session_providers.dart`, `repositories_providers.dart`.
- `lib/features/trips/presentation/screens/driver_active_trip_screen.dart`.
- `test/driver_cash_completion_hook_test.dart`,
  `driver_trip_completion_contract_test.dart`,
  `driver_completion_error_mapping_test.dart`,
  `supabase_driver_completion_adapter_test.dart`;
  lifecycle test names in `test/active_trip_creation_lifecycle_test.dart`.
- Targeted SQL sections in
  `supabase/migrations/008_phase3_trip_cash_change_foundation.sql`,
  `017_phase3_trip_payment_concurrency.sql`,
  `019_phase3_safe_exposure_hardening.sql`,
  `020_phase3_driver_finance_exposure_correction.sql`.

## Original plan baseline verification

- Verified SDK: Flutter 3.35.3, framework `a402d9a437`, Dart 3.9.2.
- Full baseline `flutter test --reporter expanded`: **656 passed, 2 skipped**,
  exit 0. No implementation proceeded before this gate.
- Focused `flutter test --no-pub --reporter expanded` with
  `test/driver_trip_completion_contract_test.dart`,
  `test/driver_completion_error_mapping_test.dart`,
  `test/supabase_driver_completion_adapter_test.dart`, and
  `test/driver_cash_completion_hook_test.dart`: **94 passed**, exit 0.
- `flutter analyze --no-pub`: **No issues found**, exit 0.
- These baseline checks preceded the journal implementation below. The
  future coordinator test matrix above remains unimplemented.
- The initial default-SDK run used Flutter 3.27.3 and was terminated; its
  dependency-resolution changes were restored. It is not counted as evidence.
  The journal slice makes no dependency changes.

## Persistence-only implementation checkpoint

- Added exactly the four authorized journal implementation/test files. The
  public interface has typed absent/valid/corrupt/unavailable inspection and
  created/existing/conflict/blocked staging results with closed diagnostic codes.
- Native file implementation accepts a private directory and uses separate
  hex-encoded backend / UUID Driver directories. It records schema, sequence,
  owner, and the exact normalized command triple in length-framed UTF-8 JSON
  with CRC32. It never overwrites, retires, repairs or deletes command records.
- Resolved directory paths share an in-isolate queue. Exclusive-create lock
  sentinels reject competing isolates/processes instead of waiting or stealing.
  Crashed writers can leave stale sentinels; automatic cleanup is not provided.
  Synchronization assumes cooperating clients and a private local filesystem
  supporting exclusive creation. This is storage serialization, not RPC
  single-flight. Other-process behavior has not been independently validated.
- Persistence acknowledgement requires append when needed, flush, close,
  exact readback and successful lock release. Uncertain acknowledgement blocks;
  a later successful flush/readback may recover a fully recorded command.
  Torn/invalid tails block the entire account journal and preserve its bytes.
- CRC32 detects accidental corruption, not malicious edits. Directory fsync,
  power-loss guarantees, total-file deletion/rollback detection, secure local
  encryption, network filesystems, web and cross-device coordination are not
  established. Journal size is bounded to 4 MiB and never automatically pruned.
- No new dependencies, production bindings, RPCs, key generation, outcome
  classification or payment/receipt authority. Developer 1 integration blockers
  above remain. Stored commands are evidence, not permission to execute.
- Flutter 3.35.3: **64 journal tests passed**, including real-file recreation,
  separate-isolate contention/recovery, conflicts, namespaces, corruption,
  interrupted appends and injected read/write/flush/acknowledgement failures.
  Full `flutter test --no-pub --reporter expanded`: **720 passed, 2 intentional
  live-test skips**, exit 0. `flutter analyze --no-pub`: **No issues found**,
  exit 0. Four-file format verification and `git diff --check` passed; whitespace
  was also checked explicitly for all five untracked deliverable files.
- Exact deliverable inventory is the revised plan plus the four authorized
  files. Existing tracked production files and dependencies are unchanged.
  Branch/HEAD remain `omar` / `d80b1fb`; tooling folders and stashes are
  preserved. No commit, push, merge, reset or hosted action occurred.

P6-07 remains incomplete. Independent review applies only to the bounded
persistence implementation, not production completion or crash-recovery readiness.
