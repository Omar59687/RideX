# P6 — Canonical payment read RPC remediation (proposed, NOT deployed)

Review target: [PR #47](https://github.com/Omar59687/RideX/pull/47), stacked repair branch `fix/p6-payment-rpc-rls-contract`. Parent contains recovered P6-08 Admin screen and `SupabaseCanonicalPaymentRepository`.

## Confirmed hosted condition (read-only SQL, 2026-10-24)

- `public.payments` has RLS enabled and **zero SELECT policies**.
- `authenticated` has table SELECT grant; Postgres RLS still filters ALL raw rows.
- Migration `019_phase3_safe_exposure_hardening.sql` intentionally dropped payment/finance-table SELECT policies and preserved the grant matrix while using restricted SECURITY DEFINER summary RPCs. Creating a broad payments SELECT policy would undo that security design.
- The parent PR #47 originally queried `public.payments` directly; Admin and Rider complete-record reads therefore cannot be considered hosted-operational.

## Proposed fix

1. **Additive migration 027 (review before deployment):** `public.user_canonical_payment_record(target_payment_id uuid)` returns one complete **limited** domain projection only after `private.require_finance_reader(payment.rider_id)`, so only a current nonblocked Admin or exact Rider can read. `public.admin_recent_canonical_payments()` verifies the canonical `public.users` row is active Admin, returns up to 50 deterministic recent safe records. Both use `security definer set search_path = ''`, explicit schema references, and `EXECUTE` granted only to `authenticated`; anonymous/public privileges are revoked. Driver access remains denied; no provider name/reference, attempts, secrets, transaction tokens, payment method details, receipts, or arbitrary raw finance rows returned. **No new RLS policy** and no payment mutations.
2. **Flutter:** switch the existing complete canonical read repository to these two explicit RPCs, preserving independent SDK session checks, before-and-after role checks, persisted ID/version validation, bounded Admin list, duplicate rejection, sanitized UI errors. Missing/uninstalled RPC must surface unavailable/error, never report a successful empty history.
3. **Tests:** update existing SDK loopback tests to require RPC paths rather than direct table SELECT; add rollback-only pgTAP test file for Rider, foreign Rider, Admin, demoted Admin, blocked user, Driver, anonymous caller, persisted IDs and version, raw-table denial and explicit grants.

## Activation gates and dependencies

- **Locally verified; NOT deployed.** PR #48 now has its own evidence below. Earlier PR #47 results still do not verify this RPC repair or hosted access.
- Dev 1 must approve migration number 027, schema/role authorization, DB pgTAP results, and rollout order **before** applying migration or releasing the new Flutter client. The client depends on the RPCs being installed first; without them it fails closed.
- Local migrations, pgTAP 019/020/027, focused/full Flutter and analysis now pass. Authenticated hosted Admin/Rider/Driver and blocked/role-change acceptance remain separately gated and were not run.
- This only resolves the **data-read access contract**. It does **not** finish B1-C Driver activation, trusted Cash settlement and receipt issuance, provider configuration, Stripe Test Mode execution, or Phase 6 approval. Phase 8 retains authorization/capture/webhooks/refunds.

## Minimum integration decision

After test and owner review: deploy the restricted additive RPC migration through Dev 1, verify RLS while selecting authenticated records through the RPC, then merge the dependent Flutter changes and test the Admin view on hosted role identities. Do not bypass RLS or replace SDK sessions with privileged/service-role clients.

## Actual PR #48 verification — 2026-10-24

- Flutter 3.35.3 / Dart 3.9.2 focused reader/Admin/architecture selection:
  **60 PASS / 0 FAIL / 0 SKIP**.
- One full non-live Flutter run after focused verification:
  **1,487 PASS / 0 FAIL / 2 existing live Supabase skips**.
- `flutter analyze --no-pub`: **no issues**. Read-only format:
  **286 files / 0 changed** (the two originally unformatted Dart files were fixed).
- Fresh native PostgreSQL **17.10** applied repository migrations **001–027**
  unmodified and in filename order after an explicit local auth/role bootstrap.
- pgTAP **1.3.4**: **019: 15/15; 020: 36/36; 027: 26/26** — **77 PASS, 0 FAIL**.
  TAP plans matched assertion counts; SQL errors or `not ok` results failed the run.
- After rollback: **0 payment fixture rows**, **0 SELECT/ALL policies on payments**.
  The temporary database server was stopped. No hosted operation was performed.
- All PR #45 source/test paths remain unchanged, including Driver authority,
  session epochs, auth error sanitization and Rider pending-lock evidence gates.

Concrete errors corrected: the Admin RPC's unqualified `id` conflicted with its
RETURNS TABLE output variable (`42702`); the foreign-Rider test had invalid dollar
quoting. The exact-payment reader now validates the normal table-RPC list shape
and cardinality explicitly, preserving P0002 notFound, missing-RPC unavailable,
identity/ownership and session checks. SDK fixtures reject raw payments paths,
assert exact POST parameters and cover duplicate records, missing exact RPC,
permission denial and oversized Admin results. No authorization gate was weakened.
The tests also cover blocked Admin, canonical demotion with unchanged JWT claims,
foreign Rider/Driver denial and direct table denial for each financial role.

### Local environment and limits

Docker/WSL were unavailable. Verification used temporary, pinned
`embedded-postgres@17.10.0-beta.17` Windows binaries and `pg@8.16.3`, a fresh data
directory and an OS-assigned loopback-only port. The password was generated locally,
kept out of logs/Git and never taken from a production configuration. Official
pgTAP tag v1.3.4 (`968eb53a33114e83042b3bdb0c664b5b80cf8bdf`) SQL/control files
were installed only in that temporary distribution, with the upstream Makefile's
version/OS substitutions. No global service or system configuration was changed.

The local scaffold defined Supabase-compatible anon/authenticated/service_role,
public default grants, extensions schema, a fixture auth.users table and auth.uid()
reading request claims. Role/default grants follow Supabase's upstream initial
schema. It then executed all actual RideX migrations and the unmodified 019/020
plus corrected 027 test files in PostgreSQL. This is real SQL/RLS/PLpgSQL execution,
**not a full Supabase Auth/PostgREST deployment**. Flutter uses real SDK loopback
HTTP, not live JWTs or hosted RPCs. Deployed grants, API schema cache and hosted
identity acceptance therefore remain NOT VERIFIED.

Sources for reproducing that temporary bootstrap/tooling:
- https://github.com/supabase/postgres/blob/develop/migrations/db/init-scripts/00000000000000-initial-schema.sql
- https://github.com/leinelissen/embedded-postgres
- https://github.com/theory/pgtap/tree/v1.3.4

Flutter commands:

```powershell
flutter test --no-pub test/canonical_payment_reader_test.dart test/admin_payment_integration_test.dart test/architecture_boundary_test.dart --reporter expanded
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib test
flutter test --no-pub --reporter expanded
```

Local tests do not authorize deployment. Independent Dev 1 migration-numbering/
security review, parent #47 dependency review and approved database-first rollout
remain required. No Phase 6 closeout, financial activation, production data write,
production credential insertion or PR merge is claimed.
