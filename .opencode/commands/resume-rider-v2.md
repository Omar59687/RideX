---
description: Resume exactly one RideX Rider V2 checkpoint with minimal context.
agent: build
---

Resume RideX Rider V2 work with a strict one-checkpoint boundary and minimal context.

1. Read `AGENTS.md`.
2. Read `docs/ai/ops/CURRENT_STATUS.md`.
3. Read only the relevant checkpoint section of `docs/ai/plans/RIDER_UI_V2_PLAN.md`.
4. Do not read other context documents unless these three files conflict with code. Read only application and test files directly required by the active checkpoint. Never scan the entire repository.
5. Do not spawn, delegate to, or use subagents.
6. Verify the branch is `feature/omar/rider-ui-v2` and the working tree is clean. Stop if either check fails.
7. Do not redo completed work. Implement exactly the single checkpoint named in `CURRENT_STATUS.md`.
8. Format intended Dart files, run focused checkpoint tests, and run `flutter analyze`. Run broader tests only if shared behavior changed or this is the final verification checkpoint.
9. Inspect status, diff, and staged files; commit only the implemented checkpoint locally.
10. Update `docs/ai/ops/CURRENT_STATUS.md` with the checkpoint commit, focused test results, limitations, and exact next checkpoint. Commit this documentation update locally.
11. Confirm the working tree is clean and stop. Do not begin the next checkpoint.

Never push, merge, switch branches, rewrite history, discard teammate work, or fabricate backend functionality.
