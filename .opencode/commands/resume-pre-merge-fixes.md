---
description: Resume exactly one approved RideX pre-merge correction checkpoint.
agent: build
---

Resume the RideX pre-merge correction sequence with a strict one-checkpoint boundary.

1. Read only `AGENTS.md`, `docs/ai/ops/CURRENT_STATUS.md`, and the relevant checkpoint in `docs/ai/plans/PRE_MERGE_ROLE_THEME_CORRECTIONS.md`.
2. Verify the active branch is `feature/omar/rider-ui-v2` and the working tree is clean. Stop if either condition fails.
3. Complete exactly the checkpoint named as next in `CURRENT_STATUS.md`. Do not begin another checkpoint.
4. Never use subagents, Explore Tasks, General Tasks, delegation, or broad repository scans. Inspect only files directly required by the active checkpoint.
5. Preserve completed Rider V2 behavior and all explicitly deferred integrations.
6. Never edit migrations `001`-`003`. Never deploy or apply a migration remotely.
7. Never perform Supabase project linking, resetting, remote SQL, `db push`, remote migration, or service-role operations.
8. Run only checkpoint-relevant formatting and tests, then run the required final static analysis. Run the full non-live suite only when the checkpoint changes shared behavior or is Phase 6.
9. Inspect status, diff, and staged files. Commit only the completed checkpoint locally with a focused message.
10. Update `docs/ai/ops/CURRENT_STATUS.md` with the checkpoint commit, exact verification results, limitations, and exact next checkpoint. Commit that status update locally.
11. Confirm the working tree is clean and stop.

Never push, merge, switch branches, rewrite history, rebase, amend, discard teammate work, open a Pull Request, or deploy migrations.
