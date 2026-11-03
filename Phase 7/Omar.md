# Phase 7 — Omar

**Owner:** Omar (عمر)
**Assigned Division:** Realtime and GPS
**Workstream:** P7-D — Realtime and Driver Location Infrastructure
**Suggested branch:** `feature/p7-d-realtime-location`
**Expected development:** Independent local work first; actual integration later.

> Status: READY FOR INDEPENDENT LOCAL START (checkpoints remain unchecked until verified). Proposed P7 checkpoint IDs, not previously approved task IDs. No source implementation, deployment or acceptance is claimed.
> Scope: Phase 7 Cash-only matching and realtime. Stripe/Card remains disabled. Use existing code/contracts before creating anything new.
> Working rule: start from main; no dependency on another developer's unmerged branch. Use local fakes, separate code ownership, and independently passing tests. No PR, merge, migration deployment, financial operation or hosted mutation without owner authorization.
> Before each checkpoint: inspect current main, record exact paths, canonical API/RPC names and tests. If missing a Phase 6 dependency, give the owner the exact P6-Rxx task, missing evidence and stop/resume condition; continue unrelated work.
> Phase 6 authoritative task references: docs/parallel-development/phase-6/SPRINT_TRACKER.md and P6_POST_MERGE_ROADMAP.md. Those sources contain dated history; re-verify current implementation/hosted evidence.

## Start here — READY_LOCAL (2026-11-03)

**First issue:** [#95](https://github.com/Omar59687/RideX/issues/95)

Begin P7-D01: inventory existing Phase 4 GPS and realtime contracts. Then build P7-D02/D03 with injectable fake streams without waiting for backend assignment.

**Dependency gates:** P7-A's canonical accepted Trip contract gates live wiring, not independent local development. P6-R04 protects relevant hosted actor/role acceptance; P6-R01 only where canonical Driver context is reused.

**Execution:** Create your own feature branch from the latest main when ready; never depend on another owner's unmerged branch. Work with fake adapters/contracts for integration-facing features. Review changes, prove tests, and request owner approval before opening a PR or doing any hosted mutation. READY_LOCAL does not mean deployed, integrated, tested or accepted.

### GitHub checkpoint issues
- [P7-D01](https://github.com/Omar59687/RideX/issues/95)
- [P7-D02](https://github.com/Omar59687/RideX/issues/96)
- [P7-D03](https://github.com/Omar59687/RideX/issues/97)
- [P7-D04](https://github.com/Omar59687/RideX/issues/98)
- [P7-D05](https://github.com/Omar59687/RideX/issues/99)
- [P7-D06](https://github.com/Omar59687/RideX/issues/100)

## Phase 6 dependency guidance
P6-R04 hosted protected-role/session evidence where reused (exit/integration gate); P6-R01 Driver canonical context when reused (integration gate). P6-R06 Stripe is NOT required for Cash-only streams.

When the dependent functionality is encountered: STOP only that portion, report the exact ID and current missing evidence, go to the existing Phase 6 task, and resume after reviewed evidence. Do not block unrelated local checkpoints.

## Checkpoints

### [ ] P7-D01 — Read-only Phase 4 GPS and event contract audit
- Work: Find approved driver location tracking, lifecycle, Supabase channels/policies, canonical Trip IDs, Riverpod owners and existing mock-versus-real switches.
- Done when: Inventory and shared minimal event contract; no reimplementation of Phase 4 GPS.
- Status: PLANNED (not implemented).

### [ ] P7-D02 — Secure Trip Realtime adapter
- Work: Implement isolated, injectable subscription adapter for authorized assigned Trip status/assignment events; do not introduce finance-specific state.
- Done when: Unit tests with fake event sources; unauthorized foreign Trip isolation criteria.
- Status: PLANNED (not implemented).

### [ ] P7-D03 — Driver location publisher
- Work: Extend existing foreground permission and active-Trip location logic with throttling/staleness checks, ownership, battery-aware bounded updates, stop on offline/logout.
- Done when: Local timing/lifecycle tests and documented privacy rules; no background tracking invention.
- Status: PLANNED (not implemented).

### [ ] P7-D04 — Rider location subscription and recovery
- Work: Implement typed ordered stream, duplicate/out-of-order guards, reconnect/backoff and canonical read-after-reconnect; avoid relying on event alone as authority.
- Done when: Fake stream tests for reorder, missing events, disconnect, expired Trip and user change.
- Status: PLANNED (not implemented).

### [ ] P7-D05 — Security/hosted verification boundary
- Work: Test RLS and channel permission matrix for Rider, assigned Driver, unrelated users and blocked identities, with approved fixtures only.
- Done when: Recorded local results; hosted tests blocked until explicit permission and valid actor fixtures.
- Status: PLANNED (not implemented).

### [ ] P7-D06 — Integration handoff
- Work: Publish adapter APIs and synthetic events for the two UI owners; independently verify streams locally. Integrate accepted Trip only after A contract is merged.
- Done when: A reproducible fake end-to-end stream test and physical two-device plan; real device success not claimed early.
- Status: PLANNED (not implemented).

## Delivery checklist
- [ ] No other owner's files changed without agreement.
- [ ] Existing repositories/RPCs reused wherever safe; no unnecessary duplicate abstractions.
- [ ] Relevant local tests and analyzer/SQL checks passing with actual recorded evidence.
- [ ] No hosted activation, Stripe dispatch or financial state changes without separate authorization.
- [ ] Integration dependencies and P6-Rxx status recorded exactly, not assumed complete.
- [ ] Owner acceptance recorded separately after integration and physical-device checks.
