# Project Context

## Product

RideX is a Jordan-focused ride-hailing graduation project. It covers rider and driver demos with future administration scope. Rider V2 is implemented as native Flutter UI; driver behavior remains preserved without a visual redesign.

## Technology

- Flutter/Dart
- Riverpod
- GoRouter
- Supabase Flutter
- `intl`, `equatable`, `flutter_animate`, and `flutter_svg`

## Important State And Data

| Area | Owner |
|---|---|
| Session, role, restoration, sign-out | `sessionControllerProvider` |
| Booking draft and selected ride | `bookingControllerProvider` |
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

Booking locations, upfront fares, driver matching, trip transitions, history, notifications, maps, phone OTP, ratings, and most profile/settings data are mock, session-local, or presentation-only. Profile identity is repository-backed, while profile editing, ride statistics, rewards, saved places, and payment methods remain unavailable or presentational. Unsupported controls must explain that limitation.

## Design References

The curated Urban Aurora package is under `references/UI/`. `references/UI/tokens/ridex-v2-tokens.json` is the token authority. Runtime identity copies live under `assets/branding/`; reference originals remain unchanged. Official Plus Jakarta Sans static weights 400 through 800 and `OFL.txt` are bundled under `assets/fonts/`.

## Constraints

- Preserve architecture and backend behavior.
- Do not introduce HTML/WebView or a map SDK.
- Do not fabricate persistence or production integrations.
- Keep V2 screens modular, responsive, accessible, dark-theme aware, and reduced-motion aware.
- Driver screens are outside visual scope but require regression tests.
