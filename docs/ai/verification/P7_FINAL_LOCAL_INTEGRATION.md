# Phase 7 final local integration

Base: `55340287f33226762f47b95ad720318e71642198` (fetched origin/main).
Branch: `feature/moath/p7-final-integration`, isolated worktree. Existing branches,
worktrees and teammate changes preserved. Resulting commit is recorded by Git.

## Implemented flow

Existing real Rider confirmation retains Booking/locked Quote lineage, enters
canonical Searching and invokes the existing authenticated `cash-matching`
endpoint. New bounded foreground-only polling rereads that same booking every
two seconds for at most the screen soft-timeout window, without dispatching a
matching retry. It skips in-flight matching/assignment reads and covered routes,
pauses while backgrounded and disposes its timer. The original feedback timeout
survives polling. Assignment still requires the existing participant-authorized
full Trip reader before navigation. Manual same-booking recovery remains after
the polling window. No new Matching or Trip repository was introduced.

Driver Home already links to B10's guarded canonical entry. The new
`lib/main_acceptance.dart` root supplies an explicitly configured target to B10,
using the application's verified normal-user SDK client and existing AuthService.
Runtime read opt-in and command authorization remain independent. B07/B08/B09
retain discovery, role/block/approval/active-vehicle checks, original offer/version/
key, pending/expiry/error presentation, duplicate-tap fencing and canonical
accepted-offer/Trip recovery. The controlled entry displays the verified Trip;
completion stays disabled. It forwards only existing accept/decline contracts.

Before RPC handoff, the original decision is exclusively reserved in native
application-support storage, flushed, closed and read back. Existing, partial,
empty or unreadable evidence blocks another handoff across owners/processes.
There is no automatic deletion, replay or repair. It reuses the existing native
completion-journal I/O boundary, without enabling completion. An eight-second
prepare deadline encloses persistence and eligibility/offer rereads; the RPC is
outside that future, so a late preparation cannot dispatch. B07 resolves RPC
uncertainty through canonical rereads. Reentry can recover a canonical active
Trip, but never resubmit a retained offer. This is local filesystem/process-restart
protection, not a guarantee against power loss, app-data deletion or rollback.
Preserve application data and evidence during UNKNOWN recovery.

No backend schema/contracts, GPS publisher, settlement, receipt, Stripe, Card or
Trip completion were added or activated. Driver Home's existing local online
switch is not canonical availability authority. Acceptance requires a clean,
canonically available approved fixture; this integration never frees an occupied
Driver or synthesizes a heartbeat.

## Build and configuration procedure (NOT authorization)

Default `main.dart` behavior stays unchanged. For a future explicitly approved
nonproduction build, use `flutter build apk --debug --no-pub -t
lib/main_acceptance.dart --dart-define-from-file=<external-approved-config.json>`.
Both participants use the same approved backend, with distinct sign-ins. Config
contains existing SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (never service-role),
RIDEX_ENABLE_CASH_MATCHING_INTEGRATION=true,
RIDEX_ENABLE_TEST_DRIVER_CANONICAL=true, RIDEX_APPROVED_NONPRODUCTION=true,
RIDEX_ACCEPTANCE_APPROVAL_REF, RIDEX_ACCEPTANCE_SUPABASE_URL (exact match to
SUPABASE_URL), RIDEX_ACCEPTANCE_DRIVER_ID and RIDEX_ACCEPTANCE_VEHICLE_ID.
RIDEX_APPROVED_OFFER_COMMANDS independently defaults false and may be true only
with explicit accept/decline authorization. These are trusted operator build
inputs, not proof that approval was obtained. No target/identity is approved in
source. Release always denies Driver target and commands even with defines.
Do not put passwords in build configuration or commit config/evidence files.

Local gate-off debug compilation was executed successfully. It is a compilation
artifact, NOT an approved nonproduction acceptance build. No APK was installed,
replaced or launched. Package: `com.ridex.app`, no separate Rider/Driver flavors.
Both emulators were observed booted. Rider package absent; Driver existing APK
versionCode 4001, SHA256
`7a07b401e03a648efc3029b260cba931a717c090e5f8ef069d26b892e18bc539`.
Its integration/configuration provenance is unverified. SDK observed Flutter
3.41.2 / Dart 3.11.0, differing from the historical guide. Build warnings concern
existing Gradle/Kotlin support, Java 8 options and SDK XML versions.

