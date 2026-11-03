# RideX Phase 7 — Parallel Ownership and Phase 6 Dependency Gates
Status: proposed execution policy for owner review; documentation only.
Date: 2026-11-03. Baseline: main at documentation branch creation. Do not infer hosted deployment or phase approval.

## Mandatory rule for EVERY Phase 7 task
Before implementation, every P7 task description, AI coding prompt, PR and review MUST declare:
- P7 task ID, named owner, bounded file ownership, and acceptance tests;
- **P6 dependency**: exact P6-Rxx ID(s), or `NONE`, never "finish Phase 6" generically;
- dependency class: **HARD BLOCK** (do not implement/activate dependent behavior), **INTEGRATION GATE** (can build/test against mocks but cannot activate/live-merge), **EXIT GATE** (implementation independent, cannot claim final acceptance), or **NO DEPENDENCY**;
- exact missing evidence/action, the canonical P6 tracker/roadmap link, status, and restart criteria;
- whether Cash-only is supported; Card/Stripe remains disabled unless separately approved.

If a missing P6 requirement is discovered: stop ONLY the affected dependent operation; name its exact P6-R ID and evidence, send owner back to that P6 task, continue independent P7 tasks, and resume only when the missing gate is documented and verified. Never substitute mock data for canonical backend proof, or label a blocked task passed.

## Four independent workstreams (proposed P7 IDs, not preexisting official IDs)
| P7 task | Owner | Scope and safe independently testable deliverable | Dependencies and stop lines |
|---|---|---|---|
| P7-A — matching backend | Yousuf | Audit/reuse existing Supabase availability, offers, eligibility, concurrency and atomic assignment; implement only gaps; local pgTAP/transaction race tests | P6-R08 Cash-only confirmation is an **INTEGRATION GATE** for real new bookings; P6-R06/R08 Card authorization is a **HARD BLOCK** for Card matching/payment behavior. No provider dispatch. Existing Phase 4/5 fare lock, canonical booking and driver authorization contracts must be verified. |
| P7-D — realtime/location | Omar | Own secured Trip event/location stream adapters, session/reconnect/reorder guards, RLS tests; local fake streams | Canonical accepted Trip identity from P7-A is an **INTEGRATION GATE** for live two-device sync; P6-R04 role/hosted authorization evidence is an **EXIT GATE** where its protected read surfaces are reused. Not a Stripe blocker. |
| P7-B — Driver UI | Moath (معاذ) | Driver availability, request offer, accept/reject, trip display and safe state UI; fakes and widget tests | P7-A contract/assignment and P7-D stream are **INTEGRATION GATES** only. **P6-R01/R02/R03/R07 HARD BLOCK** activating trusted Cash completion, settlement or receipt UI before scoped hosted/owner evidence. Do not turn mock Driver transitions into finance authority. |
| P7-C — Rider UI | Sanad (سند) | Searching, assigned Driver, map marker, tracking/reconnect, cancellation display; fakes and widget tests | P7-A and P7-D are **INTEGRATION GATES**. P6-R08 Cash-only booking authority is an **INTEGRATION GATE** for live booking handoff. **P6-R06/R08 HARD BLOCK** for Card enablement and any claimed payment success. P6-R05 exact scoped cash payment reads remain separate from broad Phase 8 history. |

## Explicit Phase 6 return-to-task matrix
| Trigger in Phase 7 | Return to P6 task | What to close/check before resume | Class |
|---|---|---|---|
| Want to enable fresh Card booking, Stripe UI, authorization or provider dispatch during matching | **P6-R06 + P6-R08** | Provider/JOD/account/actor/attempt approval, approved Card confirmation authorization gate and secure hosted payment entry; preserve Cash-only denial until verified | HARD BLOCK |
| Cash-only booking cannot establish canonical confirmed booking/fare/Trip lineage for matching | **P6-R08** (and relevant P5 fare-lock/confirmation checks) | R08 owner acceptance, backend Cash-only guard and canonical Booking/Fare Quote checks, hosted/device evidence | INTEGRATION GATE |
| Driver Trip panel tries to perform trusted completion, Cash settlement or receipt | **P6-R01, P6-R02, P6-R03, P6-R07** | Default-off gate scope, canonical Driver source, authorized one-time command/recovery, retention/operator decision, hosted Cash receipt/idempotency/restart evidence | HARD BLOCK for financial operations |
| Protected Admin/Rider/Driver payment read or role behavior is used without relevant hosted actor evidence | **P6-R04** (and **P6-R05** for exact Rider payment details) | Appropriate authorized fixture/role matrix, RLS, session/race tests and scoped cash canonical evidence; do not fabricate payment IDs | EXIT/INTEGRATION GATE as applicable |
| Phase 7 end-to-end acceptance is presented as Phase 6 finance completion | **P6-R07 + P6-R09** | Hosted Cash acceptance and integrated financial closeout or explicit documented partial/deferred disposition | EXIT GATE |
| Active Trip restoration / full history is required beyond Phase 7 | **Phase 8** (not P6) | Separate Phase 8 plan and ownership; don't slip into P7 | OUT OF SCOPE |

Source of truth for current P6 statuses is `docs/parallel-development/phase-6/SPRINT_TRACKER.md`, with bounded task details in `P6_POST_MERGE_ROADMAP.md`. This matrix is a routing policy, **not** a claim that those tasks are still all incomplete or that earlier documentation overrides recent PR/hosted evidence. Recheck merged main and owner evidence before each stop/go decision.

## Parallel-development / integration rules
1. Freeze a small shared contract at the start: exact canonical Booking/Trip/Driver identities, accepted Trip lifecycle, available RPC/event schema and error semantics. Reuse existing names before adding wrappers. Put changes to shared contracts in a tiny reviewed PR, **not** in four competing branches.
2. Each owner creates a branch from current main, modifies own code and tests only, and uses fakes/mocks at boundaries. No branch imports or cherry-picks another unfinished team's code. Existing shared code changes require recorded approval.
3. Each independent PR must run scoped tests and declare any fake-versus-hosted limitation. Integrate P7-A/P7-D contracts before the final live wiring of P7-B/P7-C. Sequence of integration does not block parallel local implementation.
4. No automatic merges, hosted migrations, finance mutations, recovery retries, Stripe requests, or secrets. Require explicit operator/owner authorization for sensitive hosted operations.
5. End-to-end acceptance requires authenticated hosted role/permission checks and Rider+Driver physical device flow (Cash-only booking -> matching -> single atomic assignment -> realtime location/Trip updates), with failure/reconnect/concurrency evidence. Phase 6 full approval and Stripe are never silently inferred.
6. Track each task as `READY_LOCAL`, `BLOCKED_P6-Rxx`, `READY_INTEGRATION`, `VERIFIED_HOSTED`, or `ACCEPTED` with proof/commit ID, not optimistic percentages.

## Copyable gate in all future P7 task prompts
```
P7_TASK_ID:
OWNER:
OWNED_FILES:
P6_DEPENDENCY: NONE | P6-R01 ... P6-R09
DEPENDENCY_CLASS: NO DEPENDENCY | HARD BLOCK | INTEGRATION GATE | EXIT GATE
MISSING_P6_EVIDENCE:
SAFE_INDEPENDENT_SCOPE:
STOP_CONDITION:
RESUME_WHEN:
TESTS_AND_EVIDENCE:
```

This document defines planning and stop conditions only. It does not authorize Phase 6 closeout, production matching, payment actions, or declaration of Phase 7 completion.
