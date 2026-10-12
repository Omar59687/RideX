# Phase 5 checkpoint: Booking Confirmation Handoff

Status: implemented and verified; ready for focused independent review. Independent review
has not been performed. This is not Phase 5 completion.

Required branch and HEAD verified before editing:
`codex/phase-4f-evidence-hardening`, `a421bf8`.
All pre-existing uncommitted work, including Slices 1–3, is preserved.
No Git mutation, Software Factory execution, dependency installation, hosted
operation, backend edit, migration edit, Edge Function edit, or RLS edit occurred.

## Existing contract inspected

- Migration 007, lines 653–727, implements authenticated
  `rider_confirm_booking(target_booking_request_id uuid, expected_version integer,
  idempotency_key text)`. It requires a nonblocked Rider owning the booking,
  status `draft`, matching version, and a linked locked quote. It advances the
  booking to `confirmed` and sets `confirmed_at`. The optimistic-version trigger
  adds one booking version. Quote identity, version, amount, and inputs remain
  unchanged; the fare-quote immutability trigger protects the pricing snapshot.
- The confirmation response contains booking ID and status, not canonical
  booking/quote versions. The client therefore reads canonical state afterward
  before displaying confirmation. JSON error envelopes are rejected.
- Migration 021's lock implementation and migration 026's Rider lock wrapper
  only lock/link a quote and advance the draft version. Lock success is not
  booking confirmation.
- The existing BookingRepository exposes saved locations, vehicle types, and
  demo fare estimation. No client confirmation operation existed.
- `/rider/searching` creates Mock trips from local draft state. It is not a
  valid destination for authoritative bookings. A bounded
  `/rider/confirmation` route now reviews/confirms the original booking and
  explicitly states that live driver matching is unavailable.

## Implementation and safety

The new optional BookingConfirmationRepository capability shares the existing
fare repository infrastructure and canonical reader. Mock/double fare contracts
are unchanged. Production confirmation wiring checks SDK Rider ownership before
and after dispatch. The pending owner serializes handoff reads, submission, and
post-submission verification on its existing queue; it captures the session
snapshot/generation and checks ownership after asynchronous boundaries.

Review navigation performs no backend transition. Explicit confirmation invokes
the verified RPC with the original booking ID, canonical post-lock version, and
a deterministic per-booking/version idempotency key. Canonical reads verify the
original pending tuple, Rider, quote ID/version, single locked candidate, storage
lineage, and exact booking status/version. Supported statuses are locked draft
at original version +1 and confirmed booking at original version +2. Other
statuses or advanced versions remain blocked. Slice 2 classification stays
unchanged; the handoff classifier adds the confirmed-booking interpretation.

No draft create/update or quote calculation occurs during handoff. A second
queued attempt reads confirmed state and does not submit again. A lost response
is reconciled by a later read; any retry against a still-draft booking uses the
same expected version/idempotency key. Duplicate navigation callbacks are
guarded. Disposed widgets publish nothing; stale sessions cannot navigate or
publish original Rider results. In-flight RPCs cannot be cancelled.

Pending evidence is NEVER deleted by this checkpoint, even after authoritative
confirmation. The central create/update gate remains enforced. There is still
no approved completion/abandonment contract authorizing a replacement booking.

## Exact files changed by this checkpoint

- `lib/app/router/app_router.dart`
- `lib/app/router/route_guards.dart`
- `lib/core/models/booking_handoff.dart` (new)
- `lib/core/providers/repositories_providers.dart`
- `lib/core/providers/session_providers.dart`
- `lib/core/repositories/fare_repository.dart`
- `lib/features/booking/presentation/screens/booking_confirmation_screen.dart` (new)
- `lib/features/booking/presentation/screens/fare_estimate_screen.dart`
- `test/booking_confirmation_handoff_test.dart` (new)
- This verification record (new)

Other dirty files belong to the pre-existing worktree and were not edited by
this checkpoint.

## Verification

Focused command:

```powershell
flutter test --no-pub test/booking_confirmation_handoff_test.dart test/booking_mutation_gate_test.dart test/fare_lock_recovery_test.dart test/fare_repository_test.dart test/fare_estimate_screen_test.dart test/session_route_guards_test.dart --reporter expanded
```

Result: `+116: All tests passed!`, exit 0. Nine new handoff tests cover fresh
lock/real provider wiring, canonical recovery, owner recreation, same-Rider
reauthentication, uncertainty, advanced lifecycle, unchanged identity/amount,
duplicate submissions/navigation, lost confirmation response, stale ownership,
screen disposal, pending retention, and production gate/GoRouter redirect and
re-entry. Existing fare tests cover Mock flow regression.

`flutter analyze --no-pub`: no issues found, exit 0.

Initial verification found five style infos (fixed), test-fixture queue waits
(fixture awaited restoration behind its deliberately held request), guarded
callback assertions (changed to expectSync), and loopback widget timing/idle
socket timer issues (corrected). Interrupted/failed runs are not counted as
passing evidence.

Final checkpoint commands and results (all exit 0):

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` | No issues found (30.4s) |
| `dart format --output=none --set-exit-if-changed lib test` | 215 files, 0 changed |
| `git diff --check` | No whitespace errors |
| `git diff --quiet HEAD -- supabase pubspec.yaml pubspec.lock` | No backend/dependency differences |
| `git status --short --untracked-files=all -- supabase pubspec.yaml pubspec.lock` | No backend/dependency tracked or untracked changes |
| `flutter test --no-pub --reporter expanded` | `01:44 +440 ~2: All tests passed!` |
| `git branch --show-current` | `codex/phase-4f-evidence-hardening` |
| `git rev-parse --short HEAD` | `a421bf8` |

The full suite was run once at this checkpoint, including Mock and Driver
regression tests. Two live Supabase tests skipped without intentional live
configuration. Existing non-failing SVG filter diagnostics remain present.

## Remaining limits

- No hosted confirmation RPC/RLS execution or physical-device process-kill,
  cold restart, or navigation verification was performed here. Loopback tests
  exercise client wiring, not PostgreSQL execution.
- SharedPreferences remains best-effort local recovery evidence, not proof of
  crash-durable server state. App-data loss, other devices, and other processes
  are outside this single-process boundary.
- A nonsettling storage/network operation can hold the shared queue; transport
  timeout/liveness hardening remains unverified.
- A dispatched RPC can commit after session change/disposal. Its late result is
  withheld; later authorized canonical recovery establishes the outcome.
- Searching, matched, terminal, or otherwise advanced booking versions remain
  blocked for this checkpoint. Live matching and authorized evidence cleanup
  are not implemented.

Stop after this checkpoint. No Phase 5 completion is claimed.
