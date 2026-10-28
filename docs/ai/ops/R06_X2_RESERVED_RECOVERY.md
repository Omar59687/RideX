# R06-X2 guarded reserved recovery

This is a local implementation for fixture `8168236a-6a53-4a08-8dfa-f79e68fe8925`, Trip `dda56345-4123-4a0c-9771-5287899d2344`, Payment `cbbb4b94-ac92-49b9-8b43-1f370c783e5b`, and Attempt/reservation primary key `45ae3584-fa38-4fa5-b8c8-10efd79f8416`. No hosted recovery, deployment, provider request, approval provisioning, or Driver restoration has been performed.

The historical `ceff7eb6-…` retirement RPC and migration are unchanged. New Card confirmation remains blocked by the Cash-only migration. Provider dispatch remains disabled in the Edge entry point; the preparation seams also permanently deny this exact Trip, Payment, or Attempt.

## Evidence and authority

Recovery intentionally fails until a database owner provisions a reviewed row in `private.r06_x2_owner_approvals`. There is no approval RPC, client grant, service-role grant, or automatic provisioner. RLS and explicit revokes protect the private tables. Approval, recovery, and late-observation rows reject UPDATE, DELETE, and TRUNCATE, including ordinary owner SQL. The database owner remains the trusted offline authority and can change schema or disable triggers; API actors cannot gain this authority with JWT claims or custom settings.

An owner must independently review all of the following before provisioning anything:

1. Provider-side/operator evidence covering the original operation from its creation, establishing that it was **never dispatched**. Missing database references, pending status, an unconfirmed intent, or a disabled current deployment do not establish this.
2. Worker/deployment evidence establishing that **all original claim holders have been revoked and drained**, including paused workers, queues, old deployments, outbound requests, callbacks, and ambiguous network outcomes. Database fencing cannot stop a request already sent or a worker paused immediately before sending it. Uncertainty is a refusal condition.
3. Owner authorization for this exact fixture and evidence snapshot. Record distinct provenance and SHA-256 digests for the independent evidence, the reviewed deployment digest, and a fresh quiescence epoch bound to `r06-x2-permanent-dispatch-deny-v1`. Artifact contents/signatures are reviewed offline; the database validates their bindings and structure, not their external truth.

The owner captures the current private snapshot under the canonical row locks and inserts its digest directly, without returning a reservation row or claim token. `private.r06_x2_snapshot_digest()` includes the token privately and is not executable by API roles. No token, raw snapshot, provenance artifact, or evidence digest is returned to a Rider or written into the recovery audit. No real approval or token is included in migrations or tests. The separate synthetic approval fixture is exclusively for disposable local databases.

Approvals expire within one hour, cannot be edited, and may be superseded by a new independently reviewed approval with a new ID/epoch. Recovery is uniquely bound to one consumed approval and one request ID. Hardcoded Trip v1, Payment v1, Driver availability v12, Driver profile v2, Booking v5, and GLOBAL Attempt sequence 2 deliberately match the assessed fixture. Any version/state drift requires a new assessment; a newer approval cannot relax these exact gates. An unknown/prepared reservation, provider reference, extra Attempt, Refund, Receipt, completion/failure evidence, inconsistent relationship, or missing evidence refuses recovery.

## Transaction and fencing

`rider_recover_r06_x2_reserved_fixture` is authenticated-only and requires the nonblocked owning Rider. It accepts exact identifiers, expected versions, an existing owner-approval ID, and a fresh request ID. Caller booleans or caller evidence are not accepted.

The transaction requires READ COMMITTED. It locks Trip → Payment → Attempt → reservation → Driver availability; post-wait statements re-read the evidence with fresh snapshots. The Rider row has a compatible SHARE lock to serialize blocking. Existing Driver administration serializes active-Trip decisions on the Trip. The wrapper inserts an immutable private revocation record, creates a protected transient authorization only around `private.rider_cancel_trip` and `private.reconcile_cancelled_trip_payment`, removes that authorization, and verifies the full result before committing. The transaction ID alone grants no authority after the wrapper returns. Trip and Payment advance once to `cancelledByRider` and `paymentCancelled`; Driver availability advances once to offline. `paymentCancelled` records canonical cancellation and is not provider void proof.

The original Attempt, reservation, token, Booking, and FareQuote remain unchanged. Failed postconditions roll back the cancellation, financial change, Driver release, revocation, events, and audit together. Generic cancellation cannot bypass the target-specific guard by setting a custom marker. The historical fixture guard is separate.

