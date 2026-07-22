# Rider UI V2 Plan

Implementation is complete on `feature/omar/rider-ui-v2`. See `docs/ai/ops/CURRENT_STATUS.md` for final verification and handoff details.

## Goal And Scope

Convert the approved Urban Aurora rider references into modular native Flutter UI while preserving Riverpod, GoRouter, Supabase email authentication, repositories, controllers, models, redirects, and backend behavior. Driver screens are regression-tested but not redesigned.

## Design Sources

Use all curated files under `references/UI/`:

- `RIDEX-V2-DESIGN.md`
- `ridex-rider-ui-v2.html`
- `ridex-v2-screen-gallery.html`
- `ridex-v2-brand-board.html`
- `ridex-v2-system.css`
- `ridex-v2-screens.js`
- `tokens/ridex-v2-tokens.json`
- Supplied SVG identity assets and gallery preview

The token JSON is the structural authority. References remain unchanged and are never embedded through WebView.

## Screen Mapping

| Experience | Flutter route/screen strategy |
|---|---|
| Authentication and registration | Existing `/sign-in` and `/sign-up`; email remains real |
| Phone and OTP | Mock-only phone UI and `/verify-otp`; unavailable in production mode |
| Home | `/rider/home` |
| Destination search | `/rider/destination` |
| Confirm pickup | `/rider/pickup` |
| Economy/Standard/Premium | `/rider/vehicle` |
| Booking review | Existing `/rider/fare` |
| Driver search | `/rider/searching` |
| Assigned and active trip | Existing `/rider/trip`, driven by `TripStatus` |
| Completion and rating | `/rider/completed`, `/rider/rating` |
| History and details | `/history`, approved `/history/:tripId` |
| Profile | `/rider/profile` |
| Notifications | `/notifications` |
| Settings | `/settings` |

Booking order is home, destination, pickup confirmation, ride, review, search, trip, completion, rating.

## Reusable Strategy

- Material `ColorScheme` plus `RideXTheme` extension for custom route, marker, gradient, map, shadow, and state tokens.
- Shared branded scaffold, buttons, fields, sheets, dialogs, status cards, route timeline, vehicle silhouette, map painter, driver card, rating control, settings rows, and bottom navigation.
- Feature-local widgets keep screens focused.
- Existing providers own session, booking, active trip, and notifications.
- Native `CustomPainter` supplies the stylized map; no map SDK.

## Implementation Phases

1. Urban Aurora theme, tokens, dark mode, motion, and runtime assets.
2. Shared RideX V2 components.
3. Rider authentication and demo-only phone/OTP.
4. Home and destination-first booking flow.
5. Search, assigned, active, cancellation, completion, and rating lifecycle.
6. Phase 6A: trip history and trip details only.
7. Phase 6B: rider profile only.
8. Phase 6C: notifications and settings only.
9. Responsive, accessibility, route, provider, and driver regression tests.
10. Official bundled Plus Jakarta Sans and license after download approval.
11. Documentation, final verification, and cleanup.

Each numbered item is a checkpoint. Complete, test, commit, update status, and stop before starting the next checkpoint.

## Acceptance Criteria

- Complete Urban Aurora light/dark themes with `ThemeMode.system`.
- No old green rider presentation or scattered palette values.
- Provider-derived route, category, fare, driver, and trip-state continuity.
- Safe areas, dynamic text, reduced motion, semantics, and at least 44x44 targets.
- Stable bottom navigation with `context.go()` and no `StatefulShellRoute`.
- No dead or misleading unsupported controls.
- Existing email authentication, guards, sign-out, and driver demo flow remain functional.

## Out Of Scope

Real phone OTP, SMS provider integration, Google Maps, GPS, routing, geocoding, live tracking, card processing, promotions, rewards, persisted saved places, persisted settings, call/message, safety services, and rating persistence. Present these as disabled, coming soon, or explicit deterministic demo behavior.

## Verification

- `dart format lib test`
- `flutter analyze`
- Focused widget/navigation/provider tests for each checkpoint
- Broader non-live tests only when shared behavior changes or during final verification
- Route guards, auth, booking, cancellation, trip states, history/details, settings, sign-out, and driver regression
- Light/dark, reduced motion, large text, approximately 390x844 and 430x932
- Visual comparison against the gallery and brand board
- Confirm no HTML, WebView, map SDK, temporary artifact, or unrelated change
