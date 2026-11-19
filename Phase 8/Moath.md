# Phase 8 — Moath (Developer 3)

**Owner:** Moath / معاذ  
**Division:** Driver canonical Trip completion and durable recovery  
**Workstream:** P8-C — Driver Completion & Trip Lifecycle  
**GitHub:** https://github.com/Omar59687/RideX/issues/153  
**First branch:** `feature/p8-c01-driver-completion-flow`  
**Status:** READY FOR INDEPENDENT LOCAL DEVELOPMENT; trusted hosted completion NOT accepted.

## Mission
Finish the Driver-side canonical Trip lifecycle and safe completion handoff, while the payment and receipt consequences remain **server-owned** by Yousuf. Develop against existing completion interfaces and fakes; do not wait for Card backend or another developer's unmerged branch.

## Start here
1. Inspect the already implemented `lib/core/repositories/driver_trip_completion_repository.dart`, `supabase_driver_trip_completion_repository.dart`, `lib/features/trips/application/driver_completion_coordinator.dart` and `driver_completion_recovery_coordinator.dart`.
2. Inspect the durable journal, Driver canonical runtime and screens before writing replacements. Reuse existing one-time command/journal and server-authorized `driver_transition_trip`; do not create a competing completion controller.
3. Preserve Cash-only behavior and current accepted Trip identity from Phase 7.
4. Local fakes and widget tests require no new SQL, Stripe activation or hosted fixtures.

## File ownership
**Moath alone:** Driver-only `lib/features/driver_flow/**` where lifecycle/Driver presentation lives, `lib/features/trips/presentation/screens/driver_*.dart`, specifically Driver completion application/coordinator and journal integration files, plus their focused tests.  
**Shared but read-only for Moath:** global providers/router, Trip/Payment models, Rider payment/History UI and Supabase migrations/functions. For any shared file or backend API, hand a precise request to Omar/Yousuf instead of editing it.

## Independent checkpoints

### [ ] P8-C01 — Current lifecycle and authority audit
- Trace accepted → driverArriving → driverArrived → inProgress → completed, using the actual enum/RPC conditions rather than inventing transitions.
- Verify role, approved Driver, assigned vehicle, pinned SDK session, exact Trip ID, version and active-trip eligibility at every action.
- Isolate Driver state UI from legacy `MockTrip` completion and fake paid/receipt presentation.
- **Done:** current source path diagram, fake Trip/transition port and security-state tests.

### [ ] P8-C02 — Canonical Driver completion interaction
- Safely enable the visual completion action only for authorized inProgress canonical Trip and an explicit reviewed nonproduction integration configuration.
- Reuse original backend command, expected version, durable idempotency/dispatch journal and no-replay rules; no direct Payment or Receipt writes.
- Pending/failed/UNKNOWN states block duplicate submit. A successful UI completion is shown only after canonical Trip reread.
- **Done:** focused controller and widget tests for eligibility, duplicate taps, stale versions, invalid transitions, unauthorized/blocked Driver and disconnected state.

### [ ] P8-C03 — Durable journal and UNKNOWN recovery
- Verify journal-before-command ordering and durability: write, flush/readback, then original dispatch once; protect old unknown attempts after process death.
- On app restart/reconnect, recover read-only by authorized canonical Trip status. Do not delete unknown evidence or automatically resubmit a command.
- Preserve all legacy R01/R02/R03 guardrails; add tests if an actual missing case exists rather than reimplementing them.
- **Done:** deterministic restart, write-failure, lost-response, duplicate-command, late-callback and A→B→A tests.

### [ ] P8-C04 — Driver active Trip restoration and presentation
- Reconstruct only the current Driver's verified nonterminal Trip after login/resume; reject stale IDs, another Driver's Trip, session changes and terminal records.
- Show explicit stale GPS/Realtime disconnected or recovery-required states without inventing progress.
- Clear subscribed state and pending commands when logged out or actor is no longer eligible.
- **Done:** fake-backed widget tests for restore, offline, canonical completion and invalid authority.

### [ ] P8-C05 — Completion handoff with Card/Cash boundaries
- Consume Yousuf's contract of what a trusted completed Trip means; do not call a Stripe capture yourself.
- Keep delayed Receipt, Cash settlement pending, failed Card capture and unknown payment state separate from the Trip completion result.
- Publish a small typed Driver completion event/result example for Omar/Sanad without requiring their implementation.
- **Done:** Cash/Card presentation tests that never show paid merely because Trip is complete.

### [ ] P8-C06 — Driver verification and integration package
- Run focused controller/widget/session/restart tests, format, analyzer on owned files and compile checks.
- Hand off the exact insertion point to Omar's integration branch; do not edit router/providers in your feature branch.
- **Done:** reviewable files, test logs and risk list; live device/hosted completion explicitly deferred.

## Cross-team boundaries
| Team member | Your dependency (only for final integration) |
|---|---|
| Yousuf | Trusted Trip/payment completion backend contract; never your SQL edits |
| Omar | Rider UX reflects canonical Trip and Payment states; he owns shared routing |
| Sanad | Historical/active-trip Reader; do not modify his History UI |

## Definition of Done
- [ ] No mock completion can become a trusted financial command.
- [ ] Journal prevents duplicate/replayed actions even with unknown outcomes.
- [ ] Driver role/session/version/Trip guards and recoverability tests passed.
- [ ] No Payment paid status or Receipt fabricated by Flutter.
- [ ] Handoff review and owner-approved PR/merge separated from live acceptance.

## Rules shared by all developers
- One checkpoint = one short-lived feature branch and separate worktree from latest origin/main. Preserve everyone else's files.
- Do not edit app/router/**, core/providers/repositories_providers.dart, core/repositories/trips_repository.dart, shared payment models, or another person's feature folder. Omar alone coordinates shared runtime wiring AFTER reviewed feature work.
- One backend owner: Yousuf. Changes to Supabase migrations, RPCs, RLS, payment Edge Functions and webhook contracts must go through him.
- Each checkpoint: report branch, commit, changed files, actual tests, evidence, known limits and the one interface needed from another developer.
- No PR, merge, hosted deployment, migration, credentials, Stripe dispatch, capture/refund, or financial data mutation without owner permission. Each PR needs an independent reviewer.
- Do not label mock tests, local pgTAP or CI success as hosted financial acceptance. Default Card execution remains disabled.
- Phase 7 source integration is merged, but hosted Realtime/Cron and live actor/device acceptance remain unproven. R06/X2 hosted migration discrepancy is tracked in issue #149. Do not bypass these gates.
