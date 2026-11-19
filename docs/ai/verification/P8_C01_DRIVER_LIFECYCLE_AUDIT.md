# P8-C01 - Driver lifecycle and authority audit

Owner: Moath / Developer 3. Issue #153. Local review checkpoint only.
Base: origin/main 3be1aa6. Assignment read from
origin/docs/phase-8-parallel-assignments-20261118, `Phase 8/Moath.md`.
Branch: feature/p8-c01-driver-completion-flow. C02 is not started.

## Current source path

```mermaid
flowchart TD
  A[ControlledDriverRuntimeScreen] --> B[ControlledDriverRuntime]
  B --> C[CanonicalDriverPresentationController]
  C --> D[CanonicalDriverRepository]
  D --> E[CanonicalDriverPort / SupabaseCanonicalDriverPort]
  E --> F[Normal user SDK: eligibility, availability, offers, Trip reads]
  D --> G[inspectTransition: read-only C01 preflight]
  H[DriverCanonicalTripScreen / DriverCashCompletionPanel] --> I[Existing Cash controllers and composition]
  I --> J[SupabaseDriverCompletionSource: pinned active Cash Trip]
  J --> K[DriverCompletionCoordinator]
  K --> L[JournalDriverCompletionStagingGateway]
  L --> M[FileDriverCompletionCommandStore: append, flush, close, readback]
  K --> N[SupabaseDriverTripCompletionRepository]
  N --> O[driver_transition_trip completed]
  N --> P[Canonical Trip reread then Driver-safe receipt summary]
  I --> Q[DriverCompletionRecoveryCoordinator: journal inspection and authorized reads]
  R[DriverActiveTripScreen / MockTrip] --> S[Disabled completion; no success navigation]
```

These are existing separate runtime paths, not new wiring. C01 does not activate
or connect them. Completion coordinator and journal remain their original owners.

## Actual canonical transitions

`DriverTripLifecycleStatus` uses exact camelCase backend enum values.
`008_phase3_trip_cash_change_foundation.sql`'s `private.enforce_trip_transition`
is the edge authority, intersected with `014_phase3_driver_lifecycle_reconciliation.sql`'s
Driver RPC allowlist:

| Current | Forward Driver action | Driver cancellation |
|---|---|---|
| accepted | driverArriving | cancelledByDriver |
| driverArriving | driverArrived | cancelledByDriver |
| driverArrived | inProgress | cancelledByDriver |
| inProgress | completed | forbidden |
| completed or any other terminal | none | forbidden |

No skipped steps, reversal or terminal resurrection is a new valid command.
Same-status RPC acknowledgement can precede version comparison; it is not a new
transition or proof of permission to replay. Canonical reads can legitimately
skip intermediate observations when delivery is delayed.

Acceptance targets the offer ID/version and creates the Trip. Every subsequent
transition targets the exact Trip ID/version. P7 A04 wraps acceptance with matching
locks, expiry and active-Trip checks, and delegates non-acceptance to the preserved
017 wrapper. 017 locks the owned Trip, ensures server payment prerequisites,
checks Card progression for intermediate steps and delegates to the private
014 implementation (moved by 016). 014 requires approved unblocked Driver,
claims the actor/scope/key payload, checks Trip ownership/version and invokes
the transition trigger. Completion rejects an unapplied approved adjustment and
cancels unresolved changes; terminal completion clears active availability.
Cash settlement/receipt are server consequences in 017, never Flutter writes.
The 008 vehicle/driver FK and immutable assignment protect Trip vehicle identity;
acceptance verifies active compatible owned vehicle. Later RPCs do not independently
repeat availability/vehicle eligibility checks. Client preflight is stricter and
cannot replace server authorization or atomicity.

## Existing versus C01 changes

Existing: authenticated Cash-only canonical readers; revoked SDK session/epoch
ownership; canonical reference UI with blocked completion; completion command
triple and one-shot coordinator; journal-before-dispatch; UNKNOWN evidence;
authorized read-only recovery; canonical completion distinct from payment/receipt.
No replacement controller, completion repository or journal was introduced.

Added: Driver-only transition policy and `CanonicalDriverRepository.inspectTransition`.
It reuses existing eligibility and canonical parsing, requires exact Trip/version,
correlates onTrip availability and assigned vehicle before/after the Trip read,
checks unchanged availability version, then rechecks eligibility. It has no write,
key generation, staging, router or provider hook. Observed is a point-in-time
read result, never a reusable dispatch lease. C02 must revalidate at dispatch.

Legacy DriverActiveTripScreen previously called MockTrip completion and navigated
to shared success presentation. It now shows disabled completion and explicit
unverified payment/receipt text. Legacy controller behavior remains intact for
other consumers. Canonical and preview completion stop gates stay disabled.

Added a test-only fake Trip/transition port with an independent edge table,
version checks and original-key conflict/no-duplicate behavior. It simulates no
payment settlement or receipt and is never production authority.

## Verification

- Focused lifecycle audit + legacy completion hook: 51 passed initially.
- Driver journey regression updated for the explicit completion stop: 1 passed.
- Scoped `dart analyze` on all seven changed Dart files: no issues.
- `flutter analyze --no-pub`: 21 inherited diagnostics in unchanged files
  (3 unused-import warnings, 18 infos); exit 1. No new owned-file diagnostics.
- Final `flutter test --no-pub`: 2869 passed, 6 intentional skips, 0 failed.
  Existing completion/coordinator/journal/recovery suites are included. Initial
  full run caught one obsolete mock-success widget expectation; updated it and
  reran the full suite successfully.
- Host SDK: Flutter 3.41.2 / Dart 3.11.0; differs from guide's 3.27.3/3.6.1.
  SDK dependency-resolution and generated plugin changes are excluded.
- No hosted configuration, hosted mutation, Stripe, migration, PR, push or merge.

## Remaining boundaries and exact handoff

Omar integration request: keep the Driver branch of the shared
TripCompletionScreen/router disconnected from trusted success until canonical
completed evidence is supplied by the reviewed existing completion composition.
Its current Driver view can render hard-coded success/fare on direct navigation;
C01 removes the Driver-owned mock navigation to it but does not edit that shared
Rider/Driver screen or global router. This is a known integration risk.

C02 must attach reviewed nonproduction completion interaction to existing
coordinator/journal, revalidate active Trip/vehicle eligibility at dispatch, and
verify canonical reread before success. Preflight alone cannot prevent a server
change immediately after a read. Active-Trip restoration and terminal presentation
remain C04. No new payment/receipt contract is claimed; Yousuf owns it. C03 retains
existing durable recovery/no-replay behavior and adds only proven missing cases.
File flush is not universal directory-fsync/power-loss acceptance. Hosted migration
discrepancy #149, live device authority and trusted hosted completion remain unproven.

C01 status: implemented locally; awaiting checkpoint review. Stop before C02.
