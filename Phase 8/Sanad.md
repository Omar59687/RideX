# Phase 8 — Sanad (Developer 4)

**Owner:** Sanad / سند  
**Division:** Persistent Rider Trip history and active Trip restoration  
**Workstream:** P8-D — Trip History & Restoration  
**GitHub:** https://github.com/Omar59687/RideX/issues/154  
**First branch:** `feature/p8-d01-persistent-trip-read-contract`  
**Status:** READY FOR INDEPENDENT LOCAL DEVELOPMENT; hosted history acceptance NOT asserted.

## Mission
Replace the Rider-facing mock/history assumptions with a **read-only, authenticated, canonical Trip** history and safe active-trip restoration. Start with a feature-local typed repository and fake data; no waiting for Yousuf's SQL deployment, Omar's payment flow, or Moath's Driver completion.

## Start here
1. Inspect `lib/features/history/presentation/screens/trip_history_screen.dart`: it currently reads `List<MockTrip>` through `tripsRepositoryProvider`. Do not silently reuse mock IDs in configured Supabase mode.
2. Inspect existing canonical Rider Trip/detail readers and RLS patterns, `lib/features/history/presentation/providers/rider_payment_providers.dart` and `rider_canonical_trip_detail_providers.dart`.
3. Define feature-local read DTOs/ports and a fake with genuine-looking but **synthetic** test identities. Do not introduce privileged client reads or write RPCs.
4. Plan central `tripsRepositoryProvider`/router wiring as a request to Omar's separate final integration workstream.

## File ownership
**Sanad alone:** `lib/features/history/**`, feature-specific Rider history/active-trip read-only adapters and fake ports/tests (prefer a new dedicated feature-local directory), and Rider history/detail widgets.  
**Do not edit:** `lib/features/booking/**` (Omar), Driver UI/completion (Moath), Supabase migrations/functions (Yousuf), or shared global providers/router until Omar's final integration stage.

## Independent checkpoints

### [ ] P8-D01 — Canonical Trip history read contract
- Reuse existing Trip/detail authorization patterns and identify actual current backend read contracts; request additive read-only improvements from Yousuf only if truly missing.
- Specify owned Trip ID, Rider ID, lifecycle status, timestamps, pickup/destination, locked fare amount/currency, linked Payment ID if supplied and Receipt existence only if independently verified.
- Ensure stable deterministic page ordering, pagination/cursor, terminal vs nonterminal status, and sanitized errors.
- **Done:** feature-local repository interface and fake responses, no backend integration prerequisite.

### [ ] P8-D02 — Persistent Rider history list
- Build loading/empty/error/retry and completed/cancelled filters with real canonical Trip records for configured backend mode.
- No automatic fallback to demo records after a real-backend error. Keep mock demo path explicitly separate.
- Support paging/deduplication and stable timestamps; avoid unbounded client reads and duplicate visible Trips.
- **Done:** widget tests for zero/many records, pagination, filtering, offline/retry, sorting and same-Rider ownership.

### [ ] P8-D03 — Exact Trip details and payment/receipt separation
- Rider Trip Detail must reread the exact authorized Trip; show participant-safe Driver/vehicle and location context only when legitimately available.
- Use Yousuf's typed read contract for Payment and Receipt once reviewed; no fabricated Payment ID from Booking ID or assumption that Trip completed means cash paid/card captured.
- Handle missing/late receipt, Card UNKNOWN/pending and cancellation as honest states.
- **Done:** ownership/status/receipt separation widget tests, including blocked and foreign Rider.

### [ ] P8-D04 — Rider active Trip restoration
- On login, restart, resume or reconnect, locate only the current authenticated Rider's canonical nonterminal Trip and verify current backend/SDK session across awaited reads.
- Do not navigate to a stale/foreign Trip, don't restore terminal trips as active, don't retain previous Rider's details after logout or user switch.
- When multiple or uncertain active records appear, fail closed and show a recoverable error instead of selecting an arbitrary Trip.
- **Done:** deterministic initial/reconnect/session A→B→A/out-of-order/terminal tests.

### [ ] P8-D05 — History resilience and privacy
- Cover stale pagination responses, duplicate rows, missing summary fields, canceled/failed vs completed, unsupported payment/receipt, backend unavailability and partial data.
- Test pagination and active restoration together: never let a history row override a fresher active canonical Trip read.
- Sanitize logs/UX; no leaked other-Rider fields, secrets, internal SQL errors or financial claim.
- **Done:** security/privacy regression suite and analyzer/format validation on owned files.

### [ ] P8-D06 — History integration handoff
- Supply a stable adapter, fake/contract suite and one documented injection point to Omar.
- Keep `lib/core/repositories/trips_repository.dart` and central router/provider files untouched until integration owner handles the final wiring.
- **Done:** reviewable branch and tests; user-visible history only claimed hosted-verified after approved actor-level acceptance.

## Cross-team boundaries
| Team member | Your interaction |
|---|---|
| Yousuf | Request paginated Rider-owned Trip and exact payment/receipt reads, but do not write SQL |
| Omar | He owns Rider checkout and central router/provider integration |
| Moath | Read canonical Trip completed status, never depend on Driver UI state |
| Your own feature | Read-only, owner-scoped, no financial mutation |

## Definition of Done
- [ ] No configured-mode MockTrip leakage into canonical history.
- [ ] Read-only history and active restore pass ownership/session/privacy tests.
- [ ] Payment/receipt claims appear only from separately verified backend records.
- [ ] Full widget and focused analyzer evidence attached to checkpoint.
- [ ] No unauthorized shared-file edit or hosted financial acceptance claimed.

## Rules shared by all developers
- One checkpoint = one short-lived feature branch and separate worktree from latest origin/main. Preserve everyone else's files.
- Do not edit app/router/**, core/providers/repositories_providers.dart, core/repositories/trips_repository.dart, shared payment models, or another person's feature folder. Omar alone coordinates shared runtime wiring AFTER reviewed feature work.
- One backend owner: Yousuf. Changes to Supabase migrations, RPCs, RLS, payment Edge Functions and webhook contracts must go through him.
- Each checkpoint: report branch, commit, changed files, actual tests, evidence, known limits and the one interface needed from another developer.
- No PR, merge, hosted deployment, migration, credentials, Stripe dispatch, capture/refund, or financial data mutation without owner permission. Each PR needs an independent reviewer.
- Do not label mock tests, local pgTAP or CI success as hosted financial acceptance. Default Card execution remains disabled.
- Phase 7 source integration is merged, but hosted Realtime/Cron and live actor/device acceptance remain unproven. R06/X2 hosted migration discrepancy is tracked in issue #149. Do not bypass these gates.
