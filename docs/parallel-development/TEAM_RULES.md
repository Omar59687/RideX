# RideX Parallel Development — Team Rules

Authority: this file defines process. Task status authority:
`phase-6/SPRINT_TRACKER.md`. Source of truth for scope:
`Plan.md`, `docs/ai/ops/CURRENT_STATUS.md`.

## 1. Branches

- One short-lived feature branch per implementation task, based on latest `main`
  (currently reachable from this branch baseline `6bae92e`).
  Examples: `feature/p6-cash-contract`, `feature/p6-rider-payment-ui`,
  `feature/p6-admin-payment-visibility`. Names are per-task, not fixed.
- Never implement directly on `main` or on this planning branch.
- Never switch branches for another developer; each dev owns their checkout.
- Verification-only tasks (V4-*/V5-*) use no code branch unless a fix is required;
  then they follow the same one-task-one-branch rule.

## 2. Reviews and integration

- Every PR needs one independent reviewer; no self-approval.
- Integration Owner rotates per sprint: Sprint 1 Dev 1, Sprint 2 Dev 2,
  Sprint 3 Dev 3, Sprint 4 Dev 1, repeat. Owner coordinates reviews, checks
  boundaries/tests/acceptance, detects shared-file/contract conflicts,
  coordinates safe merging, updates `SPRINT_TRACKER.md`, confirms `main` stays stable.
- Merge only verified + approved work. Unready tasks stay on their branches;
  next sprint starts from updated `main`.
- Two-day cadence is a target, never permission to merge incomplete/unsafe work.

## 3. Shared-file ownership (actual structure)

Sensitive — one production writer per sprint, others test/mock-only or read-only:

- `lib/app/router/app_router.dart`, `route_guards.dart`, `route_names.dart`
- `lib/core/providers/session_providers.dart`, `repositories_providers.dart`
- `lib/core/repositories/fare_repository.dart`, `booking_repository.dart`,
  `trips_repository.dart`, new `payment_repository.dart` once created
- `lib/core/models/fare_quote.dart`, `booking_draft.dart`, `mock_trip.dart`,
  new payment models once created
- `supabase/migrations/*.sql`, `supabase/functions/fare/*`, `supabase/functions/places/*`

If two tasks need the same shared file in one sprint, the plan must name an
integration strategy (single owner + mock interface, or sequentialize). Different
files do not imply independence — API/runtime coupling counts.

## 4. Supabase coordination

- Dev 1 is primary Supabase coordinator (schema, RLS, migration numbering, RPC/Edge
  contracts). Devs 2/3 may write Flutter repos, SDK integration, and assigned backend
  work, but shared backend contract changes require Dev 1 review.
- Never rewrite an applied migration. New migrations only when separately authorized,
  additive, Dev 1-numbered. No hosted operations or deploys during planning;
  none are authorized by these docs.

## 5. Security restrictions

- Stronger review for payments, matching concurrency, auth/RLS, secrets.
- Never collect/store raw card data; never put Stripe/service-role secrets in
  Flutter, config, Git, logs, or client-readable rows.
- Flutter never declares canonical payment success; callbacks/redirects are advisory.
- Webhook/replay protection, idempotency keys, and expected-version checks required
  where Phase 2/3 contracts demand them.

## 6. Contract-first

1. Name the contract + owner. 2. Define inputs/outputs/transitions/errors.
3. Frontend builds against a matching mock/fake. 4. Integrate only after contract +
   compatibility tests pass. Do not invent backend contracts; respect
   Service → Repository → Provider/Controller → UI.

## 7. AI-agent usage (limited free tier)

- One bounded task per agent invocation; pass task-specific files only.
- Focused tests during work; larger verification at integration boundaries.
- Lightweight review for low-risk UI; strong review for financial/auth/matching.
- Never auto-commit/merge/push/deploy. No Software Factory for routine work.

## 8. Definition of Done

- Scope met + acceptance criteria checked; focused tests + `flutter analyze` clean;
  full non-live suite at integration boundary; no shared-file/contract break;
  docs updated on the task branch; Integration Owner confirms tracker + stable `main`.