# Recovered Phase 6 foundation integration — 2026-10-24

PR #48 correction: the direct payments reader below was not hosted-operational
because migration 019 intentionally removed direct SELECT policies. PR #48
replaces it with locally tested restricted RPCs in proposed, undeployed migration
027. The counts below are historical PR #47 evidence, not PR #48 evidence. Current
results and rollout gates are in `P6_PAYMENT_RLS_RPC_REMEDIATION.md`.

Base main: `fc1d28b27a6d6432031eb05e562e5bec61c133e4`, including merged PR #45
(B1-B session epochs and synchronous Driver authority revocation).
Integration branch: `feature/p6-integration-recovered`, in one new isolated worktree.
Independent review: [replacement PR #47](https://github.com/Omar59687/RideX/pull/47).

## Recovery provenance

PRs #41–#44 and #46 were closed without merge. They remain closed. Their original
commits are sources, not evidence of merged or independently approved payment code:

- P6-08 Admin surface: `acce1e6` (#41).
- P6-04 server-only test-intent interface/fake/transport tests: `f7ac283` (#42).
- Complete canonical payment reader and exact infrastructure allowlist entry:
  `5daa4fb`, `0e27171` (#43, originally stacked on #41).
- P6-02/P6-07 Cash completion/recovery composition: `6777a90`, `cf6c550` (#44).
- Parser-to-Admin/Rider compatibility acceptance: `160abc7`; final previous
  snapshot `58160ec` (#46). Its stale integration history/tracker was not merged.

Recovery restored the needed implementation paths once from that snapshot onto
current main. No old branch merge, reopening, reset, rebase, duplicate runtime
owner or modification of another developer's worktree was performed.

## Shared-file and session reconciliation

All 11 source/test paths changed by PR #45 remain identical to `fc1d28b`, including
session/repository providers, AuthService, SessionEpochOwner, sanitized auth errors,
Driver authority/binding regressions and Rider pending-lock/recovery regressions.
PR #45 already contains the deterministic completion-store fixture clock; the old
integration's equivalent helper change was deliberately not reapplied.

The current-main tracker was preserved and reconciled with this replacement work;
its B1-B evidence is retained and marked merged. The only recovered modifications
to existing non-document paths are the Admin screen and the architecture test's
single explicit SDK-infrastructure allowlist entry. Router/guard, migrations,
Rider features, SDK overrides and payment/matching domain logic are unchanged.

The recovered Cash suite adds eight actual B1-B composition regressions, using
`AuthService.driverBinding` and its application epoch owner, not a replacement
lifecycle. They verify the original journal command, revocation during canonical
user/profile/Trip preflight, late completion/receipt responses, retained evidence,
no retry, and read-only recovery rejection. A newly created coordinator rejects an
already revoked session at admission; a running attempt is invalidated. Both remain
fail-closed. No production assertion or authority gate was relaxed to pass tests.

## Verification

Toolchain: Flutter 3.35.3 / Dart 3.9.2, Node 24.14.1, TypeScript 5.9.3.
No intentional live Supabase configuration, provider credentials or secret values
were inserted; all SDK financial test transport is loopback-only.

- Full non-live Flutter suite (one full run): **1,480 PASS / 0 FAIL / 2 existing live Supabase tests skipped**.
- Final focused Flutter selection: **959 PASS / 0 FAIL / 0 SKIP**, 32 files.
- Cash composition subset: **26 PASS / 0 FAIL**, including eight B1-B integration cases.
- Flutter analysis (`flutter analyze --no-pub`): **PASS, no issues**.
- Read-only formatting: **286 files, 0 changed**.
- Stripe injected transport: **32 PASS / 0 FAIL / 0 SKIP**.
- Strict TypeScript production-module checking: **PASS**.

Commands (run with the installed Flutter 3.35.3 SDK):

```powershell
$focused = @(rg --files test | Where-Object {
  $_ -match '_test\.dart$' -and $_ -match '(payment|completion|p6_contract|p6_closeout|driver_cash_composition|driver_authority|driver_single_client|session_epoch|session_revocation|fare_estimate|fare_lock_recovery|booking_confirmation|pending_fare_lock|session_route_guards|supabase_initialization_provenance)'
} | Sort-Object)
flutter test --no-pub @focused --reporter expanded
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib test
flutter test --no-pub --reporter expanded
node --test supabase/functions/_shared/payments/test_intent_provider_test.ts
npx --yes --package=typescript@5.9.3 tsc --noEmit --strict --target ES2022 --module ESNext --moduleResolution bundler --allowImportingTsExtensions --lib ES2022,DOM,DOM.Iterable supabase/functions/_shared/payments/test_intent_provider.ts supabase/functions/_shared/payments/test_intent_fake.ts
```

## Actual runtime activation and open gates

- **Admin:** the existing guarded route now composes sanitized read-only payment
  summaries through the existing configured application SDK. Missing configuration,
  lost Admin access, invalid role/session or RLS errors fail closed. This integration
  was verified with SDK loopback transport and widget tests, not hosted Admin data.
- **Canonical reader:** complete existing RLS-protected columns supply persisted
  booking identity and Payment version; the reduced summary RPC and deployed
  migrations are untouched. No identity/version is inferred. This is not receipt or
  completed-Trip authority; Rider success/history providers remain unchanged.
- **Driver Cash:** the injectable trusted RPC/Trip/receipt/recovery composition is
  present and compatible with merged B1-B. It is NOT installed as a production
  provider or Driver-screen consumer. B1-C needs explicitly approved backend
  endpoint-to-namespace mappings and canonical active-Trip/provider/UI composition.
  No default mapping, mock-to-production shortcut, automatic replay or journal
  retirement was added. Hosted Cash settlement/issued-receipt acceptance is unverified.
- **Stripe:** only a server-only unconfirmed Test Mode preparation interface exists.
  No handler/deployment or client-secret/card-entry flow was activated. Account/JOD
  approval, server Test Mode credentials and trusted actor/attempt composition remain
  external runtime dependencies. No real provider call was made. Authorization,
  capture, webhook verification, refunds and persistent history remain Phase 8.
- **Review:** this replacement integration still needs independent technical review,
  approved merge and Integration Owner acceptance. Offline fixtures do not prove
  deployed financial behavior or authorize payment execution.

P6-01/P6-03/P6-05/P6-06 remain complete within approved scope. P6-08, the canonical
reader and bounded P6-04 interface are implemented for review; P6-02/P6-07 remain
partial at runtime. P6-09 local compatibility is verified but final approval is open.

**Ready for independent foundation review; NOT approved for final Phase 6 closeout.**
Phase 7 planning can use these documented contracts and open dependencies without
claiming runtime Cash/Stripe readiness, matched-Trip availability or Phase 6 approval.
No Phase 5 hosted/device tests, production data operations, migration changes,
financial deployment, live charges, secret insertion or merges occurred.
