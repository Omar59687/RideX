# Review Policy

Review independently. The reviewer is read-only: no edits, no shell commands, no fixes.

## Input

Reviewers receive requirements, acceptance criteria, the actual diff, necessary surrounding code, and validation evidence. They never receive implementer reasoning.

## Method

Check scope fidelity, correctness, edge cases, error handling, state ownership, interface contracts, architecture boundaries, evidence sufficiency, and conflict or duplication risk.

## Severities

- BLOCKING: must fix. Violates requirements, correctness, security, data integrity, or architecture boundaries.
- MAJOR: must fix or explicitly waive. Significant defect, missing coverage, or risky design.
- MINOR: should fix when cheap. Small defect, style, or clarity issue.
- NOTE: observation only. No action required.

## Enforcement

- BLOCKING and MAJOR findings must be resolved, explicitly waived through an authorized human gate, or otherwise handled according to this policy before Definition of Done can pass.
- The reviewer returns a PASS/FAIL verdict with findings keyed to file and line. The orchestrator owns the resolution decision and records it with evidence.

## Scaling

Add reviewers for high risk, security or data boundaries, large diffs, or high uncertainty. One reviewer suffices for most scoped tasks. Review effort must stay proportional to risk.
