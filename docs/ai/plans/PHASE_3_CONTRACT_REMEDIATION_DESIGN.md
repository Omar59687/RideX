# Phase 3 Contract Remediation Design

Status: **Approved / Completed** August 9, 2026

Branch: `codex/phase-3-contract-remediation`

Base: merged Phase 3 commit `fe8e65a`

## Purpose

Close confirmed differences between the approved Phase 2 domain contract and the
Phase 3 database implementation before Phase 4 begins. This work corrects
existing database boundaries; it does not add maps, Flutter integration, Stripe,
Realtime, or Admin UI.

## Migration Safety

- Migrations `001` through `013` are immutable and must not be edited, renamed,
  reordered, deleted, or squashed.
- Every committed additive migration/test becomes immutable as well. At the
  3R.1HC checkpoint, migrations/tests `001` through `015` are protected.
- All schema and function corrections use additive compensating migrations
  beginning with `014`.
- Every migration receives a matching focused pgTAP regression file.
- Migrations `001` through `021` remain preserved; migration/test `022` is the
  final additive Phase 3 remediation.
- No remote Supabase deployment occurs in this remediation.

## Resolved Gaps

The following gaps drove the remediation design and are all resolved in the
final implementation through migration `022`:

1. Driver promotion, approval, rejection, and blocking do not consistently
   provision or reconcile the canonical `driver_availability` row.
2. The `reserved` availability state has no trusted transition path, and active
   vehicle switching can invalidate non-offline availability.
3. Card Trips can progress without a verified authorized Payment.
4. Trip creation, cancellation, and Cash completion are not atomically connected
   to Payment and Receipt lifecycle operations.
5. Some versioned RPCs do not reject null or non-positive expected versions.
6. Cash FareAdjustment pricing recalculates a full route instead of charging only
   a nonnegative remaining-route difference, and applied changes do not reconcile
   the Payment amount.
7. Payment-attempt state compatibility and idempotency payload equivalence are
   incomplete.
8. Finance table row access exposes columns beyond the approved safe Rider,
   Driver, and restricted Admin views.
9. HelpRequest text lacks Card-data rejection, and Notification navigation data
   lacks a strict destination allowlist.
10. Existing pgTAP coverage and retained verification evidence do not prove these
    boundaries.

## Checkpoint Design

### 3R.0 - Plan and Resume Workflow

Create the detailed implementation plan, remediation status file, and a
token-efficient resume command. Record Phase 3 as remediating rather than finally
approved. Do not change SQL in this checkpoint.

### 3R.1 - Driver Lifecycle Consistency

Add migration/test `014`. Provision one canonical availability row whenever a
Driver profile becomes relevant. Promotion and approval leave it offline;
rejection or blocking force it offline and clear vehicle, reservation, Trip, and
heartbeat references. Add trusted reservation/release operations and enforce
Driver ownership, approval, blocking, active vehicle, reservation, and active-Trip
consistency under row locks. Activating a different vehicle must fail while the
current vehicle is referenced by non-offline availability.

### 3R.1H - Driver Lifecycle Verification Hardening

Add migration/test `015` without changing committed migration/test `014`.
Automatically release a reservation when its offer expires or is cancelled, or
when its BookingRequest reaches a terminal state before Trip assignment. Make
release idempotent and ensure a stale terminal event cannot clear a newer valid
reservation. Reservation and release operations write bounded audit records.

Reject Driver rejection or blocking while that Driver is assigned to a
nonterminal Trip. The trusted Admin must first terminate the Trip through its
approved lifecycle operation; this checkpoint must not silently detach the
Driver or fabricate Trip, Payment, or Receipt state. Expand focused coverage for
missing-row reconciliation, actual offer-driven reservation, terminal release,
ownership and vehicle eligibility, concurrency, reserved/onTrip vehicle
switching, assignment consistency, active-Trip rejection/blocking, and audit
evidence.

### 3R.1HC - Driver Lifecycle Concurrency Correction

Add migration/test `016` without changing committed migrations/tests `001`
through `015`. Serialize Trip assignment and Driver rejection/blocking using the
same canonical lifecycle lock order: lock the target user row, then the Driver
profile row, before locking Trip or availability state. Revalidate role,
blocked state, and approval after acquiring those locks. Admin rejection and
blocking must then check for a nonterminal Trip while the lifecycle lock is
held, so a concurrent assignment cannot appear after a successful check.

Focused verification must use two independent database sessions with controlled
interleaving for assignment versus rejection and assignment versus blocking. A
second sequential call is not concurrency evidence. Each race must finish
without deadlock and leave exactly one valid result: either assignment succeeds
and the Admin operation fails closed, or the Admin operation succeeds and
assignment fails. Also verify repeated availability reconciliation is
idempotent and automatic offer/Booking releases write bounded audit evidence.

