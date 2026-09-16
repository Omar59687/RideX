# Checkpoint 4B Replacement Routing Guard Design

Date: 2026-09-14
Status: Implemented and verified

## Problem

Commit `41dd2f5` clears a committed pickup or destination while map/GPS reverse
geocoding is unresolved. Prediction-details and forward-geocode replacements do
not clear the existing endpoint before awaiting the repository, so
`BookingDraft.isRoutingReady` can remain true with stale coordinates during
those operations.

## Behavior

When `selectPrediction` or `submitAddress` begins resolving a replacement, the
controller clears the affected endpoint from `BookingDraft` before awaiting the
repository. This makes all existing downstream `isRoutingReady` checks fail
closed.

On success, the controller commits the newly resolved `RideLocation`. On empty
results or failure, the affected endpoint remains absent and the existing safe
selection error remains visible. The controller does not silently restore the
old endpoint because the rider has explicitly started replacing it.

## Implementation

Reuse `_clearCommittedLocation()` in
`lib/core/providers/place_providers.dart`. Call it in `selectPrediction` and
`submitAddress` immediately before the state enters `PlaceSearchStatus.resolving`.
Do not change repository contracts, `BookingDraft`, routing, screens, or backend
services.

## Concurrency

Preserve the existing generation counter and stale-response checks. A newer
selection may commit only its own result. Clearing the endpoint at the start of
each replacement ensures no older committed location is considered current
while any replacement operation owns the active generation.

## Tests

Extend `test/place_selection_controller_test.dart` with regression coverage for:

- Pickup and destination prediction replacements remain routing-blocked until
  Place Details settles.
- Pickup and destination forward-geocode replacements remain routing-blocked
  until geocoding settles.
- Direct vehicle selection remains disabled during both replacement operation
  types.
- Successful resolution commits the replacement and restores routing readiness.
- Empty/error outcomes leave the affected endpoint uncommitted.

Run formatting for the two changed Dart files, the focused controller test,
`flutter analyze`, and the complete non-live Flutter suite.

## Scope

This change closes only the Checkpoint 4B replacement routing guard. It does not
implement routing, change location provider contracts, alter the Edge Function,
or modify Checkpoints 4C through 4G. Checkpoint approval still depends on the
recorded physical/live evidence supplied by the project owners.
