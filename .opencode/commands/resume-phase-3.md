# Resume Phase 3

Resume the RideX Phase 3 work on the assigned branch.

## Required reading

1. Verify the active branch is exactly `codex/phase-3-supabase-foundation` and the working tree is clean. Do not switch branches. Stop if unrelated changes exist.
2. Read `AGENTS.md`.
3. Read `docs/ai/ops/PHASE_3_STATUS.md`.
4. Read only the current checkpoint section of `docs/ai/plans/PHASE_3_SUPABASE_IMPLEMENTATION_PLAN.md`.
5. Read only the migration and pgTAP test files directly related to the current checkpoint.
6. Read the smallest predecessor migration or test file required to resolve a concrete conflict.

Do not reread the complete Phase 2 document unless `docs/ai/ops/PHASE_3_STATUS.md` records a specific contradiction requiring it.

## Execution rules

- Complete exactly one Phase 3 checkpoint in the session.
- Preserve migrations `001` through `004`, the approved Phase 2 contracts, legacy Driver availability fields, and unrelated teammate changes.
- Run focused local verification for the current checkpoint.
- Update `docs/ai/ops/PHASE_3_STATUS.md` separately after the checkpoint and verification are complete.
- Stop without automatically beginning the next checkpoint.
- Do not push, merge, commit, deploy, link, reset a remote database, or modify remote Supabase without explicit approval.
- Do not implement excluded Flutter, GPS, mapping, Stripe, matching-execution, Realtime, or Admin UI work in Phase 3.
