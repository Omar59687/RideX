# P7-D06 — Realtime and GPS Integration Handoff

> **Superseded:** use [P7-RECONCILED-INTEGRATION-HANDOFF.md](P7-RECONCILED-INTEGRATION-HANDOFF.md) for the current-main reconciliation, Rider searching/cancellation integration, publication gate and Windows procedure. This earlier D06 note is retained only for its checkpoint-local evidence.

**Checkpoint:** P7-D06 / [GitHub Issue #100](https://github.com/Omar59687/RideX/issues/100)
**Reviewed baseline:** `e8d22f5c7dd7d8672cc7ec051493f2dd15e9137e`
**Checkout:** detached `HEAD` in an isolated checkout of the existing `omar` branch
**Disposition:** implementation and handoff evidence prepared for owner review; this document does not claim checkpoint acceptance.

## Scope and files

This handoff composes the existing D02 canonical Trip adapter, Phase 4/D03 foreground GPS publisher, and D04 Rider location adapter using fakes. It adds no production publisher, migration, Supabase configuration, or UI integration.

Files added for D06:

- `test/p7_d06_realtime_gps_integration_test.dart` — fake-backed Trip + GPS integration scenarios.
- `docs/ai/verification/P7-D06-Realtime-GPS-Integration-Handoff.md` — contracts, synthetic event sequence, device procedure, and open gates.

## Existing integration contracts

| Boundary | Existing contract | Consumer guidance |
|---|---|---|
| Canonical Trip | `TripRealtimeAdapter.watchTrip(tripId)` emits `TripRealtimeUpdate` values, including `VerifiedTripRealtimeEvent`, connection updates, verification updates, and failures. `TripRealtimeSource` supplies channel hints and `readCanonicalTrip`; the adapter verifies the authenticated participant and treats signals as hints. | Rider UI should render only verified Trip state and handle connection/verification states explicitly. Do not treat a Realtime row payload as canonical state. |
| Driver GPS publisher | `driverTrackingControllerProvider` exposes the existing `DriverTrackingController`; `start()`, `stop()`, `stopForSignOut()`, `synchronizeCanonicalState()`, and `recoverAfterConnectivity()` are the current control surface. It publishes foreground GPS through the existing `DriverLocationRepository`. | Driver UI should invoke the existing controller based on the current user action/lifecycle and show its state. Do not create a second GPS stream, location writer, or publisher. |
| Rider location | `RiderTripLocationAdapter.watchTrip(tripId)` emits `RiderTripLocationUpdate` variants: `RiderTripLocationSnapshot`, `RiderTripLocationCleared`, `RiderTripLocationConnectionUpdate`, and `RiderTripLocationVerificationUpdate`. It verifies the Trip through D02 and rereads canonical location on signals/recovery. | Rider UI should subscribe to this typed stream and dispose the subscription with its view/session. Location-change notifications carry Trip/Driver identity as triggers; coordinates come from the canonical read. |

Relevant implementations are `lib/core/services/trips/trip_realtime_adapter.dart`, `trip_realtime_source.dart`, `rider_trip_location_adapter.dart`, `rider_trip_location_source.dart`, and the existing `lib/core/providers/driver_tracking_providers.dart`.

### Synthetic event sequence

The integration test uses synthetic UUIDs and no account or hosted data:

1. Canonical Trip assignment returns Trip `c1000000-0000-4000-8000-000000000001`, Rider `a1000000-0000-4000-8000-000000000001`, Driver `b1000000-0000-4000-8000-000000000001`, status `accepted`, version 1.
2. Canonical status progresses in order: `driverArriving` version 2 / status sequence 1; `driverArrived` version 3 / sequence 2; `inProgress` version 4 / sequence 3.
3. Duplicate/out-of-order status signals for sequences 1 and 2 are delivered after sequence 2 and must not replay older state.
4. A Trip channel error/rejoin triggers a canonical reread; the restored Trip remains `inProgress` at version 4.
5. The existing DriverTrackingController receives foreground GPS fixes. The fake repository records monotonically sequenced samples and makes them available to the Rider source. D04 emits the exact Trip/Driver snapshot.
6. A delayed canonical location read returns sequence 1 after sequence 2 was published. The stale duplicate result is not emitted; the later canonical signal is processed in sequence.
7. The location channel disconnects. A third Driver fix is persisted while notifications are unavailable. The controlled bounded retry reconnects and rereads canonical location sequence 3, recovering the missed update.
8. A deliberately stale sequence-1 row is read after sequence 3 and must not move the Rider location backwards.
9. Terminal Trip status `completed` version 5 / status sequence 4 clears Rider location state. The test checks that Trip, location, and foreground GPS subscriptions are canceled.
10. Separate cases replace the session identity and cancel the consumer, verifying immediate clear/cancellation behavior.

## Local validation scenarios

The single focused test file contains three deterministic scenarios:

| Scenario | What it exercises |
|---|---|
| Ordered Trip + GPS flow, duplicate/stale status, Trip reconnect, delayed stale location, location disconnect/missed update recovery, stale location, terminal Trip, cleanup | D02 and D04 adapters over fake source streams and the real existing Riverpod `DriverTrackingController` over fake GPS/repository dependencies. Verifies canonical rereads, location ownership, sequence order, terminal clear, and cancellation. |
| Session identity replacement | D04 clears the subscribed Rider state and closes both its location source and D02 Trip source subscription. |
| Logout | Setting the fake authenticated user to null and emitting the session-change signal clears Rider state and closes both subscriptions. |
| Consumer cancellation | Disposing the D04 consumer cancels both source subscriptions and leaves zero active fake subscriptions. |

These are synthetic local adapter tests. They do not prove PostgreSQL RLS, JWT refresh/revocation, Realtime publication membership, Supabase channel delivery, dispatch integration, or physical-device behavior.

## UI owner handoff

### Rider UI owner — Sanad

Compose the existing `SupabaseTripRealtimeSource` and `SupabaseRiderTripLocationSource` with one authenticated Supabase client, then inject them into `TripRealtimeAdapter` and `RiderTripLocationAdapter`. Subscribe with the exact current Trip ID using `watchTrip(tripId)`. Render a location only from `RiderTripLocationSnapshot`; clear it on `RiderTripLocationCleared`; represent connection and verification updates as non-authoritative status. Cancel the subscription when the Trip view is disposed, the Trip changes, or the auth session is replaced. Do not subscribe directly to tables or parse location coordinates from Realtime payloads.

### Driver UI owner — Moath

Use the existing `driverTrackingControllerProvider` and `DriverTrackingController` from `lib/core/providers/driver_tracking_providers.dart`. Start foreground sharing only through its existing `start()` action after the UI's existing authorization/availability flow, and call the established `stop()` / `stopForSignOut()` paths when sharing ends. Use its `DriverTrackingState` to represent sharing status. Canonical state and connectivity recovery remain on the controller's established methods. The Driver UI must not create another GPS publisher or write `driver_locations` directly.

The integration test is independent of either owner's unmerged UI work. These are API handoff notes, not a claim that the UI integrations are complete.

## Physical two-device test plan

### Prerequisites and actors

- Owner-approved isolated staging Supabase project and test accounts; do not use production identities or dispatch.
- Accepted/merged Trip contract and the intended D02/D04 integration available on the test build.
- Current schema, confirmed Realtime publication membership, and approved Rider/Driver/blocked-role RLS checks for the exact tables and operations used.
- One assigned Driver account on Device A and its assigned Rider account on Device B; one synthetic Cash-only Trip. No Card selection, Stripe action, or real financial operation.
- Both devices signed in to the intended test accounts, foreground location permission granted to Device A, and a written test window/owner available to stop the run.

### Procedure and expected results

1. Create the synthetic Trip through the approved staging flow and verify the canonical Trip ID and exact assigned Rider/Driver on both devices.
2. On Device A, enter the existing Driver sharing flow. Confirm the existing controller reports sharing and the Driver's foreground location advances. Device B must show only snapshots scoped to that Trip and assigned Driver.
3. Advance the Trip through the approved ordered lifecycle. Both clients should reflect canonical verified status; duplicate/reordered notifications must not regress the status or location.
4. Briefly interrupt network connectivity on one device. After reconnect, confirm the client rereads canonical Trip/location and recovers the latest state without replaying an older coordinate.
5. Complete or cancel the Trip through the approved lifecycle. Device B should clear active location state; Device A should stop publishing under the existing lifecycle behavior.
6. Sign out or replace the Rider session and verify old Trip/location state is cleared before any new account's state appears. End the test by signing out both accounts and recording the synthetic Trip ID and observations for authorized cleanup.

### Stop and rollback conditions

Stop immediately if either device shows another Trip's data, an unassigned Driver's coordinates, a stale coordinate after terminal status/session replacement, an authorization error that exposes row contents, unexpected background publishing, or any financial/Card/Stripe flow. Stop sharing and sign out. Preserve logs and identifiers for owner review; do not manually delete rows or change policies/publication settings. Any fixture teardown must use the owner-approved staging cleanup path.

This is a proposed test plan only. No physical run occurred for this handoff.

## Dependencies and acceptance gates

The Phase 6 tracker is not closed. The current local closeout record `docs/parallel-development/phase-6/P6_CURRENT_CLOSEOUT_GATES_2026-10-25.md` marks:

- **P6-R01 PARTIAL:** canonical Driver eligibility/Trip source and mapping exist, but the activation flag remains default-off, the canonical Driver UI is not mounted, and hosted acceptance is missing. This does not block fake adapter composition; it blocks a physical flow that depends on the canonical Driver path until the owner-approved integration/acceptance is available.
- **P6-R04 PARTIAL:** local hardening exists, but the hosted Admin/Rider/Driver/blocked-role actor matrix and PostgREST/session checks remain unverified. This is a blocker for hosted/device security acceptance, not for synthetic local tests.
- **P6-R06 is not part of D06:** Stripe runtime remains unconfirmed. D06 stays Cash-only and performs no payment work.

Issue #100 also calls for adapter/UI integration only after the accepted Trip contract is merged. This isolated test composes the available adapters using synthetic canonical models; it does not assert that the cross-team production contract or UI branches have been merged.

## Realtime and security limitations

- `supabase/config.toml` enables the Realtime service, but this repository snapshot does not establish publication membership for `trips`, `trip_status_events`, or `driver_locations`. No local database inspection or hosted query was performed. Publication membership and live delivery remain unknown and require separately authorized evidence.
- `SupabaseTripRealtimeSource` subscribes only to `PostgresChangeEvent.insert` and `.update` on `trips`, plus `.insert` on `trip_status_events`; it registers no DELETE callback. D02 then rereads canonical Trip state and does not treat the payload as authoritative. DELETE exposure for other subscribers remains a publication-wide security gate; the migration is now deferred and fails closed when DELETE/TRUNCATE are enabled.
- JWT refresh, account blocking, role changes, and server-side authorization revocation while a Realtime channel is already open were not exercised. Local session identity replacement tests only the adapter's injected-session invalidation behavior.
- No hosted Supabase, RLS, migration, physical-device, or real Realtime operation was performed.

## Validation record

**Status: NOT RUN in this workspace.** Flutter and Dart SDK executables are unavailable, so the new Dart test was not compiled or executed and no Flutter analyzer result is claimed. The test has not been independently accepted by the owner.

Run from the repository root on the Windows Flutter 3.27.3 / Dart 3.6.1 checkout:

```powershell
flutter test --no-pub test/p7_d06_realtime_gps_integration_test.dart
flutter analyze --no-pub
git diff --check
```

Record the actual branch, full commit SHA, exact test counts, analyzer result, and any device/hosted gates separately after local execution. Do not copy this document's baseline SHA as evidence of a different local commit.
