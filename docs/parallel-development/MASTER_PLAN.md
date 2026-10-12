# RideX Parallel Development — Master Plan (Phases 6–10)

Baseline: `yousuf/supabase-env-audit` at `6bae92ed4fb2ab909913b6c3c1d91eb875794daa`
(which contains latest `main`). Source of truth: `Plan.md`, `docs/ai/ops/CURRENT_STATUS.md`,
`docs/ai/ops/ARCHITECTURE.md`, actual repo files. Status authority:
`docs/parallel-development/phase-6/SPRINT_TRACKER.md`.

## Standing verification guard

- Phase 4: checkpoints 4A–4F approved; 4G automated 4.36/4.37/4.39 passed.
  Task 4.38 (two-device), task 4.40, and `PHASE 4 APPROVED` remain unchecked.
- Phase 5: five implementation checkpoints passed focused review in `65e9bf9`;
  hosted/device verification and `PHASE 5 APPROVED` remain pending.
- Merging code never approves a phase. Do not mark Phase 4 or 5 APPROVED without evidence.

## Phase scope (from Plan.md)

### Phase 6 — Payment Foundations
- Persistent Cash payment foundations (reuse Phase 3 `008`/`009`/`017`/`022` concepts; no migration rewrite).
- Provider-independent Card payment contracts (no Stripe types in domain/UI contracts).
- Stripe Test Mode PaymentIntent + secure UI foundations (secrets server-side only,
  manual capture, client callbacks advisory only).

### Phase 7 — Matching and Realtime
- Driver availability (canonical availability remains source of truth).
- Nearby Driver matching + atomic assignment (no double acceptance).
- Supabase Realtime Rider–Driver trip/location sync (RLS-preserving, canonical re-fetch on gaps).

### Phase 8 — Payment Completion and History
- Card authorization (post-match only), capture (post-trusted-completion only),
  cancellation/refund, webhook verification + replay protection, receipts, payment history.
- Persistent trip history + active-trip restoration (replace `MockTripsRepository` behavior).

### Phase 9 — Secondary and Admin Workflows
- Persistent profiles, notifications, ratings, help requests.
- Basic admin driver approval, trip visibility, sanitized payment visibility.

### Phase 10 — Verification and Release
- Flutter/DB/payment/security verification; two-device E2E; responsive/a11y/platform/release.

## Dependency overview

```text
P5 fare lock/confirm ──> P6 cash/card foundations ──> P8 auth/capture/refund/receipts
P4 driver location/GPS ──> P7 availability/matching/Realtime ──> P8 trip completion triggers
P6 + P7 ──> P8 (capture only after match + trusted completion)
P8 ──> P9 (history/admin visibility) ──> P10 (E2E/release)
P4.38/P5 hosted/device tails run parallel, never gate P6 contract/UI work,
but gate P6→P8 financial execution claims and P10 release.
```

Blocked-by-verification tasks: any task claiming trusted capture, atomic assignment,
or release readiness is blocked until its hosted/device evidence exists. Contract and
mock-backed UI tasks are not blocked.

## Parallel workstreams (hybrid)

- Stream A (Backend/contracts, Dev 1 leads): P6-01…P6-04, P6-09; P7/P8 RPC/RLS/Edge later.
- Stream B (Rider, Dev 2 leads): P6-05, P6-06; P8 history/receipts; P9 rider secondary.
- Stream C (Driver/Admin + verification, Dev 3 leads): P6-07, P6-08; P7 driver-side;
  V4-01/V4-02/V5-01…V5-04 carry-over verification.
- Anyone may use Supabase SDK/Flutter repos; schema/RLS/migration numbering/shared
  contracts require Dev 1 coordination.

## Risks

1. Shared providers/router (`repositories_providers.dart`, `session_providers.dart`,
   `app_router.dart`, `route_guards.dart`) — one writer per sprint; others mock/test-only.
2. Fare/payment/trip model drift — contract-first; fakes mirror version/idempotency rules.
3. Client-authoritative payment success — forbidden; server-canonical only.
4. Secret leakage (Stripe/service-role) — server-side only; review gate blocks.
5. Matching concurrency (double acceptance) — P7 needs locked assignment; no UI shortcut.
6. Realtime bypassing RLS — subscriptions validate participant + canonical state.
7. Migration numbering conflicts — Dev 1 owns; additive only, never rewrite applied ones.
8. Two-device/hosted evidence scarcity — tracked separately, never silently deferred.

## Update policy

- When Phase 6 finishes: preserve `phase-6/` as history, refresh this file,
  generate detailed Phase 7 files from latest repo state. Never follow stale estimates blindly.
- `SPRINT_TRACKER.md` is the only status authority; other docs reference it.