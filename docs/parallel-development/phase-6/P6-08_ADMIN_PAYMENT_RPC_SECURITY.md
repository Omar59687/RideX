# P6-08 Admin payment RPC recovery

Status: local proposal on `feature/p6-admin-payment-rpc-hardening`; not deployed.
Base: `5c2eb010182be57a04160e2a6226d79399916cea` (`origin/main`, merged PR #49).
Historical source: open PR #48, `fix/p6-payment-rpc-rls-contract` at
`6d0ee1b1d638aaa803f7d44297ae4938ef96dfbc`. PR #47 was inspected as the
parent integration branch and was not merged or cherry-picked.

## Recovery decisions

- Reused PR #48's read-only Admin listing shape, canonical
  `booking_request_id` and stored Payment `version`, 50-row bound, and explicit
  selected output fields.
- Did not reuse PR #48's exact-ID error behavior: it looked up a Payment before
  authorization, raised `P0002` for a missing ID, and a different error for a
  foreign ID. The recovered exact-ID reader filters by both target ID and
  current profile authorization, so missing and unauthorized IDs both return
  zero rows. An active Admin and the owning nonblocked Rider retain legitimate
  access; Drivers and blocked/demoted accounts do not.
- The Admin list invokes the existing `private.require_nonblocked_admin()`
  authorization helper. The exact reader uses a new private boolean helper
  that checks the current `public.users` row and the ownership boundary.
- All new functions use `SECURITY DEFINER` with an empty `search_path` and
  fully qualified relation/function references. The private helper and public
  RPCs have default/client execution revoked; only `authenticated` can invoke
  the public RPCs. The private helper is not client executable.
- The RPCs return only canonical IDs, role-safe status, amount/currency,
  Payment version, and card brand/last four. Provider names/references, attempt
  metadata, failure messages, and raw Payment rows are excluded.
- No Payment SELECT policy, grant, or existing production RLS definition is
  modified. Migration 019's deny-all direct Payment RLS behavior and migration
  020's Rider/Admin finance authorization boundary remain the source controls.
- No financial facts are generated in migration logic. The pgTAP fixture's 56
  synthetic Payments are transaction-local test data rolled back at completion.

## Verification

`supabase/tests/database/027_phase6_admin_payment_read_rpc.test.sql` covers
active Admin listing and exact reads, Rider/Driver rejection, foreign and
nonexistent IDs with identical empty results, blocked and demoted Admins,
stored identity/version, the 50-row limit, provider-field exclusion, direct
RLS reads, RPC/helper privileges, and repeat-read stability. Its SQL test uses
valid four-argument `throws_ok` forms for Admin denials.
The historical #48 assertions invoked set-returning RPCs as scalar SELECT
expressions inside `throws_ok`; the recovered tests use `SELECT * FROM ...` in
the dynamic SQL argument and were executed successfully by pgTAP.

Verification used Supabase CLI 2.122.0 with a disposable project copy,
`ridex-p6-admin-rpc-test`, on database port 55432. The isolated database applied
migrations 001–027 successfully. Full local database test suite:
**24 files, 1,021 pgTAP assertions, PASS; 0 failures**. This includes the
new 027 suite and existing 019/020 compatibility suites. Fixture writes were
transaction-local and rolled back. Hosted RLS acceptance is not claimed;
hosted migrations were not applied.

## Review and deployment gates

Require independent database and security review of migration 027, its
`SECURITY DEFINER` ownership assumptions, exact-ID concealment, selected output
columns, and the pgTAP suite. Run migration 027 and all applicable database
tests on a disposable local Supabase instance, then run the repository's
019/020 compatibility tests against the resulting schema. Confirm reviewed
hosted RLS behavior separately through the approved deployment process before
production use. This change does not claim that approval or deployment.
