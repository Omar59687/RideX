# Android Rider Demo smoke test

Uses Flutter's official `integration_test` binding and `flutter drive` runner.
The test calls the real `lib/main.dart` entrypoint and uses the app's existing
unconfigured Demo repositories, navigation, validation and UI controls. It does
not use provider overrides, injected booking states or coordinate taps.

## Run locally

Use **Flutter 3.35.3 / Dart 3.9.2**, which matches the committed SDK-pinned
dependencies. Invoke it explicitly; do not change global PATH. Start an existing
Android emulator first and confirm its device ID. From the repository root:

```powershell
$sdkFlutter = Join-Path $env:LOCALAPPDATA 'RideXSDKs\flutter-3.35.3\flutter\bin\flutter.bat'
& $sdkFlutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw 'Dependency compatibility check failed.' }

$evidenceRoot = Join-Path $env:TEMP ('ridex-demo-smoke-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
foreach ($run in 1..2) {
    $env:RIDEX_SMOKE_OUTPUT_DIR = Join-Path $evidenceRoot "run-$run"
    New-Item -ItemType Directory -Path $env:RIDEX_SMOKE_OUTPUT_DIR -Force | Out-Null
    & $sdkFlutter drive --no-pub -d emulator-5554 `
        --driver=test_driver/rider_demo_smoke_driver.dart `
        --target=integration_test/rider_demo_smoke_test.dart
    if ($LASTEXITCODE -ne 0) { throw "Smoke run $run failed." }
}
```

The host driver writes five screenshots and `result.json` outside the checkout.
If the output environment variable is absent, it creates a unique system-temp
directory and prints the path. Capture runner stdout/stderr externally if logs
are needed. Do not supply backend, Maps or credential dart-defines: the test
rejects configured environments before calling application bootstrap.

## Coverage and boundaries

- All onboarding slides and Continue; Demo Rider entry and Home.
- Destination no-results feedback followed by successful search recovery.
- Destination and pickup chosen through existing search/prediction controls.
- Incomplete selection disables continuation; a valid current route enables it.
- Economy and Standard selection; Cash -> Card -> Cash with selected semantics.
- Booking review retains Standard/Cash and the deterministic Demo fare.
- No misleading route warning; confirmation enabled but **never pressed**.
- Back navigation retains vehicle/payment; framework errors and overflows fail.
- Dark status-bar style on the current light Rider screens.

Finder polling and animation settling are bounded to ten seconds; the whole
test has a three-minute timeout. Scrolling uses widget finders and a bounded
number of gestures. Existing production keys are sufficient; no production
entrypoint or widget changes are needed.

Continue to run `test/onboarding_navigation_test.dart`,
`test/status_bar_contrast_test.dart`, `test/fare_estimate_screen_test.dart`,
`test/route_stops_test.dart`, `test/booking_stops_flow_test.dart` and
`test/rider_payment_selection_test.dart` for zero/small-height, dark-theme,
invalid-route, lock-recovery and payment-selection edge cases. The Android smoke
test covers the supported valid route, rather than replacing that focused suite.

Manual device inspection remains useful for actual system-bar visual contrast
and smoothness. No hosted Supabase, real authentication, Maps/GPS, completed
booking, matching, card processing or paid receipt is exercised or simulated.
The P6-09 compatibility harness is unchanged.
