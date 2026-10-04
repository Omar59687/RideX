# RideX Project State (verified checkpoint)

Cache/index only — Git, code, authoritative docs, migrations, and tests remain authoritative.
Reconstructed 2026-10-04 from branch, history, `docs/ai/ops/CURRENT_STATUS.md`, `Plan.md` (sampled), code, migrations, and tests. No product files were modified to produce this file.

## Current branch

- Active branch: `codex/phase-4f-evidence-hardening` (tracks `origin/codex/phase-4f-evidence-hardening`).
- Worktree: clean at bootstrap (`git status --porcelain=v1 -b` showed only the branch line; `git diff --stat` empty).
- HEAD: `3127191` ("docs(ai): close Phase 4F operational follow-up"); parent `f1d34e8` ("test(phase4): harden architecture and database verification").

## Current verified phase/workstream

- Phase 4 driver-location track: Checkpoints 4D (approved 2026-09-20), 4E (approved 2026-09-24), 4F (approved 2026-09-27) are done. Checkpoint 4G automated gates completed 2026-09-27; final approval is NOT done.
- Therefore: Phase 4 is NOT finally approved and Phase 5 must NOT begin.

## Completed milestones (evidence in `CURRENT_STATUS.md`)

- Rider V2 implementation checkpoints (theme → components → auth → booking → lifecycle → history → profile → notifications → regression → fonts → reconciliation) plus pre-merge Phases 1–6: complete, merged through `300c8d5`-era mainline.
- Checkpoints 4A (maps/GPS foundations), 4B (place search/geocoding + routing-readiness guard), 4C (authenticated Edge routing): approved with automated + physical/live evidence.
- Checkpoint 4D slices (provider-neutral location contracts, GPS stream service, tracking controller, lifecycle, network recovery, Realtime reconnect wiring, Driver Home sharing card + corrections, final audit corrections): approved 2026-09-20 with owner-reported physical/live pass (GPS sharing, canonical sequence/timestamp growth, Stop, lifecycle + reconnect recovery, Rider 403/42501 rejection with no row).
- Checkpoint 4E tasks 4.24–4.30 (movement filtering, state-dependent cadence, offline-state shutdown/restart, resource policy, validation policy + migration `024`, typed failure states, `AppErrorReporter` containment): approved 2026-09-24.
- Checkpoint 4F tasks 4.31–4.35 (architecture boundaries, Smart City readiness evidence `docs/ai/verification/PHASE_4F_ARCHITECTURE_READINESS_2026-09-27.md`): approved 2026-09-27.
- Migration `024_guard_driver_location_recorded_at.sql`: verified and deployed 2026-09-27 (local reset through `024` passed; db tests `004`–`023` passed sequentially, 928 assertions; lint clean; hosted dry-run listed only `024`; remote status confirms local `024` == remote `024`).

## Last verified checkpoint (numbers as recorded, not re-run at bootstrap)

- 4G automated gates: focused regression command passed 175 tests (reused location/place/route/map/flow/GPS/network/reconnect/repository/provider/controller suites + 4 newly added contract/loading cases). No fabricated `BookingRequest` API; existing Rider/Driver flow tests stand in as integration-equivalent coverage.
- Latest full-suite figures on record: 235 non-live tests with 2 intentional live skips (task 4.30 boundary); `flutter analyze --no-pub` clean; formatting clean (185 files at 4.29/4.30 boundary); `git diff --check` clean modulo pre-existing generated-desktop line endings; known non-failing `flutter_svg` `<filter>` warnings.
- Migrations on disk: `001`–`024`. Database tests under `supabase/tests/database/`. No migration edits at bootstrap.

## Active/incomplete work

- Checkpoint 4G task 4.38: final approval evidence from two physical devices (or equivalent Rider/Driver environments). No new implementation — evidence collection + approval decision only.
- Final Phase 4 approval and Phase 5 entry: blocked on the above.

## Test/build evidence (this bootstrap ran no test/build commands)

- None generated here by design (bootstrap + read-only test only). Authoritative figures are those cited above from `CURRENT_STATUS.md` and the `f1d34e8` evidence-hardening commit.

## Unresolved blockers

- None in repository structure or configuration found at bootstrap. No conflicting status sources observed on sampled sections (`CURRENT_STATUS.md` branch line matches live `git` branch; recent log aligns with recorded 4F/4G history).

## Outstanding human gates

- 4G physical two-device verification (device access + hosted Supabase credentials + approved Driver and Rider/pending accounts) and owner sign-off.
- Any push/merge/PR, deployment, or remote Supabase operation.
- Phase 4 final approval and Phase 5 entry authorization.

## Known technical debt (relevant to continuation)

- Matching, Rider live-trip tracking, and continuous OS-background location remain later work (foreground-only location; no background permission declared).
- Booking/matching/trips/history/notifications/ratings/profile-extras remain mock/session-local/presentation-only on top of Phase 3 database foundations; card provider integration, secure execution, and Flutter wiring remain later-phase work.
- `npx supabase test db` directory-wide runs are not authoritative for fixture-heavy files (shared-database interference); isolated sequential execution is the recorded standard.
- Local pgTAP requires a working Docker engine; its absence must be recorded as a limitation, never a pass.

## Next documented objective (DO NOT execute yet)

- Checkpoint 4G task 4.38: collect the missing two-physical-device (Rider + Driver) evidence and obtain final Phase 4 approval. Recommended first real factory objective: orchestrator-led, read-only evidence plan for 4.38 (prerequisites, manual sequence per `Plan.md` §4D verification-attempt pattern, expected artifacts), with `0I + 0R` unless the plan itself justifies more.

