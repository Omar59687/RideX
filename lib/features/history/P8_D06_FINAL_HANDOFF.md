# RideX Phase 8 — Sanad / P8-D Final Handoff

## Scope & review status
- Branch: `feature/p8-d06-history-integration-handoff`, built on D05 -> D04 -> D03 -> D02 -> D01. All five prior checkpoints had **48 focused Flutter tests passing** and zero focused analyzer issues on Sanad's Windows checkout. **D06 test and fresh full-suite evidence remain pending.**
- Production app integration **has not happened**: canonical history is not yet wired to the global Router or existing mock history route. No hosted Rider/Driver actor test has been run.
- The new feature-local `RiderHistoryIntegrationBundle` is the **single injection point**; it composes three independent adapters and one authorization/session boundary. No runtime configuration, credentials or demo fallback included.

## What Omar must wire (integration owner)
1. Build the bundle using the app's authenticated nonblocked Rider profile, application-owned Supabase client, trusted provenance, SDK session *object* and changing SDK epoch. Do not instantiate it with the constant test epoch.
2. Inject `history` into `CanonicalRiderHistoryList` and `bundle.details` into `CanonicalRiderTripDetail`. Only route to exact details with the canonical Trip ID returned from the authorized list.
3. On login/startup/reconnect/resume invoke `bundle.activeController.refresh(riderId)`. Navigate only for `RiderActiveRestoreStage.restored` with fresh session/Trip validation. `unavailable` requires retry, never speculative navigation.
4. On logout, SDK auth object replacement, account/role change, block, loss of trusted Supabase provenance: call `onAuthIdentityChanged()` and dispose/rebuild the bundle. Clear old history/detail widgets before navigation. A -> B -> A must not reuse old Rider snapshots.
5. Replace the Rider production mock-history path only **after** an approved participant-safe backend adapter exists. Keep explicit demo flows separate. Do not edit central router/global providers from Sanad's branch.
6. Protect against competing writes: a history row must never overwrite a fresher live canonical active Trip result. No payment/receipt success inference.

## What Yousuf must confirm (backend owner)
- `RiderTripHistoryRepository.readPage`: bounded (1..50) participant-scoped Trip read ordered by `created_at DESC, id DESC`; stable keyset cursor; strict Rider ID/Trip ID/booking ID/status and canonical fields, route labels, locked fare (JOD fils), time columns. No privileged client access.
- `readExactTrip`: exact canonical Trip + Rider filter; participant RLS; no silent fallback on denied/failed reads. All async paths must pin SDK session and require the same nonblocked Rider profile.
- `RiderActiveTripReadPort.findActiveCandidates(limit:2)`: include all four nonterminal backend statuses (`accepted`, `driverArriving`, `driverArrived`, `inProgress`), expose ambiguity. `rereadExact`: fresh exact Trip identity/status/version or timestamps.
- `RiderTripFinancialReadPort`: only from **backend-issued Trip↔Payment linkage** and separately participant-authorized Payment/Receipt RPCs. Do not derive Payment IDs, presume Cash paid, Card captured, refund or Receipt from Trip completion.
- Agree on missing pickup/destination/locked-fare contract; do not synthesize valid-looking defaults for missing financial evidence.
- Verify actual schema/read permissions before claiming production readiness.

## Security and behavior cases covered by feature-local tests
- Empty/page/cursor/dedup/sort/filter/retry/network failure, foreign-Rider denial and sanitized UI errors.
- Exact Trip ownership, blocked Rider, SDK epoch, missing payment ID, Card unknown, unverified receipt and cancellation.
- Active restoration: zero/multiple/foreign/terminal candidates, exact reread, A-B-A session switch, out-of-order requests and invalidation.
- D05 regression: reject contradictory or foreign terminal exact reread before returning no-active.
- D06: bundle composition, no inferred financial state, synchronous invalidation on account change.

## Commands for reviewer (Sanad's checkout)
```powershell
git fetch origin
git switch feature/p8-d06-history-integration-handoff
flutter test test/p8_d01_rider_trip_history_contract_test.dart test/p8_d02_canonical_rider_history_list_test.dart test/p8_d03_exact_trip_detail_test.dart test/p8_d04_active_trip_restoration_test.dart test/p8_d05_history_privacy_regression_test.dart test/p8_d06_history_handoff_test.dart
flutter analyze lib/features/history/data lib/features/history/presentation/widgets/canonical_rider_history_list.dart lib/features/history/presentation/widgets/canonical_rider_trip_detail.dart
git status --short --branch
```

## Explicit restrictions / release gates
- No PR or merge without owner approval and independent reviewer.
- No hosted migration, deployment, privileged secrets, Card dispatch or financial mutation here.
- Focused fake tests are **not** hosted acceptance. Real Supabase actor and device acceptance, app navigation/resume tests, backend shape validation and full-suite/CI review remain required.
- Preserve user's unrelated dirty local `analysis_options.yaml`, `pubspec.lock` and generated Flutter registrants, without resets/stashes/commits.
