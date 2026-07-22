# Git And Verification Workflow

## Branch Rules

- Never implement directly on `main`.
- Rider V2 work uses `feature/omar/rider-ui-v2`.
- Verify branch and clean status before editing.
- Never push, merge, switch branches, force-update, reset, rebase, amend, or discard changes automatically.
- Preserve unrelated teammate work and stop if concurrent changes conflict with the active phase.

## Updating From Main

At a clean checkpoint:

1. Run `git fetch --prune origin`.
2. Inspect `git rev-list --left-right --count origin/main...HEAD` and recent logs.
3. If the feature branch has no unique work and can fast-forward, use fast-forward-only behavior.
4. If unique feature commits exist, do not rewrite or merge automatically. Report upstream movement and agree on integration strategy.
5. Never switch to `main` merely to inspect it.

## One-Phase Cycle

1. Read `CURRENT_STATUS.md` and the relevant plan section.
2. Inspect only files involved in the next phase.
3. Implement exactly one coherent phase.
4. Format intended Dart files.
5. Run focused tests.
6. Run `flutter analyze` at the phase boundary.
7. Run all non-live tests when shared behavior changes.
8. Inspect `git status`, `git diff`, and staged files.
9. Commit only that phase with a focused message.
10. Update `CURRENT_STATUS.md`, commit the status update with the phase when practical, and stop.

Never commit caches, `.artifact.json`, temporary files, credentials, generated Open Design metadata, or machine-specific paths.

## Verification Order

```powershell
dart format <intended Dart paths>
flutter test <focused test paths>
flutter analyze
flutter test
```

Live Supabase tests require deliberate credentials and otherwise skip. Do not treat an unconfigured live integration as a product failure.

## Clean Checkpoint And PR Handoff

A checkpoint is complete when intended changes are committed, the worktree is clean, analysis passes, required tests pass, and `CURRENT_STATUS.md` names the next phase. Do not start that next phase automatically.

For Pull Request handoff, inspect all feature commits and the complete `origin/main...HEAD` diff, report tests and limitations, then leave push and PR creation to explicit user approval.
