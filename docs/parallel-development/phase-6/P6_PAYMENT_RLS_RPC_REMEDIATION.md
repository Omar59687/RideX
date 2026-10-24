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

- **NOT TESTED/DEPLOYED here.** Github content changes do not alter Supabase. The local Flutter/pgTAP suites cannot be executed from this connector environment; reported passing PR #47 tests predate this patch.
- Dev 1 must approve migration number 027, schema/role authorization, DB pgTAP results, and rollout order **before** applying migration or releasing the new Flutter client. The client depends on the RPCs being installed first; without them it fails closed.
- Run local migrations on an isolated database and `supabase/tests/database/027_phase6_canonical_payment_read_rpc.test.sql` plus regression `019`/`020`, then authenticated hosted Admin/Rider/Driver and blocked/role-change acceptance, and Flutter analyze + focused/full integration suites.
- This only resolves the **data-read access contract**. It does **not** finish B1-C Driver activation, trusted Cash settlement and receipt issuance, provider configuration, Stripe Test Mode execution, or Phase 6 approval. Phase 8 retains authorization/capture/webhooks/refunds.

## Minimum integration decision

After test and owner review: deploy the restricted additive RPC migration through Dev 1, verify RLS while selecting authenticated records through the RPC, then merge the dependent Flutter changes and test the Admin view on hosted role identities. Do not bypass RLS or replace SDK sessions with privileged/service-role clients.
