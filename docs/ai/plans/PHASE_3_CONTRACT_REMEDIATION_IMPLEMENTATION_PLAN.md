# Phase 3 Contract Remediation Implementation Plan

Status: Approved and completed August 8, 2026

Final hardening branch: `codex/phase-3-post-merge-hardening`

Design: `docs/ai/plans/PHASE_3_CONTRACT_REMEDIATION_DESIGN.md`

Contract: `docs/ai/plans/PHASE_2_DOMAIN_ARCHITECTURE_AND_CONTRACTS.md`

## Objective

Close the confirmed Phase 2 contract gaps in the merged Phase 3 database
foundation before Phase 4 starts. Complete exactly one checkpoint per Build-mode
session. Preserve migrations `001` through `013` byte-for-byte and use only
additive migrations and tests numbered `014` through `019`.

## Global Rules

- Verify the active branch and clean worktree before every checkpoint.
- Never edit, rename, delete, reorder, squash, or replace any committed
  migration/test. At 3R.1HC, migrations/tests `001` through `015` are immutable;
  later checkpoints must also preserve every newly committed predecessor.
- Keep Flutter, maps, GPS, Stripe calls, Realtime, real matching execution,
  Admin UI, dependencies, credentials, and remote Supabase out of scope.
- Use transactions, row locks, explicit authorization, positive expected
  versions, strict state validation, and payload-bound idempotency.
- Run the focused pgTAP file while developing, then the complete database suite
  once before the implementation commit.
- Commit implementation and status documentation separately, update the exact
  next checkpoint, stop Supabase, confirm a clean worktree, and stop.
- Never push, merge, open a Pull Request, or deploy without explicit approval.

## Checkpoint 3R.0 - Planning and Resume Package

Files:

- `docs/ai/plans/PHASE_3_CONTRACT_REMEDIATION_DESIGN.md`
- `docs/ai/plans/PHASE_3_CONTRACT_REMEDIATION_IMPLEMENTATION_PLAN.md`
- `docs/ai/ops/PHASE_3_REMEDIATION_STATUS.md`
- `.opencode/commands/resume-phase-3-remediation.md`
- Minimal pointer correction in `docs/ai/ops/PHASE_3_STATUS.md`

No SQL, tests, dependencies, configuration, or remote state changes.

Definition of done: every document agrees on branch, migration immutability,
checkpoint order, exact next checkpoint, verification rules, exclusions, and
completion criteria; `git diff --check` passes; documentation is committed; the
worktree is clean.

## Checkpoint 3R.1 - Driver Lifecycle Consistency

Migration: `supabase/migrations/014_phase3_driver_lifecycle_reconciliation.sql`

Test: `supabase/tests/database/014_phase3_driver_lifecycle_reconciliation.test.sql`

Required behavior:

- Backfill any missing canonical availability row without altering valid rows.
- Revise trusted promotion/approval/rejection/blocking functions additively so
  each relevant Driver has exactly one canonical row.
- Promotion and approval produce a valid offline row when none exists.
- Rejection or blocking locks and forces availability offline, clearing vehicle,
  Booking reservation, active Trip, and heartbeat references.
- Add backend-only reservation and release operations for the `reserved` state.
- Reservation requires a non-blocked approved Driver, owned active compatible
  vehicle, eligible BookingRequest, and no other reservation or active Trip.
- Trip assignment requires the same reservation and vehicle; acceptance moves
  `reserved` to `onTrip` atomically.
- Activating another vehicle fails whenever the existing active vehicle is
  referenced by available, reserved, or onTrip state.
- Direct client writes remain denied and all functions use empty search paths
  and explicit grants.

Focused coverage: post-`006` promotion, approval, rejection, blocking, idempotent
reconciliation, reservation/release, stale versions, wrong ownership, inactive
vehicle, vehicle switching, concurrent reservation, and active-Trip consistency.

Implementation commit: `fix(db): reconcile Driver lifecycle state`

Documentation commit: `docs(ai): advance remediation to 3R.2`

## Checkpoint 3R.1H - Driver Lifecycle Verification Hardening

Migration: `supabase/migrations/015_phase3_driver_lifecycle_verification_hardening.sql`

Test: `supabase/tests/database/015_phase3_driver_lifecycle_verification_hardening.test.sql`

Required behavior:

- Preserve migration/test `014` byte-for-byte and correct it only through this
  additive migration and focused regression file.
- Release a Driver reservation automatically and idempotently when the matching
  offer expires or is cancelled, or when the BookingRequest becomes terminal
  before Trip assignment.
- Lock and compare the current reservation identifiers so a stale terminal event
  cannot release a newer reservation.
- Write bounded audit records for reservation and release without copying
  sensitive Booking, location, or free-text data.
