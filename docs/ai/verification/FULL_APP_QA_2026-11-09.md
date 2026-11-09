# RideX bounded full-app QA ? 2026-11-09

## Scope and provenance

Developer: Moath. Base fetched from origin/main: `1aa60fa9b1d831d1d825bbb9f3c620450af257d5`.
The fetched tip equals the historical baseline; it was verified rather than assumed.
Branch: `qa/moath-full-app-20261109`, isolated worktree. Original checkout and its
`feature/p7-b04-driver-offer-actions` branch were preserved. No other worktree was overwritten.
Tested source commit: `13850dedfd64428b740833c2a52c9276e5a1569b`.
The following report/checkpoint commit changes documentation only.

Open PRs inspected: #127 Realtime/GPS (review-only, unverified live delivery),
#129 Driver workstream documentation, #130 offline CI. None was merged or changed.
This is bounded offline and single-device QA, not production or financial acceptance.

## Environment

Flutter 3.41.2, framework 90673a4eef; Dart 3.11.0; Windows 11.
Android SDK 36.1.0 / build-tools 36.1.0; JDK 21.0.9; flutter doctor: no issues.
Samsung Galaxy A71 SM-A715F, Android 13/API 33, arm64, authorized USB ADB.
Device screen: 1080x2400, density 420. Location coarse/fine grants were false.
No system accessibility settings, secrets, backend configuration or production data changed.
Flutter SDK resolution changed five SDK-pinned packages locally (characters, matcher,
material_color_utilities, meta, test_api). Tests used that SDK-compatible resolution;
committed lockfile and generated registrants are preserved. This is not an
`--enforce-lockfile` pass with Flutter 3.41.2.

## Confirmed defects and regression evidence

| Defect | Root cause | Resolution and evidence |
|---|---|---|
| P2: Android Back exits booking to launcher | Home booking entries used `go` on sibling top-level routes, replacing home | Three entries now use `push`. Native Profile reproduction saved destination/launcher XML and screenshots. System Back widget regressions cover Where to?, View all and saved destination. Native retest recorded below. |
| P3: obsolete stop-search empty/error feedback | Query edits retained feedback from the previous query; successful predictions did not replace it | Clear obsolete feedback and predictions on edit, preserving generation guards. New test failed before fix at empty?success and passes after fix; also checks empty?clear. |
| QA harness: smoke cannot return to lazy search field | Helper scrolled only forward using the first Scrollable, which can be a text field | Select vertical page, reset to start, then locate/scroll deterministically. Initial physical run failed with `Bad state: No element`; repeated repaired Debug runs passed. |

No repository/provider/backend rewrite, financial transition, activation flag or authorization bypass.

## Test matrix

PASS means the specified automated scope passed, not hosted end-to-end acceptance.

