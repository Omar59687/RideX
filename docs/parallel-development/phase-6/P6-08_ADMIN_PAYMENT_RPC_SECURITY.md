# P6-08 Admin payment RPC recovery

Status: local proposal on `feature/p6-admin-payment-rpc-hardening`; not deployed.
Base: `5c2eb010182be57a04160e2a6226d79399916cea` (`origin/main`, merged PR #49).
Historical source: open PR #48, `fix/p6-payment-rpc-rls-contract` at
`6d0ee1b1d638aaa803f7d44297ae4938ef96dfbc`. PR #47 was inspected as the
parent integration branch and was not merged or cherry-picked.

## Recovery decisions and guarantees

- Reused PR #48's read-only Admin listing shape, canonical `booking_request_id`
and stored Payment `version`, 50-row bound, and explicit selected output fields.
- Both RPCs are `STABLE SECURITY DEFINER` functions with an empty
`search_path`; relation, type, auth, and private-helper references are schema
qualified. The exact reader's private boolean helper checks the current
`public.users` profile, `auth.uid()`, blocked status, and the persisted rider
ownership relation. It never trusts user-editable JWT metadata. The listing
calls the existing `private.require_nonblocked_admin()` check.
- The Admin RPC returns at most 50 rows ordered by `created_at DESC, id ASC`.
It selects canonical payment and booking/trip identities, stored version,
role-safe status, amount/currency, and card brand/last four. Provider names and
references, attempt metadata, and raw failure messages are omitted.
- The private helper and both RPCs have PUBLIC/anon/client execution revoked;
only `authenticated` is explicitly granted execution on the public RPCs. The
private helper is not client executable. The Admin RPC checks the current DB
profile, so blocked/demoted accounts fail even with stale JWT role claims.
- Migration 019 retains an authenticated SQL `SELECT` table grant for
`public.payments`, but its deny-all direct SELECT RLS boundary has no applicable
SELECT policy; direct client reads return no rows. Migration 027 does not alter
that grant or any existing RLS policy. The definer functions are a narrow,
explicitly authorized read path. Migration 020's finance boundary continues
to exclude Drivers.
- The exact RPC filters by both requested ID and current caller authorization.
A legitimate owner/nonblocked Rider or nonblocked Admin receives the persisted
row. Foreign and nonexistent IDs both return zero rows with the same result
shape; no distinct not-found/unauthorized error is raised. Missing profile or
empty subject returns no exact rows and fails Admin listing authorization. A
malformed UUID subject raises PostgreSQL `22P02`; it does not yield payment
rows. Blocked/demoted Admins cannot use exact reads or list access.
- Repeated reads are read-only. The tests snapshot Payment identity/version/
status and the full Payment-table count/content digest before and after calls.
No payment facts or versions are synthesized by migration logic.

## Migration 027 conflict

Migration 027 is unused on the current `origin/main` base, and PR #50 is based
on that main line. However, PR #48 remains OPEN and independently proposes a
different migration also numbered 027. The collision is therefore not
resolved by the current base. If PR #50 is selected as the canonical recovery,
PR #48's conflicting migration must not be merged or deployed. This change does
not close or modify PR #48; owner/release coordination must explicitly
supersede or close it before migration ordering is considered settled. Do not
apply both versions.

## Performance assessment

A disposable local PostgreSQL transaction inserted 100,000 synthetic payment
rows and rolled them back. On PostgreSQL 17, the listing's `ORDER BY
created_at DESC, id ASC LIMIT 50` plan without an ordering index used a parallel
sequential scan and top-N sort: 38.517 ms execution, 1,864 shared buffers
reported. In the same disposable transaction, a candidate
`(created_at DESC, id ASC)` index produced an index scan returning 50 rows in
0.243 ms (1 hit, 3 reads). This is synthetic single-run evidence, not a
production workload benchmark; cache state, concurrent writes, row widths,
hardware, table growth, and hosted planner settings differ. At 100k rows, the
full scan/sort is a material scale risk for repeated listing requests.

Propose a separate, reviewed index change:
`CREATE INDEX payments_created_at_id_idx ON public.payments (created_at DESC, id ASC)`.
No index is added in this migration. Before a hosted change, validate the plan
against representative hosted statistics and select an operationally safe
index-build procedure for a populated table.

## Local verification

A disposable local Supabase database applied migrations 001–027 before the
suite. No hosted database was contacted or migrated. Current remediation
verification used Supabase CLI 2.122.0:

- Focused migrations 019, 020, and 027: **3 files, 103 pgTAP assertions, PASS; 0 failures**.
- Full local database suite: **24 files, 1,047 pgTAP assertions, PASS; 0 failures**.
- Migration compatibility: migrations 019/020 and the 027 contract all passed
in the focused run after the complete migration set had been applied.
- SQL validation is exercised by applying the migration and executing the
pgTAP files in local PostgreSQL. `git diff --check` is also run before commit.

These results establish local behavior only. They do not constitute hosted RLS
acceptance, hosted performance acceptance, or permission to deploy.

## Review and deployment gates

Migration 027 still requires independent database/security review and explicit
resolution of the PR #48 numbering collision. Before production use, the
release owner must select one migration 027, review definer ownership and
function grants in the target environment, validate the RLS boundary and query
plan on hosted-equivalent data, and approve the hosted deployment through the
normal release process. No hosted RLS acceptance is claimed, and this change
does not authorize deployment.
