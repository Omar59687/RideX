# P8-D04 — Safe Rider Active Trip Restoration (Sanad)

## What is implemented
- `RiderActiveTripRestorer.restore(riderId)` is read-only: discover at most two owner-scoped canonical nonterminal Trips; if there are two, fail closed. Zero means no active Trip.
- Exactly one candidate is followed by a **fresh** exact-ID Trip read. Terminal or vanished record means no active Trip; foreign, contradictory, stale or ambiguous responses fail closed. Never resume from a history row alone.
- Session and authorization are verified before and after each await. `sessionEpoch()` **must** be a changing SDK session-object/generation token, including A→B→A.
- `RiderActiveTripRestoreController.refresh()` invalidates overlapping older responses; `invalidate()` clears previous Trip immediately on logout, account switch, auth/SDK epoch change, blocked status, etc.

## Backend contract for Yousuf
Implement `RiderActiveTripReadPort` using only authorized Rider-owned reads and an authenticated/active/nonblocked Rider profile:
1. `findActiveCandidates(riderId, limit: 2)`: bounded query for **all** nonterminal Trip states (`accepted`, `driverArriving`, `driverArrived`, `inProgress`), ordered deterministically; must return 2 when more than one qualifies, never silently pick first. RLS is the authority.
2. `rereadExact(riderId, tripId)`: precise Trip ID and Rider filter, with participant RLS, fresh status and `updated_at`. Parse canonical IDs and values strictly.
3. Pin SDK session object and auth/profile across awaited calls. Read failures or uncertain results must not be reported as empty.
4. No write RPC, financial state inference, receipt claim, or privileged client keys.

## Runtime handoff to Omar
- Wire startup/login/resume/reconnect through the owner-authenticated Rider provider, and call `invalidate()` synchronously on logout, Rider account switch, role/blocked change or SDK auth epoch change.
- Only navigate after `RiderActiveRestoreStage.restored` with a freshly verified Trip ID and a still-current session. Keep router/global providers untouched here.
- When `unavailable`, provide a user-triggered retry instead of assuming no trip. Do not auto-navigate on uncertain/multiple records.
- This slice has **no app runtime injection or hosted actor verification**. Required integration and hosted acceptance remain pending.

## Validation
```powershell
flutter test test/p8_d01_rider_trip_history_contract_test.dart test/p8_d02_canonical_rider_history_list_test.dart test/p8_d03_exact_trip_detail_test.dart test/p8_d04_active_trip_restoration_test.dart
flutter analyze lib/features/history/data lib/features/history/presentation/widgets/canonical_rider_history_list.dart lib/features/history/presentation/widgets/canonical_rider_trip_detail.dart
git status --short --branch
```

No PR, merge, migration or hosted deployment in this checkpoint.
