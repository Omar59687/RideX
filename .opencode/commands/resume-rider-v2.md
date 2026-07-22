---
description: Resume exactly one remaining RideX Rider V2 implementation phase.
agent: build
---

Resume RideX Rider V2 work with a strict one-phase boundary.

1. Read `AGENTS.md`.
2. Read `docs/ai/ops/CURRENT_STATUS.md`.
3. Read `docs/ai/plans/RIDER_UI_V2_PLAN.md`.
4. Load only the relevant sections of `docs/ai/ops/ARCHITECTURE.md` and `docs/ai/ops/DECISIONS.md` for the named next phase.
5. Verify the branch is `feature/omar/rider-ui-v2` and the working tree is clean. Stop if either check fails.
6. Do not redo completed phases. Implement exactly the single next phase recorded in `CURRENT_STATUS.md`.
7. Format intended Dart files, run focused tests, run `flutter analyze`, and run broader non-live tests when shared behavior changes.
8. Inspect status, diff, and staged files; commit the phase locally with a focused message.
9. Update `docs/ai/ops/CURRENT_STATUS.md` with the commit, test results, limitations, and next phase. Commit that update with the phase when practical.
10. Confirm a clean checkpoint and stop. Do not begin another phase.

Never push, merge, switch branches, rewrite history, discard teammate work, or fabricate backend functionality.
