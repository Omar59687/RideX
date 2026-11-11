# P7 Cash matching endpoint ? consolidated handoff

## Result and scope

Git status statements in this report describe the verified pre-delivery checkpoint. The subsequent delivery commit and PR preserve this evidence; they do not authorize deployment.

Latest verified remote main, HEAD and merge base: `c286dd6ff3d483d686f02eb2bad8410ff820644c`. Branch `feature/p7-yousuf-matching-endpoint`; isolated checkout retained with original patch preserved and extended. No commit, push, PR, deployment, hosted call, Card/Stripe operation or feature activation. All unrelated worktrees preserved; the newly created detached baseline checkout is only for verification.

Local verdict: **READY TO COMMIT** for this scoped backend patch; integrated app/live activation is not approved. This document supersedes the previous run's BLOCKED report: Docker became available and independent local security work continued. Application/hosted activation remains gated separately.

Sol (`gpt-6.1-sol`, harness medium; cannot change parent effort in-turn) owned integration and acceptance. Catalog-resolved Codex `gpt-6-luna`, high reasoning, handled independent baseline investigation, TS security/expiry work, read-only boundary review, DB guard implementation and final review. File ownership never overlapped between active writers. Sol corrected incomplete agent results, finished the baseline report, fixed the expiry test's inaccurate Booking transition, added transport/429 regressions, completed guard race/clock/deleted-session tests, reviewed every diff and reran evidence. No agent PASS was accepted without inspecting actual results.

## What changed

The baseline ALREADY wires `cash-matching/index.ts` to `SupabaseCashMatchingPort` and A05 `CashMatchingAdapter`; no duplicate endpoint or matching state machine was added.

- HTTP runtime validation now rejects null/array results, unknown states, mismatched canonical IDs, invalid assigned Trip IDs, and Trip IDs on pending responses. Returns sanitized 502.
- Admission runs once per valid matching request, using the Rider credential with a new authenticated no-argument `rider_matching_request_guard()` RPC. True admits; false returns sanitized 429 with `Retry-After: 60`; revoked/invalid sessions fail authorization. Malformed or unavailable guards fail closed without dispatch.
- A private durable budget row per Rider enforces 30 requests per fixed UTC minute, across instances. Advisory transaction locking serializes each Rider before sampling time; exhausted counters cannot reopen on clock rollback. Budget rows are deleted with the user; no unbounded request log. Authenticated/anon/service-role callers cannot read or reset the budget directly. The two new RPCs grant execute only to authenticated; no client-supplied actor argument.
- Repeated `owner()` checks use authoritative Auth user/profile reads and `rider_matching_session_is_active()` with the Rider JWT. The DB checks linked `auth.sessions.id/user_id`, nonblocked Rider and nullable `not_after`. The in-memory session object remains request context only.
- Persisted offered rows are reconciled via existing service-role `backend_expire_booking_match_offers`, then canonical state is reread. Expired offer history is retained, and no deadline is extended or offer resurrected. Lost mutation responses are reconciled without automatic mutation replay.
- A03/A04 discovery, locks, Driver eligibility, 15-second offers, 90-second search, maximum three active offers, authenticated Driver acceptance and financial invariants remain authoritative. No existing migration was rewritten.

The new migration must be installed before any future function deployment. Missing guard RPCs fail closed. No deployment is authorized by this report.

## Rider contract ? Sanad

Function URL: `<SUPABASE_URL>/functions/v1/cash-matching`. POST JSON, Rider Bearer JWT, maximum body 4096 bytes; exactly these fields:

```json
{"booking_request_id":"<uuid>","fare_quote_id":"<uuid>","expected_booking_version":3}
```

Driver IDs, coordinates, amounts, payment state and privileged actor data are rejected. The request must identify an owned confirmed/searching Cash Booking and its locked JOD FareQuote with matching route/stops lineage. Existing Flutter request repository and Confirmation/Searching/Tracking composition exist behind `RIDEX_ENABLE_CASH_MATCHING_INTEGRATION`, default false.

```json
{"data":{"booking_id":"<uuid>","fare_quote_id":"<uuid>","state":"awaitingDriver"}}
{"data":{"booking_id":"<uuid>","fare_quote_id":"<uuid>","state":"noCandidates"}}
{"data":{"booking_id":"<uuid>","fare_quote_id":"<uuid>","state":"assigned","trip_id":"<uuid>"}}
```

