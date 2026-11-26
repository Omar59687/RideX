# P8 Omar A04 Financial Read Adapter

## Scope

This checkpoint adds a strict parser and injectable, read-only consumer for
`user_trip_financial_read_v1`, plus fake-backed tests. The reviewed source
contract is on Yousuf's `feature/p8-local-backend-integration-preview` branch
at `5fbbcc6fd4964ef1f96597f9e5189873bbb98ce8`. Its SQL is local preview code;
this work did not deploy or modify it.

The parser accepts the one-row v1 shape and validates contract version,
canonical UUIDs, Trip status/version, Payment method/status/version, JOD
amounts, and linked receipt identity/number/amount/currency/time. An empty
result, `P0002`, privacy-masked result, or transport failure is UNKNOWN or
unavailable; none is treated as proof of absence. `receipt_evidence =
unverified` maps to receipt UNKNOWN. `linked` establishes only the exact
server-side linkage and is not interpreted as provider settlement.

## Trip identity composition and production gate

The financial RPC returns `trip_id`, `trip_version`, and `trip_status`, but
does not return `bookingRequestId`, `riderId`, or `driverId`, which
`RiderCheckoutTrip` requires. The adapter obtains those fields, current Trip
fare, and currency only from an injected authenticated, participant-scoped
canonical Trip reader, then binds the A04 row to the exact Trip ID, version,
status, method, fare amount, currency, and session. It does not derive these
fields from a Booking or financial response.

The current application Trip reader still enforces Cash-only Trip reads, so
it is not a safe production source for Card Trips. No live Supabase transport
or provider wiring was added. Production integration remains disabled until a
reviewed Card-capable canonical Trip reader supplies exact Booking, Rider and
assigned Driver identity under the authenticated session and the A04 SQL is
approved/deployed through the normal backend process.

Completed Card Trips may read historical payment and linked receipt/refund
evidence through the feature-local controller. Their Trip state remains
terminal, and checkout handoff still requires an eligible nonterminal Trip.
Cash handling is unchanged.

## Local verification

Authored tests cover exact Card/JOD mapping, linked evidence without
settlement inference, unverified receipt handling, zero rows, `P0002`,
malformed fields, foreign Trip/Rider context, blocked sessions, stale Trip
version/status, canonical fare/Payment amount agreement, receipt
amount/currency/timestamp, logout and A→B→A session replacement, and completed
Trip receipt/refund presentation without checkout. Fourteen adapter tests and
additional controller regressions were authored.

Flutter and Dart were unavailable in the implementation environment, so
these tests, formatting, and analyzer were **not run**. `git diff --check` was
run before the local commit.

Windows verification commands:

```powershell
flutter test --no-pub --concurrency=1 test/rider_a04_financial_read_adapter_test.dart
flutter test --no-pub --concurrency=1 test/rider_checkout_controller_test.dart
flutter test --no-pub --concurrency=1 test/rider_checkout_handoff_test.dart
flutter test --no-pub --concurrency=1 test/rider_checkout_panel_test.dart
flutter test --no-pub --concurrency=1 test/rider_checkout_provider_test.dart
dart format --output=none --set-exit-if-changed lib/features/rider_payments/data/a04_rider_financial_read_adapter.dart lib/features/rider_payments/application/rider_checkout_controller.dart lib/features/rider_payments/models/rider_checkout_state.dart test/rider_a04_financial_read_adapter_test.dart test/rider_checkout_controller_test.dart test/rider_checkout_handoff_test.dart test/rider_checkout_panel_test.dart test/rider_checkout_provider_test.dart
flutter analyze --no-pub
git diff --check
```