| Area | Status | Evidence / boundary |
|---|---|---|
| Startup, onboarding slides/Continue, Demo sign-in and Rider home | PASS | Real main entrypoint on A71 Debug; native Profile startup; onboarding/auth widget tests |
| Authentication role boundaries, blocked/malformed profiles, session restoration/revocation/sign-out | PASS offline | Full session/route/auth unit and widget suites; real hosted credentials not used |
| Destination empty/invalid search, successful search and selection | PASS Mock | A71 typed no-match?Abdali selection; place controller/repository and booking tests |
| Intermediate stops, order/limits/duplicates/remove/clear | PASS Mock | Focused stop suites; A71 add/clear and empty-search recovery |
| No Maps key / map-off fallback | PASS | A71 fallback rendered; map configuration and camera failure tests |
| Real configured map rendering, Places and Routes | BLOCKED BY CONFIGURATION | No approved Maps/backend configuration supplied to this isolated run |
| Route presentation and pickup resolution | PASS Mock | Route-ready shown on A71 and full route rendering/controller/repository tests |
| Booking entry/review and incomplete selection guards | PASS Mock | Physical confirmation guards, Cash/Card selection, route-ready and review; never submitted |
| Searching/cancellation, navigation, stale/UNKNOWN behavior | PASS offline | Booking/search/cancellation/lifecycle unit/widget suites; no real matching request |
| Android Back from home booking entry | FAIL?FIXED | Native Profile exit reproduced; three widget regressions and physical retest |
| Driver Home/availability | PASS offline | Driver Home/location-sharing + B01/B02 tests; no physical Driver sign-in |
| Incoming offers, Accept/Decline, expiration/stale offers | PASS offline | B03/B04 tests; fake/simulation only, default-off guards preserved |
| Driver trip presentation/nonfinancial progression | PASS offline | B05 controller/screen tests; no canonical ride progressed |
| Driver UNKNOWN/auth-loss/background/resume | PASS offline | Driver regression cases including remount and expiry; no physical Driver scenario |
| Cash completion stop gate/payment-receipt separation | PASS offline | B06 and canonical completion/read-only regression suites; no payment or receipt issued |
| Light/dark, phone/tablet/landscape, large text | PASS widget scope | Adaptive suite includes 320x568?430x932, landscape and tablet bounds; 1.3/2.0 scale |
| Keyboard, scrolling, loading/empty/error/retry | PASS covered scope | Widget suites and physical Debug search/scroll/selection; not every screen/device permutation |
| Accessibility semantics/targets | PASS automated | Existing semantics/target tests; manual TalkBack NOT TESTED |
| Native Profile Back/background/resume/relaunch | See physical results | Mock has no durable authenticated session; process relaunch returns to onboarding |
| Profile integration text injection | FAIL automation | Timeout waiting for empty-search message after injected input; no app crash proven |
| Production Rider?Driver, hosted acceptance/two phones | BLOCKED BY CONFIGURATION / NOT TESTED | Current integration branches/approved fixtures and owner acceptance required |
| Stripe/Card, real Cash completion/settlement/receipt | INTENTIONALLY DISABLED / NOT TESTED | No financial operation, canonical matching or hosted mutation attempted |

## Maps investigation

The exact text originates in `lib/core/widgets/ride_location_selection_map.dart`.
`mapAvailable` requires supported Android/iOS plus `mapConfigurationProvider == true`.
`GOOGLE_MAPS_ENABLED` defaults false. When enabled, `GoogleRideMapService` calls
`ridex/maps_configuration`; Android checks nonblank `com.google.android.geo.API_KEY`.
Gradle obtains its key from `GOOGLE_MAPS_API_KEY` dart-define or local `MAPS_API_KEY`.
A nonblank key check does not establish valid key authorization or successful tiles.
No flag/key was enabled or inserted by this audit.

Place search is independent of map rendering: without backend configuration,
`MockPlaceRepository` supplies fixed Jordan places; with configured Supabase it
uses `GooglePlaceRepository` through `SupabasePlaceService`. Routes have analogous
Mock/service selection. Thus Maps OFF is expected in ordinary Mock runs and search
still works in that configuration. The fallback sentence is accurate for the tested
Mock path, but does not promise availability of a configured hosted Places service.
Existing error/retry presentations handle search failure. No valid real configured
map/search path was executed, so no real Maps defect or success is claimed.

## Verification commands and results

- Baseline `flutter test --concurrency=1`: 2423 passed, 0 failed, 2 intentional live skips.
- Stop/place/map focused run: 58 passed.
- Explicit Driver B01?B06 contract/controller/screen run: 468 passed.
- Final navigation/route-guard/adaptive/stop focused run: 37 passed.
- Intermediate full suite after stop fix: 2424 passed, 0 failed, 2 skipped.
- Final full suite: **2427 passed, 0 failed, 2 intentional live skips**, 4:10 elapsed.
  Four added regressions explain the increase of four over the 2423 baseline.
- Scoped analyzer: five changed Dart files, no issues (exit 0).
- Full analyzer: exit 1, eight infos, zero warnings/errors, same as baseline.
- Changed Dart formatting: five files, zero changes (exit 0). Git whitespace checks pass.

