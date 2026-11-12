# P7 B09A: two-emulator acceptance foundation (Moath)

This is read-only readiness tooling and a reproducible execution specification.
It does not run a connected ride or authorize hosted operations. All fourteen
scenario actions remain **NOT RUN / BLOCKED** in generated reports. No installed
application, feature gate, provider, route, backend or migration is changed.

## Base and reuse

The request named main `88072339bfd805c66f890e9509dd40ba0c133b0f`.
The interrupted isolated branch had already advanced to fetched main
`30288ab562851920d53baf5b61c279e03891af96` when implementation resumed. That is
this phase's actual source base; the original feature checkout is preserved.

Reuse the existing [Cash handoff](../ops/P7_MOATH_CASH_E2E_HANDOFF.md),
[endpoint contract](../ops/P7_MATCHING_ENDPOINT_HANDOFF.md),
[backend acceptance](../ops/P7_YOUSUF_FINAL_BACKEND_ACCEPTANCE.md),
[Realtime/GPS handoff](../verification/P7-OMAR-FINAL-REALTIME-GPS-HANDOFF.md),
[B07](P7_B07_CANONICAL_ADAPTER_FOUNDATION.md), and
[B09 discovery](P7_B09_DRIVER_OFFER_DISCOVERY.md). Those contain the authoritative
RPCs, local Auth/SQL harnesses and operational runbooks. B09A adds no parallel
matching, Realtime, financial architecture or full application test driver.

Current source contains `cash-matching`, canonical Driver B07/B08, inactive B09
authenticated polling, Rider assignment readers, and Realtime adapters. Source
presence is checked separately from deployed/runtime/actor acceptance. It does
not establish their composition, approved target, or successful live delivery.

## Three different evidence levels

| Level | What it demonstrates | What it cannot demonstrate |
|---|---|---|
| A: independent Mock UI | Each emulator can navigate its own Mock app | Shared identity, matching, assignment or propagation |
| B: synthetic/local integration | Deterministic evidence validation, fake ports, existing local adapter/Auth/SQL tests | Hosted/mobile event delivery or a connected device trip |
| C: shared nonproduction two-emulator | Distinct approved actors execute one exact canonical chain on one approved backend | Financial completion; separate approval and scope would be required |

This implementation executes B tests and local read-only device probes. It never
promotes A or B into C. Even completely consistent imported evidence stays
UNKNOWN because an operator-supplied JSON claim is not independent verification.
The scenario specification is ready; C execution is not.

## Tool and contracts

- `bin/b09a_preflight.dart`: strict CLI, external JSON/Markdown reports, exit 2 for
  incomplete readiness, 64 for usage/output errors; `--help` exits 0. There is no
  success path that means a connected trip passed.
- `lib/src/acceptance/read_only_preflight.dart`: injectable fixed commands;
  git SHA/status, Flutter version, direct SDK ADB version/device/boot queries,
  `pm path`, `dumpsys package`, and installed standalone APK `sha256sum`.
  Commands are sequential, bounded to 15 seconds/64 KiB stdout each; stderr is
  discarded. No logcat, screenshot, environment-file or credential extraction.
  Android shell paths and package IDs are strictly whitelisted. Split/unreadable
  APK fingerprints stay unknown. Availability does not prove Gradle health,
  licenses, build provenance or embedded backend configuration.
- Source application ID is read from the single literal Gradle declaration;
  computed IDs/flavors/suffixes stay blocked. No package name is guessed.
- `lib/src/acceptance/two_emulator_acceptance.dart`: pure fail-closed checker,
  exact S01-S14 IDs/owners, bounded freshness/correlation validation and sanitized
  report. Its `ApprovedReadOnlyActorAccess` is an injectable future seam, **no
  hosted implementation**. A future owner-reviewed adapter must borrow approved
  normal-user access and validate the target/approval and server-owned actor
  records. It must never trust user-editable metadata or service-role access.
  The CLI supplies no adapter, so independently verified actors stay BLOCKED.
