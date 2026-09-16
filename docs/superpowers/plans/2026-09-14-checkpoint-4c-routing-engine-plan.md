# Checkpoint 4C Routing Engine Implementation Plan

Date: 2026-09-14
Status: Verified and approved

## 1. Domain And Repository Boundary

- Add provider-neutral route request, result, status, and state models under
  `lib/core/models/` using `LocationPoint` and precise meters/seconds.
- Add sanitized route failures under `lib/core/errors/`.
- Add route service and repository contracts plus Supabase/Google and Mock
  implementations under `lib/core/services/routes/` and
  `lib/core/repositories/`.
- Decode and validate encoded provider geometry only inside the production
  repository.
- Add model/repository tests and deterministic route fakes.

## 2. Edge Function Route Operation

- Extend `supabase/functions/places/core.ts` with strict `route` validation,
  Routes API request policy, normalized response, and existing auth/rate/error
  behavior.
- Read a separate `GOOGLE_ROUTES_API_KEY` in
  `supabase/functions/places/index.ts` without changing existing credential
  boundaries.
- Replace the old unsupported-route expectation and add focused operation tests
  in `supabase/functions/places/core_test.ts`.

## 3. Route State And Provider Selection

- Select Mock or Supabase routing beside existing repository selection in
  `lib/core/providers/repositories_providers.dart`.
- Add a session-local route controller in `lib/core/providers/` that observes
  canonical booking endpoints, coalesces synchronous writes, recalculates,
  invalidates old results immediately, supports retry, and rejects stale results.
- Add controller tests for valid routes, endpoint changes, failure/retry, and
  out-of-order responses.

## 4. Map And Booking UI

- Extend the provider-neutral location-map builder with route geometry.
- Convert route points to Google `Polyline` and route bounds only inside
  `google_location_selection_map.dart`.
- Add a shared route status/metrics surface to pickup and destination selection.
- Require a ready route matching current endpoints before pickup, vehicle, fare,
  or searching progression.
- Add rendering-handoff, Google conversion, and progression tests.

## 5. Verification And Documentation

- Format only changed Dart files.
- Run focused Flutter tests, Edge Function tests if Deno is available,
  `flutter analyze --no-pub`, and `flutter test --no-pub`.
- Update `Plan.md`, Phase 4/current architecture documentation, README, and the
  4C specification with actual results and blockers.
- Do not approve 4C without evidence for every approval-gate item. Do not start
  4D, commit, or push.

## 6. Implementation Evidence

- Flutter domain, repository, controller, map-adapter, status, and fail-closed
  progression work is implemented.
- The authenticated `places` Edge Function contains the strict `route`
  operation and separate `GOOGLE_ROUTES_API_KEY` boundary.
- Focused 4C and booking-flow verification passed 15 tests.
- `flutter analyze --no-pub` reported no issues.
- The complete non-live Flutter suite passed 144 tests with 2 intentional
  live-test skips.
- `git diff --check` passed.
- The Deno `places` Edge Function suite passed 23 tests with 0 failures.
- Routes API and the separate server-side key are configured, and the deployed
  `places` function returned an authenticated live Google route.
- Physical Android verification passed for route geometry, polyline rendering,
  distance, duration, endpoint identity, and endpoint-change recalculation.
- Checkpoint 4C is approved. Mock-backed Trip History remains outside this
  routing checkpoint and is not approval evidence.
