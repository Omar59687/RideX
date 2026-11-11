# RideX — Omar Phase 7 Realtime/GPS Closure Handoff

> **Historical closure snapshot.** The current Rider Searching/Cancellation recovery and final source reconciliation are documented in [P7-RECONCILED-INTEGRATION-HANDOFF.md](P7-RECONCILED-INTEGRATION-HANDOFF.md). This file records the prior 24-path closure package and should not be used alone as the current integration candidate manifest or acceptance report.

**Purpose:** local integration and acceptance handoff for P7-D02 through D06.
This is not a hosted or physical-device acceptance record.

## Reconciled baseline

| Item | Verified reference |
|---|---|
| `main` base used for this worktree | `88072339bfd805c66f890e9509dd40ba0c133b0f` |
| Omar PR #127 head | `c0c05b7d46a7643f8794f50b42dbd7cda9c487cc` (draft; based on an older `main`) |
| Moath B07 merge | `ef45428f4f8791cbf5c450e3f8abff036d098c3d` |
| Moath B08/current `main` | `88072339bfd805c66f890e9509dd40ba0c133b0f` |
| Workspace state | Detached isolated checkout at the `main` base above; no commit, push, PR, merge, or hosted operation made |

PR #127 applied cleanly to the verified current base. Its D02/D04 adapters and tests are retained. B07/B08 remain canonical: no old experimental Driver repository was copied over them. The preserved 35-file patch and its manifest based on `1aa60fa9` were not present in the accessible workspace, so that exact archive could not be reconciled file-by-file. The available PR #127 diff and merged current source were reconciled directly.

### Superseded or intentionally not activated

- The old 35-file patch's contents cannot be asserted because the artifact was unavailable. Any old Driver repository/provider/UI composition in it must not replace `CanonicalDriverRepository`, `CanonicalDriverDelivery`, or the B08 controller.
- B07 canonical reads/commands remain the Driver authority. B08 is default-off and unmounted. The new `TripRealtimeCanonicalDriverDelivery` only bridges D02 verified hints for a Trip already pinned by B07; it does not discover offers, assign Trips, or replace B08 lifecycle state.
- The existing `riderTripTrackingRepositoryProvider` remains `null`. The accepted Rider repository requires a full `RiderAssignedTrip` (Cash fare, pickup/destination, route and vehicle fields); D02 deliberately supplies only minimum Trip identity/status. Mapping one into the other would invent or drop canonical UI state. The new D02/D04 Riverpod adapter providers expose injectable streams but do not mount routes or remove the Rider feature gate.
- Phase 4 `DriverTrackingController` remains the only GPS publisher. No second publisher, database writer, or map route was introduced.

## Source changes in this integration patch

1. `lib/core/providers/trip_realtime_providers.dart` composes D02/D04 from the normal authenticated Supabase client, returning `null` in no-backend mode. It does not replace the disabled full-data Rider repository.
2. `lib/features/driver_flow/data/trip_realtime_canonical_driver_delivery.dart` implements B08's existing `CanonicalDriverDelivery` with D02 verified Trip hints and connection health; it checks exact assigned Driver and pinned Trip identity and cancels the D02 stream on disposal/session change.
3. `lib/core/providers/driver_tracking_providers.dart` adds an injectable auth-session monitor. An active GPS session is fenced and stopped on identity/session replacement. The existing foreground-only lifecycle, canonical availability rereads, cadence, quality policy and repository remain the publisher path.
4. `test/trip_realtime_canonical_driver_delivery_test.dart` covers assigned Driver delivery, a different Driver receiving no Trip identifier, and session replacement cleanup.
5. `test/driver_tracking_controller_test.dart` adds a deterministic session-replacement regression.
6. `supabase/deferred/20261106120000_phase7_realtime_publication_membership.sql` is kept outside the automatic migration path and now aborts if `supabase_realtime` publishes DELETE or TRUNCATE. It never changes publication-wide operations.
7. `test/p7_d06_realtime_gps_integration_test.dart` and `docs/ai/verification/P7-D06-Realtime-GPS-Integration-Handoff.md` are the PR #127 fake-backed integration test and prior D06 document. Use the current document here for corrected, final handoff facts.

All D02/D04 raw notification payloads are advisory. D02 rereads `trips` through the authenticated client after the initial subscription, relevant `trips` INSERT/UPDATE and `trip_status_events` INSERT hints, and after reconnect. The source subscribes only to INSERT/UPDATE for `trips` and INSERT for `trip_status_events`; it does not register a DELETE callback. D04 reads location only after D02 verifies the exact Rider, Trip and assigned Driver, and it checks sequence/time freshness before emitting coordinates.

## Integration/API handoff

