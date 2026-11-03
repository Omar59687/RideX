# Phase 7 — Sanad

**Owner:** Sanad (سند)
**Assigned Division:** Rider UI and Tracking
**Workstream:** P7-C — Rider UI and Live Trip Tracking
**Suggested branch:** `feature/p7-c-rider-tracking`
**Expected development:** Independent local work first; actual integration later.

> Status: PLANNED. Proposed P7 checkpoint IDs, not previously approved task IDs. No source implementation, deployment or acceptance is claimed.
> Scope: Phase 7 Cash-only matching and realtime. Stripe/Card remains disabled. Use existing code/contracts before creating anything new.
> Working rule: start from main; no dependency on another developer's unmerged branch. Use local fakes, separate code ownership, and independently passing tests. No PR, merge, migration deployment, financial operation or hosted mutation without owner authorization.
> Before each checkpoint: inspect current main, record exact paths, canonical API/RPC names and tests. If missing a Phase 6 dependency, give the owner the exact P6-Rxx task, missing evidence and stop/resume condition; continue unrelated work.
> Phase 6 authoritative task references: docs/parallel-development/phase-6/SPRINT_TRACKER.md and P6_POST_MERGE_ROADMAP.md. Those sources contain dated history; re-verify current implementation/hosted evidence.

## Phase 6 dependency guidance
P6-R08 Cash-only booking confirmation is an integration gate; P6-R06 + P6-R08 Card authorization is a HARD BLOCK; P6-R05 canonical Cash detail is scoped and must not be confused with Phase 8 full history.

When the dependent functionality is encountered: STOP only that portion, report the exact ID and current missing evidence, go to the existing Phase 6 task, and resume after reviewed evidence. Do not block unrelated local checkpoints.

## Checkpoints

### [ ] P7-C01 — Rider booking/Trip UI audit and isolated contracts
- Work: Review current Cash-only handoff, booking confirmation, map and trip screens, Riverpod providers and accepted mock boundaries.
- Done when: Bounded own-files map, fake Trip repository/event/location stream, expected screens.
- Status: PLANNED (not implemented).

### [ ] P7-C02 — Searching/matching presentation
- Work: Implement searching, timeout, retry, unavailable Driver and cancellation presentation without duplicate booking or fake assignment authority.
- Done when: Widget tests for empty/no driver, timeout, retry, session change and navigation.
- Status: PLANNED (not implemented).

### [ ] P7-C03 — Driver assigned details
- Work: Show Driver and vehicle from exact authorized assigned Trip, with read-only loading/unknown fields and no fabricated IDs.
- Done when: Widget tests for verified assignment, stale event, wrong Trip and missing vehicle details.
- Status: PLANNED (not implemented).

### [ ] P7-C04 — Live map tracking screen
- Work: Render map Driver marker and route state from injected location snapshots, with stale/GPS-unavailable indicators; no direct database ownership.
- Done when: Widget/map-state tests using fake coordinate sequences and permission/offline cases.
- Status: PLANNED (not implemented).

### [ ] P7-C05 — Trip state and reconnect lifecycle
- Work: Track accepted, approaching, arrived, active and terminal statuses as supported by canonical backend; restore from fresh read on reconnect.
- Done when: Widget tests for duplicates, out-of-order events, logout and background/resume.
- Status: PLANNED (not implemented).

### [ ] P7-C06 — Cash-only guard and integration handoff
- Work: Keep Card/Stripe entry unavailable; show no paid/receipt success without canonical read. Integrate with A/D only after contracts are verified.
- Done when: Independent UI tests, exact P6-R08 handoff gate and later two-device acceptance checklist.
- Status: PLANNED (not implemented).

## Delivery checklist
- [ ] No other owner's files changed without agreement.
- [ ] Existing repositories/RPCs reused wherever safe; no unnecessary duplicate abstractions.
- [ ] Relevant local tests and analyzer/SQL checks passing with actual recorded evidence.
- [ ] No hosted activation, Stripe dispatch or financial state changes without separate authorization.
- [ ] Integration dependencies and P6-Rxx status recorded exactly, not assumed complete.
- [ ] Owner acceptance recorded separately after integration and physical-device checks.