## Hosted read-only findings and blockers

Observed project `ykasivejjchupswqyxpm`; nonproduction testing is NOT approved.
Management-plane SELECTs are administrative observations, not participant RLS or
SDK-session acceptance. No credentials were requested, retrieved or exposed.

The proposed Driver remains `onTrip`, availability version 12, with active Trip
pointer `dda56345-4123-4a0c-9771-5287899d2344`; that Trip is `accepted`, version 1.
Approval and active vehicle do not make this Driver available. Another available
Driver exists but is not an approved fixture. Yousuf must supply/approve a clean
Driver/active-vehicle fixture or resolve the legitimate existing Trip through a
separately authorized owner workflow. Never reset it for this test.

`cash-matching` is ACTIVE version 1 with JWT verification. Participant SELECT
policies exist for offers, Trips and locations. Deployed contract/grant/migration
parity and actual participant negative reads still require approved SDK sessions.
Realtime publication has no member tables. pg_cron is absent; no database expiry
scheduler was verified. Yousuf must establish expiry scheduling/disposition and
hosted contract/grant acceptance. No migrations/functions/jobs were deployed.

Stored GPS evidence is stale (latest proposed Driver sequence 3 from October 26).
Available GPS config still permits low accuracy, a 50m distance filter and 120s
publish silence; this cannot guarantee the server's <=60s / <=50m eligibility.
Omar must supply genuinely refreshed accurate stationary observations, ordered
sequences and received-at evidence. No retimestamping or relaxed security policy.
A02 states last_heartbeat_at has no canonical writer; no heartbeat was invented.

Polling can support initial offer/assignment recovery without Realtime. It does
not establish live Trip-event or moving-location delivery. Existing participant
tracking adapters remain reused and show stale/unavailable data when appropriate.
Omar owns publication security review, delivery/reconnect proof and GPS cadence.
The deferred DELETE/TRUNCATE/publication migration remains untouched.

## Controlled acceptance procedure: BLOCKED / NOT RUN

Reuse B09A S01-S14 evidence contracts in
`docs/ai/plans/P7_B09A_TWO_EMULATOR_ACCEPTANCE.md`.
Before execution, owners must approve target, distinct named fixtures, normal-user
credential access, exact source/config/APK hashes, device installation scope,
allowed booking/offer/atomic Cash Payment side effects, expiry disposition and
stop window. None was approved. Owner explicitly prohibited hosted mutations,
credential requests, migration deployment and APK replacement during this task.

After future approval: sign in separately on 5554/5556; read roles, approval,
owned active vehicle, availability, reservations and existing Trips. Stop if
occupied. Obtain genuine matching-quality GPS through the existing publisher.
Confirm one Cash booking; retain Booking/Quote/version and matching response.
Open controlled discovery; read the exact authorized offer/version/deadline.
Accept once with original journaled key. Stop on UNKNOWN and reconcile reads,
never replay. Independently read Driver accepted offer/Trip and Rider original
booking/assigned Trip; compare exact Trip, Booking, Quote, participants and vehicle.
Observe authorized tracking only with satisfied prerequisites; distinguish polling
from actual Realtime delivery. Stop BEFORE completion/payment/receipt operations.
Retain restricted raw evidence separately and sanitized B09A evidence IDs/reports.
No scenario PASS may be inferred from local tests or imported operator claims.

Owners remaining: Moath config/build/hash/install approval and controlled run;
Yousuf approved project/clean fixture, availability, grants/contracts and expiry;
Sanad Rider identity and original-confirmation/assignment acceptance; Omar genuine
GPS freshness/stationary behavior and separately approved safe Realtime delivery.

## Verification

Final command results and independent review disposition are appended below.
Full serial tests intentionally skip unconfigured live Auth/role and opt-in real
Realtime acceptance. No live test was enabled. Broad local tests cover wrong
actors/vehicle, no candidates, occupied Driver, expiry/duplicates/stale versions,
lost response/UNKNOWN, session/lifecycle replacement, repeated taps, invalid GPS,
missing Realtime, canonical recovery and financial stop gates. They do not prove
hosted SQL execution or actual two-emulator interoperability.

### Files changed and purpose

