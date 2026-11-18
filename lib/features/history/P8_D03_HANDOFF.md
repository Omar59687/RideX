# P8-D03 — Exact Rider Trip detail handoff (Sanad)

## Scope and trust
- Feature-local `RiderExactTripDetailReader.readExact(riderId,tripId)` rereads the requested canonical Trip; it does not use a latest-Trip shortcut.
- The production `RiderTripHistoryRepository` adapter must enforce participant RLS, authorized Rider profile (including `is_blocked = false`), SDK session-object/epoch pinning, and post-await checks. The callback gates in this coordinator are defense-in-depth, **not** substitutes for backend authorization.
- `RiderTripFinancialReadPort` may only be attached after Yousuf reviews typed, participant-scoped Trip↔Payment and independent Receipt reads. It requires a backend-issued Payment ID; there is **no** inferred payment ID from Booking ID or Trip ID.
- All reported financial success and receipt issuance remain **unverified** in the UI. Trip completion, cancellation, and locked fare are not settlement, capture, refund or receipt evidence.
- Driver/vehicle and precise location are intentionally not rendered: an approved participant-safe detail read supplying those fields has not been established in this feature slice.

## Omar integration boundary
- Inject the feature-local reader and current authenticated Rider gate when wiring the route, after review; don't edit `app/router/**`, shared providers, mock history or central repositories here.
- Never silently fall back to mock details after a production read failure.
- Use a *real* session epoch/object invalidation callback in the production composition: a static token cannot prevent A→B→A session reuse.
- Do not claim hosted acceptance from feature-local fake tests.

## Validation to run locally
```powershell
flutter test test/p8_d01_rider_trip_history_contract_test.dart test/p8_d02_canonical_rider_history_list_test.dart test/p8_d03_exact_trip_detail_test.dart
flutter analyze lib/features/history/data lib/features/history/presentation/widgets/canonical_rider_history_list.dart lib/features/history/presentation/widgets/canonical_rider_trip_detail.dart
```

No PR, merge, Supabase deployment or financial mutation in this checkpoint.