`awaitingDriver` means canonical offers remain pending; `noCandidates` means no eligible bounded candidates, not a fabricated assignment. Searching must recover canonical Booking/Offer/Trip state. The returned Trip locator is never navigation or tracking authority by itself: the existing participant-scoped assignment repository verifies exactly one linked canonical Trip and accepted offer before presenting tracking.

Errors have `{error:{code,message}}`: 400 invalid request; 401 invalid initial authentication; 403 unauthorized Rider/session; 409 conflict; 422 invalid canonical state; 429 rate limit; 502 malformed adapter response; 503 unresolved backend outcome; 405 method. Current Flutter maps an unknown `rate_limited` code to `unavailable`, safely; explicit retry-delay UX is proposed Sanad work. Honor 60 seconds before retry, reread canonical status/version after conflicts/unknown outcomes, never blindly replay writes. Late results after SDK session replacement must remain discarded. Baseline Searching compile and controller-test errors block integrated UI acceptance; this patch changes no Dart files.

## Driver contract ? Moath

Offers persist in `public.driver_match_offers`. Driver observation must use authenticated participant-scoped readers/RLS; events are hints requiring canonical reread. This endpoint does not establish event delivery. Existing inactive canonical Driver foundations are preserved.

Accept through existing `driver_transition_trip(offer_id, 'accepted', expected_offer_version, idempotency_key)`; decline through `driver_decline_match_offer(offer_id, expected_offer_version, idempotency_key)`. The database revalidates eligibility, expiry, ownership and canonical Cash/quote lineage under locks. A successful accept must recover the real canonical Trip; the endpoint never accepts for a Driver. A persisted offer is not evidence of Realtime delivery. Autonomous expiry scheduling remains an operations requirement despite request-time expiry reconciliation.

## GPS and Realtime ? Omar

A03/A04 use the latest location sequence, with device and received freshness at most 60 seconds, accuracy at most 50m, no future server receipt, and bounded device skew. Invalid latest evidence does not fall back to older fixes. The available-GPS publisher permits 120 seconds, which can make Drivers ineligible. Align cadence with the existing server rule rather than relaxing matching security.

PR #127 remains OPEN at review. Some Realtime/GPS source already exists on main; PR state is not proof of merged code or delivered events. Its publication work remains deferred, and no unsafe publication migration is copied or enabled. Owner review must prove participant filtering, subscription teardown, DELETE/TRUNCATE safety and real delivery.

## Fresh verification and baseline classification

- Deno matching suite: **57 PASS / 0 FAIL / 0 SKIP**. Includes strict HTTP responses, 429, expiry reconciliation, retries/lost responses, canonical lineage, block/session guards, credential separation and guard 403/404/500 failure handling.
- Entrypoint Deno type check and formatting of all five changed TS files: PASS. Existing untouched `core_test.ts` CRLF formatting is not relabeled as a new failure. `git diff --check`: PASS.
- Current serial full Flutter suite: **2316 PASS / 22 FAIL / 4 SKIP**.
- Exact detached baseline suite: **2316 PASS / 22 FAIL / 4 SKIP**. All 22 normalized errors and stack traces are identical. These are reproduced baseline failures, not inferred from the absence of Dart changes.
- Analyzer: **24 identical diagnostics** on both: 4 errors, 5 warnings, 15 informational. Full names, paths, lines, errors and stack traces are in [baseline comparison](../verification/P7_MATCHING_FLUTTER_BASELINE_COMPARISON.md), with independent compact JSON evidence.
- Installed SDK Flutter 3.35.3 / Dart 3.9.2 differs from guide 3.27.3 / Dart 3.6.1. No failure is attributed solely to SDK mismatch without another-SDK evidence. Deno 2.9.6.
- Guard verification: **27 pgTAP PASS**, **2 independent-session budget races PASS**, **two full 35-migration replays PASS**. Includes foreign/missing/malformed/expired/deleted sessions, block changes, role grants, budget exhaustion, rollover and backward clock. SQL fixtures do not replace GoTrue/PostgREST acceptance.
- Full pre-existing SQL regression and A04 race reruns against final migration: see final closeout below. Earlier in this continuation, 1317 SQL assertions and 19 real races passed on 34 migrations; these earlier results are not substituted for final 35-migration evidence.
- Hosted Auth/PostgREST, function gateway, Realtime and two-device E2E: NOT RUN. No full E2E claim.

## Authentication proof limits

