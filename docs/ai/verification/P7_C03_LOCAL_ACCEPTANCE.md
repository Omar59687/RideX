# P7-C03 local acceptance record — fail-closed scope

Date: 2026-11-05. Owner: Sanad. Issue: [#114 — Driver assigned details](https://github.com/Omar59687/RideX/issues/114).
Branch: `feature/p7-c03-driver-details`. Base: `origin/main` at `6a9485b`.
Recorded HEAD: `7cddadabd2812e54dc58d56d52dda220e41c8221`.

This record documents the locally committed, fail-closed C03 slices. It does not
claim that production Rider Driver/Vehicle details, matching, or live tracking are
implemented or accepted. P7-C03 in `Phase 7/Sanad.md` remains unchecked/PLANNED;
Issue #114 must remain open until the production acceptance evidence below exists.

## Objective and delivered scope

Issue #114 asks RideX to show Driver and Vehicle information from the exact
authorized assigned Trip, retain read-only loading/unknown fields, and invent no
IDs. Its widget acceptance calls for verified assignment, stale event, wrong Trip,
and missing Vehicle details. It also requires relevant local automated-test
evidence and no unapproved hosted, financial, or Stripe operations.

The delivered scope is deliberately narrower than that production objective:

- Slice 1 supplies a canonical-Trip-ID-validated production provider which always
  returns `unavailable`. It performs no Trip repository read and opens no watch.
- Slice 1 also contains a **private test-library reconciliation prototype** driven
  by deterministic fakes. It tests read/session/version/event behavior, but is not
  imported by production and is not production authorization evidence.
- Slice 2 supplies a standalone, stateless Driver/Vehicle card and a display-only
  allowlisted projection. The card is not mounted in a production screen and does
  not read providers, repositories, Supabase, or streams.

Therefore no production code presently displays an assigned Driver or Vehicle.
The reported fake-backed verified-assignment tests and card presentation tests do
not establish the issue's production “exact authorized assigned Trip” requirement.

## Commit and file inventory

The two C03 commits on top of the recorded base are:

- `33b2667514c0094a831c613ef232271d545ca655` (`33b2667`) — Slice 1,
  fail-closed Rider assigned-details boundary.
- `7cddadabd2812e54dc58d56d52dda220e41c8221` (`7cddada`) — Slice 2,
  standalone Driver/Vehicle presentation card.

Exactly four files were added relative to `origin/main` `6a9485b`:

1. `lib/features/trips/presentation/providers/rider_assigned_details_provider.dart`
2. `test/rider_assigned_details_controller_test.dart`
3. `lib/features/trips/presentation/widgets/rider_driver_vehicle_details_card.dart`
4. `test/rider_driver_vehicle_details_card_test.dart`

No existing file was modified by these commits. No C02 implementation, router,
shared authentication provider, migration, SQL, Stripe, hosted resource, or other
developer-owned file is part of the four-file change.

## Previously reported local verification

The following counts were reported from the implementation sessions. They are
historical reports, **not tests freshly executed while preparing this record**:

| Verification | Reported result | Scope/limitation |
|---|---:|---|
| Slice 1 controller tests | 21 passed | Exercises the private fake-backed prototype, not an enabled production controller. |
| Existing C01 contract/fake tests | 42 passed | `RiderAssignedTrip` and deterministic tracking repository contracts/fakes. |
| Slice 2 card widget tests | 15 passed | Tests card rendering with explicit presentation values only. |
| Full non-live Flutter suite | 2,018 passed, 2 skipped, 0 failed | Includes the C03 files; the two skips were intentional credential-gated live tests. |
| `flutter analyze --no-pub` | 6 diagnostics outside Slice 2 | Four existing warnings and two existing infos, detailed below; no Slice 2 diagnostics were reported. |

The six reported diagnostics were warnings at
`lib/core/repositories/location_repository.dart:45,102` and
`lib/core/repositories/supabase_auth_repository.dart:50,83`, plus deprecated
`containsSemantics` infos at
`test/rider_v2_adaptive_accessibility_test.dart:145,342`. These locations are
outside the C03 four-file inventory. No hosted test, authenticated Rider/Driver
handoff, live Supabase mutation, financial operation, or Stripe operation is
claimed.

The prior implementation reports state scoped formatting and whitespace checks
passed. This documentation task did not rerun those checks or the test suite.

## Fail-closed security and privacy

The production `riderAssignedDetailsProvider` validates that its explicit Trip ID
is canonical and returns only `RiderAssignedDetailsState.unavailable()`. It does
not access `findByTrip`, `findByBooking`, or `watch`; a missing Supabase client,
repository argument, provider invalidation, or recreation cannot enable details.
No production widget consumes or mounts the card.

The card projection includes only these display fields from the C01 Driver/Vehicle
summary contract: Driver display name, rating average/count, Vehicle make/model,
color, registration plate, and seat capacity. It carries no Trip, booking, Driver,
or Vehicle identifiers, ETA, contact details, or actions. Canonical UUID-shaped
strings supplied in the display-text fields normalize to unavailable; blank text
also normalizes to unavailable. Out-of-range values are rejected, and invalid
display-string length errors identify the field/reason without echoing the rejected
input. Card semantics use one composed label, with child semantics excluded;
switching the input to unavailable removes the prior display content.

These are presentation safeguards, not an authorization mechanism. The projection
constructor does not prove that supplied text came from an authorized Trip. A
future caller must only create it after trusted, exact-Trip and Rider verification.
UUID filtering does not make arbitrary display strings trustworthy.

## Dependencies and gates

**Shared SDK Session Lineage — owner assignment pending.** The installed Supabase /
GoTrue path can silently replace a Session for the same Rider without an event
which the current app can rely on to invalidate already-visible details. A shared,
owner-approved authentication/session mechanism must publish an observable,
token-free lineage generation for every SDK Session replacement, including silent
same-Rider recovery. The current C03 production provider intentionally remains
disabled until that boundary exists and has been reviewed. No shared-auth owner is
assigned in this record; project ownership must assign one before this dependency
is undertaken.

Phase 6 gates remain as stated in `Phase 7/Sanad.md` and the Phase 6 tracker:

- **P6-R08** gates live Cash-only booking confirmation/integration.
- **P6-R06 and P6-R08** hard-block Card activation.
- **P6-R05** is a bounded canonical Cash detail read, not full history.

No live matching or booking handoff is included here. These gates are not inferred
complete from the local UI and fake tests.

## Remaining production acceptance

Before claiming P7-C03 production functionality or closing Issue #114, the team
still needs to:

1. Assign and implement the shared observable SDK Session-lineage boundary, with
   regression coverage for silent same-Rider replacement and invalidation of
   already-visible data.
2. Implement/review the session-scoped production C01 repository adapter and
   trusted exact-Trip/Rider handoff; only fresh canonical reads may populate the
   display projection.
3. Compose the card with that trusted source without reusing MockTrip, guessing
   IDs, or mounting fake/test evidence in production.
4. Add production-composition/widget acceptance for verified assignment, stale
   event/version, wrong Trip/Rider, missing optional Vehicle fields, unavailable
   evidence, session replacement, and stale-data clearing.
5. Re-run the relevant tests and analyzer against the final integrated commit,
   document limitations, and obtain owner/integration acceptance. Any physical or
   hosted acceptance must be separately authorized and recorded.

The C01 `RiderAssignedTrip` model requires a Vehicle summary and Vehicle ID; its
optional display fields can be absent, but a truly missing Vehicle association is
not expressible without changing that contract. This remains an integration/model
question, not something the card fabricates.

## PR and issue disposition

Any PR based on these commits must be described only as a **scoped fail-closed
foundation and standalone presentation component**. It must say plainly that the
production provider returns unavailable, the card is unmounted, and fake-backed
tests are not production authorization evidence. The PR must not claim the C03
production objective is complete or close Issue #114. Owner approval is required
before any Push or PR. Issue #114 remains open until actual production acceptance
is complete and reviewed.
