# Checkpoint 4E Task 4.30 Error Sanitization Design

## Goal

Prevent raw GPS, map-provider, backend, HTTP, SDK, and exception details from
entering user-facing state or UI while retaining technical failures through an
injectable internal debug-reporting boundary.

This task closes Checkpoint 4E only if every approval-gate item is supported by
the implementation and verification evidence from tasks 4.24 through 4.30.

## Confirmed Audit Result

The location, place, route, and Driver tracking flows already map most provider
failures to typed application failures and fixed UI copy. Their state models do
not retain exception objects. The confirmed direct leak is the GoRouter error
page, which interpolates `GoRouterState.error` into visible text.

Google map camera futures are a secondary boundary gap. Their asynchronous SDK
errors are not copied into RideX state, but they are not caught locally and can
escape into Flutter framework diagnostics. Several existing catch blocks also
discard technical details instead of forwarding them to an internal diagnostic
channel.

## Architecture

Add a provider-neutral `AppErrorReporter` contract with one operation that
accepts:

- A static RideX operation name.
- The raw error object.
- An optional stack trace.

The default reporter emits diagnostics only in debug mode. Release builds do
not print raw details. The reporter never produces user-facing text and is
replaceable through Riverpod for deterministic tests or a future redacting
telemetry adapter.

Operation names are static developer-authored values. They must not contain
URLs, coordinates, account identifiers, provider payloads, session tokens, API
keys, or other request data.

## Error Flow

Each failure is reported once at the first boundary that still owns the raw
technical error, then converted to an existing typed application state:

- One-shot location repository failures map to `LocationFailure`.
- Place service failures map to `PlaceFailure`; unexpected repository failures
  are reported by `PlaceSelectionController` before fixed fallback copy is set.
- Route service failures map to `RouteFailure`; unexpected repository failures
  are reported by `RouteController` before a safe unavailable state is set.
- Driver GPS, Supabase location, and Realtime failures map to
  `DriverLocationFailure`; only unexpected downstream errors are additionally
  reported by the tracking controller.
- Map configuration and camera-operation failures are reported internally and
  retain the existing unavailable or still-usable map behavior.
- Navigation failures render a fixed RideX error view and report the raw router
  error internally.

Typed exceptions are not re-reported by downstream controllers because their
raw source was already handled at the adapter boundary. This avoids duplicate
diagnostics.

## User-Facing Policy

Application state and UI may contain only:

- Existing 4.29 status and failure enums.
- Fixed RideX-authored messages.
- Expected successful place names, formatted addresses, route metrics, and
  location metadata.

Application state and UI must never contain:

- `error.toString()` or interpolated exception objects.
- Stack traces or exception class names.
- Provider URLs, response bodies, request payloads, status details, or SDK
  implementation messages.
- API keys, authorization values, session tokens, or backend implementation
  details.

Successful provider display data such as place names and formatted addresses is
product content, not an error channel. It remains displayable after existing
type, length, and response-shape validation.

## Map Behavior

Map configuration failure continues to fail closed to the existing native
fallback without exposing platform-channel details. Camera animation and route
fit failures are caught and reported. They do not replace canonical location or
route state, display an SDK error widget, or disable manual/search fallback
behavior.

This task does not add a new map state owner, provider-specific domain type, or
automatic map retry loop.

## Navigation Behavior

The GoRouter error page is replaced with a fixed, branded-safe error view. The
raw `GoRouterState.error` value is sent only to the internal reporter. No URI,
query parameter, exception text, or framework message is rendered.

## Testing

Use raw-error canaries that include a provider URL, key-like token, HTTP payload,
SDK class name, exception text, and stack-like content.

Focused coverage will verify:

- The internal reporter receives the original error object and stack where
  available.
- Current-location, place, route, and Driver state contains only typed failures
  or fixed messages.
- Current-location, place, route, Driver Home, map fallback, and navigation UI
  contains none of the canary content.
- Map camera failures are caught at their boundary.
- Existing retry and recovery paths still work and do not duplicate GPS
  subscriptions or corrupt canonical state.

Verification order:

1. Format changed Dart files.
2. Run focused location, place, route, map, Driver tracking, and router tests.
3. Run `flutter analyze --no-pub`.
4. Run the complete non-live `flutter test --no-pub` suite.
5. Run diff and staged-diff checks.

## Checkpoint 4E Approval

After task 4.30 verification, review each approval-gate item against recorded
evidence from tasks 4.24 through 4.30:

- No duplicate GPS subscriptions.
- Controlled update frequency.
- Tracking stops when not required.
- Minimized network and database writes.
- Minimized map rebuilds.
- Stale and out-of-order updates are handled.
- Temporary GPS and network failures preserve canonical state.
- User-facing errors are clear and safe.
- Relevant tests pass.

Checkpoint 4E is marked approved only if all items remain supported after the
full regression run.

## Scope Boundaries

This task does not add matching, Rider live-trip tracking, continuous OS
background tracking, production telemetry, new backend contracts, provider
payload persistence, or task 4F work. No raw error details are stored in
application state.

The design specification, implementation, tests, and final documentation are
included in the single requested commit, `Sanitize GPS and map errors`.
