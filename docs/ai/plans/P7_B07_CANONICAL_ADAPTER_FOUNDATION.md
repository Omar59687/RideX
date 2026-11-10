# P7 Driver canonical adapter preparation — Moath

Base: main `5cc55d73cf4ee14380e550167736dab477321366`.
Scope: independently tested integration foundation, **inactive**, not live
two-device acceptance. No hosted operation, schema change or production
activation is authorized by this document.

## Design and ownership

The chosen design adds a canonical data seam beside B01–B06. Directly changing
the default DriverFlowRepository would activate unreviewed behavior; extending
simulated snapshots with backend rows would incorrectly grant them authority.
Instead CanonicalDriverRepository returns separate minimal, authorized canonical
references. B01–B06 contracts, controllers, providers and UI remain unchanged.
It owns no parallel booking, GPS, matching, payment or active-Trip UI state.

An alternative of using only fakes would not verify SDK request signatures and
session binding; a global SDK client/provider would bypass the existing
provenance/single-client boundary. The new unmounted SDK port borrows verified
application access and AuthService.driverBinding instead. Tests exercise both
fake ports and the actual vendored SDK over loopback HTTP, never a hosted URL.
The dependency set is not upgraded by this phase.

New production files:

- `lib/features/driver_flow/data/canonical_driver_repository.dart`
- `lib/features/driver_flow/data/supabase_canonical_driver_port.dart`

New test files:

- `test/canonical_driver_repository_test.dart`
- `test/supabase_canonical_driver_port_test.dart`
- `test/helpers/fake_canonical_driver_port.dart`

## Implemented boundaries

- Every public read revalidates the authenticated, nonblocked, approved Driver
  through existing DriverEligibilityRepository. Owner/backend identity, epoch
  and exact SDK Session are pinned for the repository lifetime. Logout,
  same-user replacement, new epoch, account switch, disposal or observed
  ineligibility prevents delayed publication. A fresh session needs new reviewed
  composition; this instance does not recover its old authority.
- `observe(offerId: ...)` reads canonical availability and optionally one exact
  owned offer. The offer ID is only a locator. No delivery discovery, subscription,
  polling or server endpoint is invented. `watch()` explicitly reports unavailable.
- `readTrip(tripId, expectedVersion: ...)` reads one owned Cash Trip; wrong
  owner/ID, malformed fields, unsupported payment method, version regression,
  same-version state changes and changed relationship identities fail closed.
- Minimal offer/Trip references do not fabricate fare, route, Rider details,
  vehicle presentation or location. Results are point-in-time observations,
  not a permission lease or complete B05 journey/UI projection.
- Accept/decline re-read the original offer, reservation and linked Cash booking,
  compare ID/version/booking/quote/vehicle/deadline, and recheck eligibility before
  dispatch. Inclusive deadline expiry blocks an unsent command.
- Command responses are acknowledgements only. Assignment requires fresh owned
  accepted offer and actual correlated Trip rows; decline requires canonical
  declined evidence. Missing/filtered rows, expiry, transport failures, SQL
  conflicts and successful-looking RPC payloads alone never establish assignment
  or a negative outcome. UNKNOWN stays read-only until canonical reconciliation.
- A repository instance retains one intent/key. Exact concurrent duplicates share
  one Future; new keys, opposite decisions or new intents never authorize another
  write through that instance. Reconciliation reads only and preserves original
  correlation. Incompatible offer observations latch stale; they cannot be
  cleared by a later equivalent observation or delayed command response.
- `offerCommandsEnabled` defaults to false. No provider, route, registry,
  compile-time activation flag or runtime caller is added. The existing
  DriverFlowRepository remains unavailable and no canonical result is labelled
  simulated. B06 remains unsupported; the port has only accept/decline RPCs.

## Exact existing backend contracts

| Operation | Existing source/shape | Adapter behavior |
|---|---|---|
| Availability | `driver_availability`: driver_id, state, vehicle_id, reserved_booking_request_id, active_trip_id, version; migrations 006/A02 | Authenticated own-row GET only; no availability mutation in this phase |
| Offer | `driver_match_offers`: id, booking_request_id, fare_quote_id, driver_id, vehicle_id, status, version, expires_at; migration 007/A04 | Exact ID + Driver filter; immutable correlation/version/deadline checks |
| Booking check | `booking_requests`: id, fare_quote_id, status, payment_method; participant RLS `private.can_read_booking(uuid)` | Exact locator under normal-user RLS, independently correlated with owned offer; Cash/searching required before write |
| Accept | `driver_transition_trip(target_id uuid, requested_status trip_status, expected_version integer, idempotency_key text) returns jsonb`; A04 wrapper over existing Phase 6 implementation | target_id is **offer ID**, status accepted, exact offer version and original key; response alone grants no assignment |
| Decline | `driver_decline_match_offer(target_offer_id uuid, expected_offer_version integer, idempotency_key text) returns driver_match_offers`; A04 | Exact original offer/version/key, then canonical readback |
| Trip | `trips`: id, booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id, status, version, payment_method; migration 008 | Exact ID or booking ID plus authenticated Driver filter; Cash only |

