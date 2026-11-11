# RideX Phase 7 Reconciled Integration Handoff

**State:** review candidate for isolated Windows Flutter/Deno/Supabase testing. This is not Phase 7 acceptance, production activation, hosted RLS validation, or physical-device evidence.

## Verified source baseline and reconciliation

| Source | Full SHA / evidence |
|---|---|
| GitHub `main` and isolated checkout base | `88072339bfd805c66f890e9509dd40ba0c133b0f` (verified from GitHub on 2026-11-10) |
| PR #127 source head | `c0c05b7d46a7643f8794f50b42dbd7cda9c487cc` |
| Moath B07 merge | `ef45428f4f8791cbf5c450e3f8abff036d098c3d` (PR #132) |
| Moath B08 merge/current `main` | `88072339bfd805c66f890e9509dd40ba0c133b0f` (PR #133) |
| Reconciled worktree | Detached at the exact `main` SHA above; no commit or remote ref changed |

The preserved closure package supplies the earlier integration source and ordered patch components. Its combined patch reports 25 changed paths when inspected with `git apply --stat`; the component manifest includes repeated path entries across the ordered patches. The distinct historical 35-file patch is unavailable and was not reconstructed by guessing. The consolidated patch applies the preserved PR #127/closure content to current `main`, then adds the missing Rider booking-to-matching/tracking composition and focused tests. Its final file count is generated from the reconciled diff, not forced to 24 or 35.

Reconciliation decisions:

- Keep B07/B08's `CanonicalDriverRepository`, B07 eligibility/Trip authority and B08 `CanonicalDriverDelivery` as the only Driver canonical flow. The closure bridge forwards advisory D02 hints only for an already pinned B07 Trip. No experimental Driver repository from an older patch is carried forward.
- Keep Phase 4 `DriverTrackingController` as the only GPS publisher. Its existing foreground GPS, quality, cadence and availability contracts are preserved; the closure adds session-replacement fencing only.
- Preserve the legacy `/rider/searching` and `/rider/trip` demo routes. The new canonical Cash search and Trip routes are mounted only when `RIDEX_ENABLE_CASH_MATCHING_INTEGRATION=true`; the default remains `false`.
- Reuse the existing `CashMatchingAdapter`, `SupabaseCashMatchingPort`, A03 candidate RPC and A04 offer RPC. The new `cash-matching` Edge Function is an authenticated HTTP boundary for that server-only adapter, not a new SQL/RPC or Driver lifecycle contract. It accepts only Booking ID, locked Quote ID and expected canonical Booking version. No caller-supplied Rider, Driver, location, fare or payment fields are accepted.
- Treat Edge results and Realtime events as advisory. Matching result `trip_id` is only a locator. Rider navigation requires the authenticated `findByBooking` canonical read to verify the same Booking, Rider and Cash Trip; the tracking route then rereads the exact Trip through D02-backed RLS and starts D04 location only after canonical Trip verification.
- Pending Booking cancellation calls `rider_cancel_booking(target_booking_request_id, expected_version, reason_code)`. Assigned Trip cancellation is a different operation: `rider_cancel_trip(target_trip_id, expected_version, reason_code)`, followed by an authenticated canonical Trip reread. Existing version conflicts and cancellation-vs-acceptance outcomes remain unresolved until reread.
- Keep `20261106120000_phase7_realtime_publication_membership.sql` at `supabase/deferred/`. It is absent from `supabase/migrations/`; do not move or deploy it. It does not alter the shared publication or turn off DELETE/TRUNCATE.

## Implementation and API contracts

| Flow | Contract | Evidence/guard |
|---|---|---|
| Confirmed Cash booking | `BookingConfirmationScreen` → saved `ConfirmedBookingReference` → `/rider/cash-searching?booking=...` | Exact current Rider, confirmed canonical booking, locked Quote lineage and Cash. Feature gate defaults off. |
| Matching request | `RiderMatchingRequestRepository.requestMatching(reference, expectedBookingVersion)` → authenticated `cash-matching` Edge boundary → existing A05 adapter | Edge authorizes a nonblocked Rider; A05 rereads own Cash Booking/locked Quote and uses service-only A03/A04 calls. Bounded to existing three-candidate/offer policy. |
| Searching/cancellation | `RiderSearchController` + existing `RiderCancellationCoordinator` | Canonical status/version monotonicity; one in-flight request; no automatic replay on unknown timeout; same-booking rereads; pending cancellation uses the Booking RPC. |
| Rider Trip assignment | `RiderTripTrackingRepository.findByBooking` and `findByTrip` | Participant-scoped authenticated reads; exact Rider/Booking/Trip/Cash checks; only the verified model can drive navigation. |
| Trip status | `TripRealtimeAdapter.watchTrip(tripId)` | D02 verifies exact Rider or assigned Driver with canonical Trip rereads; notifications prompt rereads and never become status authority. |
| Rider location | `RiderTripLocationAdapter.watchTrip(tripId)` | D04 requires canonical active Trip and exact assigned Driver; sequence, time and freshness checks; clear on terminal/session/assignment invalidation. |
| Driver presentation | B08 `CanonicalDriverDelivery` | D02 hint is emitted only for the exact B07-pinned assigned Trip and Driver; B08 still rereads through its own repository. |
| Driver location | Existing `DriverTrackingController` | Foreground-only Phase 4 publisher; no second location publisher or direct UI database writer. |

Synthetic search sequence: confirmed Cash Booking v3 + locked Quote → matching result `awaitingDriver` (Booking remains canonical `searching`) → Driver acceptance updates canonical Booking/Trip → authorized `findByBooking` verifies matching IDs/Rider/Cash → only then navigate using the canonical Trip ID → D02 canonical Trip subscription → D04 location reread for exact Trip and assigned Driver. A `noCandidates` result is not a new Booking or terminal server status; it remains a UI result tied to the canonical Booking version. A retry is explicit and begins with a canonical reread. Unknown/timeout matching outcomes are not auto-replayed.

## Source-level overlap and ownership matrix

| Area | Reconciliation outcome |
|---|---|
| PR #127 D02/D04 models, sources, adapters and tests | Retained from the closure package; no rewrite of verified local adapter behavior. |
| PR #127 unsafe publication migration | Kept deferred under `supabase/deferred/`, outside the CLI automatic migration path. |
| D06 D02/D04 providers and B08 bridge | Retained, reviewed against B07/B08 symbols on current `main`; no competing Driver source of truth. |
| Rider searching | Existing standalone controller/screen extended and now composed behind the compile-time gate. The old demo searching route remains unchanged. |
| Rider assigned Trip tracking | New authenticated canonical repository composition uses the existing `RiderTripTrackingRepository` and lifecycle controller contract. It does not map D02's minimal status event into fabricated fare/vehicle data. |
| Rider cancellation | Existing pending Booking cancellation coordinator/RPC preserved; a separate typed Trip cancellation adapter invokes the canonical Trip RPC. |
| New backend surface | One small Edge HTTP entrypoint wraps the existing trusted A05 adapter. No database migration, grants, RLS policy or matching RPC changes. |
| Dependencies on unmerged teammate branches | None. The current main B07/B08 is used; Yousuf's offer UI and Sanad's merged Rider UI remain untouched. |

## Focused regression coverage added

- `test/rider_matching_controller_test.dart`: initial confirmed Cash request uses the canonical Booking version; no-candidate result stays tied to that version and is not repeated by a status refresh; an `assigned` response locator does not create an authorized Trip; session replacement fences a late result; a controlled matching timeout fences late completion and blocks retry/replay.
- `test/rider_cancellation_rpc_routing_test.dart`: synthetic loopback Supabase HTTP verifies pending Booking cancellation calls only `rider_cancel_booking`, assigned Trip cancellation calls only `rider_cancel_trip`, both with exact expected-version arguments, and Trip acceptance is canonical-reread before success.
- `supabase/functions/cash-matching/core_test.ts`: Edge boundary rejects missing/invalid/oversized input, extra caller authority fields, unauthorized callers and malformed output; result is sanitized and unknown remains unresolved.
- `supabase/functions/_shared/matching/cash_matching_adapter_test.ts`: existing A05 fake tests remain; adds loopback-only HTTP URL allowance for local Supabase while rejecting nonloopback plaintext endpoints.
- Existing D02/D04 fake tests, D05 pgTAP/harness tests, D06 fake end-to-end test, B08 bridge tests and Phase 4 GPS tests are preserved.

These tests are **written but NOT RUN in this workspace**. No PASS count is claimed for this reconciled candidate.

## Windows validation plan

Base SHA for applying this patch: `88072339bfd805c66f890e9509dd40ba0c133b0f`. Use the repository CI Flutter version (`3.41.2`, stable) and the committed lockfile. Do not edit `pubspec.lock`. Apply the patch only in a disposable clean checkout or a backed-up working tree:

```powershell
git status --short
git rev-parse HEAD
git apply --check .\ridex-phase7-integration-working.patch
git apply .\ridex-phase7-integration-working.patch
git diff --check
```

Run the focused Flutter suites:

```powershell
flutter --version
flutter test --no-pub test\rider_matching_controller_test.dart
flutter test --no-pub test\rider_cancellation_rpc_routing_test.dart
flutter test --no-pub test\trip_realtime_adapter_test.dart
flutter test --no-pub test\rider_trip_location_adapter_test.dart
flutter test --no-pub test\trip_realtime_canonical_driver_delivery_test.dart
flutter test --no-pub test\trip_realtime_providers_test.dart
flutter test --no-pub test\p7_d06_realtime_gps_integration_test.dart
flutter test --no-pub test\rider_booking_search_controller_test.dart
flutter test --no-pub test\rider_booking_cancellation_controller_test.dart
flutter test --no-pub test\canonical_ride_searching_screen_test.dart
flutter test --no-pub test\canonical_ride_searching_cancellation_screen_test.dart
flutter test --no-pub test\booking_confirmation_handoff_test.dart
flutter test --no-pub test\driver_tracking_controller_test.dart
flutter test --no-pub test\driver_gps_stream_service_test.dart
flutter test --no-pub test\driver_location_repository_test.dart
flutter test --no-pub test\driver_location_validation_policy_test.dart
flutter test --no-pub test\driver_home_location_sharing_test.dart
flutter analyze --no-pub
```

Then run the offline full suite with the CI serial setting:

```powershell
flutter test --no-pub --concurrency=1
```

Run Deno separately:

```powershell
deno test supabase/functions/cash-matching/core_test.ts supabase/functions/_shared/matching/cash_matching_adapter_test.ts
deno check supabase/functions/cash-matching/index.ts
```

Database and live checks are separate and must use the existing D05 identity/port-binding preflight. RideX default `54322` conflicts with the existing R08 database container. Do not start/reset the default RideX project. Use only the already documented isolated D05 checkout/project `ridex-d05-isolated`, loopback API `55421`, DB `55422`, exact expected container labels/names, and local synthetic keys. Stop if the D05 preflight fails. Only after it passes:

```powershell
supabase test db supabase/tests/database/p7_d05_realtime_rls.test.sql
$env:D05_REALTIME_ACCEPTANCE = '1'
$env:D05_SUPABASE_URL = 'http://127.0.0.1:55421'
$env:D05_SUPABASE_ANON_KEY = '<isolated-local-anon-key>'
$env:D05_SUPABASE_SERVICE_ROLE_KEY = '<isolated-local-service-role-key>'
flutter test --no-pub test/p7_d05_realtime_acceptance_test.dart
```

The live harness does not prove `trip_status_events` WebSocket delivery, DELETE/TRUNCATE disclosure, JWT revocation on an open channel, hosted RLS, or physical-device behavior. Do not use production credentials. Do not deploy migrations or the Edge Function from this handoff.

For a default-off Flutter build, run tests without defines. For a separately approved isolated local UI flow only, pass `--dart-define=RIDEX_ENABLE_CASH_MATCHING_INTEGRATION=true`; this does not enable production. The local `cash-matching` Edge Function must be served against the isolated local project and local-only service key. It must be explicitly reviewed and launched by the local test owner; this patch does not run or configure that environment.

When the isolated local project is already running and the D05 identity/port preflight has passed, serve only this function with a local-only env file:

```powershell
supabase functions serve cash-matching --env-file .env.local
```

`.env.local` must contain only values for the isolated local `ridex-d05-isolated` project (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`). Never copy hosted/production values into it. Stop the function and discard the local test process after the acceptance run; do not deploy the function.

### Physical two-device check (future owner-approved gate)

Prerequisites: accepted P6-R01 canonical Driver context, approved P6-R04 hosted actor matrix, approved P6-R07/R08 scope disposition, reviewed local/hosted publication operations, Yousuf's matching/offer liveness and expiry path, Moath B07/B08 owner authorization, Sanad Rider UI/full-trip integration, two devices, and synthetic nonproduction Rider/approved Driver identities. This implementation does not satisfy those prerequisites by itself.

1. Confirm each device's actor alias, current session and approved Driver state. Create one synthetic confirmed Cash booking through the approved path.
2. Enable the canonical flow only in the isolated test build. Verify matching uses that exact Booking/locked Quote. Driver acceptance must occur through the approved canonical Driver path; an Edge result alone must not open tracking.
3. On the Rider device, confirm navigation occurs only after the exact Rider/Booking/Trip/Cash canonical read. Verify location appears only for that Trip and assigned Driver, and only after D04's fresh canonical row read.
4. Interrupt and restore network. Confirm D02/D04 recover from canonical rereads; duplicate/out-of-order hints do not regress status or coordinates.
5. In separate synthetic runs, race pending Booking cancellation against Driver acceptance, cancel an assigned Trip through its distinct RPC, replace a session, and end a Trip. Verify canonical rereads decide each result and old coordinates clear.

Stop immediately if a foreign Trip/Driver/location appears, uncertain matching is replayed, stale coordinates survive terminal/session invalidation, foreground-only GPS is violated, Card/Stripe/payment processing appears, or fixture cleanup fails. Sign out of both test devices and stop the isolated test flow through the approved operator process.

## Phase 6 gates, security limitations and blockers

| Gate | Current disposition for this candidate |
|---|---|
| P6-R01 | Canonical Driver registry and eligibility contracts exist on main, but P6-R01's production completion context/activation acceptance is not proved by this integration. Blocks live Driver-to-Cash completion/physical end-to-end acceptance; fake/local adapters can still be tested. |
| P6-R04 | Local auth/session/RLS hardening exists, but hosted authenticated role, block/demotion, SDK session-replacement and remote-revocation matrix remains blocked until approved identities/runtime are available. |
| P6-R07 | Fixture preparation does not prove natural matching/offer liveness. Hosted synthetic fixture execution is not authorized or run. |
| P6-R08 | **Scope naming conflict:** the authoritative Phase 6 roadmap labels R08 secure Stripe UI foundation; older Phase 7/A05/A06 records call R08 the Cash integration gate. This candidate remains Cash-only and does not close either interpretation. Owner must record the intended R08 disposition. |
| P6-R06 and Card/Stripe | Hard-blocked; dispatch and payment work remain disabled. No Stripe/Card behavior is introduced. |
| P6-R09 | Phase 6 exit remains open/not approved. |
| P7-A05 matching | Existing server-only A05 adapter is reused; this new HTTP boundary has not passed local Deno or local/hosted Supabase tests. Matching is default-off. |
| Publication membership | No local publication inventory or subscriber inventory exists. The guarded SQL remains deferred. Deployment safety is not established. |
| Matching liveness | A04 offer expiry is 15 seconds and search window is 90 seconds. Scheduler/liveness proof and live GPS compatibility remain outside this patch. |
| GPS freshness | Repository contracts differ by layer: Phase 4 publisher can allow a much older persisted point, while A03/A04 matching eligibility is 60 seconds and <=50m. Do not relax A03/A04; prove live supported-device cadence before enabling natural matching. |

No hosted Supabase query/write, migration, Edge deployment, financial action, commit, push, PR, merge, branch change or Phase 8 work was performed.

## Integration matrix

| Area | Status | Evidence boundary |
|---|---|---|
| Current-main/B07/B08 source reconciliation | PASS (static) | Exact GitHub base SHA verified; current canonical Driver contracts remain in place. |
| D02/D04 provider composition and Rider canonical ownership | PASS (static) | Source wiring and identity guards reviewed; must be confirmed by Flutter suites. |
| Cash search/matching/cancellation implementation | BLOCKED pending tests | Implementation and focused tests are present; Flutter/Deno toolchains unavailable here. |
| D05 synthetic RLS tests | BLOCKED | Not executed; D05 isolated database unavailable in this environment. |
| Real Realtime/WebSocket and publication behavior | BLOCKED | No local Supabase/Docker/PostgreSQL or hosted access used. |
| Physical two-device Rider/Driver acceptance | BLOCKED | Requires P6-R01/R04/R07 and owner-approved isolated actors/environment. |
| Production/hosted activation | BLOCKED | Feature gate defaults off; no deployment or owner acceptance. |
