# P7-D03 — Driver Location Publisher: Reuse and Privacy Record

**Status:** Local D03 validation recorded; the existing Phase 4 publisher is reused.
**Source review checkout:** `omar` at `83896280689e68d1b01f17e9a97362c9d70d861a`.
**Validation checkout:** `omar` at `95ecc1caa37255cae9b2b5d36d0c13bca9ebd2d5`.
**Scope:** P7-D03 / GitHub Issue [#97](https://github.com/Omar59687/RideX/issues/97).

## Bounded implementation decision

Phase 4 already implements the D03 foreground publisher requirements. The
current `DriverTrackingController` owns the GPS subscription and ordered write
queue; the service and repository use the existing canonical availability and
`driver_record_location` contracts. The implementation also has local fake-
backed coverage for cadence, stale fixes, eligibility, lifecycle, sign-out,
offline state, and cleanup. Reimplementing any of those behaviors in Phase 7
would create a second publisher and is not needed.

No D03 publisher, test, migration, or dependency change was needed: the
existing Phase 4 implementation already covers the local publisher scope. This
update records its validation evidence and privacy boundaries only. The shared
`Phase 7/Omar.md` planning file was not changed.

## Existing implementation and evidence paths

- `lib/core/providers/driver_tracking_providers.dart` —
  `DriverTrackingController` starts only after canonical availability and
  latest-location reads; enforces one foreground stream and serialized writes;
  carries `active_trip_id` only for canonical `onTrip`; stops on Stop,
  sign-out, backgrounding, disposal, offline/ineligible canonical state, and
  connection failure; and re-reads canonical state before recovery.
- `lib/core/services/driver_location/driver_gps_stream_service.dart` —
  `DriverGpsTrackingConfig` defines the existing state-specific accuracy,
  device filtering, write cadence, movement threshold, and stream-driven
  freshness limits. Freshness does not schedule a timer or poll.
- `lib/core/services/driver_location/driver_location_validation_policy.dart` —
  `DriverLocationValidationPolicy` rejects missing accuracy, fixes older than
  15 minutes, fixes more than 5 minutes in the future, non-advancing source
  timestamps, and fixes rejected by its uncertainty-aware accuracy rule.
- `lib/core/services/driver_location/geolocator_driver_gps_stream_service.dart` —
  requests a foreground Geolocator stream and maps positions to provider-neutral
  fixes; cancellation propagates to the provider stream.
- `lib/core/repositories/driver_location_repository.dart` and
  `lib/core/services/driver_location/supabase_driver_location_service.dart` —
  validate sample association against canonical availability, derive actor
  identity from the authenticated Supabase user, read only that Driver's
  availability/latest row, and publish through `driver_record_location`.
- `supabase/migrations/011_phase3_driver_location_foundation.sql` and
  `supabase/migrations/024_guard_driver_location_recorded_at.sql` — define the
  RPC's approved-Driver, availability, active-Trip, timestamp, and monotonic
  ordering checks, plus participant read policy and a backend-only seven-day
  purge function. This source review does not verify the hosted deployment or
  purge schedule.
- `test/driver_tracking_controller_test.dart`,
  `test/driver_gps_stream_service_test.dart`,
  `test/driver_location_repository_test.dart`,
  `test/driver_home_location_sharing_test.dart`, and
  `test/driver_location_validation_policy_test.dart` cover the local path.

## Privacy and location handling rules

1. **Explicit, foreground-only sharing:** the Driver starts sharing through
   the existing Driver Home control. The app uses foreground location
   permission and stops the GPS stream when backgrounded. Returning to the
   foreground requires canonical revalidation before sharing resumes. Do not
   add background permissions, a background service, or silent tracking.
2. **Canonical eligibility and Trip association:** publish only while the
   authenticated Driver's canonical availability is `available`, `reserved`,
   or `onTrip`. Include the canonical active Trip ID only in `onTrip`; reject
   a mismatched Trip ID. Offline, missing, or otherwise ineligible state stops
   publication. A location event is not authority to start a Trip.
3. **Minimum useful sample:** the publisher sends coordinates, required
   accuracy, source `recorded_at`, and optional heading/speed, with an
   increasing per-Driver sequence. It filters stale, out-of-order, unchanged,
   or insignificant fixes and bounds update frequency using the existing
   profiles:

   | Canonical state | Accuracy | Device filter | Minimum write interval | Movement threshold | Stream-driven maximum silence |
   | --- | --- | ---: | ---: | ---: | ---: |
   | `available` | Low | 50 m | 30 s | 50 m | 2 min |
   | `reserved` | Medium | 25 m | 20 s | 25 m | 1 min |
   | `onTrip` | High | 10 m | 5 s | 10 m | 15 s |

   Maximum silence permits a write only when a new GPS fix arrives; it is not a
   timer or forced heartbeat.
4. **Authenticated ownership and visibility:** the client calls the existing
   RPC and does not write directly to `driver_locations`. The migration
   contract binds a sample to the authenticated approved Driver and canonical
   availability/Trip. Its read policy permits the Driver's own rows, Admin
   reads, and the assigned Rider's active-Trip rows. This documents repository
   policy only; it is not fresh hosted RLS evidence.
5. **Retention and logs:** the schema contains a backend-only purge function
   for rows older than seven days, and the domain plan says precise locations
   are excluded from ordinary application logs. This checkout does not verify
   that the purge job is deployed or scheduled. Do not log coordinates or raw
   location payloads. Before release, publish the Terms and Privacy Policy
   disclosures required by `README.md`; this engineering note does not replace
   that user-facing notice.
6. **Stop and cleanup:** explicit Stop, sign-out, backgrounding, disposal,
   ineligibility, or loss of the tracking connection cancels the foreground
   stream and prevents stale queued fixes from publishing. Foreground or
   connectivity recovery re-reads canonical availability and latest sequence
   before restarting.

## Phase 6 dependencies and gates

- **P6-R01 — Approve backend registry and canonical completion context:** the
  current Phase 4 publisher uses `driver_availability.active_trip_id` and the
  existing location RPC; it does not use the P6 canonical Driver completion
  source. P6-R01 is therefore not a blocker for this isolated local publisher
  or its fake-backed tests. It becomes a gate if later integration replaces
  this existing source with a new matching/accepted-Trip Driver context. The
  local P6 roadmap records the approved default backend mapping and production
  canonical completion source as unresolved.
- **P6-R04 — Hosted Admin and canonical RPC read acceptance:** the local Phase 6
  roadmap records hosted authenticated acceptance as partial/blocked. D03 local
  tests can continue with fakes. Do not treat P6-R04 as proof of hosted
  `driver_record_location` or D03 actor-role acceptance; no hosted operation was
  performed for this checkpoint.
- **P6-R06 — Stripe preparation:** not a D03 dependency. Cash-only behavior
  remains in force, and this checkpoint introduces no payment or financial
  operation.

## D02 independence

The Phase 4 publisher uses `DriverTrackingConnection` and the
`driver_record_location` RPC; it does not import or require
`TripRealtimeAdapter`. D03 validation was run on the `omar` checkout identified
above, which includes the locally committed D02 work. The publisher remains
independent of the D02 adapter API and does not depend on another developer's
unmerged branch.

## Local verification to record

Run from the RideX repository root on the target `omar` checkout to reproduce
the listed suite results:

```powershell
flutter test --no-pub test/driver_tracking_controller_test.dart
flutter test --no-pub test/driver_gps_stream_service_test.dart
flutter test --no-pub test/driver_location_repository_test.dart
flutter test --no-pub test/driver_location_validation_policy_test.dart
flutter test --no-pub test/driver_home_location_sharing_test.dart
flutter analyze --no-pub
```

The project owner reports these local results on branch `omar` at commit
`95ecc1caa37255cae9b2b5d36d0c13bca9ebd2d5`:

| Suite | Result |
| --- | ---: |
| `test/driver_tracking_controller_test.dart` | 54 PASS |
| `test/driver_gps_stream_service_test.dart` | 9 PASS |
| `test/driver_location_repository_test.dart` | 6 PASS |
| `test/driver_location_validation_policy_test.dart` | 3 PASS |
| `test/driver_home_location_sharing_test.dart` | 7 PASS |
| **Total** | **79 PASS, 0 FAIL** |

`flutter analyze --no-pub`: **No issues found**. These are owner-provided
execution results; they were not independently rerun in the documentation
review workspace. Reproduction commands:

```powershell
flutter test --no-pub test/driver_tracking_controller_test.dart
flutter test --no-pub test/driver_gps_stream_service_test.dart
flutter test --no-pub test/driver_location_repository_test.dart
flutter test --no-pub test/driver_location_validation_policy_test.dart
flutter test --no-pub test/driver_home_location_sharing_test.dart
flutter analyze --no-pub
```

Remaining limits for this D03 validation:

- No new hosted Supabase actor/role or RLS verification, live publisher
  integration, or Realtime test was performed for this checkpoint. The local
  P6-R04 record remains partial/blocked for hosted acceptance; it does not
  validate `driver_record_location` for D03.
- No new physical-device GPS permission, foreground/background, Stop/resume, or
  connectivity-recovery run was performed specifically for D03. Earlier Phase
  4 device/hosted evidence is recorded separately and is not new D03 evidence.
- The migrations define a seven-day backend purge function, but this review did
  not verify its hosted deployment or schedule.
- Before release, publish the user-facing location disclosures in the Terms and
  Privacy Policy as required by `README.md`.
