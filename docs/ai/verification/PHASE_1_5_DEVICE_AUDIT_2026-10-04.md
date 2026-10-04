# Phase 1–5 device regression audit — 2026-10-04

## Scope and evidence

Branch: `codex/phase-4f-evidence-hardening`; baseline: `9be82b6`.
Main is excluded. This is a targeted source review prompted by device failures,
not a certification that every Phase 1–5 requirement works. Screenshots show a
blank Google map, disabled location services, and a later destination screen
with intermediate stops but no committed final destination. Stops do not replace
the required destination.

## Implemented corrections

1. Repeating an in-flight autocomplete query no longer invalidates its own
   response and leaves search loading indefinitely.
2. Keyboard/button address submission synchronizes the visible field text to
   the provider before geocoding, including after an earlier selection.
3. Reverse-geocode failure retains the selected coordinate and clears stale
   uncommitted search text so the fallback pin can be used.
4. Pickup listens for app resume and rechecks GPS/permission. A refresh requested
   while an older location operation runs is queued rather than discarded.
5. Selection maps center on asynchronously available GPS when no endpoint or
   route has priority, including GPS arriving before the native controller.
6. Explicit new-booking actions on Rider Home reset draft and place-selection
   state. Editing/back navigation inside the current booking does not reset it.
7. Destination screen explains why intermediate stops alone cannot continue.
8. Successful draft persistence retains its new backend version even when the
   subsequent quote request fails, allowing retries with that saved version.
9. Fare lock blocks repeated submission; errors are no longer obscured by the
   existing quote. Quote expiry schedules a UI refresh and is checked on click.
10. Live mode ends at the locked fare with an explicit limitation; it no longer
    enters the deterministic mock driver-search flow. Demo behavior is separate.

## Verification status

- Added regression coverage for repeated pending autocomplete, visible-address
  submission, reverse-geocode fallback readiness, queued location refresh, and
  live fare locking without mock navigation. These tests are NOT yet run.
- Source diff/whitespace review only in this environment. Flutter/Dart, Deno,
  PostgreSQL, Android runtime and a physical test device are unavailable.
- Historical passing test counts in status documents do not validate this patch.
- No Cloud settings, backend deployment, secrets or existing migrations changed.

Required local gates after pulling (PowerShell, from repository root):

```powershell
flutter pub get
dart format lib/core/providers/location_providers.dart lib/core/providers/place_providers.dart lib/core/widgets/google_location_selection_map.dart lib/features/booking/presentation/screens/destination_selection_screen.dart lib/features/booking/presentation/screens/fare_estimate_screen.dart lib/features/booking/presentation/screens/pickup_selection_screen.dart lib/features/booking/presentation/widgets/location_search_panel.dart lib/features/rider_home/presentation/screens/rider_home_screen.dart test/current_location_controller_test.dart test/place_selection_controller_test.dart test/fare_estimate_screen_test.dart
flutter analyze
flutter test --no-pub
flutter run --dart-define-from-file=.env.json
```

Run existing documented Deno/SQL suites against a disposable local backend,
then authenticated staging checks; do not reset a hosted database.

## Blank native map — still open

The source includes the Android Maps manifest metadata and Internet/location
permissions. A nonempty key is not proof of successful native authorization.
Places search runs through a separate backend path; working Places search does
not prove the Android Maps SDK credential is valid. GPS permission is not needed
merely to display ordinary map tiles.

Check Maps SDK for Android enablement and billing in the key's Google Cloud
project. Android application restrictions must match `com.ridex.app` and the
SHA-1 of the certificate signing this installed build. Teammates' debug
certificates can differ. Keep native and server credentials appropriately
restricted; do not disable restrictions or put server secrets in Flutter.

Reference: https://developers.google.com/maps/documentation/android-sdk/get-api-key

With the blank map open, collect a small diagnostic excerpt locally:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat -d -s "Google Maps Android API" "Google Maps Android API v2"
.\android\gradlew.bat -p android signingReport
```

If the tag-filtered log is empty, inspect Android Studio Logcat around map launch.
Before sharing, remove API keys, tokens and personal location data. Share only
the authorization/error text, package name and signing SHA-1, not the full log
or `.env.json`. Rebuild after credential changes; hot reload is insufficient for
Android manifest changes. Continue using the working ASCII drive path on Windows.

## Remaining acceptance and audit work

- Repeat: select destination, back/cancel, start new trip, submit same address,
  select via prediction/map/GPS, and verify stops reset only on a new trip.
- Disable GPS, enter pickup, open Settings, enable GPS, return without restart;
  repeat with permission denied and permission granted. Verify map centering.
- Test valid/invalid native credential cases and network loss on physical Android.
- Test fare create/update/quote/lock against deployed Supabase, quote expiry,
  double taps, lost responses and version conflicts. Canonical reconciliation of
  an ambiguous successful lock response and post-lock editing remains open;
  this patch is not a full idempotency/recovery implementation.
- Re-run Phase 1–3 auth/roles/RLS and Phase 4 location/route/driver regressions;
  this targeted review does not establish that those systems are defect-free.
- Phase 4 task 4.38 remains deferred, not approved. Phase 5 is provisional and
  not complete. Real dispatch/matching is a later phase, not supplied by mocks.
