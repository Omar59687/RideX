# Phase 4C Routing Implementation Verification

Date: 2026-09-16

## Status

Checkpoint 4C is **approved**. Automated Flutter and Deno evidence passes, and
the deployed authenticated Google routing flow is verified on physical Android.

## Implemented Scope

- Provider-neutral route request, result, status, state, error, service, and
  repository contracts.
- Deterministic Mock routing and configured Supabase routing without production
  fallback to Mock after failure.
- Google encoded-polyline decoding and strict geometry/metric validation.
- A central Riverpod route controller that observes canonical booking state,
  coalesces synchronous endpoint writes, invalidates old results immediately,
  retries safe failures, and rejects stale responses.
- Provider-neutral geometry handoff to the shared selection map, with Google SDK
  polyline construction and route-bounds fitting isolated in the adapter.
- Service-backed distance/duration presentation and fail-closed pickup, vehicle,
  fare, and searching progression.
- Ordered intermediate points in the stable request contract, with non-empty
  lists rejected for Checkpoint 4C.
- An authenticated `route` operation in the existing Supabase `places` Edge
  Function using a separate `GOOGLE_ROUTES_API_KEY` and the approved Routes API
  v2 request policy.

No Fare Quote, fare calculation, multi-stop execution, Driver matching/tracking,
GPS optimization, Checkpoint 4D/4E, or later-phase behavior was added.

## Automated Evidence

- Focused 4C plus booking-flow command: 15 passed.
- `test/rider_trip_lifecycle_test.dart`: 5 passed after explicitly initializing
  its direct-search fixture with a matching trusted route.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 144 passed, 2 intentional live-test skips.
- `git diff --check`: passed; only line-ending conversion warnings were emitted.
- `deno task test`: 23 passed, 0 failed.
- Temporary upstream diagnostic logging was removed, and only the `places` Edge
  Function was redeployed successfully after cleanup.
- Existing Rider booking and Driver regression tests remain green.

## Live And Physical Evidence

- Google Routes API v2 and the separate server-side `GOOGLE_ROUTES_API_KEY` are
  configured.
- The `places` Edge Function was deployed with JWT verification enabled.
- An authenticated Rider received a valid live Google route for the selected
  pickup and destination.
- Physical Android verification passed for polyline rendering, service-backed
  distance and duration, origin/destination identity, and recalculation after an
  endpoint change.

## Scope Note

Trip History still uses `MockTripsRepository` and `MockData.history()`, so it
shows static sample endpoints rather than the current booking. This is a known
booking/history persistence limitation, not a Checkpoint 4C routing defect or
approval gate. No History persistence work was added.

No credential value was modified, copied into tracked files, or committed.
