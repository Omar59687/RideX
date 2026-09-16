# Checkpoint 4C Routing Engine Design

Date: 2026-09-14
Status: Approved design; implementation pending

## Scope

Checkpoint 4C calculates and displays one trusted route between the Rider's
settled pickup and destination. It exposes route geometry, distance, duration,
origin, and destination; recalculates when either endpoint changes; and prevents
stale responses from replacing the current route.

This checkpoint does not calculate fares, create Fare Quotes, route through
intermediate stops, manage stops, match Drivers, track Drivers, publish location,
or implement Checkpoint 4D or later behavior.

## Provider Policy

Production Supabase mode uses Google Routes API v2 `computeRoutes` through the
existing authenticated `places` Edge Function. The request asks for one
traffic-aware driving route with overview encoded geometry, metric units, and no
alternatives.

The Edge Function reads a separate server-only `GOOGLE_ROUTES_API_KEY`, restricted
to Routes API. Existing Android/iOS Maps SDK keys remain Maps-only, and the
existing `GOOGLE_MAPS_WEB_SERVICES_API_KEY` remains restricted to Places API
(New) and Geocoding API v4. Flutter never receives either server credential.

Development Mock mode uses a deterministic route repository and never calls
Google. Configured Supabase mode never falls back to Mock routing after failure.

## Architecture

```text
Google Routes API v2
  -> authenticated Supabase Edge Function `route` operation
  -> RideX Routing Service
  -> Route Repository
  -> Riverpod Route Controller
  -> provider-neutral Route State
  -> booking UI
  -> Google map visualization boundary
```

Google request/response types and encoded polylines remain inside the service and
repository integration boundary. `LatLng`, `Polyline`, and camera objects remain
inside the Google map widget.

## Domain Contracts

`RouteRequest` contains:

- `LocationPoint origin`
- `LocationPoint destination`
- ordered `List<LocationPoint> intermediatePoints`

The intermediate list is part of the stable contract so Phase 5 can add ordered
stops without replacing the routing architecture. Checkpoint 4C accepts only an
empty list and rejects non-empty lists as unsupported.

`RouteResult` contains:

- exact request origin and destination snapshots;
- decoded provider-neutral `List<LocationPoint>` geometry;
- positive integer `distanceMeters`;
- positive integer `durationSeconds`.

A valid result must contain at least two valid geometry points, positive metrics,
and request endpoints that still match the current settled booking endpoints.
Route metrics remain separate from fare calculation and are not treated as an
authoritative Fare Quote.

`RouteState` distinguishes idle, loading, ready, and failure. Loading and ready
states retain the exact `RouteRequest` identity. User-facing failures are fixed,
sanitized RideX messages and never expose raw Google or Supabase errors.

## Edge Function Contract

The existing authenticated function gains this strict operation body:

```json
{
  "operation": "route",
  "origin": {"latitude": 0.0, "longitude": 0.0},
  "destination": {"latitude": 0.0, "longitude": 0.0},
  "intermediates": []
}
```

Non-empty `intermediates`, unknown keys, invalid coordinates, and equal endpoints
are rejected. The Google request uses:

- `travelMode: DRIVE`
- `routingPreference: TRAFFIC_AWARE`
- `computeAlternativeRoutes: false`
- `polylineQuality: OVERVIEW`
- `polylineEncoding: ENCODED_POLYLINE`
- `units: METRIC`

The response field mask requests only distance, duration, and encoded polyline.
The function returns one normalized route and applies existing Rider
authorization, request-size, timeout, concurrency, rate-limit, and sanitized
error behavior.

## State And Recalculation

One session-local `RouteController` observes the canonical
`bookingControllerProvider` rather than relying on screen callbacks. It starts a
request only when both settled endpoints exist and differ.

Each endpoint change increments a route generation and immediately clears any
old geometry and metrics. The controller schedules calculation in one microtask;
additional endpoint writes before that microtask replace the pending request, so
sequential synchronous rebooking writes issue only the final route request. A
response commits only when:

- its generation is still current;
- its request equals the controller's current request;
- the booking's current origin and destination still equal that request.

Invalid endpoints clear route state. Retry repeats only the current valid
request. Sign-out/session container disposal removes route state.

## UI And Progression

Destination and pickup screens watch the route controller. Their shared map
receives only provider-neutral route geometry. The Google map adapter converts
geometry to a `Polyline`, uses existing semantic route colors, and fits the
camera to route bounds after valid geometry changes.

A shared compact route-status surface shows loading, service-derived distance
and duration, or a safe failure with Retry. No route is drawn in idle, loading,
or failure states. The illustrative `MapPlaceholder` is not treated as trusted
geographic rendering.

Pickup, vehicle, fare, and searching progression fails closed unless a ready
route exactly matches the current endpoints. This prevents endpoint validity
from being mistaken for a successfully calculated current route. These guards
do not calculate or alter fare.

## Verification

Minimum Flutter coverage:

- request/result validation and intermediate-stop rejection;
- encoded-polyline decoding and malformed response rejection;
- service-derived geometry, meters, seconds, origin, and destination;
- automatic route calculation for valid settled endpoints;
- endpoint-change recalculation and immediate old-route invalidation;
- stale/out-of-order response rejection;
- safe failure and retry;
- fail-closed booking progression;
- provider-neutral geometry handoff to the map builder;
- Google map polyline construction and route-bounds calculation without network
  access.

Minimum Edge Function coverage:

- authentication and Rider authorization remain enforced;
- strict route request validation;
- non-empty intermediate rejection;
- exact Google route policy and field mask;
- successful normalized response;
- empty, malformed, timeout, rate-limit, and upstream failure mapping;
- existing place/geocoding operations remain unchanged.

Run formatting, focused Flutter tests, Edge Function tests when Deno is available,
`flutter analyze`, and the complete non-live Flutter regression suite.

## Approval Boundary

Checkpoint 4C is approved only when every Plan approval-gate item has evidence.
If the Routes API key, API enablement/restrictions, deployed function version,
authenticated live route, or physical Android polyline rendering cannot be
verified, record those gaps and leave 4C unapproved. Do not start 4D.

## Implementation Status

The planned Flutter and Edge Function source changes are implemented locally.
Automated Flutter evidence covers route normalization, encoded-polyline decoding,
ordered-stop rejection, recalculation, immediate invalidation, stale-response
protection, retry, provider-neutral map handoff, Google polyline/bounds conversion,
service-backed metrics, and fail-closed progression.

Final verification passed 15 focused cases, all 144 non-live Flutter tests with
2 intentional skips, `flutter analyze --no-pub`, formatting, and
`git diff --check`. The Deno `places` suite passed 23 tests with 0 failures.
Routes API/key setup, deployment, authenticated live routing, physical Android
polyline rendering, service metrics, endpoint identity, and endpoint-change
recalculation are verified. Checkpoint 4C is approved.
