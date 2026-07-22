# Project Context

## Product

RideX is a Jordan-focused ride-hailing graduation project. It covers rider and driver demos with future administration scope. Current implementation work targets the Rider V2 native Flutter interface; driver behavior must remain stable.

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
| Repository selection | `repositories_providers.dart` |
| Email authentication/profile | Supabase repositories and services when configured |
| Booking, matching, trips, history | Deterministic mock repositories |

Important routes include `/sign-in`, `/verify-otp`, `/rider/home`, `/rider/destination`, `/rider/pickup`, `/rider/vehicle`, `/rider/fare`, `/rider/searching`, `/rider/trip`, `/rider/completed`, `/rider/rating`, `/history`, `/rider/profile`, `/notifications`, and `/settings`.

## Supported Versus Demo

Real Supabase behavior covers email/password authentication, session restoration, profile role data, blocked state, driver approval state, and sign-out.

Booking locations, upfront fares, driver matching, trip transitions, history, notifications, maps, phone OTP, ratings, and most profile/settings data are mock, session-local, or presentation-only. Unsupported controls must explain that limitation.

## Design References

The curated Urban Aurora package is under `references/UI/`. `references/UI/tokens/ridex-v2-tokens.json` is the token authority. Runtime identity copies live under `assets/branding/`; reference originals remain unchanged.

## Constraints

- Preserve architecture and backend behavior.
- Do not introduce HTML/WebView or a map SDK.
- Do not fabricate persistence or production integrations.
- Keep V2 screens modular, responsive, accessible, dark-theme aware, and reduced-motion aware.
- Driver screens are outside visual scope but require regression tests.
