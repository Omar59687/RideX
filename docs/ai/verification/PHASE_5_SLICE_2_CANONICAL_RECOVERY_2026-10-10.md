# Phase 5 Slice 2: Canonical fare-lock recovery

Status: implemented and automated checks passed; ready for independent review.
This is not Phase 5 completion or authorization to begin Slice 3.

Branch: `codex/phase-4f-evidence-hardening`.
Verified starting HEAD: `a421bf89101446a93ddae135d2ff441271af7085`.
Existing uncommitted Phase 5 and Slice 1 changes were preserved. No commits,
pushes, branch switches, dependency installations, backend changes, or Software
Factory activation occurred.

## Schema and read contract

Read-only inspection covered migrations `007` and `026`, with the status enum
definitions in `005`. Booking statuses are draft, confirmed, searching, matched,
cancelled, expired, and failed. Quote statuses are calculated, locked, expired,
and superseded.

Migration 007 grants authenticated SELECT on booking_requests and fare_quotes.
Both participant policies use private.can_read_booking: a nonblocked Rider may
read only their own booking; Driver/Admin permissions remain separate. No RLS
policy, SQL function, migration, or Edge Function was modified.

The new SupabaseFareLockReader uses the existing authenticated Supabase client
and one table GET with explicit booking ID and rider ID filters. It embeds the
booking's quote rows through fare_quotes_booking_rider_fk, disambiguating the
other booking-to-current-quote FK. One embedded SELECT provides a consistent
database snapshot rather than two independent booking/quote snapshots. There
is no first/latest-quote selection, mutation, lock RPC replay, or Edge call in
recovery. SDK user identity is checked before and after the GET, and parsed rows
are checked against the requested rider and booking.

FareLockRecoveryRepository is an optional provider-neutral read capability of
SupabaseFareRepository. Existing fare injection, existing test doubles, and the
unconfigured/demo fare path keep their contracts. The SDK adapter is explicitly
listed in the architecture boundary test; models and feature UI remain free of
Supabase SDK imports.

## Classification and ownership

Confirmed recovery requires exactly one booking for the owning rider and
original booking ID, draft status, original expected booking version plus one,
and a link to the original quote. It also requires exactly one locked quote,
the original quote ID/version, a canonical lock timestamp, consistent rider and
booking ownership, and no duplicate quote IDs or versions. This follows the
exact linked-lock replay condition in migration 026 while conservatively
refusing bookings that have subsequently advanced. Expiry after commit does
not invalidate an already locked quote.

All missing, ambiguous, malformed, inconsistent, advanced-version, or otherwise
unresolved states retain the original command. An empty SELECT is never proof
that an in-flight original request cannot subsequently commit. Authentication
or authorization rejection suspends recovery and retains evidence. No new
version is invented, and there is no automatic abandonment of terminal or
expired-looking states.

PendingFareLockController restores the same authorized rider's command and
serializes the read/classification/exact-cleanup through its existing operation
queue. Its existing generation, session, role, status, disposal, and exact-slot
checks protect asynchronous completions. Canonical confirmation clears only
the exact resolved pending command. Failed cleanup or changed/corrupt evidence
keeps recovery unresolved. Recovery never changes the immutable command.

The fare screen offers Check fare status for a restored pending command when
the repository supports canonical reads. Confirmed recovery displays the
original booking's fare with an explicit warning that current route selections
may differ; it does not relabel that fare as belonging to a new local draft.
An uncertain read cannot replace a definitive original locked response. Existing
exact RPC replay behavior is preserved. No new BookingController or session
redirect behavior was added.

## Files changed in this slice

- lib/core/models/fare_lock_recovery.dart (new)
- lib/core/services/fare/supabase_fare_lock_reader.dart (new)
- lib/core/repositories/fare_repository.dart
- lib/core/providers/repositories_providers.dart
- lib/core/providers/session_providers.dart
- lib/features/booking/presentation/screens/fare_estimate_screen.dart
- test/fare_lock_recovery_test.dart (new)
- test/architecture_boundary_test.dart (one exact SDK-adapter allowlist entry)
- This verification document (new)

The pre-existing pending/fare tests and Slice 1 model/store were compared with
an external starting snapshot and remain byte-for-byte unchanged.

## Deterministic tests and final verification

There are 35 new tests covering the actual Supabase GET shape using a local
loopback server, SDK owner checks, malformed/foreign rows, HTTP/JWT authorization
rejections, restored fare-screen recovery, confirmed linkage, unknown outcome,
lost response, expiry after commit, advanced booking versions, missing records,
inconsistent linkage, ambiguous candidates, same-Rider reauthentication,
different-Rider isolation, disposal/session races, delayed original success,
exact-cleanup failure, and a concurrently replaced persisted command.
These fixtures model the inspected schema, not a proposed backend contract.

Exact final commands and available final summaries:

| Command | Final result | Exit code |
| --- | --- | --- |
| `flutter test --no-pub test/fare_lock_recovery_test.dart test/pending_fare_lock_test.dart test/fare_repository_test.dart test/fare_estimate_screen_test.dart --reporter expanded` | `+114: All tests passed!` | 0 |
| `flutter test --no-pub test/architecture_boundary_test.dart --reporter expanded` | `+5: All tests passed!` | 0 |
| `flutter analyze --no-pub` | `No issues found! (ran in 6.8s)` | 0 |
| `flutter test --no-pub --reporter expanded` | `01:09 +408 ~2: All tests passed!` | 0 |
| `dart format --output=none --set-exit-if-changed lib test` | `Formatted 211 files (0 changed) in 1.06 seconds.` | 0 |
| `git diff --check` | No whitespace errors reported | 0 |

The two skipped tests require intentional live Supabase configuration. No live
hosted-Supabase, RLS deployment, or physical-device recovery test was performed.
The full suite includes Driver regression tests. Existing non-failing SVG and
expected diagnostic output do not change the passing final summaries.

The first full-suite run failed the explicit infrastructure allowlist check:
407 passed, 2 skipped, 1 failed. Adding only the new SDK adapter's path corrected
that failure; the full suite was then rerun successfully. Earlier test-fixture
and analysis issues were corrected before the final commands recorded above.

## Remaining dependencies and limits

Slice 3 is not implemented. App-wide mutation gating during cold-start and
session/storage readiness, cross-route safety enforcement, and durable booking
confirmation/navigation handoff still require that separate authorized slice.
Fare-screen integration here consumes the existing pending owner locally; it is
not a global safety gate. Confirmed recovery is delivered to the active fare
screen; no persistent confirmed-booking handoff was introduced.

A consistent SELECT is a point-in-time read, not a global server lock. Future
booking actions still need canonical reads/optimistic version protection and
the later safety gate. Advanced lifecycle states and ambiguous outcomes stay
blocked rather than being automatically abandoned. SharedPreferences remains
a best-effort recovery hint and cannot prove server commit/non-commit.

Hosted SELECT/RLS behavior and device restart recovery remain unverified by
live execution. No Phase 5 completion or independent-review approval is claimed.