## Human gate decision (deferred 4.38, provisional Phase 5)

- Recorded 2026-10-04: owner has no two-device environments; explicitly DEFERRED 4.38 and AUTHORIZED provisional Phase 5. This is not Phase 4 approval.
- Phase 4: PAUSED — NOT FINALLY APPROVED, task 4.38 OPEN. Procedure + analysis preserved in `.factory/state/phase-4g-task-4-38.md`; resume on owner notice without restarting analysis.
- Phase 5: PROVISIONAL WORK AUTHORIZED — only packages independent of 4.38 may proceed toward DoD. No milestone release/approval may rely on the missing device evidence. Blocker link: provisional packages ↔ 4.38 gate.

## Phase 5 dependency graph (PROVISIONAL)

Scope authority: `Plan.md` Phase 5 (ordered multi-stop ≤3 stops; route distance/duration, persistent Fare Quotes, route-based fixed fares), `PHASE_2_DOMAIN_ARCHITECTURE_AND_CONTRACTS.md` §§3.9/3.11/7-9/pricing, 4C routing design (stable `intermediatePoints` contract, 4C rejects non-empty), migration `007` (`pricing_configurations`, `fare_quotes`, `backend_*` RPCs are service_role-only per `007:1171-1177`; no Flutter fare integration exists).

- P5-1 multi-stop draft management: **DONE (DoD PASS, provisional).** `BookingController` + `maxStops=3`, add/remove/reorder/clear with reset semantics; 13 focused tests; review PASS (1 MINOR resolved); full suite 258 + 2 skips. Evidence: `.factory/state/phase-5-p5-1-stops-domain.md`. Incidental recovery: fixed pre-existing self-matching `credential_boundary_test.dart` (compiled regex unchanged, canary-proven).
- P5-2 routing via intermediates: **DONE (DoD PASS, provisional).** Edge `route` op 0–3 intermediates; repos send/validate; controller unchanged (verified); 8 new + extended route tests; Deno suite updated but not executed (runtime absent — recorded limitation, reviewer-weighted). Review PASS (1 MINOR accepted as mirrored fail-closed debt).
- P5-4 multi-stop UI: **DONE (DoD PASS, provisional).** `stops_section.dart` + destination/vehicle embeds; fare screen pre-existing stop display confirmed; 10 widget tests; test isolation from P5-2 verified. Review PASS (3 NOTEs recorded, no rework).
- Combined integration: route + booking suites 57/57; full suite 278 passed + 2 intentional live skips; analyze clean; `git diff --check` clean. Evidence: `.factory/state/phase-5-p5-2-p5-4-routing-ui.md`.
- P5-3 fare-quote integration: **DONE (DoD PASS, provisional).** Edge `fare` `quote` op (verify_jwt, sanitized, geometry omitted); integer-fils `FareQuote`/`FareBreakdown`; repository + fakes; fare-screen authoritative display with version/expiry/re-quote and relabeled demo fallback; lock reserved for Phase 7. Review PASS (3 LOWs recorded as debt). Full suite 295 + 2 skips; analyze clean. Evidence: `.factory/state/phase-5-p5-3-fare-quotes.md`.
- Phase 5 provisional coverage COMPLETE (P5-1…P5-4 DoD PASS): ordered multi-stop domain, routing with stops, stop UI, persistent route-based quotes. Remaining environment-gated verification (Deno suites, live fare/multi-stop routing, 4.38 devices) is tracked below — no further 4.38-independent implementation remains.
- P5-4 multi-stop UI (stop management surfaces, fare screen stops + breakdown): needs frozen P5-1 controller API; parallelizable with P5-2/P5-3. **A — IN PROGRESS in parallel with P5-2** (frozen contract: P5-1 controller API + `RouteRequest.fromDraft` stops mapping; stop-route display integration validated when P5-2 lands).
- Topology: P5-1 → {P5-2 → P5-3, P5-4} (MIXED). No Phase 5 package materially relies on unverified two-device GPS behavior (quotes derive from the verified route service + pricing config; device-level fare-vs-trip confirmation belongs to the Phase 10 roadmap): **B (blocked by 4.38) is empty.** C investigated and resolved: the fare-RPC grant boundary is now a bounded contract decision, not a human gate.

## Authoritative evidence references

- `docs/ai/ops/CURRENT_STATUS.md` (full checkpoint ledger through 4G automation + `024` deployment).
- `docs/ai/verification/PHASE_4F_ARCHITECTURE_READINESS_2026-09-27.md`, `PHASE_4AB_FINAL_VERIFICATION_2026-09-14.md`, `PHASE_4C_IMPLEMENTATION_VERIFICATION_2026-09-16.md`.
- `git log --oneline -15` (HEAD `3127191` … `e5a466c`); `supabase/migrations/` (`001`–`024`); `test/` (43 entries incl. `architecture_boundary_test`, `checkpoint_4g_contract_regression_test`, live-supabase skips); `lib/app/config/env_config.dart`; `lib/app/bootstrap.dart`.

## Factory version note (not a product checkpoint)

- Software Factory V1 bootstrapped 2026-10-04; V1.1 delegation hardening applied afterwards (topology-vs-delegation split, implementer-default for substantive work, direct-edit exception, recovery delegation, reviewer-count independence, progress observability). Policy-only change: no product checkpoint, verification figure, or milestone above was restated or altered to conform. RideX boundaries in `.factory/PROJECT.md` unchanged.
