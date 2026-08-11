# Phase 4A - Google Maps and GPS Foundation

Status: Approved for implementation

## Scope

Checkpoint 4A adds Google Maps to Rider Home and Driver Home, retrieves one
foreground device location, models all required permission and service states,
and keeps both experiences usable when maps or GPS are unavailable.

The existing illustrative maps on booking, searching, trip, arrival, and
history screens remain unchanged because their route and movement semantics
belong to later checkpoints.

## Architecture

Device location follows:

```text
Geolocator
  ->
RideX Location Service
  ->
Location Repository
  ->
Riverpod Current Location Controller
  ->
Rider/Driver UI
  ->
Google Map visualization
```

`LocationPoint` is the provider-independent coordinate value. Geolocator and
Google Maps types remain inside their integration boundaries. Current location
does not mutate `BookingDraft`, publish Driver locations, or start a stream.

## State And Lifecycle

The location state distinguishes permission not requested, granted, denied,
permanently denied, and device location service disabled. It also represents
loading, an available point, a timeout, and a sanitized unavailable state.

Permission requests occur only after an explicit user action. A persistent
client-safe flag distinguishes the first request from a previous denial. The
controller deduplicates concurrent operations and ignores stale asynchronous
results. Checkpoint 4A performs one-shot foreground location retrieval only.

## Google Maps

One shared map widget serves Rider Home and Driver Home. It converts
`LocationPoint` to `LatLng` at the widget boundary, renders the current point,
and positions the camera after a valid location arrives. When no location is
available, the map uses a neutral world view and a clear fallback overlay; it
does not invent a user coordinate or Jordan location.

Tests replace native map and location boundaries with deterministic fakes, so
they require no map network access, hardware GPS, or live credentials.

## Configuration And Security

Android and iOS use separate native, ignored API-key configuration. Dart uses
only a non-secret compile-time enablement flag so no API key is placed in
ordinary Dart source or logs.

- Android reads `MAPS_API_KEY` from ignored `android/local.properties` and
  supplies it to the Maps SDK manifest metadata.
- iOS reads `GOOGLE_MAPS_API_KEY` from ignored
  `ios/Flutter/config.local.xcconfig` and supplies it to `GMSServices`.
- Each key must be restricted to its platform application and only its Maps
  SDK. Places, Geocoding, Routes, and Directions APIs are not enabled by this
  checkpoint.

Missing configuration produces a safe in-app fallback. No credential is
invented, committed, or printed.

## Dependencies And Platforms

- `google_maps_flutter: 2.12.3`, pinned for the documented Flutter 3.27.3 and
  Dart 3.6.1 baseline.
- `geolocator: 13.0.4`, pinned below the release requiring newer Flutter.
- Existing `shared_preferences` moves to runtime dependencies for the local
  permission-request marker.
- Android receives Internet and foreground coarse/fine location permissions.
- iOS receives foreground-only usage text and moves to the Maps-compatible
  iOS 14 deployment target.

No background location permission, location service, or capability is added.

## Verification

Focused unit and widget tests cover coordinate validation, permission states,
service-disabled behavior, successful and failed current-location retrieval,
timeout/error mapping, stale operation protection, Rider/Driver fallback
behavior, and offline map substitution. Formatting, `flutter analyze`, focused
tests, and the complete non-live Flutter regression suite run before approval.

Physical Google Map and GPS verification remains incomplete until valid
restricted credentials and suitable devices are available. iOS build/device
verification is also unavailable on the current Windows host.

## Exclusions

Phase 4A does not implement Places, search, pickup/destination selection,
geocoding, Routes/Directions, route geometry, distance, duration, ETA, fares,
FareQuote, matching, Realtime, continuous Driver tracking, Driver-location
publishing, payments, or Phase 5+ behavior.
