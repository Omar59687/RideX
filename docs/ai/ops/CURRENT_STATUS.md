# Rider V2 Current Status

## Git Checkpoint

- Active branch: `feature/omar/rider-ui-v2`
- Base commit: `e374d86`
- Latest implementation commit: `b31ec2f`
- Position at documentation start: five commits ahead of `origin/main`

## Completed Phases

| Commit | Completed phase |
|---|---|
| `781b437` | Urban Aurora theme, semantic tokens, dark mode, and motion |
| `a015caa` | Shared RideX V2 components, SVG runtime assets, and native map painter |
| `eed7155` | Rider authentication, real email flow, and mock-only phone/OTP |
| `5327cb7` | Rider home and destination-first booking flow |
| `b31ec2f` | Rider search, trip lifecycle, cancellation, completion, and rating |

**Do not redo, replace, or restart these five completed implementation phases.** Inspect them only when the next phase requires an integration point or a failing test identifies a regression.

## Verification Status

At `b31ec2f`, `flutter analyze` passed and all 21 non-live tests passed. Two live Supabase tests skipped because backend environment variables were absent. Existing SVG `<filter>` warnings in tests are informational.

## Exact Next Phase

Implement history/details, profile, notifications, and settings as one focused phase:

- Redesign `TripHistoryScreen` with loading, error, empty, completed/cancelled filters, and selected-trip navigation.
- Add `/history/:tripId` and a selected `TripDetailsScreen`.
- Redesign `RiderProfileScreen` using session data and honest unavailable-field treatment.
- Redesign `NotificationsScreen` while preserving `notificationsControllerProvider`.
- Redesign `SettingsScreen` with session-local push/SMS/email Riverpod state and real sign-out.
- Keep shared `/history` and `/settings` functional for drivers without redesigning driver screens.

Relevant files and state only:

```text
lib/app/router/app_router.dart
lib/app/router/route_names.dart
lib/core/mocks/mock_data.dart
lib/core/providers/session_providers.dart
lib/core/providers/repositories_providers.dart
lib/core/repositories/trips_repository.dart
lib/features/history/
lib/features/profile/presentation/screens/rider_profile_screen.dart
lib/features/notifications/presentation/screens/notifications_screen.dart
lib/features/settings/
lib/core/widgets/ride_x_bottom_navigation.dart
lib/core/widgets/settings_row.dart
lib/core/widgets/coming_soon_dialog.dart
```

Relevant routes/providers:

```text
/history
/history/:tripId
/rider/profile
/notifications
/settings
tripsRepositoryProvider
sessionControllerProvider
bookingControllerProvider
notificationsControllerProvider
```

## Remaining Phases

1. History/details, profile, notifications, and settings.
2. Responsive, accessibility, route, provider, theme, and driver regression test pass.
3. Bundle Plus Jakarta Sans and its official license after explicit download approval.
4. Final documentation, full verification, visual comparison, and cleanup.

## Font Status

Plus Jakarta Sans is configured as the intended family but font files and license are not bundled. Network download is not approved implicitly. Pause at the gate described in `DECISIONS.md`.

## Known Limitations

Phone OTP, maps/live location, booking/history persistence, card payments, promotions, rewards, calls/messages, safety services, saved-place persistence, notification persistence, and rating persistence are not production integrations. They must remain explicit demo, session-local, disabled, or Coming soon behavior.
