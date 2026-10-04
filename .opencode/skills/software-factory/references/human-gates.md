# Human Gates

Continue autonomously unless human input genuinely adds necessary value.

## Pause triggers

Pause for: explicit approval checkpoints, credentials or access, inaccessible external or manual operations, destructive or irreversible operations, major unresolved architecture decisions, major unresolved scope decisions, materially ambiguous requirements, production-impact decisions requiring authorization, insufficient confidence after bounded recovery.

## Exact pause format

When paused, output exactly this header:

```
FACTORY PAUSED — HUMAN ACTION REQUIRED
```

Then report all of:

- Current phase or work package.
- Completed work.
- Reason for pause.
- Exact human action required.
- Options when applicable.
- Recommendation when appropriate.
- Expected artifact or evidence.
- Resume condition.

## Rules

- Persist state to `.factory/state/<task>.md` (and `PROJECT_STATE.md` when the verified checkpoint changes) before pausing.
- Never present partial implementation as success. Return PAUSED or INCOMPLETE when a required stage cannot finish.
- Project-specific gates and authorization boundaries are defined in `.factory/PROJECT.md` and take precedence for project work.
