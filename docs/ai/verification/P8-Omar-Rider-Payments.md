# P8 Omar Rider Payments — Local Handoff

## Branch and checkpoint commits

- Work branch: `feature/p8-b01-rider-payment-state`
- Base: planning commit `03ad682e60c89e70cc4981a2df0b3d317864b94c`
- Verified main base: `3be1aa67eecb49ce95ea77077b63964eb3cbc62c`
- B01: `49e79f981f83e736835aa70653e4c9d0805c43db`
- B02: `ddde68270af0f08250db0ac3db56feff979f96eb`
- B03: `078913a52e248e33e2ca3205d2279fb0917887c9`
- B04 hardening: `5af5cd6753d1b6f4be439ef3c348fa1868d648d4`
- B04 resume-race correction: `8d7ac7a8a968bbdb7df427d5d08d5fc65bce826f`

These commits are local only. They have not been pushed or opened as a PR.

## Implemented

- Feature-local typed Trip and Payment presentation states, separated from
  each other. Payment reads are attempted only after the authenticated,
  unblocked Rider's canonical Trip read verifies exact Trip/Rider ownership,
  a Driver assignment, Card method, eligible nonterminal status, and version.
- Session identity and generation fencing clear checkout state on logout or
  account replacement and suppress late Trip/Payment reads. Duplicate reads
  share one active operation; older Trip or Payment versions fail closed.
- A provider-neutral checkout launcher interface accepts only Trip ID and
  expected Trip version. Its default implementation is disabled. Return,
  cancel, malformed, network-failure, and unavailable signals are advisory;
  only a fresh canonical read changes displayed Payment state. A per
  Rider/Trip/version guard prevents repeat handoffs within the session.
- App-resume reconciliation and a post-return forced canonical reread are
  covered by fake-backed tests.
- An accessible, responsive, theme-aware payment status panel presents
  pending, UNKNOWN, authorized, captured, failed, cancelled, refund pending,
  refunded, and canonical read-error states. Retry performs reads only.
- No booking, Cash, History, router, shared provider, Supabase, migration,
  Driver, or payment execution code was changed. No card data, CVV, Stripe
  SDK, secrets, capture, void, or refund operation was added.

## Acceptance limits

- The canonical Trip/Payment reader is an injection seam with a fail-closed
  default. It is not connected to production. Issue #151's approved backend
  request/response contract is still required before a live authenticated
  adapter can be implemented; no RPC or Payment ID was inferred.
- The repository's `CardPayment` contract has no receipt evidence field or
  canonical receipt reader. The UI therefore does not claim receipt issuance
  or availability. Receipt presentation remains blocked on an approved
  canonical receipt contract.
- The existing Card model does not define a distinct capture-pending status;
  the UI presents only statuses supported by its canonical enum. Financial
  capture/refund/void remain backend-only.
- The new status widget is feature-local and is not wired into shared
  navigation or the Cash booking flow. The production Card path remains
  disabled.
- B05 live backend integration is BLOCKED on Yousuf's reviewed Issue #151
  contract. B06 team integration is NOT STARTED.

## Tests and validation

Authored focused coverage: 15 controller tests, 7 fake launcher/handoff tests,
and 4 widget tests (26 total). They cover missing and foreign Trips, blocked
Rider, Cash gating, assignment eligibility, terminal Trips, duplicate reads
and handoffs, stale Trip/Payment versions, UNKNOWN/error retry, session
replacement including A→B→A, late reads, cancellation/malformed/network
returns, logout during provider UI, app resume, post-return reread, lifecycle
copy, dark theme, and retry presentation.

Execution status in the implementation workspace:

- Flutter focused tests: **NOT RUN** (`flutter` unavailable).
- Dart format/analyzer: **NOT RUN** (`dart` unavailable).
- `git diff --check`: **PASS** for each implementation commit; no whitespace
  errors were reported.
- Cash regression tests: **NOT RUN**.
- Supabase/live checkout/device validation: **BLOCKED / NOT RUN**.

On a Windows checkout with Flutter 3.27.3 / Dart 3.6.1, run:

```powershell
dart format lib/features/rider_payments test/rider_checkout_controller_test.dart test/rider_checkout_handoff_test.dart test/rider_checkout_panel_test.dart test/helpers/fake_rider_checkout_reader.dart test/helpers/fake_rider_checkout_launcher.dart
flutter test --no-pub test/rider_checkout_controller_test.dart
flutter test --no-pub test/rider_checkout_handoff_test.dart
flutter test --no-pub test/rider_checkout_panel_test.dart
flutter analyze --no-pub
```

Keep the dependency lock unchanged. Run the existing Cash booking regression
suite after the focused tests; no Cash production code was modified in this
workstream.