The target's claim, result-record, and completion RPCs use the same financial parent locks and check the durable fence. Existing implementations are retained privately with API execution revoked; unrelated identifiers delegate to the original behavior. Direct target Attempt/reservation mutations and Receipt/Refund/provider-event inserts also check the fence under parent locks, closing FK-wait insertion gaps. Refund/provider-event reassignment checks both OLD and NEW relationships; existing target evidence cannot be updated, unlinked, or deleted to manufacture a clean snapshot. Target Trip-change rows have the same additional fence. Target Trip/Payment rewrites and direct Payment cancellation cannot bypass the guard. Noncanonical direct updates can abort on a reversed-lock deadlock; canonical RPCs maintain the specified order.

The old record RPC rejects fenced results. The new backend-only `backend_record_stripe_test_preparation_fenced` validates original claim ownership privately and stores late observations append-only without changing financial/reservation history. It returns `quarantined`, which the server adapter treats as an uncertain result, never provider success. A later unknown acknowledgement cannot erase a stronger reference. Reconciliation then returns `review_required` and `requires_provider_review: true`; references and tokens remain private. A late completion is rejected and must be retained for operator review; it must not be retried as a new financial operation.

## Lost responses and Driver restoration

Call the recovery mutation once for an explicitly approved operation. Duplicate or conflicting requests refuse mutation and direct the caller to read-only reconciliation. After a lost/uncertain response, call `rider_read_r06_x2_recovery` with the fixture and original request ID. It performs SELECTs only and always returns `retry_allowed: false`. An absent row is `unresolved`, not permission to retry; a late contradiction is `review_required`.

Driver restoration is a separate Driver-authenticated call to the existing `driver_set_availability`, after verifying cancellation and resolving any review blocker. Recovery never makes the Driver available. The canonical Driver RPC validates the current availability version and active vehicle.

## Local verification

Run `python supabase/tests/ops/r06_x2_local_test.py`. It creates a new network-none Docker cluster from a cached pinned PostgreSQL image, uses only a local Auth shim, replays the entire lexical migration chain twice into new databases, verifies exact history and zero seeded approvals, and runs focused pgTAP plus historical retirement, reservation, and Cash-only regression tests. It neither resets nor drops any existing database/container and leaves its disposable resources for inspection. It does not run GoTrue/PostgREST or hosted integration tests.

The concurrency runner uses independent PostgreSQL sessions, observes the winner idle after its command, observes the loser blocked on real PostgreSQL locks, and only then commits the winner. It covers claim, result-record, completion, direct Attempt insertion, duplicate, and conflicting recovery orderings. Because the historical Attempt is older than the original two-minute claim window, the successful claim-first case uses a fresh synthetic Attempt creation time; recovery must refuse that changed snapshot. The recovery-first case uses the exact historical snapshot and refuses the old claim at the durable fence. No `pg_sleep` is used as a barrier.

Relevant Deno tests run without network/environment permissions. Test transports are deterministic fakes; no Stripe or other provider is called. Full Flutter/Dart checks are outside this SQL/server-only change.

## Interrupted-session resume verification — 2026-10-28

The existing branch `feature/r06-x2-guarded-reserved-recovery` remains based on
`a7e2ae7f9c5c6008bd36aed137dc7bb4e667a788`. No worktree, migration, or earlier
implementation was recreated during resume. At that checkpoint, all changes
were uncommitted; R06-X3 publication is recorded below.

The complete rerun against the final candidate passed:

- 252 pgTAP assertions: 119 recovery/security/postconditions, 4 isolation,
  14 evidence-boundary regressions, 45 historical retirement, 31 reservation,
  and 39 Cash-only confirmation assertions. Zero failed or skipped.
- 16 real independent-connection races: both orders of claim, record,
  completion, direct Attempt insertion, webhook reassignment, Refund
  reassignment, and owner-only Trip-change insertion, plus duplicate and
  conflicting recovery requests. Zero failed or skipped in the final run.
- Two full clean-database replays of all 31 migrations, with exact history
  and zero provisioned approvals after each replay.
- 91 Deno tests, zero failed or skipped, using
  `deno test --no-config --no-lock --cached-only` on the three payment test files.
  The default configuration initially could not resolve `npm:@types/node`;
  the explicit configuration-free cached run succeeded with type checking.
- `deno check --no-config --no-lock --cached-only` on the three payment modules
  and three test modules; formatting checks on all three changed TypeScript
  files; Python in-memory compilation; and Git whitespace checks.