No invented `driver_accept_trip`, service-role matching call, payment, receipt or
completion RPC is introduced. Acceptance retains the existing backend's automatic
Cash-selected Payment-row side effect; it is not collection/settlement. No real
acceptance occurred here. Future nonproduction write approval must cover that
side effect as well as the Trip/offer/availability changes.

## Deliberately unavailable / integration handoff

- **Yousuf:** supply the reviewed matching application endpoint and trusted offer
  delivery/discovery contract. The adapter already accepts the exact authorized
  offer locator and existing versioned RPC shapes. Backend expiry cleanup,
  schema/grant/RLS/FK parity and approved vehicle/availability fixtures remain
  separately accepted work; this phase does not call the service-only endpoint.
- **Omar:** PR #127 is neither changed nor required for these local tests. Offer
  delivery and Realtime invalidation are absent. Connect only reviewed advisory
  signals to canonical rereads, reuse the existing foreground GPS controller,
  resolve matching GPS freshness and synchronize canonical availability/Trip
  association after acceptance. No second publisher or channel is created here.
- **Sanad:** consume the real assigned Trip via the Rider's own approved reader,
  tracking adapters and exact confirmed-booking lineage. Driver references are
  not a Rider authorization contract, and this code cannot make Rider tracking
  live. Session-lineage and richer presentation composition remain shared review.
- **Moath / integration owner:** agree how B01–B06 projects canonical references
  into full journey/display contracts without treating simulated sources as
  authoritative. Default providers must remain unchanged until that review.
  Trip progression, full live observation, multi-intent lifetime/retry persistence
  and process-restart reconciliation remain unavailable here. Do not recreate the
  repository or rotate keys to bypass a pending/UNKNOWN attempt. Host future
  attempts under the existing session/Trip lifetime owner with reviewed durable
  recovery; this preparation object is not that persistence layer.

Result getters revoke copied references on detectable local identity/epoch or
eligibility invalidation. A future UI must subscribe to shared invalidations and
clear already-copied display data immediately. No instant remote block detection,
silent-SDK invalidation event, Realtime delivery guarantee, coherent transactional
multi-table read or hosted security acceptance is claimed. Server RPCs/RLS remain
final authority under concurrent changes. Do not activate this seam to fill those
gaps by assumption.

## Verification and acceptance

Focused tests are deterministic and serial. They cover approved/unauthorized
Drivers, wrong Driver/Trip ownership, stale correlation and versions, expiry,
duplicate acceptance, network failure/timeout, committed lost-response recovery,
UNKNOWN without replay, logout/session/epoch replacement, missing delivery,
default-off commands, actual SDK query/RPC signatures and no financial dispatch.

Commands:

```sh
flutter test --no-pub --concurrency=1 test/canonical_driver_repository_test.dart test/supabase_canonical_driver_port_test.dart test/architecture_boundary_test.dart
dart analyze lib/features/driver_flow/data test/canonical_driver_repository_test.dart test/supabase_canonical_driver_port_test.dart test/helpers/fake_canonical_driver_port.dart
flutter test --no-pub --concurrency=1
flutter analyze --no-pub
```

Focused new tests: **66 passed**, serial; the existing architecture suite adds
five passing cases. Final full Flutter regression with `--concurrency=1`:
**2,493 passed, 0 failed, 2 intentional credential-gated live skips**.
Scoped analysis: **no issues**. Full analysis: zero errors,
zero warnings and eight existing baseline infos in Rider/map/semantics code
outside this change (exit 1); this is not a clean full-analysis claim.

Verification uses Flutter 3.41.2 / Dart 3.11.0, matching the current offline CI
workflow. Its generated lockfile/desktop registrant refresh is excluded; the
committed lockfile and dependencies are unchanged.

Independent Astra High static/read-only review on 2026-11-10:
**APPROVE for the inactive foundation scope; no blocking security or correctness
findings.** The sole nonblocking documentation correction was the existing helper
name `private.can_read_booking(uuid)` and is fixed above. The reviewer did not
rerun tests or contact a backend. The parent owns final regression verification.

No hosted/device acceptance is implied by any local pass. Next safe step is
review of the delivery/canonical-UI composition contract, followed by approved
shared integration tests before any two-emulator shared-backend activation.