| Consumer | Stable interface | Required behavior |
|---|---|---|
| Rider Trip status UI | `TripRealtimeAdapter.watchTrip(tripId)` → `TripRealtimeUpdate`; render canonical state only from `VerifiedTripRealtimeEvent` | Keep exact current Trip ID; treat connection/verification updates as transport state; never render source payloads as status; cancel on Trip/session disposal. |
| Rider live location UI | `RiderTripLocationAdapter.watchTrip(tripId)` → `RiderTripLocationUpdate`; render only `RiderTripLocationSnapshot` | Clear immediately for terminal Trip, logout, session replacement, assignment change or stale location; do not plot source event payloads. |
| Rider full Trip screen | Existing `RiderTripTrackingRepository` injection contract | Keep the provider unavailable until an owner supplies a full canonical Cash Trip mapper; D02/D04 do not manufacture fare, route or vehicle details. |
| Driver canonical presentation | B08 `CanonicalDriverDelivery` → `CanonicalDriverTripHint` / `CanonicalDriverConnectionHint` | Supply only after B07 has pinned the Trip. B08 must reread via its own repository; hints cannot assign, replace, or authorize a Trip. No offer hint is supplied because Yousuf's offer delivery is not available here. |
| Driver GPS UI | Existing `driverTrackingControllerProvider` / `DriverTrackingController` | Use the existing foreground controller and canonical availability; do not write `driver_locations` directly or create another GPS stream. On account/session replacement, the controller stops and requires a fresh explicit start. |

Example synthetic sequence: canonical assignment `(Trip C, Rider A, Driver B, accepted, v1)` → `driverArriving/v2` → `driverArrived/v3` → `inProgress/v4`; duplicate/reordered status hints cause authenticated canonical rereads but no state regression. Driver B's existing foreground publisher writes increasing location sequence under Trip C. A location-channel reconnect rereads the newest canonical row. `completed/v5`, logout, replacement session or revocation clears Rider location state and cancels subscriptions.

## Permission and data-scope matrix

| Identity/event | Trip/status visibility | Location visibility | Client response |
|---|---|---|---|
| Assigned, unblocked Rider | Canonical Trip RLS + D02 Rider ownership check | D04 exact Rider + assigned Driver + Trip check; DB RLS remains final | Emit verified Trip / fresh location only |
| Assigned, approved, unblocked Driver | Canonical Trip RLS + D02 assigned Driver check; B07 independently rechecks eligibility | Driver publisher requires canonical availability/active Trip; Rider location reads remain Rider-only | B08 receives a hint only for a B07-pinned Trip |
| Unrelated Rider or Driver | Canonical read is absent/unauthorized or participant mismatch | Location source query is exact Trip+Driver; RLS denies other identities | Fail closed; never forward unauthorized Trip/location payload |
| Blocked identity | Existing `can_read_trip` and location policies reject access | Same | No verified state; source error sanitized |
| Logout or session replacement | D02/D04 auth listener invalidates stream; GPS controller monitor stops publisher | D04 invalidates pending location epochs and clears state | Cancel source and discard late completions |
| Reconnect | Channel status is non-authoritative; D02 canonical Trip reread; D04 canonical latest-location reread | A delayed old read is fenced; sequence/time prevents regression | Recover only from current authenticated canonical state |
| DELETE/TRUNCATE | No D02/D04 DELETE handler. Publication membership still matters to every other subscriber. | Same publication-wide risk applies to `driver_locations` | Migration is deferred and refuses unsafe publication operations |

The D05 pgTAP file covers synthetic RLS denial assertions; the D05 Flutter live harness covers Trips INSERT/UPDATE and Driver location INSERT delivery with authenticated actor probes. It intentionally does not create append-only Trip status events because its REST fixture cleanup must be exact and reversible. D02 fake tests cover status-event hint ordering; actual status-event WebSocket delivery remains a live acceptance gap.

## GPS freshness and fail-closed rules

These are repository contracts, not newly chosen values:

| Layer | Existing rule |
|---|---|
| Phase 4 publisher validation | Reject missing accuracy; source age over 15 minutes; future source time over 5 minutes; nonadvancing timestamps and accuracy regression. Existing cadence/throttling stays unchanged. |
| Matching A03/A04 eligibility | Select newest sequence first; require `recorded_at` and `received_at` each within 60 seconds of observation, `recorded_at` no more than 5 seconds in the future, `received_at` not in future, `recorded_at <= received_at + 5 seconds`, accuracy `<= 50m`, Driver approved/unblocked and canonically available with no conflicting active Trip. A missing latest point fails closed. |
| Rider location adapter | Require exact Trip/assigned Driver, increasing sequence, nondecreasing source time, no future timestamps, and age at most 45 seconds. |
| Rider map presentation | Its existing display freshness limit is 30 seconds; a 30–45-second adapter snapshot may be represented as stale and must not be plotted as fresh. |

