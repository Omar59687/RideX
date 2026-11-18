# P8-D05 — History resilience and privacy checkpoint (Sanad)

## Source changes
- Hardened active restoration: terminal rereads must first match exact Rider, Trip and Booking identities and be no older than the discovered record. A foreign/contradictory terminal row is an invalid response, **not** a harmless no-active result.
- Added tests for foreign read rows, sanitized backend errors, missing route labels, bounded history requests, terminal states, stale terminal version and financial unavailable display.
- Tests are fake/feature-local. No Supabase hosted, user-session/device or financial acceptance is claimed.

## Runtime rules for Omar integration
- The real history adapter must enforce participant RLS and current SDK/app Rider identity before/after each asynchronous read, and invalidate all read work on session-object/epoch change (including A→B→A).
- An authenticated Rider must not receive a second Rider's Trip/payment/receipt/driver details; fail closed rather than return a plausible empty list.
- Never promote a cached/history Trip to an active Trip. Restoration requires the independent active-candidate read and fresh exact-ID reread. A page row must not overwrite a newer canonical Trip.
- A backend error must never load demo history; retries must maintain pagination cursor, and duplicate Trip IDs must not create duplicate cards.
- Don't infer settlement, Card capture/refund or Receipt issuance from terminal status or a locked fare. Preserve unknown and unsupported financial states.
- The existing `CanonicalRiderHistoryList` has a Rider-ID callback gate but no SDK epoch injection. Its production composition needs a session-epoch-aware repository and widget replacement/invalidation on any SDK epoch change; it is not hosted-ready by itself.
- Pagination and exact detail still require a production read adapter and validated actual backend shape. No direct finance-table SELECT or privileged key.

## Validation (user's Windows checkout)
```powershell
git fetch origin
git switch feature/p8-d05-history-resilience-privacy
flutter test test/p8_d01_rider_trip_history_contract_test.dart test/p8_d02_canonical_rider_history_list_test.dart test/p8_d03_exact_trip_detail_test.dart test/p8_d04_active_trip_restoration_test.dart test/p8_d05_history_privacy_regression_test.dart
flutter analyze lib/features/history/data lib/features/history/presentation/widgets/canonical_rider_history_list.dart lib/features/history/presentation/widgets/canonical_rider_trip_detail.dart
dart format --output=none --set-exit-if-changed lib/features/history/data/rider_active_trip_restoration.dart test/p8_d05_history_privacy_regression_test.dart
git status --short --branch
```

**Pending:** test execution and formatting validation; independent review; Omar's shared runtime integration; Yousuf's backend read shape/permissions review; approved real Rider acceptance. No PR, merge, database mutation or deployment performed.
