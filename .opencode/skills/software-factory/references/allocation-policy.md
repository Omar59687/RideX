# Allocation Policy (V1.1)

Ceilings, NOT targets: up to 5 implementers and up to 5 reviewers. Counts are independent.

## Topology first, delegation always

Execution topology and role delegation are two independent decisions:

1. Determine dependencies across the bounded packages.
2. Dependent packages → SEQUENTIAL. Genuinely independent packages with clear ownership and positive expected parallel value → PARALLEL. Graphs containing both → MIXED.
3. Regardless of topology, SUBSTANTIVE product and test implementation is normally delegated to IMPLEMENTER agent(s). Lack of parallelism is NOT justification for direct orchestrator implementation — a single implementer executing packages one after another is completely valid.

## Valid allocations

Any `NI + NR` combination within ceilings is valid, including:

- `0I + 0R`: orchestrator-only work (read-only reporting, planning, state reconstruction, trivially safe decisions).
- `0I + 1R`: audit or review of existing work with no implementation.
- `1I + 1R`: default for most scoped tasks — one owner, one independent check.
- `NI + MR` (e.g. `2I + 1R`, `1I + 2R`, `3I + 2R`): scaled only with justification, up to `5I + 5R`.

Never spawn an agent merely because capacity exists.

## Allocation inputs

Consider jointly: complexity, risk, dependencies, affected modules, ownership boundaries, parallelizability, expected conflicts, validation burden, uncertainty, expected information gain, token and time cost.

## Guidance

- Prefer `0I + 0R` when the orchestrator can answer directly from evidence with no product change and no meaningful information gain from another agent.
- Prefer `0I + 1R` when an independent assessment adds value but no code must change.
- Prefer `1I + 1R` when exactly one ownership boundary is touched — including fully sequential work with no parallelism.
- Add a second implementer only for genuinely independent parallel work with exclusive ownership and no shared central files.
- Add reviewers for high risk, security or data boundaries, large diffs, or high uncertainty — not by default per implementer. Three implementers does NOT imply three reviewers.
- The orchestrator directly edits only when delegation overhead clearly exceeds the work (one stale comment, deterministic status change, tiny reconciliation, mechanical typo, trivial bookkeeping). Single-file or single-module scope alone never justifies orchestrator implementation of substantive work; when uncertain, prefer delegation.
- Zero integrators is valid. Add an integrator only when combining workstreams has non-trivial interface or dependency risk.
- Record the chosen allocation and its one-line justification in `.factory/state/<task>.md`.
