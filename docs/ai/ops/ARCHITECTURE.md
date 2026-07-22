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
- `ActiveTripController`: current `MockTrip` and validated `TripStatus` transitions.
- `NotificationsController`: session notification list.
- New settings preferences remain session-local Riverpod state.
- `currentProfileProvider`: repository-backed identity for the active session.
- `driverOnlineProvider`: session-local driver availability.

Widgets read providers; they do not duplicate durable booking or trip state locally.

## Router

`lib/app/router/app_router.dart` owns routes. `route_guards.dart` protects public/private, rider/driver, blocked, and driver-approval states. Existing paths are preserved. V2 added `/verify-otp` and `/history/:tripId`. Bottom navigation uses `context.go()`. Do not introduce `StatefulShellRoute` in this project phase.

## Theme

- `app_colors.dart`: Urban Aurora primitives and compatibility aliases.
- `app_theme.dart`: complete Material light/dark themes.
- `ridex_theme.dart`: `ThemeExtension` for route, map, gradient, shadow, and custom semantic roles.
- `app_text_styles.dart`, `app_spacing.dart`, `app_radii.dart`, `app_motion.dart`: reusable roles.
- `RideXApp` uses `ThemeMode.system`.

## Components And Assets

Shared components live in `lib/core/widgets/`. Rider-specific compositions live under each feature's `presentation/widgets/`. Runtime SVGs are in `assets/branding/` and rendered with `flutter_svg`. Official Plus Jakarta Sans static weights 400 through 800 and `OFL.txt` are bundled under `assets/fonts/`.

## Tests

Tests live under `test/`, with shared repository overrides in `test/helpers/test_app.dart`. Existing coverage includes launch, onboarding, roles, auth V2, booking, provider fares, trip lifecycle, driver acceptance, transition rules, route/session state, and conditional live Supabase checks. See `CURRENT_STATUS.md` for the latest exact verification results.

## Do Not Rewrite

- `lib/main.dart` and bootstrap behavior
- Supabase repositories, services, and migrations for visual work
- Core repository contracts without explicit approval
- Session guards, role behavior, and sign-out semantics
- Curated files under `references/UI/`
- Driver screens during Rider V2 visual work