SQL eligibility is stricter than Phase 4 storage validation. A stored point older than 60 seconds or above 50 m accuracy cannot make a Driver match-eligible. Do not tighten publisher constants or loosen Matching rules without the owning acceptance work.

## Realtime publication security decision

The previously standard-path migration has been moved to `supabase/deferred/` and has a guard on `pg_publication.pubdelete` and `pubtruncate`. It raises before adding any table if either is enabled. It does not `ALTER PUBLICATION ... SET`, disable operations globally, alter RLS/grants, or modify replica identity. This is the narrowest safe code-side gate while current publication membership/operation settings and all subscribers are unknown.

No local database or hosted publication was inspected. The migration is **not approved for deployment**. Before an owner separately considers applying it, capture a read-only inventory of:

```sql
select p.pubname, p.puballtables, p.pubinsert, p.pubupdate,
       p.pubdelete, p.pubtruncate,
       t.schemaname, t.tablename
from pg_catalog.pg_publication p
left join pg_catalog.pg_publication_tables t using (pubname)
where p.pubname = 'supabase_realtime'
order by t.schemaname, t.tablename;
```

Inventory every subscriber and operation affected. PostgreSQL publication operation settings are publication-wide, not scoped to only these three new tables. Do not remove DELETE/TRUNCATE on a shared publication as part of this work. If the existing operation set is unsafe or its subscribers are unknown, leave this migration deferred.

Official references:

