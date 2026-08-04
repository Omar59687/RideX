# Phase 3 Contract Remediation Design

Status: Approved design awaiting written-spec review

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
- All schema and function corrections use additive compensating migrations
  beginning with `014`.
- Every migration receives a matching focused pgTAP regression file.
- No remote Supabase deployment occurs in this remediation.

## Confirmed Gaps

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

### 3R.2 - Trip, Payment, and Concurrency Safety

Add migration/test `015`. Every versioned public or backend RPC rejects null and
values below one before comparing canonical versions. Trip assignment creates or
reconciles its Payment. Card progression to `driverArriving`, `driverArrived`, or
`inProgress` requires the matching Payment to have a verified successful
authorization. Cancellation reconciles the Payment safely. Cash completion,
Payment settlement, and Receipt issuance occur atomically; failure rolls back the
entire transition. Card completion remains separate from provider Capture.

### 3R.3 - Fare and Payment-Attempt Correctness

Add migration/test `016`. Cash adjustments use trusted remaining-route inputs,
charge only the nonnegative difference, never recharge the completed route, and
reconcile Trip and Payment totals when applied. Payment attempts require a
compatible Payment/Trip state, correct operation type and amount, approved retry
limits, and strict idempotency payload equivalence. Reusing a key with different
operation data fails closed and is safely audited.

### 3R.4 - Safe Exposure and Final Verification

Add migration/test `017`. Replace direct client finance-table reads with approved
safe projections or RPCs for Rider/Driver summaries and restricted Admin finance
views; keep authoritative and provider fields backend-only. Reject likely payment
card data in HelpRequest subject/message without logging the rejected content.
Restrict Notification navigation to explicit application destinations and safe
identifier shapes.

Run a clean isolated reset through all additive migrations, the focused tests,
and the complete pgTAP suite. Retain Supabase CLI/Postgres versions, commit SHA,
commands, output, test totals, result, and exit status in a non-secret verification
artifact. Perform a second contract/security review, update factual project
documentation, stop local Supabase, and require a clean worktree.

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

The final clean reset must apply migrations `001` through `017` in order and run
all database tests. Existing tests remain preserved unless an additive migration
intentionally changes an expectation; any compatibility update must be isolated,
explained, and regression-tested.

## Completion Criteria

Phase 3 is fully complete for its approved backend-foundation scope only when all
five remediation checkpoints are committed, the independent full reset and test
suite pass, the second review finds no unresolved Phase 2 contract blocker, the
verification evidence is retained without secrets, Supabase is stopped, and the
branch is clean. Phase 4 then starts on a separate branch after this remediation
is reviewed, pushed, and merged.

This completion does not mean the entire RideX product is complete. Maps, live
GPS, Flutter repository integration, real matching execution, Realtime, Stripe
Test Mode, Admin UI, notification delivery, and graduation release testing remain
assigned to later roadmap phases.