- Imported build identity evidence must bind both observed APK hashes to the
  same public project reference and exact source SHA. It remains UNKNOWN until
  an independently reviewed build provenance mechanism exists. Do not scrape
  APK strings for credentials, compile a new app or enable flags in preflight.
- Actual nonempty, bounded `evidence-NNN.json` artifacts must exist below the
  selected evidence root. Arbitrary names/path strings cannot satisfy evidence.
  Existence is only reference validation, never proof of artifact truth.

No network access is required for offline validation. Tool overrides select
trusted local executables, never credentials or shell command strings. Reports
contain only allowlisted public metadata, fixed explanations and opaque evidence
IDs. Raw actor/Trip IDs, timestamps/coordinates of individual locations, tokens,
JWTs, API keys, emails, names, exception text and arbitrary paths are not copied
to generated output. Input evidence and separately retained artifacts require
operator sanitization and restricted storage; the tool does not cleanse them.

## Sanitized input schema (version 1)

All nodes are optional; absence blocks that check. Unknown keys/malformed nodes
fail schema validation without echo. No arbitrary free text or scenario PASS
field is accepted. A minimal offline input is `{"schema":1,"kind":"synthetic"}`.
Use synthetic UUIDs for tests; never put credentials in this file.

| Node | Only accepted keys | Validation / limitation |
|---|---|---|
| root | schema, kind, repository_sha, captured_at, environment, actors, builds, integrations, gps, safety, journey | kind synthetic/operator_attested; SHA-bound timezone-aware capture <=5 min old, not future |
| environment | project_ref, approved_nonproduction, approval_ref | 20 lowercase-letter public Supabase project ref; explicit approval claim plus actual evidence reference; UNKNOWN, not approval |
| actors | rider_id, driver_id, roles_verified, evidence_ref | Distinct UUIDs; claimed roles are UNKNOWN; read-only verified actor port absent in CLI |
| builds | rider, driver | Each: apk_sha256, project_ref, evidence_ref; hash must match observed device APK and intended project |
| integrations | matching, offer_delivery, driver_composition, rider_assignment, tracking, realtime, safe_publication, eligibility | Each: available, evidence_ref; missing/false is BLOCKED; true is UNKNOWN |
| gps | recorded_at, received_at, accuracy_meters, sequence, latest_verified, evidence_ref | Latest positive sequence; ages <=60 s, accuracy >0 and <=50 m; device future skew <=5 s; no future server receipt; consistency only |
| safety | completion_disabled, card_disabled, receipt_writes_disabled, no_mutations_requested, evidence_ref | All true required; no mutation dispatch exists in tool |
| journey | booking_id, quote_id, offer_id, accepted_offer_id, trip_id, rider_trip_id, trip_driver_id, trip_rider_id, trip_booking_id, trip_quote_id, trip_version, payment_method, authorized_reads, evidence_ref | UUID lineage, exact offer/Trip/participants, positive version, cash, authorized-read claim; UNKNOWN until independent canonical acceptance |

Reference values are `evidence-001` through `evidence-999999` (3-6 digits), mapped
to a separately retained `.json` artifact of that name. `approval_ref` uses the
same form. Build nodes and integration nodes have their own evidence_ref.
Backend identity/approval cannot be inferred from a URL, successful install,
matching APK version, passing fake tests, or the mere presence of an artifact.
This first schema accepts public hosted project references only. A loopback/local
Supabase identity requires a separately reviewed identity adapter/schema; do not
invent a hosted-shaped reference to make a local target pass. Existing isolated
local Auth/SQL harnesses remain level B and are reused via the handoffs above.

## Acceptance specification: S01-S14

The following are **future authorized manual actions**, never B09A commands.
Before any action obtain a named environment owner, approved public target and
two named test actors, exact allowed fixture writes/cleanup, stop window,
reviewed source/builds and canonical composition. Acceptance may create the
backend's Cash-selected Payment row as an atomic assignment side effect; this
must be explicitly included in future fixture-write approval. Collection,
settlement, receipt and completion remain excluded. No approval is supplied here.