Independent review found and prompted correction of a real service-role
Refund/webhook UPDATE bypass around the original insert-only fence. The new
tests cover NULL-to-target webhook assignment, Refund reassignment, evidence
erasure, and both concurrent orderings. The additional Trip-change insertion
fence is defense in depth: baseline service-role INSERT already fails the
route-validator CHECK permission. Its concurrency test intentionally uses
owner SQL rather than granting additional application-role permissions. An
initial expanded run exposed that test-setup ACL limitation; it was corrected
before the successful final run. The assertion helper also verifies setup
completed, and race barriers now report early session failures explicitly.

No GoTrue/PostgREST integration, hosted tests, Flutter suite, standalone legacy
retirement race script (four scenarios), or Supabase CLI `db reset` was run.
The two clean SQL migration replays are not a claim of full CLI/Auth integration.
The PostgreSQL container is network-isolated, with no host mounts. Disposable
databases and containers were retained; no existing database was reset or dropped.

Final security-sensitive source SHA-256 values:

- Migration: `87BCBB920C7FD0E1E1B0977FDAD4A69B814F42BAA4E8C3C8FC114F307A79AD05`
- Local runner: `837D28CC495428BDDDD3F15D0570938AF5F61FF50E0B328B70BE535B2084AB97`
- Evidence-boundary test: `73617BD4A10A0C7190F399CD8B6BA1216D51F68B77604E61B3653E583DAA2B11`

## Exact implementation file manifest

Existing files changed:

- `supabase/functions/_shared/payments/test_intent_provider.ts`
- `supabase/functions/_shared/payments/test_intent_reservation.ts`
- `supabase/functions/_shared/payments/test_intent_reservation_test.ts`

Files added by this change:

- `docs/ai/ops/R06_X2_RESERVED_RECOVERY.md`
- `supabase/migrations/20261028140221_phase6_r06_x2_guarded_reserved_recovery.sql`
- `supabase/tests/database/20261028140221_r06_x2_reserved_recovery.test.sql`
- `supabase/tests/database/20261028140222_r06_x2_isolation.test.sql`
- `supabase/tests/database/20261028140223_r06_x2_evidence_boundaries.test.sql`
- `supabase/tests/database/fixtures/r06_x2_reserved_target.sql`
- `supabase/tests/database/fixtures/r06_x2_synthetic_approval.sql`
- `supabase/tests/database/fixtures/r06_x2_unrelated_financial_evidence.sql`
- `supabase/tests/ops/r06_x2_bootstrap.sql`
- `supabase/tests/ops/r06_x2_local_test.py`

## Independent review and next checkpoint

Independent GPT-6.1 SOL HIGH read-only source/test review returned **APPROVE
WITH CONDITIONS**, with no unresolved blocking source findings after the
Refund/webhook remediation. The reviewer matched the final security-sensitive
source hashes above and reviewed the new evidence fixture and race tests.
The parent executed the reported tests; the reviewer did not independently
rerun them. This verification/manifest addendum was written after the reviewed
documentation snapshot, without further production or test source changes.

This is approval of a local candidate only. The outstanding conditions are
independently established no-dispatch and drained/revoked-worker evidence,
database-owner approval bound to an exact locked snapshot and deployment,
and acknowledgement of the GoTrue/PostgREST integration limitation. No actual
evidence or approval has been provisioned, and no hosted deployment or recovery
is authorized by this review. The owner subsequently authorized one commit,
feature-branch push, and PR in R06-X3. Deployment, approval provisioning,
provider operations, and recovery execution still require separate authorization.

The original `concurrency-acceptance-state.json` SHA-256 remains
`DA677A5C51129E86453C5891C404596656A16050A8D290256590C3AD8811C0A7`.

## R06-X3 publication checkpoint

Final integration review compared the 12 production/test files with the
independently approved hashes and found no differences. Only this documentation
was updated for publication. The latest verified `origin/main` was
`cea9312f01202fe6df42ecccaca8580770ed8601` (PR #84), whose six Flutter/test changes
do not overlap this 13-file candidate. No merge, rebase, or unrelated worktree
modification was needed.

Independent SOL HIGH review returned **APPROVE WITH CONDITIONS** for commit,
push, and PR publication, contingent on a passing final local rerun. That rerun
passed 252 pgTAP assertions, 16 races, two complete 31-migration replays, and
91 Deno tests, with zero failures or skips. Type checking, formatting, Python
compilation, whitespace, and scoped credential/path checks also passed. The
source review and prior remediation remain unchanged; exact commit and PR
identities are recorded in Git and the PR metadata.

Publication does not deploy this migration or authorize recovery. The
no-dispatch/quiescence evidence, protected owner approval, and GoTrue/PostgREST
integration limitations remain explicit hosted blockers. The next checkpoint
is owner review of the PR; there is no automatic merge or hosted execution.
