# P6-08 — Live Admin payment reader (proposed)

## Scope
- Read-only Flutter adapter for migration 027's `public.admin_recent_canonical_payments()` RPC.
- Compose the adapter only for an authenticated, unblocked Admin whose app session identity matches the Supabase SDK identity.
- Parse only the approved RPC response fields into existing `CashPayment` / `CardPayment` domain models and the existing sanitized Admin UI mapper.
- Reject malformed rows and responses exceeding 50 rows. Do not log raw backend errors or render payment/booking/trip/rider IDs.
- No payment mutation, direct `payments` table SELECT, schema change, or production deployment.

## Backend status
Migration 027 was deployed to hosted Supabase separately. Read-only catalog checks confirmed the two public RPCs exist, anonymous EXECUTE is denied, authenticated EXECUTE is granted, and `payments` RLS remains enabled. Those checks are not a substitute for authenticated end-to-end role tests.

## Review and release gates
1. Run `dart format --output=none --set-exit-if-changed` on changed Dart files, `flutter analyze`, `flutter test test/admin_payment_live_reader_test.dart test/admin_payment_integration_test.dart test/admin_payment_visibility_test.dart`, and the full Flutter test suite.
2. Run authenticated hosted read checks using dedicated nonblocked Admin, Rider, Driver, blocked Admin, and anonymous sessions; ensure non-Admin callers cannot read Admin summaries and no raw IDs/secrets appear in the UI.
3. Verify SDK logout, role switch, and Admin A→B→A transitions cannot publish stale results; repeat on device.
4. Obtain independent code/security review. This PR must not be merged merely because the SQL migration is deployed.
5. Do not touch the older PR #47 or the driver-lifecycle branch.

## Known limitation
This proposal has not been executed with a Flutter SDK in the connected authoring environment. It remains a **draft** until the test and review gates pass.