Every PASS requires retained evidence from that actual run. FAIL means an
observed contract/security violation. BLOCKED means missing permission,
integration, authority or trustworthy evidence; a timeout/UNKNOWN is not PASS.
Retain restricted canonical correlation details separately; reference only
sanitized artifact IDs in the B09A report. Redact screenshots and logs manually
before retention. No automatic live evidence importer certifies these scenarios.

| ID / owner | Prerequisites | Exact authority | Future action | Expected observation / evidence | PASS / FAIL / BLOCKED |
|---|---|---|---|---|---|
| S01 Sanad | Approved Rider, approved target/build, normal Auth | Real Auth user/session plus server-owned profile/role and participant RLS | Sign in on emulator-5554 through reviewed app | Authenticated Rider screen; target/hash/session-epoch and sanitized screenshot/actor read ref | PASS correct principal/role restored; FAIL wrong principal/unauthorized visibility; BLOCKED no approved account/config or read |
| S02 Moath | Separate approved Driver on same target, isolated session | Real Auth plus AuthService Driver binding and DriverEligibilityRepository | Sign in independently on emulator-5556 | Distinct principal, approved Driver role, separate session; actor read/screen refs | PASS distinct authorized Driver; FAIL shared/wrong principal; BLOCKED reader/composition/account missing |
| S03 Moath/Yousuf | S02; approved vehicle and availability fixtures | Canonical Driver eligibility, vehicle and driver_availability under normal-user RLS; A03/A04 rechecks | Read eligibility; only owner-approved availability workflow if needed | Approved/unblocked Driver, valid vehicle, available state/version; negative foreign read evidence | PASS eligible own records and foreign hidden; FAIL wrong owner/vehicle/version exposed; BLOCKED fixture/workflow or proof absent |
| S04 Omar | S03; device permission, GPS on, reviewed cadence | Latest sequenced driver_locations evidence and server received_at; A03/A04 freshness policy | Publish genuinely refreshed fixes using reviewed GPS lifecycle, including stationary interval | <=60 s ages, <=50 m accuracy, <=5 s device skew, monotonic sequence; server-read and resume refs | PASS matching-quality current fixes, stationary freshness; FAIL stale/latest invalid fallback, retimestamping or foreign read; BLOCKED GPS correction or owner approval absent |
| S05 Sanad | S01, reviewed opt-in Rider composition, approved write scope | rider_confirm_booking and owned canonical Booking/locked FareQuote lineage | Confirm exactly one Cash booking in UI | Real Booking/Quote IDs and versions, Cash/JOD, searching route; confirmation/read refs | PASS owned exact canonical booking; FAIL fabricated locator/Card dispatch/duplicate; BLOCKED config, fixture approval or canonical mapper absent |
| S06 Yousuf | S03-S05, deployed accepted endpoint/guard/grants, rate/expiry policy | POST functions/v1/cash-matching with Rider JWT, exact booking_request_id/fare_quote_id/expected_booking_version; A03/A04 rows | Dispatch via reviewed Rider action once; honor 429 Retry-After | Authorized persisted offer(s), exact Booking/Quote/Driver/vehicle/version/deadline; sanitized response and row refs | PASS actual authorized offer; FAIL unauthorized/incorrect lineage or duplicate active assignment; BLOCKED deployment/eligibility/expiry disposition unknown; UNKNOWN requires read-only recovery |
| S07 Moath/Omar | S06, reviewed mounted canonical composition and real discovery | B09 participant-scoped driver_match_offers SELECT; B07 authorized reread; hints advisory | Observe actual offer on Driver; test unavailable/disconnected source | Exact owned offer in canonical reference presentation, no invented fare/route; delivery timing/read/screen refs | PASS within deadline after canonical reread; FAIL fake authority/foreign/stale data; BLOCKED mounted delivery absent. Polling PASS does not prove Realtime |
| S08 Moath | S07; current owned unexpired offer; reviewed commands enabled only in approved build | driver_transition_trip(target_id=offer ID, requested_status=accepted, expected_version, idempotency_key), A04 locks | Accept exact pinned offer once | Single intent/key and canonical readback; response alone insufficient; request/read refs | PASS exact canonical accepted offer plus correlated Trip; FAIL replay/version/ownership bypass; BLOCKED expiry, unknown outcome or approval absent |
| S09 Moath/Yousuf | S08 | B07 owned Cash Trip read and accepted-offer/Booking/Quote/Driver/vehicle correlation | Reread Trip under Driver session; check version and immutable lineage | One exact Trip, correct participants and monotonic version; canonical read refs | PASS correlated single assignment; FAIL conflicting identities/versions/multiple active Trips; BLOCKED no authorized proof |
| S10 Sanad | S09; reviewed Rider discovery mapper/route | CashBookingAssignmentRepository / existing participant-scoped canonical assignment reader | Rider discovers assignment for original Booking/Quote, then reads Trip | Rider and Driver independently verify same Trip/offer lineage; read/screen refs | PASS exact same Trip; FAIL matching UI by guessed locator or foreign Trip; BLOCKED mapper/entry or reader unavailable |
| S11 Sanad/Omar | S10; reviewed publication safety, real transport, scoped subscriptions | TripRealtimeAdapter advisory signals followed by authorized participant Trip/location rereads | Observe authorized updates, reconnect/resume, teardown | Monotonic canonical updates, explicit stale/unavailable state, no foreign events; sanitized event/read/screen refs | PASS actual scoped delivery plus rereads; FAIL unsafe DELETE/TRUNCATE, event-authoritative assignment or leak; BLOCKED publication/transport acceptance absent |
| S12 All/security | Approved replacement/negative actors and actor test scope | Auth/session generation, B07/B08 revocation, participant RLS, actual Auth revocation semantics | Replace/logout sessions; try foreign reads/commands through approved test entry | Old continuations hidden; new session cannot inherit/replay old intent; denied foreign access; bounded evidence refs | PASS all negatives enforced; FAIL old/foreign authority survives; BLOCKED no approved negative actor/lifecycle adapter |
| S13 Sanad/Moath/Yousuf | Approved cancellation case and fresh isolated fixture; original intent retained | Existing canonical cancellation and version/idempotency contracts, read-only B04/B07 UNKNOWN reconciliation | Cancel through existing reviewed owner workflow; interrupt one approved response and explicitly reconcile without replay | Canonical cancelled/recovered state consistent for both actors; command counts and read refs | PASS canonical recovery without duplicate submission; FAIL blind retry/false negative/simulated outcome; BLOCKED missing supported cancellation workflow or durable intent recovery; never invent RPC |
| S14 Moath/payment owner | Intended reviewed build and source gate evidence | B06 unconditional completion stop and absence of completion/Card/receipt command seam | Inspect gates; exercise blocked completion UI using fake command counter only | Unsupported/disabled completion, zero financial dispatch; source/test/build evidence refs | PASS local stop-gate proof only, plus independently verified intended build gate for C; FAIL any financial dispatch; BLOCKED build/gate evidence missing. Never invoke financial RPC to test refusal |