[Supabase session documentation](https://supabase.com/docs/guides/auth/sessions) identifies the signed JWT session_id with auth.sessions and describes row removal on sign-out. The production queries use that linkage; source schema columns were checked against Supabase Auth migrations (20220811173540 and 20221114143122). Tests here create a minimal Auth session table only in new isolated test databases. Actual GoTrue logout, JWT expiry/signing, refresh, single-session/timeouts and target PostgREST grants remain unverified as an end-to-end boundary. Do not claim complete JWT revocation enforcement from these SQL fixtures or mocked HTTP tests.

Session checks before/after backend operations reduce stale-session use but are not atomic with the separate service-role matching RPC transaction. An in-flight operation can commit before a subsequent revocation check fails. No rollback or cancellation guarantee is implied. A separate transactional authorization design would be needed for stronger guarantees; this patch does not invent another matching lifecycle.

## Remaining blockers by owner

- **Yousuf:** controlled target migration/guard-grant and real GoTrue/PostgREST acceptance; approved least-privilege expiry scheduler; read-only duplicate-active-Trip preflight before deployment; no automatic repair. Rate limiting protects valid matching dispatch, not platform-wide ingress/Auth calls or account-creation abuse. Fixed-window edges can admit two adjacent-window budgets, as documented policy.
- **Sanad:** baseline undefined riderTripTrackingRepositoryProvider; assignmentHintApplied controller-test compile errors; Confirmation to endpoint to canonical assignment/tracking acceptance; proposed 429 delay UX.
- **Moath:** baseline D02/B08 session replacement delivery-scope assertion (expected 0, actual 1); authorized offer reader/delivery and acceptance-to-canonical-Trip evidence.
- **Omar:** 120s publisher versus 60s eligibility, safe publication disposition, real Realtime/GPS delivery and subscription lifecycle evidence. Shared architecture allowlist failure needs coordination with Sanad/Omar for the new repository.
- **Team/environment owners:** approved Rider and Driver accounts, one controlled nonproduction environment, safe synthetic fixtures, two emulators/devices, P6-R07/R08 acceptance and P6-R09 exit disposition. No approval or success is inferred here.

P6 Card/Stripe restrictions remain absolute. The local endpoint patch never performs Card matching, authorization, payment/receipt transitions or Stripe operations. All live gates and the default-off integration flag remain unchanged.

## Final closeout

Final 35-migration chain SQL regression: **1317 PASS / 0 FAIL / 0 SKIP / 0 incomplete**. Final A04 independent-session rerun: **19 PASS / 0 FAIL**, no deadlocks/timeouts or partial state. Combined with the new guard: **1344 SQL assertions and 21 real race scenarios passed**, not counting repeated earlier runs. Four independent full 35-migration replays completed across final commands. Evidence logs are in ../verification/p7-matching-evidence/ (database-regressions.txt, matching-concurrency.txt, guard-replay-races.txt).

Git HEAD and refetched origin/main remain c286dd6ff3d483d686f02eb2bad8410ff820644c. No staged files, commits or generated Flutter changes. Original checkout remains clean. Detached baseline checkout retains only its own tool outputs. Disposable network-none PostgreSQL containers created by the runs remain for inspection; no pre-existing stack was modified or stopped. Deno/type/format/whitespace checks passed on the integrated patch. Full Flutter and analyzer remain FAIL with exact independent baseline reproduction, not waived or altered.

Final changed-file inventory (all unstaged):
- `docs/ai/ops/P7_MATCHING_ENDPOINT_HANDOFF.md`
- `docs/ai/verification/P7_MATCHING_FLUTTER_BASELINE_COMPARISON.md`
- `docs/ai/verification/p7-matching-evidence/analyzer-comparison.json`
- `docs/ai/verification/p7-matching-evidence/baseline-failure-evidence.json`
- `docs/ai/verification/p7-matching-evidence/current-failure-evidence.json`
- `docs/ai/verification/p7-matching-evidence/database-regressions.txt`
- `docs/ai/verification/p7-matching-evidence/guard-replay-races.txt`
- `docs/ai/verification/p7-matching-evidence/matching-concurrency.txt`
- `supabase/functions/_shared/matching/cash_matching_adapter.ts`
- `supabase/functions/_shared/matching/cash_matching_adapter_test.ts`
- `supabase/functions/cash-matching/core.ts`
- `supabase/functions/cash-matching/index.ts`
- `supabase/functions/cash-matching/security_test.ts`
- `supabase/migrations/20261111095410_rider_matching_request_guard.sql`
- `supabase/tests/database/20261111095411_rider_matching_request_guard.test.sql`
- `supabase/tests/ops/p7_matching_guard_local_test.py`
