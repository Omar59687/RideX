# P7-B01 Driver UI audit and isolated state contract

Owner: Moath. Issue: #106. Branch: `feature/p7-b-driver-flow`.
Baseline: `c9ebffae323bd4b621cdd5f8edfba5a33bf91667` (2026-11-04).
Scope: local presentation contract and test fakes only; no production wiring.

## Ownership and audit

`lib/features/trips` mixes Rider screens, Driver screens, shared completion UI,
and financial infrastructure. B01 therefore adds `lib/features/driver_flow`
instead. No existing shared contract, screen, router, session provider, backend,
GPS service or other developer's file is changed. Fake implementation stays in
`test/helpers` and cannot be imported by the production boundary.

| Existing path | Finding / reuse boundary |
| --- | --- |
| `lib/features/driver_home/presentation/screens/driver_home_screen.dart` | Mock online switch, hardcoded metrics/preview, no-op preview decline; real tracking card and gated canonical entry already exist. Moath's later presentation work; unchanged in B01. |
| `lib/features/trips/presentation/screens/driver_trip_request_screen.dart` | Uses Rider booking draft, hardcoded Rider and locations; acceptance seeds MockTrip. Later Moath screen work; no assignment authority. |
| `lib/features/trips/presentation/screens/driver_arrival_screen.dart` | Local status progression, placeholder map and fallback accepted status without a Trip. Later Moath screen work. |
| `lib/features/trips/presentation/screens/driver_active_trip_screen.dart` | Mock repository completion and fallback in-progress status. Preserve existing single-flight/stale response protection. |
| `lib/features/trips/presentation/screens/trip_completion_screen.dart` | Shared Rider/Driver screen; hardcoded Driver fare and success presentation are not canonical evidence. Coordinate before future edits. |
| `lib/app/router/app_router.dart`, `lib/app/router/route_guards.dart` | Existing role/status redirects protect Driver routes; not lifecycle/offer guards. Shared ownership; no B01 edits. |
| `lib/core/providers/session_providers.dart`, `lib/core/providers/repositories_providers.dart` | Existing mock presence/Trip ownership, sign-out cleanup and MockTripsRepository. Preserve; do not replace globally. |
| `lib/core/providers/driver_cash_completion_providers.dart`, `lib/features/trips/presentation/screens/driver_canonical_trip_screen.dart` | Separate default-off canonical Cash composition and route. Preserve integration ownership. |
| `lib/features/trips/presentation/widgets/driver_cash_completion_panel.dart`, `lib/features/trips/application/driver_completion_coordinator.dart`, `lib/features/trips/application/driver_cash_recovery_controller.dart` | Journal-backed completion and read-only recovery exist. No fake data or commands enter them. |
| `lib/core/providers/driver_tracking_providers.dart` | Canonical location eligibility/tracking already exists; mock presence is independent. No B01 edits. |

Moath owns the two new `lib/features/driver_flow` files, three new focused test
files, the test fake and the two B01 documents. Yousuf retains matching/SQL;
Omar retains realtime/session integration; Sanad retains Rider presentation.
Shared routing/session/financial changes require coordination in a later scope.

## Contract

- `DriverFlowRepository`: `read(session)`, `watch(session)`, `execute(command)`.
  Default Riverpod binding returns unavailable/empty events without SDK calls.
  Test containers explicitly override the binding and own fake disposal.
- Snapshots carry a local Driver/session generation and event revision. Entity
  versions are separate: availability, offer and Trip each retain their own.
  Generations identify local lifetimes, not authenticated/approved Drivers.
- Availability reuses `DriverAvailabilityState`. Requests can ask only for
  offline/available; reserved/onTrip remain observed values, never UI overrides.
- Journey reuses `RideLocation`, `PaymentMethod` and immutable stops. Cash only;
  locked fare uses integer JOD fils, route uses meters/seconds. There is no Rider
  private identity/contact payload and no dependency on a local BookingDraft.
- Offer contains offer/booking/quote IDs, version, expiry and journey. Deadline
  comparison is explicit and inclusive (`now >= expiry`). No wall-clock timer.