## Owners and safe order

1. Yousuf supplies approved target/catalog/deployment and Auth/gateway/RLS
   acceptance for existing matching/accept contracts, named expiry job owner and
   explicit scheduler/expiry disposition; no new matching architecture is needed.
2. Omar supplies reviewed GPS acquisition/stationary fresh-fix cadence compatible
   with <=60 s / <=50 m server policy, safe publication disposition, real transport
   delivery, reconnect/disposal and actor isolation evidence. Do not merge/activate
   PR #127 or unsafe DELETE/TRUNCATE publication as a harness prerequisite.
3. Moath supplies reviewed mounting/lifecycle invalidation for existing B07/B08/B09
   canonical composition, durable intent recovery decision and approved Driver
   actor/vehicle. Polling is an existing candidate; it cannot certify S11 events.
4. Sanad supplies approved Cash confirmation/search -> matching -> exact assignment
   -> full authorized Trip mapper/tracking entry, 429 recovery UX and Rider actor.
5. Owners jointly approve accounts, nonproduction target, public build identity,
   scoped writes/cleanup and stop window. Run S01-S04, then one S05-S10 chain;
   S11/S12 need real event/security evidence; S13 uses separately approved case.
   S14 remains a stop gate throughout. Stop on unclear authority or UNKNOWN;
   canonical read-only reconciliation never authorizes a new mutation.

