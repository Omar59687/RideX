# Project Context

## Product

RideX is a Jordan-focused ride-hailing graduation project. It covers rider and driver demos with future administration scope. Rider V2 is implemented as native Flutter UI; driver behavior remains preserved without a visual redesign.

## Technology

- Flutter/Dart
- Riverpod
- GoRouter
- Supabase Flutter
- `intl`, `equatable`, `flutter_animate`, `flutter_svg`, `google_maps_flutter`,
  and `geolocator`

## Important State And Data

| Area | Owner |
|---|---|
| Session, role, restoration, sign-out | `sessionControllerProvider` |
| Booking draft and selected ride | `bookingControllerProvider` |
| Foreground permission and current GPS point | `currentLocationControllerProvider` through the location repository |
| Pickup/destination place selection | `placeSelectionControllerProvider` through the configured place repository |
| Search and trip lifecycle | `activeTripControllerProvider` |
| Notifications | `notificationsControllerProvider` |
| Current profile | `currentProfileProvider` through the configured profile repository |
| Driver availability | Session-local `driverOnlineProvider` |
| Repository selection | `repositories_providers.dart` |
| Email authentication/profile | Supabase repositories and services when configured |
| Booking, matching, trips, history | Deterministic mock repositories |

Important public routes include `/sign-in`, `/sign-up`, `/forgot-password`, and `/verify-otp`. Rider and shared routes include `/rider/home`, `/rider/destination`, `/rider/pickup`, `/rider/vehicle`, `/rider/fare`, `/rider/searching`, `/rider/trip`, `/rider/completed`, `/rider/rating`, `/history`, `/history/:tripId`, `/rider/profile`, `/notifications`, and `/settings`. Driver routes remain guarded by role and approval state.

## Supported Versus Demo

When Supabase is configured, real behavior covers email/password authentication, session restoration, profile role data, blocked state, driver approval state, and sign-out. Without configuration, authentication and profile data use deterministic mock repositories.

Google Maps/foreground GPS and place-search/geocoding foundations are
implemented, with Mock repositories used by ordinary automated tests.
Checkpoints 4A and 4B are approved after final routing-guard regression coverage
and project-owner-reported completion of all remaining physical/live checks.
Upfront fares, driver matching, trip transitions, history,
notifications, phone OTP, ratings, and most profile/settings data remain mock,
session-local, or presentation-only. Profile identity is repository-backed,
while profile editing, ride statistics, rewards, saved places, and payment
methods remain unavailable or presentational. Unsupported controls must explain
that limitation.

## Design References

The curated Urban Aurora package is under `references/UI/`. `references/UI/tokens/ridex-v2-tokens.json` is the token authority. Runtime identity copies live under `assets/branding/`; reference originals remain unchanged. Official Plus Jakarta Sans static weights 400 through 800 and `OFL.txt` are bundled under `assets/fonts/`.

## Constraints

- Preserve architecture and backend behavior.
- Do not introduce HTML/WebView. Preserve the approved Phase 4 Google Maps,
  location, and place-service boundaries.
- Do not fabricate persistence or production integrations.
- Keep V2 screens modular, responsive, accessible, dark-theme aware, and reduced-motion aware.
- Driver screens are outside visual scope but require regression tests.