- Trip and progression commands reuse the existing `DriverTripLifecycleStatus`
  vocabulary, including distinct `cancelledByAdmin` and `failed` states. This
  imports lifecycle names only, not canonical evidence or completion authority.
  Pre-trip loading/search/offer presentation stays in the phase/offer boundary;
  the shared mock `TripStatus` enum is unchanged. All five terminal states reject
  every supported progression command without dispatch.
- Commands carry the original target, positive expected version and unchanged
  idempotency token. Availability's token is local correlation only: the existing
  availability RPC has no token parameter. Decline is a local intent with no
  invented RPC mapping. Trip commands allow only arriving/arrived/in-progress.
- Sources are exclusively `simulated` and `unconfigured`; there is no canonical
  source or confirmed-assignment result. Scripted acceptance remains simulated.
  The result enum has no payment/receipt success. Completed Trip presentation
  may be seeded for a scenario, but cannot be commanded or prove settlement.
- The fake validates command identity/version/expiry and local Trip sequence.
  Missing responses/timeouts return unknown; read failures return unavailable.
  A dispatched acceptance with unavailable/unknown outcome also retains unknown
  state. Commands never synthesize assignment or success. Successful responses
  must be explicitly scripted. No retry, token replacement or version repair occurs.
- Acceptance correlation compares the captured session, offer ID/version, expiry
  instant, Booking/quote IDs and complete journey values (locations, ordered stops,
  vehicle, Cash method, integer fare and route metrics). Reconstructed equivalent
  objects match; Dart allocation identity is never an offer identity. Observation
  revision orders events and is not part of offer identity.
- Reobserving an equivalent offer while its acceptance is pending publishes pending
  state, or unknown at the inclusive expiry boundary. Unknown attempts remain
  unknown after a late success/rejection/unknown reply and later equivalent events;
  incompatible offer payloads latch stale state and invalidate late responses.
  These states block further dispatch. Duplicate/older/foreign-session events are
  rejected before they can alter attempt state.
- A deterministic `read`, offer observation or response completion checks the
  injected clock. No wall-clock timer, expiry worker or B02 controller is added.
  Before-dispatch expiry remains `expired`; expiry after dispatch proves neither
  acceptance nor rejection. Attempt tracking outlives an uncertain response and
  is cleared by session replacement/disposal or explicit fake outcome resolution.
- `observeAcceptanceOutcome(snapshot)` is a test-only, explicit scripted outcome
  observation, distinct from ordinary offer events and command replies. It requires
  simulated source, current session, increasing revision, ready phase and no offer;
  an observed Trip must retain the captured journey. It can explicitly script an
  assigned Trip or an unassigned result and retires unresolved attempts. A still
  pending command reply cannot overwrite it. Neither branch is canonical evidence:
  real adapters must obtain reviewed authoritative ownership/outcome evidence;
  RLS absence alone does not establish rejection or non-assignment.
- Fake events accept only increasing revisions for the current session.
  A-B-A replacement uses increasing generations and clears visible data.
  Pending responses check both generation and revision before publication.
  Reads and subscriptions never dispatch commands.

This is an independent UI seam, not a backend emulator or assignment authority.
Single-flight buttons, app lifecycle hooks, reconnect orchestration and actual
screen consumption remain B02-B05. No second production active-Trip owner exists.

## Scenario catalogue

Compose `driverFlowSnapshot` with availability/offer/Trip and `DriverFlowPhase`;
the fake exposes deterministic clock, event, delayed-response and explicit
outcome-observation controls.

| Surface | Supported scenarios |
| --- | --- |
| Availability | Loading; offline; available; reserved; onTrip; pending; unavailable/error; unauthorized; stale |
| Requests | Loading; no offer; offer; replaced/repeated event; exact deadline expiry; pending accept/decline; successful simulated decline; rejection; unknown/lost response; pending acceptance crossing expiry |
| Trip | Accepted; arriving; arrived; inProgress; completed; cancelledByRider; cancelledByDriver; cancelledByAdmin; failed; missing Trip; stale/read-only recovery; unauthorized; completionBlocked |
| Session / recovery | A-B-A replacement; old subscription silence; delayed read/command retirement; disposal; explicit read without replay |

UI consumers must continue to label simulated data as demonstration. Pending,
unknown and mock state never authorize routing as a canonical assigned Trip.

