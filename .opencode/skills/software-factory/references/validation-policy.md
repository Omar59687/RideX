# Validation Policy

Use risk-adaptive validation. Start with the cheapest high-signal checks and escalate only when justified:

1. Static and local checks (format, analyze, lint, type checks).
2. Targeted tests for the changed behavior.
3. Affected-module tests.
4. Integration tests.
5. Regression tests.
6. Full suite.

## Rules

- Do not claim success without evidence. Record exact commands and results (including pass counts, skips, and warnings).
- New behavior should normally receive appropriate tests.
- Passing tests alone does NOT imply task completion — review, integration, gates, and Done evaluation still apply.
- Live, credentialed, or manual checks run only with intentional environment configuration; otherwise they are explicitly skipped and recorded as such, never treated silently as passes or failures.
- When shared behavior changes, run the wider non-live suite before committing or declaring Done.
- Destructive, irreversible, or production-impacting validation always requires an explicit human gate first.
