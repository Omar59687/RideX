# Phase 7 — Sanad

**Owner:** Sanad (سند)
**Assigned Division:** Rider UI and Tracking
**Workstream:** P7-C — Rider UI and Live Trip Tracking
**Suggested branch:** `feature/p7-c-rider-tracking`
**Expected development:** Independent local work first; actual integration later.

> Status: READY FOR INDEPENDENT LOCAL START (checkpoints remain unchecked until verified). Proposed P7 checkpoint IDs, not previously approved task IDs. No source implementation, deployment or acceptance is claimed.
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

### [ ] P7-C05 — Trip state and reconnect lifecycle
- Work: Track accepted, approaching, arrived, active and terminal statuses as supported by canonical backend; restore from fresh read on reconnect.
- Done when: Widget tests for duplicates, out-of-order events, logout and background/resume.
- Status: PLANNED (not implemented).

### [x] P7-C06 — Cash-only guard and integration handoff
- Work: Keep Card/Stripe entry unavailable; show no paid/receipt success without canonical read. Integrate with A/D only after contracts are verified.
- Done when: Independent local UI/regression tests, documented Phase 6 dependency disposition, and a future two-device acceptance checklist.
- Status: LOCAL IMPLEMENTATION COMPLETE and independently reviewed. Slice 1 (`bcc3eb2`) preserves the Demo Cash-only continuation guard; Slice 2 (`59d8404`) tests canonical Cash booking confirmation as a booking result, not payment/receipt success; Slice 3 (`7809956`) records the integration handoff. Card/Stripe remains disabled. Reported C06 local evidence: 2,246 PASS, 2 SKIP, 0 FAIL in the full suite; six analyzer diagnostics are pre-existing and unrelated. See `docs/ai/verification/P7_C06_CASH_GUARD_HANDOFF.md`.
- Live/two-device acceptance: PENDING / NOT RUN. No owner acceptance is claimed. P6-R06/R07/R08 and Phase 7 matching/Rider/Driver integration dispositions remain separate gates; Phase 6 is NOT APPROVED. Keep the overall Phase 7 completion status open until those gates receive their own evidence and owner disposition.

## Delivery checklist
- [ ] No other owner's files changed without agreement.
- [ ] Existing repositories/RPCs reused wherever safe; no unnecessary duplicate abstractions.
- [ ] Relevant local tests and analyzer/SQL checks passing with actual recorded evidence.
- [ ] No hosted activation, Stripe dispatch or financial state changes without separate authorization.
- [ ] Integration dependencies and P6-Rxx status recorded exactly, not assumed complete.
- [ ] Owner acceptance recorded separately after integration and physical-device checks.