The eight existing infos are initializing-formal suggestions in
rider_live_map_projection (1) and rider_driver_vehicle_details_card (2), deprecated
RadioListTile members in canonical_ride_searching_screen (2) and its test (1),
and deprecated containsSemantics in adaptive accessibility tests (2).
No global analysis-green claim is made.

## Physical results and artifacts

External evidence directory: `ridex-qa-evidence-20261109` under the local system
Temp directory. It is deliberately outside Git; machine paths/logs/screenshots
are not staged. Host runner saves six screenshots and result JSON per expanded
Debug run. Logs include the original failure, repaired run, expanded run and
post-navigation-fix repeat. All stop at booking review without pressing confirmation.

Final expanded Debug run: PASS. Native normal Profile run: PASS startup, destination
entry, Android Back to home, Home/background/resume and force-stop/relaunch to onboarding.
A supplemental native Profile search script could not assert the empty message from
UIAutomator XML, although screenshot inspection confirms it is visibly correct.
Native input then produced an Abdali Mall result. Native selection and Android Back
to Rider home both passed (`native-profile-select.log`); screenshots retain each state.
Profile `flutter drive` failed at its empty-search wait after text injection;
its partial screenshots/log are retained. It must not be counted as a pass.
Native UI automation uses observed accessibility labels/bounds, not hardcoded taps.
No TalkBack or system accessibility changes were performed.

## Performance findings

- Skipped frames: startup warnings observed in Debug and instrumented Profile.
  Profile cannot be classified as smooth from these logs. Concurrent host testing,
  instrumentation and cold startup are confounders. No controlled frame-timing
  benchmark or improvement claim; production performance remains NOT TESTED.
- SVG `<filter/>`: confirmed unsupported feature in runtime
  `assets/branding/ridex-app-icon.svg` (shadow). Nonfatal; existing rendering skips
  the filter. Cosmetic limitation retained; no speculative branding redesign.
- `libpenguin.so`: no app/library reference found in lib/android/pubspec; historical
  warning reproduced in normal Profile logcat from Android `BufferQueueProducer`
  in the app process. Graphics/vendor-stack origin is an inference from that tag,
  not proven library provenance. Native interaction continued; no crash or missing
  RideX-owned library was demonstrated. No source-level fix is justified.
- Build warns about Gradle/AGP/Kotlin support age and Java 8 source/target; builds
  succeeded. Dependency modernization is separate work.

## Independent review

Separate Astra High read-only reviews of both stop/search and navigation changes:
no blocking findings. Reviewed source, tests and available logs; did not independently
rerun tests or operate hosted services/phone. Retained home map/listener means
configured Maps/GPS lifecycle/performance still requires configured acceptance.

## Remaining work, severity and owner

1. P1 release acceptance: Rider/Driver integration owners must validate approved
   Realtime/GPS adapters, real two-phone offer/lifecycle and auth-loss acceptance.
   This audit never promotes fake tests to production authority.
2. P1 financial acceptance: payment/backend owners retain R01/R02/R03/R07 gates;
   no Cash completion/receipt or Stripe activation is authorized here.
3. P2 QA: reproduce Profile integration text-input timeout with a minimal harness;
   compare native Profile search and capture controlled warm frame timings.
4. P2 configured QA: owner supplies approved Maps/Places/Routes configuration for
   real map/search/GPS and retained-home lifecycle verification.
5. P3 accessibility/visual: manual TalkBack and unsupported SVG shadow fidelity.
6. P3 maintenance: eight analyzer infos and Android dependency/toolchain warnings.

## Delivery history

- `13850dedfd64428b740833c2a52c9276e5a1569b`: focused source/test/smoke fix commit.
- Following documentation commit records this report and current checkpoint.
- PR is linked in the delivery response; no merge performed.

Files changed: two app Dart files (`stops_section`, `rider_home_screen`), two widget
test files (`booking_stops_flow_test`, `rider_booking_flow_test`), integration smoke
and its README, this report and `CURRENT_STATUS.md`. No lockfile, generated files,
curated references, backend contracts, secrets or migrations are included.
