# RideX Project Adapter (Software Factory V1)

Stable RideX configuration for factory runs. References, not duplicates, authoritative sources.
Code, Git, authoritative docs, migrations, tests, and explicit human decisions remain authoritative.
Verified from repository evidence at bootstrap (branch `codex/phase-4f-evidence-hardening`, 2026-10-04).

## Project identity

- Jordan-focused ride-hailing graduation project: rider + driver demos, future administration scope.
- Native Flutter UI; Urban Aurora design system translated to Flutter (never HTML embedding, never WebView).
- Stack (per `AGENTS.md`, `pubspec.yaml`): Flutter 3.27.3 / Dart 3.6.1, Riverpod state ownership, GoRouter navigation + session redirects, Supabase Flutter backend, `intl`, `equatable`, `flutter_animate`, `flutter_svg`, `google_maps_flutter`, `geolocator`, `shared_preferences`.

## Authoritative documentation (read lazily, one doc per task)

- `AGENTS.md` — agent entry point and preservation rules.
- `docs/ai/ops/PROJECT_CONTEXT.md` — product, supported-vs-demo boundary, design references.
- `docs/ai/ops/ARCHITECTURE.md` — structure, state ownership, router, theme, tests.
- `docs/ai/ops/WORKFLOW.md` — branch rules and verification order.
- `docs/ai/ops/DECISIONS.md` — approved decisions (tokens, fonts, auth, routes, scope).
- `docs/ai/ops/CURRENT_STATUS.md` — current verified checkpoint (cache; verify against Git/code/tests).
- `Plan.md` — local source of truth for goals, decisions, change log (last sampled update 2026-09-20).
- `docs/ai/plans/` — phase plans (e.g. Rider V2, pre-merge corrections, Phase 4 design specs).
- `docs/ai/verification/` — phase verification evidence (e.g. `PHASE_4F_ARCHITECTURE_READINESS_2026-09-27.md`).

Rule: `CURRENT_STATUS.md` is a cache/index, not authority. On conflict between status files, Git history/status, code, migrations, and tests, record UNRESOLVED and trigger a human gate — never guess.

## Flutter architecture (see `ARCHITECTURE.md`)

- `lib/app/`: `app.dart`, `bootstrap.dart`, `config/`, `router/`, `theme/`.
- `lib/core/`: `models/`, `providers/`, `repositories/`, `services/`, `mocks/`, `utils/`, `widgets/`.
- `lib/features/`: presentation screens + feature-local widgets (`auth`, `booking`, `rider_home`, `trips`, `history`, `profile`, `notifications`, `settings`, `driver_*`).
- State owners: `sessionControllerProvider`, `bookingControllerProvider`, `currentLocationControllerProvider`, `placeSelectionControllerProvider`, `routeController` (session-local trusted route state), `activeTripControllerProvider`, `notificationsControllerProvider`, `currentProfileProvider`, session-local `driverOnlineProvider`, `DriverTrackingController` (explicit foreground sharing intent, canonical recovery, single GPS stream, ordered publication). Widgets read providers; they never duplicate durable booking/trip state.
- Router: `lib/app/router/app_router.dart` + `route_guards.dart` (public/private, rider/driver, blocked, driver-approval). No `StatefulShellRoute` in this phase. Bottom navigation uses `context.go()`.
- Provider boundaries (Phase 4): Geolocator/Google Maps types stay in services/widgets; `LocationPoint`/`RideLocation`, `RouteRequest`/`RouteResult`/`RouteState`, and Driver GPS/location contracts stay provider-neutral. Honored by `test/architecture_boundary_test.dart` — keep it green.
- Do not rewrite: `lib/main.dart`/bootstrap, Supabase repositories/services/migrations for visual work, core repository contracts without explicit approval, session guards/role behavior/sign-out semantics, curated `references/UI/`, driver screens during rider visual work.

## Supabase architecture

