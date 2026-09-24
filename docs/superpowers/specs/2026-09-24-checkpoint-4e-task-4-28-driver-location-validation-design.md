# Checkpoint 4E Task 4.28 Driver Location Validation

## Goal

Prevent temporary GPS inaccuracies, invalid readings, stale callbacks, and
asynchronous ordering races from replacing the last valid Driver location.

## Accepted Fix Policy

`DriverLocationValidationPolicy` owns provider-neutral admission before cadence,
resource-significance, local state mutation, or publication:

- Coordinates must pass `LocationPoint` finite/range validation. The Geolocator
  adapter drops a position when they do not.
- Horizontal accuracy must be present, finite, and nonnegative. Invalid source
  accuracy is sanitized to missing by the adapter and rejected by the policy.
- `recordedAt` must be no earlier than 15 minutes before the current time and no
  later than 5 minutes after it. These are the existing trusted RPC boundaries,
  not new client-only thresholds.
- `recordedAt` must strictly advance past the latest accepted/canonical fix.
- Invalid optional heading or speed is omitted rather than making a usable
  coordinate invalid.

## Temporary Accuracy Policy

RideX does not impose a global maximum accuracy radius. Such a cutoff would be
environment-dependent and could discard legitimate urban readings.

When a candidate's accuracy is worse than the last valid fix, RideX compares
provider-neutral great-circle displacement with the candidate's own accuracy
radius. If the displacement remains inside that uncertainty radius, the
candidate cannot confidently establish a replacement position and is rejected.
A later fix with recovered accuracy is evaluated against the still-preserved
last valid fix and may proceed normally.

## Ordering And State Preservation

Rejected readings do not mutate the latest accepted fix, latest recorded time,
pending write, sequence, or server-confirmed timestamp. The existing single
ordered publisher and generation checks remain authoritative. A stale callback
arriving after a newer fix is queued cannot replace that queue entry.

Migration `024_guard_driver_location_recorded_at.sql` keeps the existing RPC
signature and per-Driver availability-row lock, then rejects a request when any
canonical row has an equal or newer `recorded_at`. The existing `23505` mapping
causes the Flutter controller to re-fetch canonical sequence/location state.
This protects against competing clients, not only callbacks in one process.

## Boundaries

- Preserve 4.24-4.27 cadence, write coalescing, profiles, lifecycle, and
  ineligible-state shutdown.
- Do not rewrite earlier migrations or loosen existing database constraints.
- Do not add UI states or new user-facing error handling from tasks 4.29-4.30.
- Do not add an arbitrary speed, distance, or absolute accuracy limit.

## Verification

Focused tests cover missing metadata, invalid provider coordinates, expired and
future source times, equal and older timestamps, temporary accuracy regression,
recovery to valid data, preserved canonical metadata, and a stale callback
racing a blocked publish. pgTAP covers a higher sequence with an older timestamp
at the trusted RPC boundary.
