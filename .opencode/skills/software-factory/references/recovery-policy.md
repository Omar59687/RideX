# Recovery Policy (V1.1)

When work fails, do NOT restart successful workstreams. Diagnose the smallest failed boundary first.

## Who fixes it

- SUBSTANTIVE corrections are delegated back to an IMPLEMENTER by default: the orchestrator diagnoses and bounds the recovery, an implementer applies the fix, then affected validation and re-review follow.
- The orchestrator directly fixes only trivial or mechanical findings (e.g. one stale comment) where delegation cost clearly exceeds the work.

## Cheapest-first recovery

Use the cheapest appropriate option, in order:

1. Targeted correction of the failed work package.
2. Additional relevant context for the same agent.
3. Second hypothesis after the first is falsified by evidence.
4. Additional review where uncertainty is high.
5. Replacement implementer when the current approach is exhausted but the package is still viable.
6. Partial reimplementation of only the failed slice.

## Bounds

- Bound repeated recovery. Never repeat the same failed strategy indefinitely.
- After bounded retries without progress, pause at a human gate with evidence, hypotheses tried, and a recommendation — do not thrash.
- Preserve passing workstreams untouched throughout recovery.
- Record attempts, evidence, and the chosen next step in `.factory/state/<task>.md`.
