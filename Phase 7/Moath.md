# Phase 7 — Moath

**Owner:** Moath (معاذ)
**Assigned Division:** Driver UI and Trip Lifecycle
**Workstream:** P7-B — Driver UI and Trip Lifecycle Presentation
**Suggested branch:** `feature/p7-b-driver-flow`
**Expected development:** Independent local work first; actual integration later.

> Status: PLANNED. Proposed P7 checkpoint IDs, not previously approved task IDs. No source implementation, deployment or acceptance is claimed.
> Scope: Phase 7 Cash-only matching and realtime. Stripe/Card remains disabled. Use existing code/contracts before creating anything new.
> Working rule: start from main; no dependency on another developer's unmerged branch. Use local fakes, separate code ownership, and independently passing tests. No PR, merge, migration deployment, financial operation or hosted mutation without owner authorization.
> Before each checkpoint: inspect current main, record exact paths, canonical API/RPC names and tests. If missing a Phase 6 dependency, give the owner the exact P6-Rxx task, missing evidence and stop/resume condition; continue unrelated work.
> Phase 6 authoritative task references: docs/parallel-development/phase-6/SPRINT_TRACKER.md and P6_POST_MERGE_ROADMAP.md. Those sources contain dated history; re-verify current implementation/hosted evidence.

## Phase 6 dependency guidance
P6-R01 + P6-R02 + P6-R03 + P6-R07 are HARD BLOCKS for enabling actual Cash completion/settlement/receipt. P6-R08 is the Cash-only matching handoff integration gate. P6-R06 Card remains disabled.

When the dependent functionality is encountered: STOP only that portion, report the exact ID and current missing evidence, go to the existing Phase 6 task, and resume after reviewed evidence. Do not block unrelated local checkpoints.

## Checkpoints

### [ ] P7-B01 — Driver UI audit and isolated state contract
- Work: Review Driver screens, navigation, Riverpod providers and Phase 6 canonical/mock panel separation. Agree on interface with fake offers/trips.
- Done when: File ownership map and fake repository supporting every screen state; no backend dependency.
- Status: PLANNED (not implemented).

### [ ] P7-B02 — Availability screen and controller
- Work: Create accessible Online/Offline controls with loading, offline/error, unauthorized and stale-state handling; do not override backend decisions.
- Done when: Widget/controller tests with local fake availability; backend wiring deferred.
- Status: PLANNED (not implemented).

### [ ] P7-B03 — Incoming requests UX
- Work: Show canonical route, pickup, destination, locked fare, countdown/expiry and vehicle details; avoid displaying unsupported private Rider data.
- Done when: Widget tests for new offer, expiry, no offer, repeated offer and background/resume.
- Status: PLANNED (not implemented).

### [ ] P7-B04 — Accept/reject UI safely
- Work: Implement single-flight buttons, optimistic UI prohibited as assignment proof, disabled stale actions and original idempotency token handoff.
- Done when: Fake tests for rapid double clicks, late response, rejected claim and lost response.
- Status: PLANNED (not implemented).

### [ ] P7-B05 — Accepted Driver Trip presentation
- Work: Present accepted Trip, navigation/map handoff, pickup/arrival/start status where canonical transitions permit, and logout/reconnect recovery.
- Done when: Widget tests for status/role changes, read-only recovery and safe screen exit.
- Status: PLANNED (not implemented).

### [ ] P7-B06 — Cash completion stop gate and handoff
- Work: Keep mock and financial authorities separate; label completion/receipt action disabled until P6-R01/R02/R03/R07 gate verified, and publish interface tests for backend/realtime integration.
- Done when: No fake payment success; independent green UI tests and explicit blocker list.
- Status: PLANNED (not implemented).

## Delivery checklist
- [ ] No other owner's files changed without agreement.
- [ ] Existing repositories/RPCs reused wherever safe; no unnecessary duplicate abstractions.
- [ ] Relevant local tests and analyzer/SQL checks passing with actual recorded evidence.
- [ ] No hosted activation, Stripe dispatch or financial state changes without separate authorization.
- [ ] Integration dependencies and P6-Rxx status recorded exactly, not assumed complete.
- [ ] Owner acceptance recorded separately after integration and physical-device checks.
