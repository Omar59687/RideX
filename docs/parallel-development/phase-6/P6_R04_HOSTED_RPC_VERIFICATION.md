# P6-R04 Admin and canonical payment RPC verification

## Current hosted closeout override — 2026-10-26

The isolated test backend and existing actors are now owner-authorized. Prior
Rider/Driver/anonymous denial and representative Payment/Receipt RLS runs passed;
the owner supplied successful Admin device/logout/navigation evidence. New
real-SDK execution verified Admin list bounds/redaction and foreign Rider exact
Payment/Trip Payment/Receipt denial. **R04 remains PARTIAL** because disposable
blocked/demoted Admin cases are unavailable. The unconfirmed-environment and
all-actors-not-run statements below describe the original audit, not current
provenance. See [current matrix and remaining limits](P6_R04_R05_SECURITY_CLOSEOUT.md).

Date: 2026-10-25 UTC. Repository base: main
`34801bcb5b89607e79a2736e83b87d82d4447bb5`.
Branch: `docs/p6-r04-hosted-rpc-verification`.

## Admin hardening update - PR implementation

Based on main `a637f5e` (after PR #57). This follow-up locally addresses the F01/F02
client integration gaps without changing migration 027 or its server contract.

- The production `SupabaseAdminPaymentReader` checks the pinned, nonexpired SDK
  session and reads the current `users` profile (`id`, `role`, `is_blocked`)
  before the Admin RPC and again after it. A missing, mismatched, blocked or
  demoted profile rejects publication. Session identity is checked after each
  asynchronous profile read and once more before returning the parsed list.
  The server-authorized Admin RPC remains the data authority.
- This is a bounded freshness check, not instantaneous revocation: a role may
  change immediately after the final profile query. No realtime revocation
  subscription, server-issued freshness token or hosted latency guarantee was
  added. When the application observes a role/block/session change, existing
  Riverpod session dependencies replace/hide the Admin view; host acceptance is
  still required to assess runtime behavior.
- Admin RPC parsing and the canonical payment record now accept `trip_id: null`
  only when the field is present. Non-null linkage must remain a nonblank string
  in the Admin adapter and a UUID in the canonical repository. Amount, version,
  status, currency, identity and card metadata validation remains strict. The
  display model omits Trip identity, so pre-Trip rows add no new visible ID.
- Regression tests cover remote demotion/blocking during the RPC, a previously
  revoked profile preventing dispatch, null linkage alongside valid rows, and
  malformed/missing linkage and financial fields. Three focused test files:
  **51 PASS / 0 FAIL**. Flutter Analyze: **No issues found**. No hosted actor
  request, financial operation, migration change, full-suite run or device test.
- F01/F02 are **locally remediated**, not hosted-accepted. R04 remains PARTIAL
  and authenticated hosted acceptance BLOCKED by missing environment approval
  and dedicated fixture authorization stated below. Earlier audit totals remain
  historical evidence from their original base.

**Status: PARTIAL; authenticated hosted acceptance BLOCKED.** Hosted project,
migration, function definitions, grants, RLS configuration and estimated plans
were inspected. No authorized R04 account/data fixture or environment testing
classification was supplied or found in the inspected records/configuration.
No hosted actor RPC or financial-row read was attempted. Local passing tests
from the initial audit characterized F01/F02; the follow-up section above records
their local remediations and remaining limits. No local passing count approves
hosted behaviors or Phase 6.

## Environment and authorization provenance

- Connected Supabase management connector project/ref: `ykasivejjchupswqyxpm`.
  `get_project_url` returns `https://ykasivejjchupswqyxpm.supabase.co`, matching
  the requested endpoint. Management metadata reports `ACTIVE_HEALTHY`, region
  `ap-south-1`, PostgreSQL 17, release `17.6.1.166`.
- Environment classification (isolated test, staging, shared or production):
  **UNCONFIRMED**. This project is treated as potentially shared/production.
  Management access and a known URL are not approval to select financial rows,
  impersonate users, create accounts, change profiles or run hosted fixtures.
- The task authorizes read-only configuration inspection. Every hosted SQL call
  used `BEGIN READ ONLY` and `ROLLBACK`; queries inspected only PostgreSQL
  catalogs or `EXPLAIN` without `ANALYZE`. No hosted role/JWT was changed. No
  account enumeration, credential request, financial table result, financial
  RPC execution, migration deployment or financial mutation occurred.
- No dedicated R04 authenticated sessions or approved representative payment
  fixtures were available. Existing tests named `admin_payment_live_reader_test`
  use a local loopback HTTP server, not the hosted project. Existing live-auth
  tests perform signup and were deliberately excluded from this read-only task.
- The owner explicitly confirmed the intended project and that environment
  classification, hosted R04 role-test authorization and dedicated isolated
  account/payment-fixture availability have not been formally established.
  The owner restricted hosted work to metadata/catalog inspection and existing
  permission/security review, with local mocks/existing fixtures permitted.
  Hosted accounts, roles, payment records, financial mutations and authenticated
  role-matrix execution remain prohibited without separate explicit approval.

## Migration and hosted catalog evidence

`list_migrations` reports versions 001 through **027**, with 027 named
`phase6_admin_payment_read_rpc`. The two public functions and private helper
exist with the expected signatures, result columns, security-definer execution
and empty `search_path`; their owner is `postgres`.

Whitespace-normalized function-body fingerprints match the repository's existing
migration 027. These MD5 values are drift-comparison fingerprints, not signatures:

| Function | Matching normalized body fingerprint |
|---|---|
| `private.can_read_canonical_payment(uuid)` | `5b9d739b6d1a86d61d342bd9a0c107ca` |
| `public.user_canonical_payment_record(uuid)` | `2caadfdf0bad36ecb9116da823a73e7e` |
| `public.admin_recent_canonical_payments()` | `c7ec98fcad993d2c8da690acd4b446f2` |

- Both public RPCs grant EXECUTE to `authenticated`; effective EXECUTE is false
  for `anon` and `service_role`. The private helper is not executable by those
  client roles. The catalog was checked for matching overloads and signatures.
- Exact reads require a current nonblocked `public.users` profile that is Admin,
  or an owning Rider. Foreign/nonexistent payments both return no rows. Driver
  payment access is excluded. This is current database profile authorization,
  not client-editable metadata or stale role claims.
- Admin listing invokes `private.require_nonblocked_admin()`: a missing,
  blocked or non-Admin profile raises SQLSTATE `42501`. It orders by
  `created_at DESC, id ASC` and applies `LIMIT 50` in the function body.
- `payments`, `payment_attempts`, `refunds` and `receipts` all have RLS enabled
  and no SELECT/ALL policies. `authenticated` retains table SELECT grants but
  RLS supplies no rows; `anon` lacks table SELECT. Thus empty direct SELECT
  under authenticated RLS differs from a SQL permission error. These are
  hosted catalog conclusions; actor-level hosted requests were not executed.
- Function definitions and their authorization helpers contain SELECT/RETURN
  logic and exception handling, with no financial mutation. No before/after
  financial-row digest was taken on hosted data, because that would require
  authorized data access; local SQL tests separately verify unchanged fixtures.

## Actor matrix

Labels below describe required dedicated identities, not discovered accounts.
No hosted account identifiers, emails or private payment identifiers were used.

| Actor label | Required behavior | Hosted execution | Local SQL contract evidence |
|---|---|---|---|
| Admin-A, active/nonblocked | List authorized canonical records, at most 50 | NOT RUN: identity/fixture approval missing | PASS: deterministic 55-row owned fixture plus foreign fixture; ordering/cap and exact/list agreement |
| Admin-B, blocked | Listing raises 42501; exact foreign read empty | NOT RUN | PASS |
| Admin-C, demoted | Listing denied despite stale claims; no former global exact access | NOT RUN | PASS; a legitimate owning Rider retains only their own read rights |
| Rider-A, owning | Exact own persisted identity/version/status | NOT RUN | PASS |
| Rider-B, foreign | Exact foreign/nonexistent indistinguishable, empty | NOT RUN | PASS |
| Driver-A | No canonical payment/list access; direct finance rows denied | NOT RUN | PASS |
| Anonymous | No RPC execution privilege | NOT RUN at HTTP/runtime level; hosted catalog EXECUTE=false | PASS for listing denial plus grants assertions |

No row-bearing hosted RPC response was available. Therefore no actor, hosted
redaction, representative latency or 50-row runtime cap is marked accepted.
An empty list would not prove ownership or maximum-list behavior; permission
errors would be recorded separately from authorized-empty results.

## Session and client publication security

| Scenario | Local evidence | Limit / hosted status |
|---|---|---|
| Logout while Admin RPC pending | New production-reader loopback test rejects delayed response | Hosted not run |
| App identity differs from SDK identity | New test blocks dispatch | This does not attest the SDK's endpoint |
| Account switch and SDK A-B-A | Existing canonical SDK tests and Admin reader identity-pinning test pass | Hosted not run |
| App observes Admin demotion/blocking | Existing provider/widget tests immediately hide summaries | Remote-only changes without an app profile refresh remain F01 |
| Out-of-order results/disposal | Existing Admin provider and Rider read-generation tests discard stale data/errors | Hosted not run |
| Canonical repository role change during RPC | Before/after current-profile reads reject the response | Point-in-time revalidation, not instantaneous remote revocation |
| Wrong backend/client provenance | Provider checks app/SDK identity; reader holds one immutable client | No expected-endpoint attestation in these readers; wrong-backend runtime activation not tested |

`SessionController` refreshes profiles on auth events/explicit refresh, rather
than subscribing to every remote profile change. The production Admin reader
pins the SDK Session object and the provider checks the same application
SessionState, but neither rereads the current server profile after its RPC.
Rider production Cash/Card providers still default to null (R05); their injected
reader tests do not establish a live Rider consumer integration.

## Redaction and error boundaries

- The hosted RPC result schema is an explicit 12-column allowlist: canonical
  payment/booking/Trip/Rider identities, method, integer amount, JOD currency,
  Cash/Card status, version, optional card brand and last four. It intentionally
  includes authorized identifiers; it is not the UI display DTO. Provider names,
  references, secrets, attempt payloads, PAN/CVV and idempotency keys are absent.
- The Admin mapper constructs only fixed method/status labels, formatted amount,
  currency, allowlisted brand and masked last four. IDs and versions are dropped.
  Unknown brand text is omitted; Cash selected remains explicitly unpaid.
- Focused parser/mapper/widget tests reject malformed input and show no sensitive
  fixture markers. Panel errors use fixed messages; no logging calls were found
  in the inspected payment reader/provider/mapper/panel/card paths.
- Canonical repository exceptions are typed/sanitized. The raw Admin reader can
  propagate a `PostgrestException` internally; its production provider catches
  and replaces it with a closed `AdminPaymentReadException`. A new local test
  verifies this provider error boundary with synthetic private markers. This
  does not promise that arbitrary direct adapter callers sanitize errors (F04).
- No hosted payment payload or production log was retrieved. This record contains
  metadata and synthetic local test outcomes only; runtime/log redaction remains
  unverified for the hosted role matrix.

## Read-only performance inspection

Hosted `EXPLAIN (FORMAT JSON)` was run on the listing's inner SELECT, with its
same 12 fields plus ordering/limit, rather than invoking the Admin RPC or using
`ANALYZE`. It reports `Limit -> Sort -> Seq Scan`, sort keys `created_at DESC, id`,
estimated scan rows 240, result rows 50, cost 20.37..20.50 at Limit. These are
planner estimates/cost units, not actual record counts or milliseconds.

The exact-read inner SELECT was inspected with `EXPLAIN (GENERIC_PLAN, FORMAT
JSON)` and a parameter placeholder, without using an invented payment ID. It
reports `Index Scan` on `payments_pkey`, `id = $1`, authorization-helper filter,
estimated one row, cost 0.14..2.61. Catalog indexes are the primary ID index and
unique booking/Trip indexes; no `(created_at DESC, id ASC)` ordering index exists.

These inner-query plans do not measure authenticated RPC/helper overhead,
network/SDK/UI latency, cache behavior or load. **Representative runtime latency
is NOT VERIFIED.** A full scan/sort may matter as the table grows; the current
small estimate alone does not justify adding an index. No index, statistics,
migration or deployed configuration was changed.

## Focused execution evidence

- Flutter: **89 PASS / 0 FAIL / 0 SKIP** across canonical payment reader, Admin
  production-reader, integration, mapper, visibility and new R04 security tests.
  Plus **28 PASS / 0 FAIL / 0 SKIP** in Rider payment provider tests: **117 total**
  distinct focused cases. F01/F02 tests characterize limitations and are not
  affirmative acceptance of remote revocation or nullable-Trip rendering.
- SQL: existing migrations 019/020/027 contract files: **15 + 36 + 52 = 103
  pgTAP assertions PASS / 0 FAIL**. They ran only inside an isolated local
  PostgreSQL database `ridex_r04_contract_20261025`, with each fixture transaction
  rolled back. The local developer database stayed at migration 026.
- Local preparation copied only auth/public/private schema definitions from the
  existing local PostgreSQL 17 Supabase container, no application rows. Default
  schema/default-privilege restore differences required local setup correction;
  extension-schema USAGE was supplied to the standard test roles. Existing 027
  was loaded only into this isolated test database. This is a schema-snapshot
  contract run, not a fresh full migration-chain/deployment verification.
- After fixtures, isolated `public.users` and `public.payments` counts were both
  zero. The schema-only test database is retained; no developer database/container
  or existing worktree was reset or removed. Docker Desktop was started to run
  the local tests; existing local services were allowed to resume.
- `flutter analyze`: **No issues found** (29.8 seconds).
- Only the new Dart test file is formatted. No full Flutter/database suite,
  live signup/auth tests, financial provider operation or physical-device test.

Reproduction: run the six payment/Admin test paths plus
`test/rider_payment_provider_test.dart`; run the existing SQL files
`019_phase3_safe_exposure_hardening.test.sql`,
`020_phase3_driver_finance_exposure_correction.test.sql`, and
`027_phase6_admin_payment_read_rpc.test.sql` only in an isolated local database
with the compatible schema/standard Supabase grants and migration 027. Never
send those fixture scripts to the hosted target.

## Findings and remaining decisions

| ID | Severity | Evidence and consequence | Required follow-through |
|---|---|---|---|
| R04-F01 | Medium, session/privacy acceptance blocker | Historical baseline: delayed responses could publish after unobserved remote demotion/blocking. Follow-up locally rechecks current profile before and after RPC, preventing publication when those reads observe revocation. This is not a demonstrated backend authorization bypass and does not close the race after the final profile check. | Local mitigation implemented in this follow-up; hosted demotion/blocking cases and acceptable freshness remain unverified. Do not claim instantaneous revocation. |
| R04-F02 | Medium, integration availability blocker | Historical baseline: schema-valid null `payments.trip_id` made the strict Admin list parser fail. Follow-up accepts an explicitly null Trip link across Admin/canonical readers; local regressions cover mixed rows. Actual hosted prevalence remains unqueried. | Local mitigation implemented in this follow-up; verify through an approved hosted read fixture. Missing or malformed linkage and financial fields still fail closed. |
| R04-F03 | Low, performance observation | Hosted estimated listing plan scans/sorts; no ordering index. No representative latency measured. | Measure with approved identities/data; consider a separate index review only if justified. |
| R04-F04 | Low, defense in depth | Raw Admin adapter RPC exceptions propagate until the provider sanitizes them. Current UI boundary tests pass; arbitrary direct consumers could expose backend details if they log exceptions. | Keep the provider boundary mandatory; consider typed error conversion in the separately scoped reader-hardening task. |

Owner input still needed: environment classification and read-test authorization;
dedicated Admin/blocked/demoted/Rider/Driver account labels and approved existing
representative records (including enough records for the cap); secure session
provision outside Git/chat; authorization for controlled profile-revocation tests
or pre-provisioned identities; the F01 freshness and F02 display-scope decisions.
No role escalation, account creation, profile changes or fixture insertion in
the hosted project are authorized by this record.

Recommended next task: a focused Admin reader-hardening/nullable-Trip contract
task addressing F01/F02, then complete R04's real authenticated read matrix and
runtime latency under approved fixtures. R05/R07 and Phase 6 exit remain open;
there is no R04 completion, security release approval or automatic merge.
