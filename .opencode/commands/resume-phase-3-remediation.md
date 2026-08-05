# Resume Phase 3 Contract Remediation

Resume exactly one remediation checkpoint with minimal context.

## Required reading

1. Verify branch `codex/phase-3-contract-remediation` and a clean worktree. Stop
   on any other branch or unrelated change; do not switch or discard work.
2. Read `AGENTS.md`.
3. Read `docs/ai/ops/PHASE_3_REMEDIATION_STATUS.md`.
4. Read only the current checkpoint in
   `docs/ai/plans/PHASE_3_CONTRACT_REMEDIATION_IMPLEMENTATION_PLAN.md`.
5. Read only the predecessor migrations/functions/tests directly required by
   that checkpoint.

Do not reread the whole repository or complete Phase 2 contract unless the
status file records a concrete contradiction.

## Rules

- Complete one checkpoint only, then stop.
- Never edit, rename, delete, reorder, or replace migrations/tests `001–013`.
- Add corrections only as migration/test `014+`.
- Run focused verification while developing and the complete local database
  suite once before the implementation commit.
- Commit implementation and status documentation separately.
- Stop local Supabase and confirm a clean worktree.
- Do not push, merge, open a Pull Request, deploy, link, reset a remote database,
  add credentials, or begin Phase 4.
