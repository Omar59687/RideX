# Architecture

## Important Structure

```text
lib/
├── app/
│   ├── app.dart, bootstrap.dart
│   ├── config/
│   ├── router/
│   └── theme/
├── core/
│   ├── models/, providers/, repositories/
│   ├── services/, mocks/, utils/
│   └── widgets/
└── features/
    ├── auth/, booking/, rider_home/, trips/
    ├── history/, profile/, notifications/, settings/
    └── driver_* and shared entry features
```

Feature folders currently emphasize presentation screens and feature-local widgets. Cross-feature state and data contracts remain under `core/`.

## State Ownership

- `SessionController`: authenticated user and role state.
- `BookingController`: pickup, destination, stops, category, distance, ETA, and upfront fare.
- `CurrentLocationController`: one-shot foreground permission and device-location state through the location repository.
- `DriverTrackingController`: explicit foreground Driver sharing intent,
  canonical availability/latest-location recovery, one GPS stream, exact-content
  deduplication, latest-pending write coalescing, canonical-state profile
  synchronization, ineligible-state resource shutdown and eligible-state
  restart, ordered publication, lifecycle/reconnection cleanup, and sanitized
  status for Driver Home.
- `PlaceSelectionController`: independent pickup/destination search, geocoding, and provisional/committed selection state through the place repository.
- `RouteController`: session-local trusted route state derived from canonical
  booking endpoints, with coalesced recalculation and stale-response rejection.
- `ActiveTripController`: current `MockTrip` and validated `TripStatus` transitions.
- `NotificationsController`: session notification list.
- New settings preferences remain session-local Riverpod state.
- `currentProfileProvider`: repository-backed identity for the active session.
- `driverOnlineProvider`: session-local driver availability.

Widgets read providers; they do not duplicate durable booking or trip state locally.

Phase 4 location flow preserves provider boundaries: Geolocator and Google
Maps types remain in services/widgets, `LocationPoint` and `RideLocation` remain
provider-neutral, and hosted place requests pass through the authenticated
Supabase `places` function. Routing uses provider-neutral `RouteRequest`,
`RouteResult`, and `RouteState` contracts; configured mode invokes the same
function's authenticated `route` operation, while only the Google map adapter
converts geometry to SDK polylines. Driver tracking uses a provider-neutral GPS
stream service, repository-owned canonical reads/RPC writes, and a Riverpod
controller that prevents duplicate streams and recovers canonical sequence
state. Task 4.24 adds movement filtering, redundant-write suppression,
latest-pending coalescing, and a tracking-card-local UI watch. Task 4.25 adds the
provider-neutral `DriverGpsTrackingConfig`: canonical `onTrip` state selects a
high-accuracy 10-meter/5-second profile, while canonical `available` and
`reserved` select a medium-accuracy 25-meter/20-second profile. The controller
can re-read canonical availability and replace a changed profile only after the
old stream is cancelled. Concurrent requests produce at most one trailing read,
and reconnect recovery is deferred until synchronization completes. The sync
request is retained when start or recovery is still reading canonical state. The
sync entry point also treats canonical `offline`, missing, or otherwise
ineligible availability as a stop boundary: it invalidates queued work, cancels
GPS, and disconnects tracking while retaining explicit sharing intent and latest
canonical metadata. A later explicit eligible sync re-reads canonical sequence
state, reconnects, and starts the appropriate profile. There is no polling or
Realtime availability subscription. Task 4.27 extends the same centralized
configuration with device and write-efficiency policy. `available` uses low
accuracy, 50-meter filtering/significance, 30-second minimum cadence, and a
two-minute maximum silence bound; `reserved` uses medium accuracy, 25 meters, 20
seconds, and one minute; `onTrip` preserves high accuracy, 10 meters, and five
seconds, with a 15-second maximum silence bound. The controller computes
provider-neutral great-circle movement and suppresses sub-threshold callbacks
until meaningful movement or the stream-driven silence bound. It adds no timer,
polling, canonical read, or subscription. Checkpoints 4A through 4D are
approved. Task 4.28 adds the provider-neutral
`DriverLocationValidationPolicy` before cadence/significance filtering and
state mutation. It requires usable accuracy, the existing
15-minute-old/5-minute-future RPC window, and strictly advancing source time. A
worse-accuracy candidate is rejected only when its displacement remains within
its own reported uncertainty radius; there is no arbitrary global accuracy cap.
Rejected fixes preserve the last accepted fix, recorded time, pending write,
sequence, and confirmed timestamp. Migration `024` adds a matching
non-advancing-`recorded_at` RPC rejection under the existing per-Driver row lock,
protecting canonical order across sessions. Tasks 4.29 and 4.30, matching, Rider
live-trip tracking, and continuous OS-background tracking remain later work.

## Router

`lib/app/router/app_router.dart` owns routes. `route_guards.dart` protects public/private, rider/driver, blocked, and driver-approval states. Existing paths are preserved. V2 added `/verify-otp` and `/history/:tripId`. Bottom navigation uses `context.go()`. Do not introduce `StatefulShellRoute` in this project phase.

## Theme

- `app_colors.dart`: Urban Aurora primitives and compatibility aliases.
- `app_theme.dart`: complete Material light/dark themes.
- `ridex_theme.dart`: `ThemeExtension` for route, map, gradient, shadow, and custom semantic roles.
- `app_text_styles.dart`, `app_spacing.dart`, `app_radii.dart`, `app_motion.dart`: reusable roles.
- `RideXApp` defaults to `ThemeMode.light`; `AppTheme.dark()` remains available for
  an explicitly selected preference.

## Components And Assets

Shared components live in `lib/core/widgets/`. Rider-specific compositions live under each feature's `presentation/widgets/`. Runtime SVGs are in `assets/branding/` and rendered with `flutter_svg`. Official Plus Jakarta Sans static weights 400 through 800 and `OFL.txt` are bundled under `assets/fonts/`.

## Tests

Tests live under `test/`, with shared repository overrides in `test/helpers/test_app.dart`. Existing coverage includes launch, onboarding, roles, auth V2, booking, provider fares, trip lifecycle, driver acceptance, transition rules, route/session state, route recalculation and rendering conversion, location permissions, map fallbacks, place selection/geocoding with fakes, and conditional live Supabase checks. See `CURRENT_STATUS.md` for the latest exact verification results.

## Do Not Rewrite

- `lib/main.dart` and bootstrap behavior
- Supabase repositories, services, and migrations for visual work
- Core repository contracts without explicit approval
- Session guards, role behavior, and sign-out semantics
- Curated files under `references/UI/`
- Driver screens during Rider V2 visual work