## Exact commands

Run from this isolated repository root. These commands perform local tests and
read-only observations only; they never install, launch, enable flags or login.
Use the trusted Flutter SDK already configured by the project. No .env.json or
secret defines are required. Supply a **new external output directory** each run.

```powershell
flutter test --no-pub --concurrency=1 test/two_emulator_acceptance_test.dart test/read_only_preflight_test.dart test/b09a_preflight_cli_test.dart
dart analyze bin/b09a_preflight.dart lib/src/acceptance test/two_emulator_acceptance_test.dart test/read_only_preflight_test.dart test/b09a_preflight_cli_test.dart
dart run bin/b09a_preflight.dart --help
dart run bin/b09a_preflight.dart --out "$env:TEMP/ridex-b09a-preflight-new"
```

After owner approval and sanitization, supplied evidence can be checked without
executing a single scenario. Both input locations are external operator paths:

```powershell
dart run bin/b09a_preflight.dart --evidence "$env:TEMP/ridex-approved-evidence/input.json" --evidence-root "$env:TEMP/ridex-approved-evidence/artifacts" --out "$env:TEMP/ridex-b09a-validated-new"
flutter test --no-pub --concurrency=1
```

An SDK override is `--sdk-root "$env:LOCALAPPDATA/Android/sdk"`; the collector uses
its `platform-tools/adb.exe` directly. Device IDs are pinned to emulator-5554 and
emulator-5556. Missing emulators never trigger a start/wipe/install action.
Exit 2 is expected even with supplied evidence. Future real S01-S14 execution
requires the separately reviewed application entry/build and all approvals above;
**there is intentionally no B09A live-ride command**. Reuse the Cash handoff's
owner-approved application execution forms only after these gates are resolved.

## Verification record

Completed on 2026-11-12 with Flutter 3.41.2 / Dart 3.11.0:

- **65 new tests pass**: 50 checker/authority/evidence tests, 11 read-only probe
  tests and 4 CLI subprocess tests. These are deterministic level B tests.
- Focused new + existing canonical Driver, B08/B09, Realtime/GPS and P6 contract
  suites: **291 pass, 0 fail, 0 skip** (226 existing tests).
- Full `flutter test --no-pub --concurrency=1 --reporter expanded`:
  **2733 pass, 0 fail, 4 skip**, 4 min 41 s. Skips are the two unconfigured live
  Supabase Auth/role tests and two opt-in D05 real-Realtime tests; no opt-in
  configuration was supplied or enabled. Synthetic D05 preflight cases do run.
- Scoped analysis of all six new Dart files: **no issues**. Full
  `flutter analyze --no-pub`: **20 inherited diagnostics**, 0 errors, 3 warnings,
  17 infos, exit 1. They are in unchanged Rider service/widgets, matching/search/
  confirmation code and existing cancellation/matching/accessibility tests.
  Full analysis is not green; no findings were suppressed or teammate files fixed.
- Independent **Astra High APPROVE**, no blocking correctness/security findings.
  Static read-only review of all seven files; reviewer did not rerun tests or
  certify the parent's regression counts. No post-review application code change.
- Actual direct-SDK read-only preflight: Flutter and Android tool availability
  observed; Gradle source package `com.ridex.app`; **neither emulator connected**
  at the time of this run. No boot/install/launch was attempted. Installed builds,
  backend identity, distinct approved actors and all C scenarios remain BLOCKED.

External evidence filenames: `full-flutter.txt`, `focused-and-integration.txt`,
`full-analyzer.txt`, `scoped-analyzer.txt`, and generated `report.json`/`report.md`
in each selected preflight output directory. The final post-commit preflight
records the exact local commit SHA and clean repository observation. Machine
paths/generated reports are intentionally not committed. No result certifies C.

Branch disposition: focused local B09A commit, ready for PR review after owner
approval to push/open it. Production composition remains default-off. No push,
PR, hosted mutation, activation or financial operation is part of this delivery.
