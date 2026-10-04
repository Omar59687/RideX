# Efficiency Policy (V1.1)

## Progressive context

Context is fetched on demand, not broadcast by default.

- Every agent initially receives only the minimum sufficient context: objective, acceptance criteria, constraints, ownership, relevant interfaces, necessary architecture rules.
- Retrieve more files only when needed for the concrete task.
- Never send the entire repository or long execution history to every agent.
- Reviewers must not automatically receive implementer reasoning. Reviewers receive requirements, acceptance criteria, the actual diff, necessary surrounding code, and validation evidence — and independently assess correctness.

## Parallelism and ownership

- Parallelize only genuinely independent work.
- For meaningful parallel modifications: establish exclusive ownership first; prefer isolated worktrees or branches where the conflict risk justifies the overhead.
- For trivial or non-conflicting work: avoid isolation overhead.
- Shared central files and interfaces must have exactly one owner or a frozen contract. Do not allow multiple agents to blindly edit overlapping files.
- Integration decisions belong to the orchestrator. The integrator only executes the named combination.

## Execution topology

- Choose sequential, parallel, or mixed from the actual dependency graph. Mixed graphs (e.g. A → {B, C} → D) run sequential packages sequentially and independent branches in parallel.
- Sequential execution still delegates substantive work to implementers; only one implementer running at a time is a valid and common shape.
- Optimize expected TOTAL cost — dispatch cost plus the cost of role mixing, rework, and lost review independence — not just the number of subagent dispatches.

## Progress observability

- For long multi-package objectives, update active task/program state at meaningful boundaries: reconstruction/planning, current bounded package(s), implementation, validation, independent review, recovery, integration, human gate, terminal DoD.
- Coarse and accurate, never noisy: no per-command status churn, and never leave a program marked as early-stage after execution has materially progressed.

## Waste reduction

- Minimum sufficient agents, context, tests, and reviews for each task.
- No duplicated work across workstreams; the orchestrator deduplicates before spawning.
- No speculative work beyond acceptance criteria.
- Compress state at every boundary: keep `.factory/state/<task>.md` compact and factual.