### 3R.2 - Trip, Payment, and Concurrency Safety

Add migration/test `017`. Every versioned public or backend RPC rejects null and
values below one before comparing canonical versions. Trip assignment creates or
reconciles its Payment. Card progression to `driverArriving`, `driverArrived`, or
`inProgress` requires the matching Payment to have a verified successful
authorization. Cancellation reconciles the Payment safely. Cash completion,
Payment settlement, and Receipt issuance occur atomically; failure rolls back the
entire transition. Card completion remains separate from provider Capture.

### 3R.3 - Fare and Payment-Attempt Correctness

Add migration/test `018`. Cash adjustments use trusted remaining-route inputs,
charge only the nonnegative difference, never recharge the completed route, and
reconcile Trip and Payment totals when applied. Payment attempts require a
compatible Payment/Trip state, correct operation type and amount, approved retry
limits, and strict idempotency payload equivalence. Reusing a key with different
operation data fails closed and is safely audited.

### 3R.4 - Safe Exposure and Final Verification

Add migration/test `019`. Replace direct client finance-table reads with approved
safe projections or RPCs for Rider summaries and restricted Admin finance views;
allow an assigned Driver only the approved restricted Receipt summary, never
Payment, PaymentAttempt, or Refund data. Keep authoritative and provider fields
backend-only. Reject likely payment
card data in HelpRequest subject/message without logging the rejected content.
Restrict Notification navigation to explicit application destinations and safe
identifier shapes.

Run a clean isolated reset through all additive migrations, the focused tests,
and the complete pgTAP suite. Retain Supabase CLI/Postgres versions, commit SHA,
commands, output, test totals, result, and exit status in a non-secret verification
artifact. Perform a second contract/security review, update factual project
documentation, stop local Supabase, and require a clean worktree.

### 3R.5 - Final Payment Lifecycle Remediation

Add migration/test `022`. Bind each Authorization, void, and Capture operation to
a deterministic authorization cycle. Prevent historical Authorization reuse,
require verified current-cycle release before Card cancellation, reject Payment
cancellation while a Trip is active, and reject generic Cash-paid transitions.
Enforce initial/replacement Authorization ordering, latest-failed Capture retry
ordering, pending Capture uniqueness, retry limits, and protected idempotency
payload equivalence. Add final regressions for atomic Cash completion and rollback,
zero remaining-route FareAdjustment, and Admin HelpRequest card-data rejection.

## Security and Transaction Rules

- Use row locks and database transactions for cross-aggregate state changes.
- Preserve RLS and deny direct anonymous/authenticated writes.
- Backend-authoritative fields remain writable only by trusted functions or the
  service role.
- Operations fail closed on missing state, invalid versions, mismatched
  idempotency data, incompatible lifecycle states, or incomplete settlement.
- Audit records contain bounded metadata only, never credentials, precise
  locations, unrestricted support text, or payment-card data.

## Testing Requirements

Focused pgTAP coverage must include promotion after migration `006`, approval,
rejection, blocking, reservation, vehicle switching, active-Trip consistency,
Card progression without/with verified authorization, Cash atomic completion,
cancellation reconciliation, null/zero/negative expected versions, remaining-route
adjustments, Payment reconciliation, attempt mismatch and retry limits, safe
finance exposure, HelpRequest Card-data rejection, and Notification navigation.

The final clean reset must apply migrations `001` through the latest additive
correction in order and run all database tests. Existing tests remain immutable
unless an explicit approval authorizes a narrowly scoped compatibility correction;
the 3R.4C approval changed only test `019`'s obsolete assigned-Driver Payment
expectation to the approved denial boundary.

## Completion Criteria

Phase 3 is fully complete for its approved backend-foundation scope because all
remediation checkpoints and required corrections are implemented, the independent
full reset and test suite pass, the second review has no unresolved Phase 2
contract blocker, and final verification is approved. Phase 4 has not started and
requires a separately approved scope.

Final completion confirmed August 9, 2026: migration/test `022` is the latest
Phase 3 correction. Omar manually verified a clean isolated migration run from
`001` through `022`, and the complete pgTAP suite passed with no failures. All
confirmed remediation gaps are resolved.

This completion does not mean the entire RideX product is complete. Maps, live
GPS, Flutter repository integration, real matching execution, Realtime, Stripe
Test Mode, Admin UI, notification delivery, and graduation release testing remain
assigned to later roadmap phases.
