# Phase 7 — Sanad

**Owner:** Sanad (سند)
**Assigned Division:** Rider UI and Tracking
**Workstream:** P7-C — Rider UI and Live Trip Tracking
**Suggested branch:** `feature/p7-c-rider-tracking`
**Expected development:** Independent local work first; actual integration later.

> Status: P7-C05 is locally complete and independently accepted, pending owner-approved PR/merge. Other checkpoints remain unchecked; Phase 7 integration, deployment and overall acceptance are not claimed.
> Scope: Phase 7 Cash-only matching and realtime. Stripe/Card remains disabled. Use existing code/contracts before creating anything new.
> Working rule: start from main; no dependency on another developer's unmerged branch. Use local fakes, separate code ownership, and independently passing tests. No PR, merge, migration deployment, financial operation or hosted mutation without owner authorization.
> Before each checkpoint: inspect current main, record exact paths, canonical API/RPC names and tests. If missing a Phase 6 dependency, give the owner the exact P6-Rxx task, missing evidence and stop/resume condition; continue unrelated work.
> Phase 6 authoritative task references: docs/parallel-development/phase-6/SPRINT_TRACKER.md and P6_POST_MERGE_ROADMAP.md. Those sources contain dated history; re-verify current implementation/hosted evidence.

## Start here — READY_LOCAL (2026-11-03)

**First issue:** [#112](https://github.com/Omar59687/RideX/issues/112)

Begin P7-C01: inventory existing Rider booking/screens and build fake assigned-trip/location streams. Then implement C02–C04 independently, with widget/map tests.

**Dependency gates:** P6-R08 gates live Cash-only booking confirmation. P6-R06/R08 hard-block Card activation; P6-R05 is only scoped canonical Cash read, not full Phase 8 history.

**Execution:** Create your own feature branch from the latest main when ready; never depend on another owner's unmerged branch. Work with fake adapters/contracts for integration-facing features. Review changes, prove tests, and request owner approval before opening a PR or doing any hosted mutation. READY_LOCAL does not mean deployed, integrated, tested or accepted.

### GitHub checkpoint issues
- [P7-C01](https://github.com/Omar59687/RideX/issues/112)
- [P7-C02](https://github.com/Omar59687/RideX/issues/113)
- [P7-C03](https://github.com/Omar59687/RideX/issues/114)
- [P7-C04](https://github.com/Omar59687/RideX/issues/115)
- [P7-C05](https://github.com/Omar59687/RideX/issues/116)
- [P7-C06](https://github.com/Omar59687/RideX/issues/117)

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

### [x] P7-C05 — Trip state and reconnect lifecycle
- Work: Implement an isolated canonical Rider Trip lifecycle state/controller and status UI; use canonical reads as the only Trip status authority and reconcile after resume or confirmed reconnect.
- Done when: Deterministic controller and provider-backed widget tests cover canonical status authority, duplicate/out-of-order events, logout, background/resume, reconnect generation ordering, stale privacy and terminal outcomes.
- Status: LOCALLY COMPLETE — ACCEPTED, PENDING OWNER PR/MERGE.
- Completed local scope:
  - Canonical Rider Trip lifecycle state/controller with authenticated Rider ownership, session protection, A→B→A isolation, Trip/repository replacement handling, stale callback fencing, and terminal protection.
  - Advisory duplicate and out-of-order event handling; canonical reads remain the only status authority.
  - Stale-state privacy, Flutter app-resume reconciliation, and confirmed reconnect generation handling.
  - Isolated canonical Rider Trip status UI with accessible presentation and an explicit payment/receipt disclaimer.
  - Provider-backed widget tests for duplicates, out-of-order events, logout, and background/resume.
- Commits:
  - `3b4327a` — Canonical lifecycle controller.
  - `4af3c8e` — App lifecycle and reconnect orchestration.
  - `886a717` — Canonical Rider Trip status UI.
  - `3130f73` — Final widget acceptance coverage.
- Reported local verification (not independently rerun during this documentation update):
  - Full Flutter suite: 2,030 passed, 2 skipped, 0 failed.
  - Focused lifecycle widget tests: 6 passed.
  - Controller/status UI/architecture regression: 47 passed.
  - Flutter analyzer: six existing unrelated diagnostics; no new C05 findings.
- Deferred integration and boundaries:
  - Live Rider Supabase repository integration and production Rider Trip route mounting remain deferred to their owning integration work.
  - C04 live-map integration is not included and is not a dependency on unmerged PR #124.
  - Payment, settlement, Stripe, and receipt issuance are outside C05; Trip completion does not establish any of these outcomes.
  - Existing Phase 6 gates remain: P6-R08 gates live Cash booking confirmation, P6-R06/R08 block Card activation, and P6-R05 is limited to bounded canonical Cash detail.
  - No hosted operation, financial action, or other owner's code change is included. Owner approval is still required before PR/merge; this does not mark Phase 7 fully complete.

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
