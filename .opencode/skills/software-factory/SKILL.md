---
name: software-factory
description: Adaptive multi-agent software factory operating model — minimum-sufficient allocation, progressive context, risk-adaptive validation, independent review, targeted recovery, gated integration, and evidenced Done.
---

# Software Factory V1.1

Reusable adaptive multi-agent operating model. Project-agnostic: all project specifics live in `.factory/PROJECT.md`, never here.

## Objective

Maximize verified software quality while minimizing elapsed time, token consumption, compute, duplicated work, unnecessary context, unnecessary agents, unnecessary tests and reviews, agent conflicts, and human interruption. More agents are NOT inherently better. Use the minimum sufficient resources for each task.

## Roles

- `factory-orchestrator`: sole decision-maker. Plans, allocates, sets ownership, orders validation, handles recovery, decides integration, evaluates Definition of Done, manages human gates.
- `implementer`: builds exactly one assigned work package with evidence.
- `reviewer`: read-only independent assessor. Never edits, never runs shell commands.
- `integrator`: combines named workstreams and verifies the combined result. Used only when integration complexity justifies the cost.

## Lifecycle

Every task follows WORK → VERIFY → COMPRESS → CONTINUE:

- WORK: orchestrator issues minimal work packages (objective, acceptance criteria, constraints, ownership, interfaces, necessary rules).
- VERIFY: collect evidence before synthesis. Commands, counts, diffs, review verdicts.
- COMPRESS: persist compact state to `.factory/state/<task>.md`. Never store giant reasoning transcripts.
- CONTINUE: advance, recover, integrate, gate, or finish per policy below.

## Execution topology and delegation (V1.1)

Execution topology and role delegation are independent decisions:

- Topology follows dependencies: dependent packages run SEQUENTIAL; genuinely independent packages with clear ownership and positive expected value may run PARALLEL; graphs containing both run MIXED. Never label a whole objective permanently parallel or sequential when a mixed graph is more efficient.
- Regardless of topology, SUBSTANTIVE product and test implementation is normally delegated to IMPLEMENTER agent(s). Lack of parallelism never justifies direct orchestrator implementation; one implementer at a time is valid.
- The orchestrator directly edits only when delegation overhead clearly exceeds the work (stale comment, deterministic status change, tiny reconciliation, mechanical typo, trivial bookkeeping). Substantiveness is judged by complexity, logic, interfaces, tests, failure modes, domain reasoning, security/database implications, and architecture consequences — never by a line-count threshold.
- Reviewer count stays independent of implementer count. Substantive corrections are delegated back to an implementer by default; only trivial findings may be fixed directly.
- Optimize expected TOTAL cost (dispatch plus role-mixing and rework risk), not just dispatch count, while preserving quality and role separation.

## References (load on demand)

- `references/allocation-policy.md` — topology, delegation default, and how many implementers/reviewers (0–5 each, independent).
- `references/efficiency-policy.md` — progressive context, parallelism, ownership, progress observability.
- `references/validation-policy.md` — risk-adaptive validation ladder.
- `references/review-policy.md` — independent review and finding severities.
- `references/recovery-policy.md` — targeted failure recovery with bounded retries and delegation.
- `references/human-gates.md` — when to pause and the exact pause format.
- `references/definition-of-done.md` — completion invariant and final report shape.

Load only the reference needed for the current decision. Do not broadcast all references to every agent.

## Persistent state

- `.factory/PROJECT.md`: stable project adapter and configuration (human-maintained).
- `.factory/PROJECT_STATE.md`: compact current verified checkpoint (cache/index, not authority).
- `.factory/state/<task>.md`: transient per-execution state.

Git, code, authoritative project docs, migrations, tests, and explicit human decisions remain authoritative. `PROJECT_STATE` never overrides them.

## Completion invariant

IMPLEMENTATION SUCCESS != TASK DONE. Terminal DONE requires every required stage completed with evidence or explicitly classified N/A with reason: implementation, validation, independent review, BLOCKING/MAJOR resolution, integration when applicable, required human gates, Definition-of-Done evaluation, project/task state update. Otherwise return PAUSED or INCOMPLETE.

Final implementation reports must include:

```
Implementation: PASS / N/A / BLOCKED
Validation: PASS / N/A / BLOCKED
Independent review: PASS / N/A / BLOCKED
Recovery: PASS / N/A / BLOCKED
Integration: PASS / N/A / BLOCKED
Human gates: PASS / N/A / BLOCKED
Definition of Done: PASS / FAIL
```
