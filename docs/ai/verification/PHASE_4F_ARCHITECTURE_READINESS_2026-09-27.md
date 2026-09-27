# Checkpoint 4F Architecture Readiness

Date: 2026-09-27
Branch: `codex/phase-4f-architecture-readiness`
Base: `1576692`
Implementation commit: `6ded865`

## Result

Checkpoint 4F is **Approved**. Tasks 4.31 through 4.35 and every 4F approval
gate item are supported by the existing implementation, focused regression
coverage, and the evidence below. Checkpoints 4A through 4F are approved.
Checkpoint 4G remains incomplete, so Phase 4 is not fully approved and Phase 5
must not begin.

No production Dart behavior was changed for 4F. The implementation adds one
targeted architecture-boundary test:
`test/architecture_boundary_test.dart`.

## Requirement Evidence

| Requirement | Classification | Evidence |
| --- | --- | --- |
| 4.31 Provider-neutral map/GPS architecture | Already compliant and adequately tested | `LocationPoint`, `RouteResult`, `RouteState`, Driver-location models, and controller states are provider-neutral. Geolocator is isolated in location/GPS services; Supabase is isolated in service/adaptor and composition boundaries; Google SDK types are isolated in the approved map widgets. The boundary test checks the model, feature UI, and adapter allowlists. |
| 4.32 Key and map-service configuration | Compliant but missing verification/documentation, now closed by 4F evidence | Supabase URL and publishable/anon key values use Dart defines and `EnvConfig`; recognized secret/service-role values are rejected. Android and iOS Maps keys use local ignored platform configuration. Google web and routing credentials are read only by the Supabase Edge Function environment. No committed production credential was found. |
| 4.33 Smart City location foundation | Already compliant and adequately tested | Shared `LocationPoint` supports Rider and Driver coordinates. Driver contracts retain canonical availability, optional active Trip association, sequence, recorded/received timestamps, accuracy, heading, and speed. Foreground Driver publication remains repository/RPC controlled. Matching and Rider live tracking are not implemented. |
| 4.34 Trusted local routing | Already compliant and adequately tested | The authenticated `places` route operation uses Google Routes API v2 and returns normalized geometry, meters, and seconds. `GoogleRouteRepository` decodes geometry into provider-neutral points and `RouteResult` preserves service-derived distance and duration. 4C evidence covers live routing, geometry, metrics, and endpoint recalculation. |
| 4.35 Future reuse | Compliant but missing verification/documentation, now closed by 4F evidence | `RouteResult.geometry` and `distanceMeters` can support later navigation, ETA, and fare inputs. Driver availability, trip association, sequence, timestamps, and coordinates can support later matching and live Driver tracking. These outputs are infrastructure only and do not implement those business features. |

## Architecture Flow

```text
Provider SDK
  -> adapter/service
  -> repository
  -> Riverpod controller/provider
  -> provider-neutral state/model
  -> feature UI
```

### Permitted Provider Boundaries

- Google Maps SDK imports are limited to `lib/core/widgets/google_current_location_map.dart` and `lib/core/widgets/google_location_selection_map.dart`.
- Geolocator imports are limited to `lib/core/services/location/location_service.dart` and `lib/core/services/driver_location/geolocator_driver_gps_stream_service.dart`.
- Phase 4 Supabase imports are limited to the explicit route, place, Driver-location, client-composition, and bootstrap files listed by `test/architecture_boundary_test.dart`.
- Provider-neutral models and feature UI do not import Google Maps, Geolocator, Supabase, or `supabase_flutter` packages.
- Google request/response handling and encoded-polyline decoding remain inside the route integration boundary. Map `LatLng`, `Polyline`, and camera types remain inside Google map widgets.

## Credentials And Configuration

- Restricted Android and iOS Maps SDK keys are client-visible platform configuration. They must remain restricted to the application and Maps SDK APIs.
- `GOOGLE_MAPS_WEB_SERVICES_API_KEY` and `GOOGLE_ROUTES_API_KEY` are server-only Supabase Edge Function secrets. Flutter never receives them.
- Supabase publishable or legacy anon keys are public-client configuration and remain subject to Row Level Security.
- Supabase service-role keys, secret keys, database passwords, administrative credentials, access tokens, refresh tokens, and user passwords are prohibited from Flutter source, committed configuration, logs, and bundled files.
- Static inspection found no committed production credential or secret value.

## Trusted Routing

Configured Supabase mode sends the canonical settled endpoints through the
authenticated `places` Edge Function. The route operation requests one
traffic-aware driving route with overview geometry and metric units. The
normalized response contains encoded geometry, positive distance in meters, and
positive duration in seconds. The repository decodes geometry to
`List<LocationPoint>`, and `RouteController` commits only results matching the
current request and booking endpoints. Straight-line coordinate distance is not
used as the route result.

## Later Mobility Reuse

- ETA can use the trusted route duration and later combine it with current route or traffic policy.
- FareQuote calculation can use trusted route distance and separately owned pricing rules.
- Driver matching can use canonical Driver availability, coordinates, timestamps, and trip association.
- Live Driver tracking can consume saved Driver locations with sequence and authoritative `receivedAt` freshness.
- Trip navigation can consume provider-neutral route geometry and endpoint snapshots.

These are future consumers only. No matching, fare calculation, Rider live-trip
tracking, trip navigation, or new live business state was added in 4F.

## Explicit Exclusions

- No Driver matching.
- No fare calculation or FareQuote implementation.
- No Rider live-trip tracking.
- No trip navigation.
- No background GPS.
- No additional map or routing provider.
- No Checkpoint 4G work.
- No Phase 5 work.
- No migration changes, deployment, or hosted Supabase operation.

## Separate 4E Operational Follow-Up

`024_guard_driver_location_recorded_at.sql` remains a separate unresolved
operational 4E follow-up. It exists in Git but has not been deployed to hosted
Supabase. Its pgTAP regression has not been independently run because Docker was
unavailable. Migration 024 was not edited, deployed, or tested during 4F.

## Verification

Focused command:

```text
flutter test test/architecture_boundary_test.dart test/app/config/env_config_test.dart test/ride_map_service_test.dart test/location_repository_test.dart test/current_location_controller_test.dart test/route_repository_test.dart test/route_controller_test.dart test/route_rendering_test.dart test/driver_location_repository_test.dart test/driver_gps_stream_service_test.dart test/driver_location_validation_policy_test.dart test/driver_tracking_controller_test.dart
```

Result: **117 tests passed**.

Full non-live verification: **238 tests passed with 2 intentional live-test
skips**. The known non-failing `flutter_svg` unsupported `<filter>` warnings
appeared.

- `dart format lib test`: 190 files checked, 0 changed.
- `flutter analyze --no-pub`: no issues found.
- `git diff --check`: passed; only existing line-ending warnings were emitted.
- No live tests were run with credentials. Docker, local Supabase, migration
  deployment, and migration 024 testing were not performed.

The focused implementation and documentation commit is `6ded865`.
