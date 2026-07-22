# RideX Agent Guide

RideX is a Flutter ride-hailing graduation project for Jordan. It contains rider, driver, and future administration experiences.

## Stack

- Flutter 3.27.3 and Dart 3.6.1
- Riverpod for state ownership
- GoRouter for navigation and session redirects
- Supabase for real email/password authentication and profile/session data
- Feature-oriented presentation folders with shared models, providers, repositories, services, themes, and widgets

Actual code is the source of truth. If these documents conflict with code, inspect the smallest relevant code area and update the documentation.

## Read Context Lazily

Start with only the document relevant to the task:

- Rider V2 plan: `docs/ai/plans/RIDER_UI_V2_PLAN.md`
- Project context: `docs/ai/ops/PROJECT_CONTEXT.md`
- Architecture: `docs/ai/ops/ARCHITECTURE.md`
- Git and verification: `docs/ai/ops/WORKFLOW.md`
- Approved decisions: `docs/ai/ops/DECISIONS.md`
- Current checkpoint: `docs/ai/ops/CURRENT_STATUS.md`

For Rider V2 work, read `CURRENT_STATUS.md` before implementation. Do not scan the entire repository unless these documents conflict with the actual code or the task crosses undocumented boundaries.

## Collaboration And Git

- Never implement directly on `main`.
- Rider V2 work belongs on `feature/omar/rider-ui-v2`.
- Verify the active branch and a clean worktree before editing.
- Never recreate, rename, delete, or switch away from an explicitly assigned branch.
- Preserve unrelated teammate changes. Do not reset, rebase, force-update, amend, or discard work without explicit approval.
- Commit focused, verified phases locally.
- Never push, merge, or open a Pull Request automatically.

## Preservation Rules

- Preserve Riverpod, GoRouter, Supabase, repositories, controllers, providers, models, services, redirects, session restoration, and sign-out behavior.
- UI consumes existing providers rather than duplicating booking or trip state.
- Do not fabricate backend integrations. Use disabled controls, clear explanations, or isolated deterministic demo behavior.
- Do not rewrite Supabase migrations or backend contracts for visual work.
- Driver screens receive regression testing during Rider V2 work, not a visual redesign.
- Do not edit curated references unless explicitly requested.

## RideX V2 References

Urban Aurora sources are under `references/UI/`. The structural token authority is `references/UI/tokens/ridex-v2-tokens.json`. Translate references into native Flutter; never embed the HTML or use a WebView.

## Commands

```powershell
dart format lib test
flutter analyze
flutter test
```

Run focused tests while developing, then all non-live tests before a phase commit. Live Supabase tests require intentional environment configuration and otherwise skip.

Before each commit, inspect `git status`, `git diff`, and staged files. Never include caches, `.artifact.json`, temporary files, generated Open Design metadata, credentials, or machine-specific paths.
