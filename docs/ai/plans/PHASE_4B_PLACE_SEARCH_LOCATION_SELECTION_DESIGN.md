# Phase 4B - Place Search and Location Selection

Status: Approved

Implementation commits: `2359a81`, `41dd2f5`

Final replacement-guard correction: verified in the current working tree;
commit pending.

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

Final repository verification on 2026-09-14 passed all 33 focused Checkpoint 4B
Flutter cases, `flutter analyze`, and the full suite with 132 tests passed and 2
intentional live Supabase skips. The known unsupported SVG `<filter>` warnings
remain non-failing. Deno is not installed on the verification host, so the Edge
Function cases were not independently rerun locally.

Read-only hosted Supabase metadata confirms that `places` is active at version 1
and that the `GOOGLE_MAPS_WEB_SERVICES_API_KEY` secret name exists. No secret
value was read. This metadata does not prove Google API enablement, restrictions,
quota controls, or a successful authenticated live request.

Commit `41dd2f5` clears a committed endpoint while map/GPS reverse geocoding is
unresolved. The final correction applies the same fail-closed behavior to
`selectPrediction` and `submitAddress`; regression coverage verifies pickup and
destination replacement, direct vehicle-screen blocking, successful resolution,
and failed/empty outcomes.

Physical Android verification additionally requires enabled Places API (New)
and Geocoding API v4, a restricted server credential stored as a Supabase Edge
Function secret, a deployed function, and a real authenticated Rider session.
Before release, RideX also requires public Terms of Use and Privacy Policy
surfaces that disclose location processing and incorporate Google's required
terms and privacy links.

On 2026-09-14, the project owner reported that Omar completed every previously
remaining Checkpoint 4B requirement successfully, including physical Android,
authenticated live Google place/geocoding, deployed Edge Function, and Google
Cloud configuration verification. Checkpoint 4B is **approved** based on that
attestation plus the repository evidence and final regression run. See
`docs/ai/verification/PHASE_4AB_FINAL_VERIFICATION_2026-09-14.md`.