- Fail closed when an Admin tries to reject or block a Driver assigned to a
  nonterminal Trip. Require the existing trusted Trip termination workflow first;
  do not detach the Driver or synthesize Trip, Payment, or Receipt transitions.
- Preserve the approved offline reconciliation behavior when no nonterminal Trip
  exists.

Focused coverage: missing availability-row reconciliation and idempotence,
approval after a missing row, actual offer-driven reservation, release on offer
expiry/cancellation and Booking cancellation, stale release protection, wrong
vehicle ownership, inactive/incompatible vehicles, concurrent reservation,
reserved/onTrip vehicle switching, reservation-backed Trip assignment,
rejection/blocking during an active Trip, and reservation/release audit records.

Implementation commit: `fix(db): harden Driver reservation lifecycle`

Documentation commit: `docs(ai): advance remediation to 3R.2`

Completed August 4, 2026: implementation commit `05610b6` added only migration/test
`015`. A clean local reset applied migrations `001` through `015`; focused `015`
pgTAP passed 27 assertions and the complete database suite passed 672 assertions
across 12 files. Local Supabase was stopped after verification. Limitations: this
checkpoint did not create or alter Trip, Payment, Receipt, or settlement
transitions.

## Checkpoint 3R.1HC - Driver Lifecycle Concurrency Correction

Migration: `supabase/migrations/016_phase3_driver_lifecycle_concurrency_correction.sql`

Test: `supabase/tests/database/016_phase3_driver_lifecycle_concurrency_correction.test.sql`

Required behavior:

- Preserve migrations/tests `001` through `015` byte-for-byte and apply only an
  additive correction.
- Replace the trusted Trip-transition and Admin rejection/blocking functions as
  needed so each acquires lifecycle locks in the same order: target user row,
  Driver profile row, then Trip/availability resources.
- Revalidate the Driver role, blocked state, approval status, and operation
  authority after acquiring the lifecycle locks; do not rely only on state read
  before waiting for a lock.
- While holding those locks, reject Driver rejection/blocking when a nonterminal
  Trip exists. Ensure a concurrent assignment cannot commit between the check
  and the Admin state change.
- Preserve all existing Trip-transition, idempotency, RLS, grants, audit,
  reservation, Payment, and Receipt behavior outside this correction.
- Avoid inverse lock ordering and verify both race directions complete without
  deadlock.

Focused coverage:

- Use two independent database sessions with deterministic synchronization to
  exercise assignment versus rejection and assignment versus blocking.
- Prove that exactly one side succeeds and final Trip, Driver approval/blocking,
  and availability state remain consistent.
- A sequential second reservation call must not be presented as concurrency
  coverage.
- Re-run repeated missing-row reconciliation/idempotence coverage and assert
  automatic offer-expiry/cancellation and terminal-Booking release each produce
  bounded audit evidence.
- If the local database cannot provide a safe two-session test mechanism, stop
  and report the blocker instead of substituting a sequential test.

Implementation commit: `fix(db): serialize Driver lifecycle transitions`

Documentation commit: `docs(ai): advance remediation to 3R.2`

Completed August 4, 2026: implementation commit `c83bdf1` added only
migration/test `016`. The focused pgTAP file used independent `dblink` sessions
with deterministic lock waits to exercise assignment versus rejection and
assignment versus blocking in both winner orders; all 37 assertions passed. A
second clean local reset applied migrations `001` through `016`, and the complete
database suite passed 709 assertions across 13 files. The correction preserves
the prior Trip transition implementation behind a private function, exposes an
authenticated-only public wrapper, and serializes accepted assignment with
Admin rejection/blocking. Local Supabase was stopped after verification.

## Checkpoint 3R.2 - Trip, Payment, and Concurrency Safety

Migration: `supabase/migrations/017_phase3_trip_payment_concurrency.sql`

Test: `supabase/tests/database/017_phase3_trip_payment_concurrency.test.sql`

Required behavior:

- Inventory every versioned public/backend/Admin Phase 3 RPC and reject null,
  zero, and negative expected versions before any comparison or idempotent
  early return.
- Trip assignment atomically creates or reconciles exactly one Payment tied to
  the BookingRequest, FareQuote, Trip, Rider, method, currency, and fare.
- Card progression to `driverArriving`, `driverArrived`, or `inProgress`
  requires the canonical Payment to be `cardPaymentAuthorized` and backed by a
  verified successful, timely authorization attempt.
- Rider/Driver/Admin cancellation atomically reconciles Cash cancellation or
  safely cancels/releases eligible pre-start Card state. It must fail closed if
  trusted provider reconciliation is still required.
- Cash completion atomically transitions the Trip, cancels unresolved
  unapproved changes, blocks approved-unapplied changes, settles the Payment at
  the reconciled final amount, and issues one Receipt. Any failure rolls back
  all changes.