- Local config: `supabase/config.toml` (`project_id = "ridex"`, Postgres 17, realtime + edge runtime enabled, `functions.places` with `verify_jwt = true`).
- Migrations: `supabase/migrations/001`–`024` (auth/profiles/roles → Phase 3 security, booking/fare/matching, trips, payments/receipts, driver locations, RLS/RPC hardening, lifecycle, concurrency, exposure hardening, `023` rider-signup repair, `024` driver-location `recorded_at` guard). Database tests under `supabase/tests/database/`.
- Edge functions: `supabase/functions/` (notably `places`, authenticated; `route` operation over the same function). Required server secret name: `GOOGLE_MAPS_WEB_SERVICES_API_KEY` (value never read into repo or logs).
- Real backend behavior covers email/password auth, session restoration, profile role data, blocked state, driver approval state, sign-out. Booking/matching/trips/history/notifications/ratings and most profile/settings data remain mock, session-local, or presentation-only (see `PROJECT_CONTEXT.md`).

## Environment rules (verified in `lib/app/config/env_config.dart`, `lib/app/bootstrap.dart`)

- `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` arrive only via `--dart-define` (`String.fromEnvironment`); no `.env` files, no committed values, no values in docs/logs.
- URL must be `https` with valid host; placeholders (`your-project`, `example.supabase.co`, `change-me`, etc.) are rejected; incomplete pairs throw.
- Publishable key only. Forbidden in Flutter: `sb_secret_*` prefixes, any `service_role` token (including JWT `role == service_role`), non-`anon` legacy JWT roles. Only `sb_publishable_*` or legacy `anon`-role JWTs accepted.
- Missing config → deterministic mock repositories; present-but-invalid config → initialization-failure app (fail closed).
- Maps: `GOOGLE_MAPS_ENABLED` (`bool.fromEnvironment`, default false) gates map configuration; Android manifest declares coarse/fine foreground location only (no background-location permission — background checks are foreground-stream cancel/resume only).
- Release vs local: debug builds may log sanitized startup categories via `AppErrorReporter` (release no-op); raw errors never enter application state or UI (canary-tested).

## Test/build commands

```powershell
dart format lib test
flutter analyze
flutter test
```

- Focused tests while developing; full non-live suite at phase boundaries and before commits.
- Live Supabase tests (`test/live_supabase_auth_test.dart`, `test/live_supabase_role_state_test.dart`) require deliberate `--dart-define` credentials and otherwise skip (2 intentional skips). Never treat unconfigured live tests as product failure.
- Local Supabase verification (pgTAP): `npx supabase db reset --local`, `npx supabase test db` (isolated sequential execution is authoritative for fixture-heavy files; directory-wide runs can interfere via shared database). Stop the local stack afterwards. Docker engine required; its absence is recorded as a limitation, not a pass.
- Non-failing known warnings: `flutter_svg` unsupported `<filter>` elements.
- Dependency pins: `geolocator 13.0.4`, `google_maps_flutter 2.12.3` with federated-plugin overrides (see `pubspec.yaml`).

## Branch/Git rules (see `WORKFLOW.md`, `AGENTS.md`)

- Never implement directly on `main`. Rider V2 work belongs on `feature/omar/rider-ui-v2`; current Phase 4 work on the assigned `codex/...` branch. Never recreate, rename, delete, or switch away from an explicitly assigned branch.
- Verify active branch + clean worktree before editing. Preserve unrelated teammate changes; never reset, rebase, force-update, amend, or discard work without explicit approval.
- Commit focused, verified phases locally; update `CURRENT_STATUS.md` with the phase when practical; then stop. Never push, merge, or open a PR automatically — handoff reports exact verification, diff scope, deviations, and upstream state, then waits for approval.
- Never include: caches, `.artifact.json`, temp files, generated Open Design metadata, credentials, machine-specific paths, `supabase/.temp/` metadata. `git diff --check` must pass (except the intentional preserved `assets/fonts/OFL.txt` trailing space that protects the verified license hash).

