# Phase 8 — Omar (Developer 2)

**Owner:** Omar / عمر  
**Division:** Rider Card payment experience and final integration coordination  
**Workstream:** P8-B — Rider Payment UI  
**GitHub:** https://github.com/Omar59687/RideX/issues/152  
**First branch:** `feature/p8-b01-rider-payment-state`  
**Status:** READY FOR INDEPENDENT LOCAL DEVELOPMENT; Card execution NOT activated.

## Mission
Build a secure, accessible Rider Card UI from typed local fakes while Yousuf works independently on the server. Existing Cash flow must not regress. Client callbacks are advisory; only an authenticated canonical backend re-read may verify Payment status.

## Start here
1. Inspect `lib/features/booking/**`, `lib/core/repositories/card_payment_repository.dart`, `canonical_payment_repository.dart` and existing Cash-only feature flags. Read, but do not edit, Sanad's History or Moath's Driver files.
2. Implement a feature-local fake checkout reader/adapter. Do not invent backend RPC names; sync a small typed contract with Yousuf's issue #151 as a coordination checkpoint only.
3. Keep Card initiation disabled unless a trusted accepted Trip exists and the separately approved integration gate is enabled.
4. Hold central router and global-provider wiring for one final integration-only branch after reviewed independent work.

## File ownership
**Omar alone:** Rider payment/checkout presentation under `lib/features/booking/**`, optionally a new `lib/features/rider_payments/**` folder, feature-local controllers/providers/fakes and focused tests.  
**Integration-only later:** `lib/app/router/**` and `lib/core/providers/repositories_providers.dart`, after each stream has supplied an approved handoff.  
**Do not edit during feature work:** Supabase/migrations/functions, `lib/features/history/**`, Driver completion files or shared payment domain contracts.

## Independent checkpoints

### [ ] P8-B01 — Rider checkout and state model
- Map canonical Fare lock → confirmed Booking → matched Driver → accepted Trip; Card authorization may begin only after trusted matching.
- Define notConfigured, loading, actionRequired, pending/UNKNOWN, authorized, cancelled, failed, paymentReadError and retryAllowed UI states.
- Preserve the Cash route and disabled Card behavior with regression tests.
- **Done:** widget/controller tests against deterministic fake, with no backend needed.

### [ ] P8-B02 — Safe provider-facing checkout seam
- Provider-neutral hosted checkout / approved PaymentSheet launching adapter. No card-number/CVV collection, client secret storage or Stripe secret in Flutter.
- Handle redirect, app return, cancel, resume and timeouts as advisory; re-read Payment canonically for the same Rider/Trip/session.
- **Done:** fake integration tests for missing provider, cancelled return, forged/stale return and lost response; no fabricated authorization.

### [ ] P8-B03 — Payment and receipt UX
- Show verified Payment state separately from Trip status and independently verified Receipt availability.
- Build accessible loading/error/unknown/refund status and support safe reconciliation instead of blind retry.
- Do not perform capture, void, refund or direct table updates from the UI.
- **Done:** widget tests for every state, missing Receipt, foreign Payment and Cash regression.

### [ ] P8-B04 — Session, lifecycle and duplicate-action hardening
- Protect double-tap, repeated redirect, stale callback, account switch A→B→A, logout, background/resume, stale Trip version and cancellation.
- Unknown outcome must never be displayed as paid or retried as a fresh financial command.
- **Done:** focused deterministic regression tests and no new analyzer warnings in owned files.

### [ ] P8-B05 — Reviewed backend contract adapter
- Once Yousuf's contract is approved, add a feature-level adapter for authenticated canonical reads/requests behind default-OFF nonproduction approval.
- Never make a teammate's unmerged branch a development prerequisite; use interface fakes until a source contract is merged.
- **Done:** focused contract tests, build passes and any hosted/physical steps explicitly deferred.

### [ ] P8-B06 — Final integration coordination
- Collect per-person checkpoint SHA, changed paths, test evidence and contract status.
- Use a **separate** integration branch from latest main to wire central router/providers, resolving any actual conflict. Integrate only approved, independently reviewed branches.
- Run full Flutter + Deno + isolated SQL + Android CI at the final integrated SHA.
- **Done:** read/write boundaries intact and source interactions verified; no premature hosted or payment acceptance.

## Cross-stream boundaries
| Team member | Your interaction |
|---|---|
| Yousuf | Consume typed contract and canonical backend response, never edit SQL/Edge |
| Moath | React to a verified completed Trip, never infer paid from Driver UI |
| Sanad | History and receipt cards belong to Sanad; you own checkout only |
| Shared router/providers | Omar edits only at integration checkpoint, no concurrent writers |

## Definition of Done
- [ ] Cash behavior and Card-disabled gate preserved.
- [ ] Payment UI works fully with fakes and backend read-back semantics.
- [ ] No raw card info, privileged key or client-owned payment status.
- [ ] Auth/logout/retry/UNKNOWN tests passed.
- [ ] Independent review and owner approval obtained for each PR/merge.

## Rules shared by all developers
- One checkpoint = one short-lived feature branch and separate worktree from latest origin/main. Preserve everyone else's files.
- Do not edit app/router/**, core/providers/repositories_providers.dart, core/repositories/trips_repository.dart, shared payment models, or another person's feature folder. Omar alone coordinates shared runtime wiring AFTER reviewed feature work.
- One backend owner: Yousuf. Changes to Supabase migrations, RPCs, RLS, payment Edge Functions and webhook contracts must go through him.
- Each checkpoint: report branch, commit, changed files, actual tests, evidence, known limits and the one interface needed from another developer.
- No PR, merge, hosted deployment, migration, credentials, Stripe dispatch, capture/refund, or financial data mutation without owner permission. Each PR needs an independent reviewer.
- Do not label mock tests, local pgTAP or CI success as hosted financial acceptance. Default Card execution remains disabled.
- Phase 7 source integration is merged, but hosted Realtime/Cron and live actor/device acceptance remain unproven. R06/X2 hosted migration discrepancy is tracked in issue #149. Do not bypass these gates.


## Implementation-first progress — 19 November 2026

Owner has requested that the team finish implementation before running the combined Phase 8 verification. Test deferral is not test acceptance.

| Task | Implemented source | Pending for true completion |
| --- | --- | --- |
| B01 | Typed Rider Card Trip/payment states, session-bound canonical read seam and fake tests | Execute focused tests; integration verification |
| B02 | Provider-neutral launch interface, default-disabled implementation and callback reconciliation | Reviewed backend/provider gate; executable provider adapter requires owner approval |
| B03 | Payment lifecycle panel plus independently verified receipt state/model/panel and authored tests | Approved canonical receipt reader, feature wiring, executed widget tests |
| B04 | Duplicate handoff, stale response, session epoch and resume protections authored | Execute focused tests, format/analyzer and Cash regressions |
| B05 | Feature-local Trip/Payment reader seams and new receipt reader seam only | Yousuf's approved contract, secure live read adapter and Card matching prerequisites |
| B06 | Integration coordination/handoff checklist documented | Reviewed cross-stream SHAs, separate integration branch, shared runtime wiring and combined verification |

Primary source branch: `feature/p8-b01-rider-payment-state`. See `docs/ai/verification/P8-Omar-Rider-Payments.md` for exact implementation and security notes.

Keep Card financial execution default-OFF. No claim of hosted checkout, successful Card capture, canonical receipt issuance, or completed B05/B06 can be made until the backend and integration gates are satisfied. No independent source test in the receipt extension has yet run.
