# Checkpoint 4D Driver Location Tracking Design

Date: 2026-09-17
Status: Approved design; implementation pending
Branch: `codex/phase-4d-driver-location`

## Goal and boundary

An approved Driver can explicitly share foreground GPS positions while the
canonical Supabase availability row is `available`, `reserved`, or `onTrip`.
RideX persists positions through the existing trusted `driver_record_location`
RPC, recovers the latest canonical position after interruptions, and prevents
stale positions and duplicate tracking subscriptions. This is the foundation
for later matching and Rider trip tracking; neither is implemented in 4D.

The Driver Home online switch is currently session-local demo state. It does
not grant backend availability and must not trigger production location writes.
The 4D tracking control reads canonical availability and explains when vehicle
or availability setup is still needed. Connecting the mock switch to real
vehicle and availability operations belongs to a later checkpoint.

## Existing contracts

- `LocationPoint` is the provider-neutral coordinate value. Geolocator types
  stay in the device service.
- Migration `011` owns `driver_locations` and `driver_record_location`; later
  migrations and security rules remain intact. Do not edit committed migrations.
- The RPC requires an approved, unblocked Driver and canonical availability in
  `available`, `reserved`, or `onTrip`. An `onTrip` sample requires the canonical
  active Trip ID; the other states must omit it.
- The RPC rejects recorded times outside its accepted window and sequences
  that do not exceed the Driver's existing maximum.
- Supabase mode never falls back to mock writes. Mock mode uses explicit,
  deterministic local behavior.

## Data flow

```text
Geolocator foreground stream
  -> RideX device location service
  -> Driver location repository
  -> Riverpod tracking controller
  -> Driver Home status and latest position

Authenticated Supabase service
  -> canonical availability/latest-location read
  -> trusted driver_record_location RPC
```

The repository exposes provider-neutral availability, timestamped sample,
saved location, and sanitized failure types. The Supabase adapter alone maps
database rows and calls the RPC. No client writes directly to
`driver_locations`.

## Tracking and ordering

Starting tracking requires a deliberate Driver action, foreground permission,
and a fresh canonical availability read. The controller owns at most one device
stream and one in-flight publish. It stops on explicit Stop, sign-out, loss of
eligibility, disposal, or app backgrounding. On foreground return it rechecks
permission and canonical availability before resuming; no background location
permission or background service is added.

`recorded_at` is the device sample time. `received_at` is assigned by the
database and is authoritative for freshness of saved locations. On start or
reconnect, the repository reads the latest row ordered by sequence and derives
the next positive sequence from it. A delayed sample must not overwrite a newer
local or canonical point. A rejected sequence triggers a canonical re-fetch
before any later publish; it must not be blindly retried with the same value.
Missing, expired, malformed, or unauthorized rows are not presented as current.

After network recovery, Realtime reconnection, foreground return, or app restart
where the session is restored, re-fetch the canonical latest row before
displaying a current position or restarting publication. Reconnect events are
coalesced so they cannot create a second GPS stream or conflicting sequence
writers. The controller may use a connectivity/Realtime signal to initiate
recovery, but missed events are never treated as a complete location history.

## Driver UI and failures

Driver Home shows a separate tracking control and a concise status: ready,
starting, sharing, paused, or unavailable. It indicates the last confirmed
position's age when known. Permission denial, disabled GPS, unavailable network,
and backend ineligibility receive safe, actionable messages. Raw provider and
database errors stay out of the UI. The existing demo request and mock presence
remain explicitly identified as demo behavior.

## Delivery slices and documentation

1. Provider-neutral models, service/repository contracts, Supabase adapter,
   deterministic mock, and focused contract tests. No GPS stream or UI change.
2. Foreground GPS stream and Riverpod controller, including ordering,
   lifecycle, reconnect, and recovery tests. Deliver this in two bounded
   steps: 2A adds only the device stream boundary and fake-driven tests;
   2B adds the controller in two small steps: 2B1 covers explicit start/stop,
   single-stream ownership, and ordered publication; 2B2 covers app lifecycle,
   reconnect, and canonical recovery tests.
3. Driver Home tracking control/status and focused widget tests.
4. Final security/architecture review, formatting, analysis, full non-live
   regression suite, and supported physical/authenticated verification.

Each slice updates `Plan.md` and `docs/ai/ops/CURRENT_STATUS.md` with its exact
result, tests, limitations, commit, and next slice. Commit only focused verified
work locally. Stop after each slice for orchestration review. No push, merge,
remote migration, or deployment is part of these prompts.

## Acceptance

- Successful canonical Driver location writes when backend eligibility is met.
- Freshness and monotonic sequence survive restart and reconnect.
- Stale/out-of-order samples cannot replace the latest valid position.
- One foreground stream and one publisher remain active at most.
- Recovery re-fetches canonical state after ambiguous interruption.
- App lifecycle and sign-out stop tracking without residual subscriptions.
- Tests cover authorization/error mapping, ordering, reconnection, and UI states.
- No Driver matching, Rider live tracking, background tracking, or 4E optimization.