- Card completion records Trip completion only; Capture remains a later trusted
  provider operation and no paid Receipt is fabricated.

Focused coverage: all invalid expected-version shapes, Payment creation/replay,
Card progression denied before authorization, accepted after verified
authorization, cancellation reconciliation, atomic Cash settlement/Receipt,
rollback on failure, and Card completion without fabricated settlement.

Implementation commit: `fix(db): enforce Trip Payment atomicity`

Documentation commit: `docs(ai): advance remediation to 3R.3`

Completed August 5, 2026: implementation commit `f9c4c08` added migration/test
`017` and made the explicitly approved compatibility correction to the Card
lifecycle expectations in test `008`; migration `008` remained unchanged. The
correction enforces positive expected versions, atomic canonical Payment
creation/reconciliation, verified Card authorization before Driver progression,
safe cancellation handling, and atomic Cash settlement with one Receipt. After
a clean reset through migration `017`, focused test `008` passed 117 assertions
and focused test `017` passed 55 assertions. A second clean reset applied
migrations `001` through `017`, and the complete suite passed 767 assertions
across 14 files. Local Supabase was stopped after verification. Card Capture
remains a trusted provider operation and was not fabricated by Trip completion.

## Checkpoint 3R.3 - Fare and Payment-Attempt Correctness

Migration: `supabase/migrations/018_phase3_fare_payment_attempt_hardening.sql`

Test: `supabase/tests/database/018_phase3_fare_payment_attempt_hardening.test.sql`

Required behavior:

- Price Cash Trip changes from trusted remaining-route metrics, excluding the
  already completed route and already charged components.
- Adjustment equals `max(0, trusted_new_remaining_fare -
  trusted_original_remaining_fare)` using approved JOD fils pricing and rounding.
- Applying an approved adjustment atomically updates Trip route/current fare,
  stops, adjustment/request states, and canonical Cash Payment final amount.
- Reconcile all operation types with compatible Payment/Trip states: initial or
  replacement authorization, Capture or Capture retry, void/cancellation, and
  Refund attempts.
- Enforce approved attempt totals and operation ordering.
- Bind each idempotency key to Payment/Refund, operation type, amount, currency,
  provider, and other authoritative operation inputs. Identical replay returns
  the canonical attempt; mismatched reuse fails closed and writes safe metadata
  audit evidence.
- A terminal attempt cannot be completed again with different terminal data.

Focused coverage: nonnegative and zero adjustments, completed-route exclusion,
Payment reconciliation, stale versions, incompatible attempt states, attempt
limits, identical replay, mismatched replay, and terminal completion mismatch.

Implementation commit: `fix(db): harden Fare and Payment attempts`

Documentation commit: `docs(ai): advance remediation to 3R.4`

Completed August 5, 2026: implementation commit `1093bdc` added only migration/test
`018`. A clean local reset applied migrations `001` through `018`; focused `018`
pgTAP passed 13 assertions and the complete database suite passed 780 assertions
across 15 files. Local Supabase was stopped after verification. The checkpoint
preserves the earlier Card Capture boundary while enforcing remaining-route Cash
pricing, Payment reconciliation, PaymentAttempt compatibility, retry limits, and
payload-bound idempotency.

## Checkpoint 3R.4 - Safe Exposure and Final Verification

Migration: `supabase/migrations/019_phase3_safe_exposure_hardening.sql`

Test: `supabase/tests/database/019_phase3_safe_exposure_hardening.test.sql`

Verification artifact: `docs/ai/verification/PHASE_3_REMEDIATION_VERIFICATION.md`

Required behavior:

- Revoke authenticated whole-row finance-table reads that expose backend-only
  or provider-sensitive columns.
- Add stable safe projections or narrow RPCs for Rider Payment summaries,
  PaymentAttempt summaries, Refund status, participant Receipt data, and
  restricted Admin finance/support views.
- Preserve direct client write denial and prevent Driver finance access beyond
  the approved Receipt/Trip relationship.
- Reject likely PAN/card-number patterns and CVV/CVC disclosures in HelpRequest
  subject/message and Admin resolution input without persisting or auditing the
  rejected content.
- Define an explicit Notification navigation destination allowlist and validate
  destination-specific identifiers. Continue recursive sensitive-payload
  rejection.
- Reassert the complete RLS/grant/function matrix after all corrections.

Focused coverage: column-level finance exposure by Rider, Driver, Admin, blocked
user, anonymous user, and service role; HelpRequest Card-data patterns;
Notification destinations/identifiers; function grants; direct writes; and all
new regression boundaries from 3R.1-3R.3.

Final verification:

1. Capture Git commit SHA, Docker version, Supabase CLI version, and PostgreSQL
   version without secrets.
