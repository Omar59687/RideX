# Canonical Driver Cash UI runtime integration — 2026-10-26

Base: `6de01b23b93bbe3a966463868ebe79cd2d35e168` (merged PR #65).
This slice mounts the existing R01/R02/R03 composition. Phase 6 remains NOT
APPROVED; hosted Cash Completion/Receipt acceptance is still pending.

## Runtime wiring

- Driver home exposes **Canonical Cash Trip (test backend)** only when the
  existing `RIDEX_ENABLE_TEST_DRIVER_CASH` compile-time gate is explicitly true.
  The gate defaults to false and also controls the existing backend allowlist.
- `/driver/canonical-trip` is a separate Driver-protected route. Gate-off deep
  links show a disabled message without mounting the financial composition.
  The route accepts no Trip/version/idempotency parameters as authority.
- The existing panel uses `driverCashCompletionProvider`: application-owned
  Supabase initialization provenance, approved endpoint/namespace registry,
  `AuthService.driverBinding`, original SDK Session object and B1-B epoch.
  Authenticated, unblocked, approved Driver identity must match the SDK user.
- **Check completion availability** loads the active Trip from canonical Driver
  availability. The existing source revalidates profile/approval, availability,
  ownership, Cash method, `inProgress` status and positive version. A changed
  context fails closed. No fixture ID is hardcoded in application code.
- **Complete Cash trip** remains an explicit action through the existing
  coordinator and `driver_transition_trip` completion adapter. Original Trip,
  expected version and idempotency key are journaled durably before dispatch.
  Existing evidence cannot authorize replay; concurrent taps remain single-flight.
- The mock Driver demonstration, mock presence switch and `/driver/trip` remain
  separate and cannot supply canonical financial authority.

## Recovery and state publication

Mounting the canonical surface creates the existing recovery controller, which
performs startup journal discovery. While mounted, application resume triggers
read-only reconciliation; **Reconcile Cash completion** is the explicit entry.
There is no application-wide background recovery service: after restart, open
the canonical surface to inspect the retained journal. Leaving it disposes its
session-scoped controller and lifecycle observer.

The panel now listens to recovery's own notifier as well as completion state.
Thus startup, resume and explicit reconciliation results render independently
of completion changes. Missing receipt evidence is unverified, never payment
failure. Completion alone is never displayed as payment success.

Existing bounded states cover unavailable, ready, processing, verified or
unverified receipt, unresolved outcome, authorization loss and storage/network
failure. Recovery preserves per-Trip strongest evidence and original commands;
it never stages, dispatches, retries, deletes or retires journal entries.
Revocation observed by the existing authority owner prevents stale publication;
this is not a claim of instantaneous detection of remote profile changes.

## Later operator activation — not executed by this change

After review/merge and separate authorization for device activation/acceptance,
use the PR code and a local ignored `.env.json` containing only the approved
`SUPABASE_URL` and publishable/anon application key. Never put a service-role key,
password or access token in application defines. Select an Android emulator or
device from `flutter devices`, replacing `ANDROID_DEVICE_ID` below:

```powershell
flutter run -d ANDROID_DEVICE_ID --dart-define-from-file=.env.json --dart-define=RIDEX_ENABLE_TEST_DRIVER_CASH=true
```

This is an explicitly enabled **test-only** command, not a normal-build default.
It was not run here. Sign in through normal SDK authentication as the approved
test Driver, then open the canonical entry. Do not press **Complete Cash trip**
until separate hosted completion/settlement/receipt acceptance is authorized.
The first readiness check is read-only and creates no journal command.
Use native application-support storage; web has no durable journal support and
must fail closed rather than authorize completion.

The approved registry remains exactly:
`https://ykasivejjchupswqyxpm.supabase.co` →
`ridex-grad-ykasivejjchupswqyxpm-v1`. Wrong endpoint/provenance/session is rejected.

## Fixture provenance and acceptance still required

The preceding owner-authorized operator execution reported Trip
`67690878-50a5-40f4-8db5-21cf41760678`, `inProgress` version 4; Booking
`5f810fac-b04a-4e3a-8b95-80d7e418260e`, matched version 5; active Vehicle
`48d007ab-c13c-4ff8-93f3-1dc7f1e6975d`; one unpaid Cash payment and zero receipts.
These are historical fixture results, not a new hosted acceptance run by this
implementation. No hosted reads or mutations were needed for this code change.

Before acceptance: review/merge this PR; obtain separate activation and financial
acceptance authorization; freshly verify session/approval, exact fixture and
version; verify native durable storage; execute one explicitly authorized
completion; verify canonical completion, exactly one settlement and issued
receipt; verify read-only restart/resume/unknown-outcome recovery and Rider/Admin
visibility under the authorized acceptance matrix. Preserve uncertain evidence
and stop for operator reconciliation. Journal retention/retirement policy remains
separate owner approval. R04 hosted role acceptance and other Phase 6 gates
remain open. Stripe dispatch remains disabled.

## Local verification

Focused widget/provider/repository and coordinator/recovery tests exercise the
route, default-off behavior, independent recovery notifications, journal
retention, ownership/session/namespace/version failures, no automatic dispatch
or replay, and preservation of the mock demo. Executed results:

- `flutter test --no-pub test/driver_cash_production_integration_test.dart test/session_route_guards_test.dart`: **74 PASS**.
- `flutter test --no-pub test/driver_completion_coordinator_test.dart test/driver_readonly_recovery_test.dart test/driver_home_location_sharing_test.dart test/app_router_error_boundary_test.dart`: **148 PASS**.
- After adding the home-entry regression, `flutter test --no-pub test/driver_home_location_sharing_test.dart test/session_route_guards_test.dart`: **17 PASS** (overlaps earlier runs).
- `flutter analyze --no-pub`: **No issues found** on the final Dart changes.
- Scoped `dart format --output=none --set-exit-if-changed`: **10 files, 0 changes**;
  `git diff --check`: passed.

No full Flutter suite, hosted completion, settlement, receipt issuance,
Stripe, migration, deployment or runtime flag activation was performed.