## Migration/database rules

- Migrations are additive and append-only: `001`–`004` base + role boundary, `005`–`022` Phase 3 foundations + remediation, `023`–`024` repairs/guards.
- Never edit an already-applied migration. New problems get new migrations plus pgTAP coverage.
- Migration `004` deploys only after its local pgTAP suite passes; same discipline applies to later migrations.
- Least-privilege client grants; new `public`-schema entities are NOT auto-exposed. Admin/driver-promotion/approval paths go through guarded RPCs.
- Destructive/irreversible operations are prohibited without an explicit human gate: no remote `db push`/deploy, reset, linking, remote SQL/query, or service-role operations on hosted projects unless explicitly authorized. Prefer local reset + pgTAP + hosted dry-run (e.g. migration-list) evidence first.
- `driver_record_location` RPC-only publishing; per-driver row lock ordering; `024` rejects non-advancing `recorded_at`.

## Security constraints

- No secrets in repo, docs, logs, or test output. No service-role credentials in Flutter — ever.
- Public signup is Rider-only; role parsing is strict (`RideRole` rider/driver/admin); missing/malformed profiles fail closed (`profileError`); blocked users take priority; sign-in accepts no caller-selected role.
- Raw card data and sensitive payment credentials are never collected or stored. Stripe/Card provider work stays provider-independent; processor secrets and service-role keys remain server-side only; canonical payment results verified server-side; card authorization only after matching, capture only after trusted completion; duplicate/webhook-replay protection explicit (see `Plan.md` acceptance criteria).
- Payment, auth, matching-execution, Realtime sync, and Admin UI scope boundaries per phase plan — do not implement excluded scope opportunistically.
- Unsupported behavior stays explicit: disabled, Coming-soon, or isolated deterministic demo with clear messaging. No dead controls, no fabricated persistence or production integrations.

## External/manual actions

- Physical Android device (`adb`/`flutter devices` visible, authorized) for GPS, permission timing, Start/Stop, background/resume, canonical-write, reconnect checks.
- Hosted Supabase project with migrations `001`–`024`, local `--dart-define` publishable URL/key, approved non-blocked Driver with vehicle + availability, plus a separate Rider or pending/blocked account for rejection checks.
- Google route polyline, service-backed distance/duration, endpoint-change recalculation (Checkpoint 4C pattern).
- Two-device (Rider + Driver) environments for final Phase 4 approval (Checkpoint 4G task 4.38).
- Font gate (fulfilled by `f4e0371`): official Plus Jakarta Sans static files + `OFL.txt` bundled; if official files were missing, stop before network access and request approval.

## Project-specific human gates (in addition to factory defaults)

- Push, merge, PR creation, deployment, remote Supabase operations.
- Physical/live verification sign-off by the project owner (device + authenticated Supabase evidence).
- Phase approvals (Phase 4 final, Phase 5 entry) — Phase 5 must not begin until Phase 4 is finally approved.
- Any production-impact, destructive, credential, or scope-ambiguous decision.

## Project-specific Definition-of-Done additions

- `dart format` clean on intended paths; `flutter analyze` no issues; focused tests pass; full non-live `flutter test` passes with only the 2 intentional live skips (when shared behavior changes); `git diff --check` passes (modulo the intentional `OFL.txt` line).
- Architecture-boundary suite (`test/architecture_boundary_test.dart`) passes; provider-neutral contracts intact (no Google Maps/Geolocator/Supabase SDK leakage into models or feature UI).
- `CURRENT_STATUS.md` updated to name the completed checkpoint with evidence and the next objective (or that none remains); worktree clean; only the phase's files committed with a focused message.
- No HTML/WebView, no map SDK outside approved boundaries, no reference edits, no credentials, no machine paths, no `supabase/.temp/` metadata in the diff.