2. Start local Supabase and perform a clean local reset applying migrations
   `001` through `019` in order.
3. Run focused `019` pgTAP verification.
4. Run the complete database test suite once and capture command, output totals,
   result, and exit status in the verification artifact.
5. Perform a second implementation/security review against the Phase 2 contract,
   this plan, the full RLS matrix, and captured results.
6. Correct any confirmed finding through migration `020+` and matching tests;
   do not declare completion while a blocker remains.
7. Update Phase 3 and remediation status documents, stop Supabase, inspect the
   complete branch diff, and confirm a clean worktree.

Implementation commit: `fix(db): finalize Phase 3 contract remediation`

Documentation commit: `docs(ai): complete Phase 3 remediation`

The original August 5, 2026 completion record is superseded by corrective
checkpoint 3R.4C below. The review found that migration `019` authorized an
assigned Driver to read Payment, PaymentAttempt, and Refund summaries, contrary
to this checkpoint's approved Receipt/Trip-only Driver relationship.

## Checkpoint 3R.4C - Driver Finance Exposure Correction

Migration: `supabase/migrations/020_phase3_driver_finance_exposure_correction.sql`

Test: `supabase/tests/database/020_phase3_driver_finance_exposure_correction.test.sql`

Required behavior:

- Preserve migrations/tests `001` through `019` byte-for-byte and correct only
  through this additive migration and focused regression file.
- Separate finance authorization by resource: Rider and Admin may read approved
  Payment, PaymentAttempt, Refund, and Receipt summaries; an assigned Driver may
  read only the restricted Receipt summary for the assigned Trip.
- Deny Drivers Payment, PaymentAttempt, and Refund summaries even for an
  assigned Trip. Deny unrelated Drivers, blocked users, and anonymous users all
  finance summaries.
- Preserve service-role operations and direct-client write denial.

Verification result, August 5, 2026: implementation commit `5564bc8` added only
migration/test `020`. The explicit compatibility approval then authorized commit
`16dbbe2` to change only test `019`'s obsolete assigned-Driver Payment-read
expectation to the approved `42501` denial. A clean local reset applied migrations
`001` through `020`; focused tests `019` and `020` passed 15 and 36 assertions.
The complete suite passed 831 assertions across 17 files. Assigned-Driver Receipt
access remains covered by test `020`. Evidence is retained in
`docs/ai/verification/PHASE_3_REMEDIATION_VERIFICATION.md`.

## Verification Commands

Use the locally configured Supabase project only:

```powershell
npx supabase@latest start
npx supabase@latest db reset --local
npx supabase@latest test db --local supabase/tests/database/<focused-file>.sql
npx supabase@latest test db --local
npx supabase@latest stop
```

If the installed CLI does not accept a focused path, document that fact and run
the complete local suite instead. Never use `supabase link`, `db push`, remote
reset, production credentials, or a remote project in this remediation.

## Final Definition of Done

Phase 3 becomes Approved/Completed for its backend-foundation scope only when:

- Checkpoints 3R.0, 3R.1, 3R.1H, 3R.1HC, 3R.2 through 3R.4, and any required
  corrective checkpoint are committed in order.
- Migrations/tests `001` through at least `019`, including any required `020+`
  review correction, apply and pass without editing any committed predecessor.
- Every confirmed blocker in the approved design has a focused regression.
- The complete pgTAP suite passes from a clean isolated local reset.
- The second review records no unresolved Phase 2 contract or security blocker.
- Verification evidence contains versions, commit SHA, commands, totals, result,
  and exit status, but no credentials or machine-specific secrets.
- Local Supabase is stopped and the worktree is clean.
- No remote Supabase deployment or Phase 4 implementation has occurred.

## Post-Merge Hardening Completion

Completed August 8, 2026: implementation commit `e2b4a30` added migration/test
`021` and the approved compatibility updates to tests `008`, `012`, and `013`.
Migrations `001` through `020` remain unchanged. `021` closes the post-merge
FareQuote version gate, retires the full-route Cash pricing RPC, binds Card
authorization to the latest applicable attempt, hardens Refund ordering and
idempotency, validates recipient-authorized Notification destinations, and
deterministically sequences historical PaymentAttempts by `created_at, id` before
generated future values.

A clean reset through `021` passed. Focused tests `008`, `012`, `013`, and `021`
passed 118, 68, 44, and 38 assertions; the complete suite passed 873 assertions
across 18 files. Database lint produced only three pre-existing warnings. Supabase
was stopped, no RideX containers remained, and no remote action occurred.

Phase 3 remediation and post-merge hardening are Approved and Completed. No known
Phase 3 contract blocker remains. The next project activity is separate Phase 4
planning; Phase 4 has not started.