- `lib/main_acceptance.dart`, `lib/app/bootstrap.dart`: explicit trusted test-root
  composition; ordinary startup unchanged, release Driver commands denied.
- `controlled_driver_runtime.dart`: enable existing B07/B08 command surfaces only
  with independent authorization, persistent reservation and checked SDK ownership.
- `driver_offer_command_journal.dart`: exclusive native acknowledged handoff
  evidence using existing journal I/O, no replay or financial command gateway.
- `controlled_driver_runtime_screen.dart`: accurate controlled-test scope copy.
- `rider_search_controller.dart`, `canonical_ride_searching_screen.dart`: bounded
  read-only assignment recovery independent of matching commands and feedback timeout.
- `controlled_driver_runtime_test.dart`: repeated-tap/lost-response/cross-role
  canonical graph, persistence/restart/race/flush-failure coverage.
- `canonical_ride_searching_screen_test.dart`,
  `rider_booking_cancellation_controller_test.dart`: bounded foreground polling,
  feedback deadline, latest-version cancellation regression.
- `cash_assignment_fixtures.dart`, `cash_booking_assignment_repository_test.dart`:
  reuse existing lineage fixtures across both canonical readers; existing cases retained.
- B10 plan follow-up and this report reconcile historical read-only scope with
  the new explicitly gated local composition.

### Independent Astra High review

Two independent read-only Astra High reviews were performed. Initial verdict:
REQUEST_CHANGES for preferences persistence, reservation concurrency, timeout
ownership and independent test graphs. Re-review confirmed those fixes and found
one P2: timeout feedback restored an obsolete Booking snapshot. It reported no
additional blocker. That small finding was fixed locally by retaining the current
verified snapshot; a new cancellation-after-version-advance test passes. Per the
review workflow, that small fix was handled locally without another delegate.
The last formal reviewer verdict is REQUEST_CHANGES, with its sole remaining
finding now fixed/tested; there is no claimed post-fix Astra APPROVE.

The first full local serial suite passed 2769 tests / 4 skips. A subsequent full
run caught a manual-refresh timeout regression during review fixes; it was fixed,
and the 102-test timeout/Driver/search/cancellation regression command passed.
Final serial suite and artifact results are recorded below. Scoped analysis is
clean. Full analysis retains 20 inherited diagnostics (0 errors, 3 warnings,
17 infos); no suppression or unrelated teammate cleanup was performed.

PR disposition: suitable for owner code review after final checks; no hosted
acceptance or runtime enablement approval implied. No push, PR or merge performed.

### Final results

- Final `flutter test --no-pub --concurrency=1 --reporter expanded`: **2771 PASS,
  0 FAIL, 4 intentional live-test SKIP**, 4m28s.
- Broader focused command: **358 PASS**, covering controlled runtime, matching,
  Searching, Cash assignment, canonical Driver repository/presentation/discovery,
  architecture boundaries, D06 GPS/Realtime, B09A evidence and confirmation handoff.
- Post-review search/cancellation/Driver regression command: **102 PASS**, including
  the final latest-version-after-timeout cancellation fix.
- Scoped analysis of new/Driver/composition/shared-fixture and changed regression
  files: **no issues**. Whole-project analysis: **20 inherited diagnostics**,
  0 errors / 3 warnings / 17 infos; full analysis exits 1 and is not claimed green.
- Formatting: **12 changed Dart files, 0 changes** on verification.
- `git diff --check`: PASS. Generated plugin metadata and SDK-induced lockfile
  changes were excluded/restored; no credentials, build artifacts or local paths staged.
- Final gate-off `flutter build apk --debug --no-pub -t lib/main_acceptance.dart`:
  PASS. SHA256 `e7887ba115457379e52f3dc81933347bbcf1cf09094d8ec909696c3cc7034ccc`.
  This unconfigured artifact was not installed and is not an acceptance build.
- Live E2E: **BLOCKED / NOT RUN**, per explicit owner restrictions and blockers above.

External evidence files (outside Git): `ridex-p7-verified-full.txt`,
`ridex-p7-final-focused.txt`, `ridex-p7-timeout-regressions.txt`,
`ridex-p7-verified-analysis.txt`, `ridex-p7-verified-scoped.txt`,
`ridex-p7-final-build.txt`, and B09A `report.json`/`report.md`.
