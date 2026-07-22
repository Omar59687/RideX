# Rider V2 Current Status

## Git Checkpoint

- Active branch: `feature/omar/rider-ui-v2`
- Base commit: `e374d86`
- Latest implementation commit: `a39aeee`
- Position after the regression checkpoint: 15 commits ahead of `origin/main`

## Completed Phases

| Commit | Completed phase |
|---|---|
| `781b437` | Urban Aurora theme, semantic tokens, dark mode, and motion |
| `a015caa` | Shared RideX V2 components, SVG runtime assets, and native map painter |
| `eed7155` | Rider authentication, real email flow, and mock-only phone/OTP |
| `5327cb7` | Rider home and destination-first booking flow |
| `b31ec2f` | Rider search, trip lifecycle, cancellation, completion, and rating |
| `9021f6a` | Rider trip history, repository-backed details, filters, and rebooking |
| `f3a35aa` | Repository-backed rider profile, disabled previews, and real sign-out |
| `96d7db9` | Rider notifications, session-local preferences, settings, and driver preservation |
| `a39aeee` | Responsive, accessibility, route, provider, theme, and driver regression pass |

**Do not redo, replace, or restart these nine completed implementation phases.** Inspect them only when the next phase requires an integration point or a failing test identifies a regression.

## Verification Status

At `a39aeee`, `dart format lib test` and `flutter analyze` passed, the focused regression set passed with 44 tests, and the full non-live suite passed with 47 tests and 2 intentional live Supabase skips. Coverage now includes the rider/driver guard matrix, booking and trip continuity, sign-out state isolation, 390x844 large-text reduced-motion rider flow, 430x932 dark rider tabs, bottom-navigation semantics and targets, and the complete preserved driver trip lifecycle. The pass fixed large-text overflows in rider availability, route fields, vehicle cards, and driver history, plus driver notification contrast in dark mode.

## Exact Next Checkpoint

Bundle **official Plus Jakarta Sans font files and their license only**, after explicit network-download approval:

- Official source: `https://github.com/tokotype/PlusJakartaSans`.
- Required static weights: Regular 400, Medium 500, SemiBold 600, Bold 700, and ExtraBold 800, plus the official `OFL.txt` license.
- Add the files under `assets/fonts/`, declare the family and weights in `pubspec.yaml`, and verify representative text styles resolve to the bundled family.
- Do not use `google_fonts`, substitute font files, or download anything until the user explicitly approves network access.
- Run `dart format lib test`, `flutter analyze`, and all non-live tests before committing.
- Do not begin final documentation, visual comparison, or cleanup in this checkpoint.

Start with these files after approval:

```text
pubspec.yaml
lib/app/theme/app_text_styles.dart
assets/fonts/
test/rider_v2_adaptive_accessibility_test.dart
```

## Remaining Phases

1. Bundle Plus Jakarta Sans and its official license after explicit download approval.
2. Final documentation, full verification, visual comparison, and cleanup.

Complete exactly one checkpoint per resume. After its implementation commit, update this file with the commit hash, focused test results, limitations, and next checkpoint; commit that documentation update, confirm a clean worktree, and stop.

## Font Status

Plus Jakarta Sans is configured as the intended family but font files and license are not bundled. No network download was performed. Pause at the gate described in `DECISIONS.md` until the user explicitly approves downloading the five static weights and `OFL.txt` from the official Tokotype repository.

## Known Limitations

Phone OTP, maps/live location, booking/history persistence, card payments, promotions, rewards, calls/messages, safety services, saved-place persistence, notification delivery/persistence, and rating persistence are not production integrations. Notification read state, preferences, booking drafts, active trips, and driver availability are session-local and reset on sign-out. Unsupported behavior must remain explicit demo, session-local, disabled, or Coming soon behavior.