## Existing RPCs and later integration

Reuse `driver_set_availability(requested_state, requested_vehicle_id,
expected_version)` and `driver_transition_trip(target_id, requested_status,
expected_version, idempotency_key)`. Accepted transitions use an offer ID/version;
later transitions use a Trip ID/version. Read back canonical ownership, state and
version; do not treat the command response alone as full assignment evidence.
`backend_create_driver_match_offer` remains service-role-only.
`user_trip_receipt_summary(target_trip_id)` remains separate receipt evidence.
No `driver_accept_trip`/`driver_reject_offer` RPC is introduced or assumed.
Merged P7-A01-A03 on this baseline may be reused later; no unmerged branch is
needed. No SQL is applied or hosted state inspected by B01.

## Phase 6 reconciliation and remaining gates

The authoritative `P6_POST_MERGE_ROADMAP.md` defines **P6-R08 as secure Stripe UI
foundation scope**, not canonical Cash booking handoff. The Cash label in the
Phase 7 briefs/issue is inconsistent. This B01 record corrects that interpretation
without editing another owner's brief or claiming Phase 6 approval.

Canonical Cash handoff is a separate Phase 5 booking / P7-A05 integration concern:

1. Authenticated owning Rider and canonical confirmed Booking; payment method Cash.
2. Canonical locked FareQuote linked to that Booking, with unchanged quote identity,
   route and fare. Existing `BookingHandoff.classify`, `validLockedSnapshot`,
   `rider_confirm_booking`, and canonical rereads are the baseline, not draft UI.
3. Canonical Driver-owned, current, unexpired offer linked to that Booking/quote
   and eligible vehicle; distinct offer/Booking/availability versions.
4. Atomic backend claim followed by participant-scoped assigned Trip reread,
   linked identities/version, and session-safe publication/reconnect.
5. Reviewed integration evidence under the authorized environment and actors.

These are later integration requirements, not missing B01 backend work, and do
not constitute a new P6 task number. `ConfirmedBookingReference` is a locator,
not authority. Existing handoff code is evidence of implementation, not proof
that every live integration requirement has been accepted.

| Exact gate | Remaining limitation / resume condition |
| --- | --- |
| P6-R01 | Approved test mapping/source exist; financial activation still requires reviewed canonical environment/session/ownership evidence and authorization. |
| P6-R02 | Durable completion/runtime wiring exists; actual Cash dispatch remains blocked pending durability and bounded completion acceptance. |
| P6-R03 | Read-only recovery wiring exists; runtime recovery and retention/retirement policy remain gated. No replay or journal deletion. |
| P6-R07 | Fixture/setup evidence is not hosted Cash completion/settlement/receipt acceptance. Resume financial work only after reviewed acceptance and separate authorization. |
| P6-R06 / P6-R08 | Card/Stripe activation remains blocked; R08 secure UI disposition is separate from Cash-only local work. |
| P6-R09 | Phase exit/approval is separate; B01 does not close Phase 6. |

P6-R04 protected-role acceptance applies if later readers reuse those paths.
P6-R05 bounded Rider Cash read acceptance is not full history or Driver completion
approval. None of these gates prevents isolated B01 tests.

## Acceptance and next scope

B01 delivers isolated ownership, immutable Cash-only presentation contracts,
unconfigured injectable boundary, deterministic fake scenario support, focused
tests, preserved existing regressions and recorded analyzer limitations. No
production screen/navigation wiring or financial capability is added. Verification
is recorded in `docs/ai/verification/P7_B01_LOCAL_VERIFICATION.md`.
The remediation tests observe all phases and all nine Trip states through both
`read` and `watch`, verify rejection from every terminal state, caller-owned stops
copying, acceptance identities/entity versions/tokens and isolation between two
fake ProviderContainers and the unconfigured default. Delayed reads after disposal
and A-B-A pending-command replacement are covered. Final remediation adds
reconstructed-offer expiry regression coverage (proved red before correction),
incompatible payload/stop-order cases, repeated pending/unknown observations,
independent outcome reads before late replies, and direct availability read/watch
values/reference isolation for all four availability states. Financial gates remain intact.
B02-B06 and integration acceptance remain unimplemented by this checkpoint.
