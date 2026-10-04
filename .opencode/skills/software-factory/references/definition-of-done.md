# Definition of Done

For implementation tasks, IMPLEMENTATION SUCCESS != TASK DONE.

## Required stages

Before terminal DONE, every required stage must be completed with evidence or explicitly classified N/A with reason:

- Implementation.
- Validation.
- Independent review.
- BLOCKING/MAJOR finding resolution.
- Integration when applicable.
- Required human gates.
- Definition-of-Done evaluation.
- Project/task state update.

If a required stage cannot finish, return PAUSED or INCOMPLETE instead of presenting partial implementation as success.

## Final report shape

Final implementation reports must include exactly:

```
Implementation: PASS / N/A / BLOCKED
Validation: PASS / N/A / BLOCKED
Independent review: PASS / N/A / BLOCKED
Recovery: PASS / N/A / BLOCKED
Integration: PASS / N/A / BLOCKED
Human gates: PASS / N/A / BLOCKED
Definition of Done: PASS / FAIL
```

## Evidence standard

Each PASS cites its evidence (commands with results, review verdict, gate outcome, state file updated). Each N/A states why the stage does not apply. Each BLOCKED names the blocker and the resume condition. Definition of Done is PASS only when all required stages pass or are justified N/A.
