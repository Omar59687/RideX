# Phase 4B - Place Search and Location Selection

Status: Approved for implementation

## Scope

Checkpoint 4B lets a Rider choose coordinate-backed pickup and destination
locations through Google place predictions, address geocoding, the current GPS
point, or direct map selection. It validates that both endpoints are resolved
before the existing booking flow can continue.

Routes, route geometry, distance, duration, ETA, fares, matching, Driver
tracking, and later phases are excluded.

## Architecture

```text
Google Places API (New) and Geocoding API v4
  -> authenticated Supabase Edge Function
  -> RideX Place Service
  -> Place Repository
  -> Riverpod Location Selection Controller
  -> Rider pickup/destination UI
```

The Edge Function owns a separate server-side Google web-services credential.
Android and iOS Maps SDK credentials remain native, platform-restricted, and
Maps-only. Flutter receives normalized RideX data and never receives the server
credential or raw provider errors.

Development Mock mode uses explicit deterministic place data. Supabase mode
never falls back to Mock results after a production failure.

The proxy applies per-Rider operation and concurrency limits as an initial
abuse boundary. Google Cloud quotas and budget alerts remain required because
Edge Function instances do not share in-memory counters.

## Domain Rules

`LocationPoint` remains the canonical provider-neutral coordinate. A
`RideLocation` adds display metadata, selection source, and optional provider
reference, but its label and address never replace its point.

Pickup and destination remain independent. They are routing-ready only when
both have valid points, no selection operation is unresolved, and their exact
latitude/longitude pairs differ. No minimum-distance rule is introduced.

## Search And Concurrency

Autocomplete ignores trimmed queries shorter than three characters, debounces
meaningful input, deduplicates repeated queries, and uses one session token for
each search interaction. A generation counter rejects stale autocomplete,
details, forward-geocode, and reverse-geocode responses. Selecting a result,
changing the marker, changing endpoints, or disposing the controller
invalidates older operations.

Search is biased toward the current GPS point when available and otherwise
toward Jordan. Results are not country-restricted so the architecture can
support later geographic expansion.

## Map Selection

The active endpoint can be placed by tapping the Google Map and refined with a
draggable marker. Reverse geocoding runs only after a tap or drag end, never for
animation frames. Valid coordinates survive an address lookup failure and are
shown as a dropped pin until address resolution can be retried.

The map displays current location, pickup, and destination distinctly. Map or
GPS unavailability never disables place search.

## Efficiency And Policy

- Autocomplete uses a 350 millisecond debounce and at most five predictions.
- Place Details requests only ID, formatted address, and point.
- Geocoding requests use fixed minimal field masks.
- Reverse-geocode results are reused for the same active point where practical.
- Google-derived predictions include visible Google Maps attribution.
- Ordinary tests use fakes and consume no Google quota.

## Verification

Unit, controller, widget, and Edge Function tests cover coordinate validation,
debouncing, empty/error states, stale response rejection, independent endpoint
selection, marker updates, forward/reverse geocoding, GPS fallback, manual
selection without GPS, and routing-readiness validation.

Physical Android verification additionally requires enabled Places API (New)
and Geocoding API v4, a restricted server credential stored as a Supabase Edge
Function secret, a deployed function, and a real authenticated Rider session.
Before release, RideX also requires public Terms of Use and Privacy Policy
surfaces that disclose location processing and incorporate Google's required
terms and privacy links.