- [Supabase Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes) — RLS and DELETE payload caveats.
- [Supabase Realtime troubleshooting](https://supabase.com/docs/guides/troubleshooting/realtime-postgres-changes-not-working) — publication membership and authorization behavior.
- [PostgreSQL `CREATE PUBLICATION`](https://www.postgresql.org/docs/current/sql-createpublication.html) — publication operation options and `TRUNCATE` behavior.

## Phase 6 and cross-team gates

- **P6-R01 — PARTIAL:** canonical Driver eligibility/Trip foundation exists, but activation remains default-off, the canonical Driver route is not mounted, and hosted acceptance is absent. It blocks a production/physical Driver flow, not synthetic local adapter tests.
- **P6-R04 — PARTIAL:** local hardening exists; a hosted Admin/Rider/approved Driver/blocked-role PostgREST and session matrix is still required. It blocks hosted security acceptance.
- **Cash-only:** Trip screens/models remain Cash-only. P6-R06 Stripe runtime is unconfirmed; no Card/Stripe/payment operation was introduced or enabled.
- **Yousuf:** provide accepted matching/offer delivery and its canonical assigned Trip contract before Driver offer discovery can be wired. This patch consumes no unmerged branch.
- **Moath:** B07/B08 remain the canonical Driver base; B08 delivery is inactive until an approved owner composes it.
- **Sanad:** Rider route and full-data repository remain unmounted/disabled pending a canonical full Trip mapper and acceptance.

## Windows validation handoff for Yousuf

### Toolchain and checkout

Use the exact tested code base `88072339bfd805c66f890e9509dd40ba0c133b0f` plus the ordered patch files in the delivered package. The repository's current Flutter CI uses Flutter `3.41.2`; `pubspec.yaml` requires Dart `^3.6.1`. Prefer the CI Flutter version for the current merged main. Do not modify `pubspec.lock` to accommodate another SDK.

The full working-tree patch has no commit SHA because no commit was created. Record the actual post-application `git rev-parse HEAD` and patch SHA-256 in the validation log; do not call the base SHA the tested patch commit.

### Focused commands

Run from the project root after applying patches in order:

```powershell
flutter test --no-pub test/trip_realtime_adapter_test.dart
flutter test --no-pub test/rider_trip_location_adapter_test.dart
flutter test --no-pub test/trip_realtime_canonical_driver_delivery_test.dart
flutter test --no-pub test/p7_d06_realtime_gps_integration_test.dart
flutter test --no-pub test/driver_tracking_controller_test.dart
flutter test --no-pub test/driver_gps_stream_service_test.dart
flutter test --no-pub test/driver_location_repository_test.dart
flutter test --no-pub test/driver_location_validation_policy_test.dart
flutter test --no-pub test/driver_home_location_sharing_test.dart
flutter analyze --no-pub
git diff --check
```

These are synthetic/fake-backed runs; record actual counts per command. The full Flutter suite may follow, but do not infer its result from the merged B07/B08 baseline.

### Isolated D05 database and live WebSocket checks

The default `supabase/config.toml` project is `ridex` and requests database port `54322`; the R08 container already owns that port. Do not start/reset the default RideX project while R08 is present. Use only a separate checkout at `C:\RideX-D05-Isolated` configured with project ID `ridex-d05-isolated`, Kong/API loopback port `55421`, and database loopback port `55422`. The acceptance harness requires containers `supabase_db_ridex-d05-isolated`, `supabase_kong_ridex-d05-isolated`, and `supabase_realtime_ridex-d05-isolated`, matching D05 project/workdir labels, exact loopback bindings, and a healthy Realtime container.

Before setting credentials, starting fixtures, resetting the database, or using service-role access, run the existing D05 Docker identity preflight in the isolated checkout. Do not bypass it. Use only local D05 anon/service keys held in Windows environment variables; never production keys. Do not run if any container name, label, workdir, health status, URL host, or port differs from the D05 constants in `test/p7_d05_realtime_acceptance_test.dart`.

The existing preflight does not inspect publication operations. After the containers are proven to be the isolated D05 project, inspect its publication and subscriber list. If it is newly isolated and has no unrelated subscribers, configure that **local D05 database only** to publish INSERT/UPDATE and not DELETE/TRUNCATE; then the deferred migration's guard may pass when explicitly applied. Do not change hosted or shared publication settings. The current harness proves Trip INSERT/UPDATE and Driver location INSERT; it does not prove `trip_status_events` delivery, DELETE behavior, JWT role revocation on an open channel, or hosted RLS.

For SQL-only local RLS regression after migrations are installed in the D05 checkout:

```powershell
supabase test db supabase/tests/database/p7_d05_realtime_rls.test.sql
```

For the live acceptance, set only the isolated local values and run:

```powershell
$env:D05_REALTIME_ACCEPTANCE = '1'
$env:D05_SUPABASE_URL = 'http://127.0.0.1:55421'
$env:D05_SUPABASE_ANON_KEY = '<isolated-local-anon-key>'
$env:D05_SUPABASE_SERVICE_ROLE_KEY = '<isolated-local-service-role-key>'
flutter test --no-pub test/p7_d05_realtime_acceptance_test.dart
```

The harness repeats its read-only Docker preflight before any service client or fixture writes. It uses synthetic actors and exact cleanup; stop on any mismatch or cleanup failure. No live check should run against hosted Supabase.

### Two-device physical test plan

**Prerequisites:** owner-approved isolated staging project/accounts; the hosted R04 actor matrix; safe publication membership and operations; accepted Yousuf matching/offer delivery; Moath B07/B08 integration authorization; Sanad Rider route/full canonical mapper; two devices and a written stop window. Use only approved test identities and a Cash-only synthetic Trip.

1. Assign an approved, unblocked Driver to a test Rider through the approved test path. Confirm both clients' authenticated identity and canonical Trip assignment.
2. Start sharing on the Driver device only through the existing foreground `DriverTrackingController`. Confirm availability and Trip ownership are canonical and location sequence advances.
3. Open Rider tracking on the Rider device. Confirm only fresh exact Trip/Driver snapshots appear; duplicate/out-of-order status/location hints do not regress display.
4. Interrupt and restore network. Confirm canonical Trip and latest-location rereads recover missed events without showing stale coordinates.
5. End or cancel the Trip, sign out, and replace the Rider session in separate runs. Confirm coordinates clear and Driver publication stops on session replacement.
6. Record test build SHA, identities by synthetic alias, Trip ID, expected/observed event sequence, and cleanup evidence. Do not delete data or change policies manually.

**Stop immediately** if another Trip/Driver's data appears, a stale coordinate remains after terminal/session invalidation, background GPS is published, session ownership is uncertain, cleanup fails, or any Card/Stripe/payment UI appears. Sign out and stop the test through the approved owner process.

## Validation and limitations

**Tool execution in this workspace: NOT RUN.** Flutter, Dart, Supabase CLI, Docker and PostgreSQL executables are unavailable here. No tests, analyzer, pgTAP, database reset, WebSocket run, hosted operation or physical-device test is claimed. `git diff --check` is the only local validation planned/available and is reported separately in the final response.

The currently available automated coverage is separated by evidence type:

- D02/D04 fake-stream tests cover participant checks, event ordering, duplicate/stale signals, reconnect canonical rereads, location sequence/freshness, lifecycle invalidation, and setup cleanup.
- The new B08 bridge tests cover assigned Driver hint delivery, wrong-Driver non-disclosure, session invalidation and cleanup.
- The D06 integration test composes D02, D04, and the real existing Phase 4 controller over fake event/GPS/repository sources.
- Existing Phase 4 tests cover GPS accuracy, coordinates, timestamp freshness, availability/session lifecycle, monotonic sequence and publisher cleanup.
- D05 pgTAP and live tests exist, but were not executed. The real `trip_status_events` WebSocket event, DELETE/TRUNCATE, JWT refresh/revocation on open subscriptions, publication membership, hosted RLS and physical device path remain unverified.
