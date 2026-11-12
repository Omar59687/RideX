# Sustained foreground Driver GPS fix

Base: `ca3e59d5de2dd99b63c6de0a3fce5df57e8f3718`.
Branch: `fix/moath/sustained-driver-gps`; existing branches/worktrees preserved.

## Diagnosis and implementation

The previous available-state collector used low accuracy and a 50 m movement
filter. Publication could suppress stationary observations for 120 seconds,
exceeding Matching's 60-second requirement. There was no independent device
refresh. Home's age label updated only during widget rebuilds. Relative accuracy
filtering could additionally starve valid stationary fixes after a better fix.

The existing Geolocator adapter now feeds its native stream and one bounded
fresh-device request every 20 seconds into the same foregroundFixes stream.
The existing controller remains the only publisher and sequence owner. Native
and Dart request deadlines are 10 seconds; only one snapshot is pending. Cancel,
pause and lifecycle/session generation fences discard late observations. Failed
refreshes grant no evidence; retries remain bounded. Actual device timestamps are
preserved. Snapshots reject observations older than 30 seconds, over 5 seconds in
the future, or with missing/invalid/nonpositive/over 50 m accuracy.

Available/reserved collection uses high accuracy and no movement filter. Minimum
publication spacing is 10 seconds and the stationary heartbeat threshold is 15
seconds; active-Trip policy is unchanged. A due heartbeat can bypass only relative
accuracy regression, with strictly newer, fresh, positive accuracy <=50 m evidence.
Other validation, ordering, authority and association checks remain unchanged.

Automatic Android observations use AndroidSettings(forceLocationManager: true)
for both the native stream and snapshots. Service/permission prechecks remain.
This avoids the Fused client settings-resolution dialog discovered during actual
GPS-off testing. No permission prompt is started by the automatic collector;
explicit Start sharing retains the existing permission flow. No background
service, alternate writer, backend migration or eligibility relaxation was added.

Controller state retains the actual canonical SavedDriverLocation. The Home card
alone ticks every second in the foreground. Sharing requires both device and
server receipt ages in [0,60] seconds and accuracy in (0,50] m. Missing, invalid or
future evidence displays UNAVAILABLE; aged evidence displays STALE. Lifecycle
exit revokes queued work synchronously. Stop, auth replacement and disposal
cancel collection; replacement clears confirmed evidence.

## Files and verification

- driver_gps_stream_service.dart: state-specific observation/publication policy.
- geolocator_driver_gps_stream_service.dart: genuine bounded observation refresh
  and nonprompting Android native path.
- driver_tracking_providers.dart: canonical quality evidence, lifecycle fencing
  and qualified stationary accuracy-variation heartbeat.
- driver_home_screen.dart: foreground age ticker and truthful eligibility label.
- Three existing GPS/controller/Home test files: targeted regressions for silence,
  invalid/cached fixes, timeout/cancellation, native settings, lifecycle/session
  replacement, sequence ownership and live UI aging.
- fake_async is a direct dev dependency at its existing locked version; no runtime
  dependencies were upgraded.

Final focused GPS/controller/Home and architecture tests: 87 PASS.
Final full serial Flutter suite: 2,782 PASS, 0 failures, 4 intentional live skips
(4m35s). Scoped analysis: clean. Full analysis: the same 20 inherited diagnostics
(0 errors, 3 warnings, 17 infos); the repository-wide analysis command therefore
exits nonzero. No diagnostic suppressions or unrelated cleanup were added.

Independent Astra High final verdict: APPROVE, no blocking findings. It inspected
the final production/test diff, verified both nonprompting native settings paths,
canonical freshness, one writer, lifecycle/auth isolation and unchanged gates,
and independently reran all 87 focused tests. Earlier accuracy starvation and
precheck-only dialog prevention findings were fixed before this final review.
Device and hosted outcomes are execution evidence below, not reviewer assertions.

## Final Driver build

Debug acceptance build 4007 installed only on emulator-5556 with install -r,
without uninstalling or clearing data. Original Driver APK/data were backed up
privately before the first replacement. Original signing certificate matches.
Installed APK SHA256 was verified against the built file:
`122fa08473471e64404773746532f1dece43fbd0048762c493d4d4edf9becc35`.

The existing Driver session restored and Start sharing was used through Home.
Password recovery was not repeated. Rider emulator-5554 remains on build 4003.
Approved private nonproduction build inputs were reused, never committed.
Source runtime activation remains default-OFF, independent commands remain gated,
release builds cannot enable them, and financial completion remains disconnected.

## Final runtime evidence

The final stationary run used Start sharing once and one emulator coordinate
input. No additional GPS input or manual tracking restart occurred during the
measured window. Eleven canonical samples span 216.566 seconds, sequences 127
through 142. Every sample is 5 m accurate, at the same coordinates, and Matching
quality. Maximum sampled device age is 18.26 seconds; receipt age is 13.82 seconds.
Sequence progression is monotonic. This is foreground emulator evidence, not a
physical-device or background tracking guarantee.

With device GPS switched off, sequence 145 remained unchanged. Canonical device
age reached 80.96 seconds and receipt age 76.51 seconds; Matching quality is false.
The visible Home card immediately showed UNAVAILABLE and continued aging to 1m
ago. No GMS resolution dialog covered it. Restoring device GPS and explicit Home
Start sharing recovered fresh sequence 147 without another coordinate input.

Stop/Start also passed independently: sequence 147 remained unchanged between
15:16:56 and 15:17:22 UTC while stopped. Start sharing recovered fresh sequence
149 (5 m, device age 6.85 seconds) without new coordinate input.

Background/resume passed: after background cancellation settled, sequence 151
remained unchanged across the read window. Foreground resume required no manual
Start and recovered fresh sequence 153 (5 m, device age 14.37 seconds). Home then
showed Sharing with receipt/device ages 8s/12s. GPS remains enabled and Driver Home
is foregrounded with its intended sharing session.

UI snapshots show age progression and reset on actual new publication. Evidence
with a future receipt relative to the device clock is conservatively UNAVAILABLE,
including briefly after some publications; it never grants a fresh badge.

All publications come from the authenticated application, using actual emulator
GPS observations. Administrative evidence queries are SELECT-only.
No location rows were inserted or retimestamped manually, and no matching, offer,
Trip or financial commands were executed.

Read-only preservation check: approved Driver remains available, version 2, with
its active vehicle and no active Trip/reservation pointers. Protected unrelated
Trip dda56345-4123-4a0c-9771-5287899d2344 remains accepted, version 1.

## Remaining Cash E2E dependency

Rider candidate yousuf@demo.com has no authenticated Rider session established for
this run. Moath/Yousuf must provide the approved existing Rider account-access
mechanism or perform its login. No Rider password reset is authorized by this
GPS task. Rider login and full Cash E2E remain BLOCKED / NOT RUN. Once login is
available, rerun existing B09A preflight with both foreground clients and fresh
Driver GPS before one controlled Cash booking. Stop before completion/settlement.

No push, PR creation, merge, production deployment or Realtime publication change
is included in this local GPS patch. A PR description is prepared for handoff.
Sanitized canonical samples, GPS-off, Stop/Start and lifecycle measurements, UI
snapshots, build identity and verification logs are retained privately in the
existing acceptance evidence store. Private backups, credentials and APKs stay outside
Git; this report contains no passwords, administrative keys or session tokens.
