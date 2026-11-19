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
- B04 session-epoch fence: `c1b31a186c4a6309751b9af607c37e7e057c39bc`
- B04 Payment identity guard: `3de74f778c36830503d7aeee5156f72140a64aa4`

The original local commits remain unchanged in the local branch. Git HTTPS
push was unavailable in the implementation environment, so the authenticated
GitHub connector replayed each checkpoint's exact tree changes and messages
onto the remote branch. GitHub generated different remote commit SHAs. The
final local and remote tree SHA was verified identical before the later
handoff-document update. No PR was opened.

| Local commit | Replayed remote commit |
| --- | --- |
| `49e79f981f83e736835aa70653e4c9d0805c43db` | `eb7b32fed8e0c6319afded4ec7ee4c3686eb32e5` |
| `ddde68270af0f08250db0ac3db56feff979f96eb` | `c02db2840376c61c279f768cb30fb831cf638eb0` |
| `078913a52e248e33e2ca3205d2279fb0917887c9` | `c5035dfdeb3b3a70e57adbe43c9fbdf33f7fe10b` |
| `5af5cd6753d1b6f4be439ef3c348fa1868d648d4` | `ca8f085e2fb1e209057a3c2c3df4982ffacd708b` |
| `8d7ac7a8a968bbdb7df427d5d08d5fc65bce826f` | `f204ad972994bc8b83cdcf7bde6d01d6133e77f8` |
| `5f0b7bcc72f59b25d3f1e69b9164b4fd4f77cee6` | `656aaf602343cba0331edb4840bd8c8e16b8782f` |
| `c1b31a186c4a6309751b9af607c37e7e057c39bc` | `18ecbaf25e1e1c3afb7e548c80208e3c92dae2b1` |
| `e44905b4dbdbaf49c665631f3146a4934fa27c98` | `83ba404c7996cc88e4bc561b57597d35be9a9528` |
| `3de74f778c36830503d7aeee5156f72140a64aa4` | `dd863a8f55b61aebe6c3a6da745f978af09b5f64` |
| `24a1d73e368533ea6d81883d686c8dd6c7281885` | `953697b907abc650f535e02507b0e99e88719d50` |

## Implemented

- Feature-local typed Trip and Payment presentation states, separated from
  each other. Payment reads are attempted only after the authenticated,
  unblocked Rider's canonical Trip read verifies exact Trip/Rider ownership,
  a Driver assignment, Card method, eligible nonterminal status, and version.
- Session identity and generation fencing clear checkout state on logout or
  account replacement and suppress late Trip/Payment reads. Duplicate reads
  share one active operation; older Trip or Payment versions fail closed.
  Canonical Payment responses without a Payment ID, or with a foreign Trip or
  Booking ID, remain UNKNOWN rather than displaying an authorized status.
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
- The duplicate-handoff fence is session-memory scoped. Cross-process
  idempotency must come from Yousuf's approved backend contract before any
  real authorization handoff is enabled.
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

Authored focused coverage: 15 controller tests, 8 fake launcher/handoff tests,
and 4 widget tests (27 total). They cover missing and foreign Trips, blocked
Rider, Cash gating, assignment eligibility, terminal Trips, duplicate reads
and handoffs, stale Trip/Payment versions, UNKNOWN/error retry, session
replacement including A→B→A, late reads, cancellation/malformed/network
returns, logout during provider UI, app resume, post-return reread, lifecycle
copy, dark theme, and retry presentation. A deterministic test also reuses
the same session object after A→B→A and checks that the old handoff return is
fenced by the session epoch.

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
