# RideX P7-C06 — Cash Guard Integration Handoff & Acceptance Checklist

Date: 2026-11-06<br>
Repository branch: `feature/p7-c06-cash-guard`<br>
HEAD: `59d8404` (`test(p7-c06): guard booking confirmation financial claims`)

This is a documentation-only handoff. It records committed local C06 behavior,
Phase 6 gates, available Phase 7 contracts, and a future two-device checklist. It
does not authorize an integration, backend operation, payment, settlement, receipt
issuance, deployment, or hosted Supabase call.

**Current disposition:** LOCAL IMPLEMENTATION VERIFIED; LIVE / TWO-DEVICE
ACCEPTANCE PENDING. No live/device scenario below has been run for this handoff.

## 1. Purpose and scope

P7-C06 establishes two local safety boundaries for the existing Cash flow:

- In the unconfigured deterministic Demo fare flow, Cash can continue to its
  existing mock search flow. Card remains selectable draft intent, but cannot
  continue. That mock search/trip flow is not canonical matching or an assigned
  Driver Trip.
- Canonical Cash booking confirmation presents a booking outcome. It does not
  establish that a Payment was paid, captured or settled, or that a Receipt was
  issued or verified. Canonical Card confirmation remains rejected.

The slices do not integrate a Rider-to-Driver matching endpoint, attach a live
Driver offer UI, enable Realtime Rider tracking, or settle Cash. Local widget tests
and existing contracts are not evidence of a live assigned Trip, financial state,
or owner acceptance.

## 2. Implemented evidence

| Slice | Commit | Committed scope | Local evidence |
|---|---|---|---|
| Slice 1 — Demo Cash-only guard | `bcc3eb2` | `lib/features/booking/presentation/screens/fare_estimate_screen.dart` and `test/fare_estimate_screen_test.dart`. Demo readiness requires Cash; Card remains selected intent and is disabled with an accessible explanation. The selected method is checked before estimate work and before navigation. Configured fare behavior is unchanged. | `test/fare_estimate_screen_test.dart`, group `P7-C06 Slice 1 demo Cash-only guard`: Cash continuation, Card selection/block, accessible explanation, Card-to-Cash restoration, retained-callback prevention, and configured Card draft behavior. `test/rider_booking_flow_test.dart` exercises the Cash mock continuation. |
| Slice 2 — Booking confirmation is not payment success | `59d8404` | `test/booking_confirmation_handoff_test.dart` only. Canonical Cash confirmation and its locked FareQuote lineage are tested without adding production behavior. The test-local matcher checks rendered claim text and semantics. | `canonical Cash confirmation stays a booking outcome, not payment or receipt success`; matcher tests cover affirmative/negative financial wording, RichText, multiline text, semantics-only claims, and coordinated predicates. Existing canonical Card rejection tests remain in the same suite. |

The cited hashes identify commits in local history, not external approvals.
Both commits are ancestors of this handoff base. No C06 source enables a payment
provider or financial mutation.

### Previously reported local verification

These are implementation-session results, not fresh runs performed while preparing
this handoff. Counts overlap and must not be added:

| Selection | Reported result |
|---|---:|
| Slice 1 fare-estimate screen suite | 36 PASS |
| Slice 2 booking-confirmation handoff suite | 37 PASS |
| Related payment/authority suites | 90 PASS |
| `test/architecture_boundary_test.dart` | 5 PASS |
| Full non-live Flutter suite with `--concurrency=4` | 2,246 PASS, 2 SKIP, 0 FAIL |
| `flutter analyze --no-pub` | Six existing unrelated diagnostics; zero reported in the C06 test file |

The two full-suite skips are the existing credential-gated live Supabase tests.
The repository contains no separate committed C06 test-run log. These reported
local results do not establish the device, hosted, matching, or financial gates
below.

## 3. Phase 6 prerequisites and gates

The Phase 6 tracker and roadmap separate implementation, integration, hosted
verification, and owner approval. Phase 6 is **NOT APPROVED**; do not interpret
any bounded result below as Phase 6 or release approval.

| Gate | Repository-recorded state | Required disposition before applicable integration |
|---|---|---|
| **P6-R05 — canonical Rider Cash payment/receipt read** | The latest tracker/current-status closeout records acceptance for the bounded completed-Cash-Trip payment/receipt read surface, based on historical owning-Rider and foreign-Rider evidence. It is not full history, payment creation, a match/assignment result, or fresh C06 acceptance. | Use only its canonical Trip-to-Payment identity lookup, exact Payment reader, and independent receipt read after an authorized completed Trip exists. Do not derive a Payment ID from a Booking or mock Trip. Reconfirm the actual integration path and scope. |
| **P6-R06 — Card/Stripe preparation** | **PARTIAL; dispatch OFF.** Preparation/reservation code and local checks exist; Stripe dispatch is disabled. Account/JOD approval, accepted Card fixture, hosted concurrency/reconciliation evidence, and separate activation review remain outstanding. Production remains blocked. | Treat any Card/Stripe entry, credential use, provider request, or Card financial test as a hard stop without separate owner/security approval. C06 does not activate or test Card. |
| **P6-R07 — Cash completion and receipt** | **PREPARED, NOT ACCEPTED.** Fixture/operator and lifecycle preparation are not hosted completion acceptance. Historical setup evidence of an `inProgress` unpaid Cash Trip with no Receipt is not settlement or receipt evidence. | Requires separate authorization, isolated synthetic actors/fixture, canonical completion, duplicate/concurrency/lost-response/recovery checks, and independent Payment and Receipt rereads. No real cash collection is in scope. |
| **P6-R08 — scope/owner disposition** | `R08_CASH_ONLY_ACCEPTANCE_2026-11-02.md` says Cash Only READY FOR REVIEW; its explicit owner-approval criterion is recorded as absent. The current Phase 6 roadmap/tracker instead describe R08 as secure Stripe UI foundation scope, while Sanad and some Phase 7 handoffs label R08 as the Cash-only confirmation gate. This repository has not reconciled that naming/scope conflict into owner approval. | Owner must explicitly resolve the bounded Cash confirmation disposition and record acceptance if intended. Regardless of that decision, Card/Stripe remains blocked by R06/R08 until separately approved. Do not infer approval from C06 commits or test results. |
| **P6-R09 — Phase 6 exit** | **NOT APPROVED.** Remaining task dispositions, hosted/runtime evidence, and explicit owner exit approval are not complete. | Keep Phase 6 and release status open. The C06 local handoff cannot close R09. |

R04's hosted role/session matrix is also incomplete in the tracker. Future device
accounts and environment must be explicitly authorized and must preserve Rider and
Driver identity separation.

## 4. Phase 7 integration dependencies

The following describes contracts in this checkout, not an assertion that they are
deployed or accepted end to end.

| Workstream | Existing contract/evidence in this checkout | Integration state and dependency |
|---|---|---|
| **Matching backend (P7-A)** | A01-A03 and A04 database/RPC contracts are in the merged history through PRs #118/#120. A03 candidate discovery is service-role-only; A04 offer creation revalidates eligibility and Driver acceptance uses authenticated `driver_transition_trip`. The A05 `CashMatchingAdapter` and `CashBookingAssignmentRepository` source are also present. | A05 describes both adapters as unwired: no authenticated application matching endpoint, provider, Realtime consumer, or scheduler is installed. The adapter is trusted-server-only and must never be called from Flutter or given client-controlled service credentials. A05/A06 local SQL/adapter evidence does not establish hosted PostgREST/JWT/device acceptance. |
| **Driver flow (P7-B)** | B01-B06 local Driver presentation contracts, fake repositories, offer/availability/trip preview UI, and B06 completion stop gate are in the merged history through #121/#125. The default `driverFlowRepositoryProvider` is unavailable; simulated/test data is not canonical assignment or financial authority. | No production DriverFlow backend adapter or offer-delivery composition is supplied by these B contracts. The separate canonical P6 Driver Cash screen remains behind its default-off `RIDEX_ENABLE_TEST_DRIVER_CASH` gate; R07 acceptance and separate authorization are outstanding. |
| **Rider tracking (P7-C01)** | `RiderTripTrackingRepository` defines authenticated `findByBooking`, `findByTrip`, and `watch` contracts; event models carry Trip ID/version/sequence and location sample data. C01 contract/fake source is in the merged C-Rider-tracking history (#119). | The repository is an abstract contract; the only implementation found in this tree is the test fake. `watch` is advisory, may not emit an initial snapshot, and requires canonical rereads on startup/reconnect. C01 contract availability is not Rider UI or Realtime integration acceptance. |
| **Rider screens and live lifecycle (P7-C02–C05)** | `Phase 7/Sanad.md` retains these checkpoints as unchecked/planned. The legacy `/rider/searching` screen uses `activeTripControllerProvider` and the `MockTripsRepository`; it is not the canonical matching flow. | Local refs for the C02, C03, C04, and C05 feature branches are not ancestors of HEAD `59d8404`. This handoff depends on none of them and does not claim their PR/CI status. Their integration remains separately reviewed. |
| **GPS and Realtime** | Driver GPS publishing/validation providers and `SupabaseDriverTrackingConnection` exist. Canonical Driver/Rider location and Trip contracts are available for reuse. | The connection status channel is not a Rider assigned-Trip subscription. A06 records matching Realtime wiring as NOT RUN. Backend GPS eligibility requires age ≤60 s, accuracy ≤50 m, and future skew ≤5 s; the Driver available-mode publisher may publish as slowly as 120 s. Resolve this freshness mismatch. A04 offer-expiry RPC exists, but no expiry scheduler/liveness evidence is installed. |
| **Rider payment/receipt presentation** | R05's bounded canonical Cash read is available via exact backend-issued Payment identity and independent receipt evidence. C06 tests booking copy and financial claim separation. | C06 does not create a Payment, issue a Receipt, or connect a matched Trip to payment/receipt authority. A missing receipt is unverified, not payment failure; booking confirmation alone is not paid/settled evidence. |

Sanad's existing checklist is intentionally not edited in this Slice 3. Its C01
status text predates the merged C01 contract; its C02-C06 entries remain unchecked.
Update it only after owner review and an authorized status change.

## 5. Future two-device acceptance checklist

**All scenarios below are NOT RUN.** Use only a separately approved non-production
environment, distinct Rider/Driver test accounts, synthetic data, and sanitized
evidence. A/B mean physical Device A (authenticated Rider) and Device B
(authenticated Driver). Do not put credentials, tokens, full private IDs, or raw
backend payloads in this repository. A test must stop on an unknown mutation result;
reconcile read-only before any further command. The matrix contains **16 future
acceptance scenarios**; none is evidence of execution.

| ID / status | Preconditions and blocking dependency | Device A — Rider | Device B — Driver | Evidence and pass/fail condition |
|---|---|---|---|---|
| **T01 — actor separation / NOT RUN** | Owner-approved non-production target, namespace, and two distinct accounts; R04 actor/session authorization remains partial. | Sign in as the designated Rider; record sanitized role/owner context. | Sign in as the distinct approved Driver; verify Driver role/approval and owned vehicle context. | **PASS:** different canonical principals and correct roles/namespace; no cross-account data. **FAIL:** same identity, wrong role, stale owner, or token/session leakage. |
| **T02 — Cash selection and canonical fare lock / NOT RUN** | Configured canonical fare service, approved route, and authorized synthetic booking. | Select Cash, enter route, request authoritative quote, review and lock it once. | Remain available only if the approved Driver/vehicle fixture is ready; do not accept an offer yet. | **PASS:** canonical Booking and locked FareQuote IDs/versions link; Cash method, route, integer-fils amount, and quote lineage agree. **FAIL:** demo fare presented as canonical, stale/mismatched quote, or Card method. |
| **T03 — canonical booking confirmation / NOT RUN** | Same owned, locked Cash booking; owner has resolved the R08 scope/acceptance disposition. | Confirm the original booking once; re-read booking and FareQuote; reopen screen. | No action required. | **PASS:** canonical booking status/version advances once; FareQuote identity and amount remain unchanged; UI says booking confirmed and does not assert paid/captured/settled/receipt issued. **FAIL:** duplicate confirmation, changed quote/method, or financial-success wording without separate evidence. |
| **T04 — Slice 1 demo guard / NOT RUN** | Isolated build intentionally in unconfigured Demo mode; this is a UI guard check, not matching acceptance. | Select Card and verify disabled continuation/accessibility explanation; switch to Cash and verify demo continuation is restored. | No action required. | **PASS:** Card stays Card intent and cannot navigate into mock search; Cash is not coerced and can continue to the explicitly labeled mock flow. **FAIL:** Card reaches mock trip or selection silently changes. This result is not canonical match evidence. |
| **T05 — Driver availability and matching request / NOT RUN** | Canonical confirmed Cash booking; eligible Driver/owned compatible active vehicle; reviewed trusted endpoint composition and R04 authorization. A05 currently has no wired endpoint. | Request matching once through the approved Rider-facing path; never call service-role RPCs. | Set/read canonical availability through approved Driver actions; keep app online. | **PASS:** service-only A03 candidate discovery and A04 offer creation use canonical booking/version/eligibility; no caller-selected Driver or client credentials. **FAIL:** direct client privileged RPC, stale/ineligible Driver, duplicate offers, or no canonical evidence. |
| **T06 — offer acceptance / NOT RUN** | One live canonical offer, correct Driver, active compatible vehicle, offer/version within the 15-second window; Driver UI/offer delivery integration reviewed. | Wait and then reread canonical assignment, not the push/Realtime payload. | Inspect exact offer and accept once using its current offer ID/version and idempotency key. | **PASS:** one accepted offer, one linked canonical Trip, matched booking; both devices resolve the same IDs after authorized rereads. **FAIL:** Trip created by UI, wrong Driver/vehicle/quote, duplicate Trip, expired/stale offer accepted, or notification treated as authority. |
| **T07 — offer rejection and expiry / NOT RUN** | Fresh isolated offer and authorized versioned Driver action. A04 expiry cleanup has no installed scheduler. | Reread and verify no assignment after rejection/expiry. | In separate runs, decline the exact offer; in another run let expiry occur and use only an approved expiry service operation. | **PASS:** decline/expiry is canonical, reservation is released, no accepted Trip appears, and stale acceptance is rejected. **FAIL:** stale offer accepted or client invents expiry. **BLOCK:** no scheduler/liveness proof; do not claim autonomous cleanup. |
| **T08 — Rider/Driver Trip visibility / NOT RUN** | A05 assignment reader and relevant Rider/Driver consumers integrated and reviewed; separate authenticated participant sessions. They are not currently wired. | Read the assigned Trip from the confirmed booking reference and verify owner/route/quote. | Read current assigned Trip/offer under Driver ownership. | **PASS:** same canonical Trip/Booking/Quote/Driver/vehicle IDs and current status/version; foreign reads fail closed. **FAIL:** mismatch, mock ID, locally fabricated assignment, or query identity accepted as authorization. |
| **T09 — GPS and Realtime location / NOT RUN** | Approved device permissions, accepted Trip, supported GPS settings, reviewed Rider Realtime subscriber; resolve the 60-second server freshness vs up-to-120-second publisher mismatch. | Treat Realtime only as invalidation; issue a fresh authorized Trip/location read before display. | Publish ordered, Trip-associated fixes while tracking is active; exercise reconnect. | **PASS:** monotonic sequence, same Trip, accepted age/accuracy/future-skew policy, and stale data hidden. **FAIL:** old fix fallback, Realtime payload used as assignment/state authority, or location crosses sessions. **BLOCK:** C04 not in HEAD and end-to-end Rider Realtime is NOT RUN. |
| **T10 — canonical lifecycle transitions / NOT RUN** | Accepted canonical Trip and versioned Driver actions; reviewed C05 integration. | Reread after each transition and on reconnect. | Advance only through accepted → `driverArriving` → `driverArrived` → `inProgress` using authorized RPCs and expected versions. | **PASS:** legal canonical statuses and monotonically advancing versions agree across devices; duplicate/out-of-order events are reconciled by reread. **FAIL:** skipped/unauthorized transition, stale state shown as current, or mock status used. |
| **T11 — cancellation and stale-state handling / NOT RUN** | One active offer/Trip, current versions, owner-approved cancellation scenario, and deterministic recording. | Cancel through the authorized Rider flow in one run; in another, change session or act against stale state. | Attempt no action after terminal cancellation; in a stale-version run submit only the originally captured Driver operation once. | **PASS:** one canonical terminal/conflict outcome; no resurrected offer, duplicate Trip, or cross-owner publication. **FAIL:** stale action overwrites newer state, duplicate effect occurs, or timeout is blindly replayed. |
| **T12 — authorized Trip completion / NOT RUN** | Canonical `inProgress` Cash Trip; R01/R02/R07 disposition and explicit test-fixture execution authorization; current completion gate is default-off. | Observe/read canonical Trip after Driver completion, without initiating settlement. | Use the reviewed canonical completion owner with original Trip version/key once; do not use mock completion. | **PASS:** one canonical completed Trip and preserved uncertainty/idempotency evidence. **FAIL:** client sets completed/paid, duplicate completion, automatic retry, or journal/evidence cleared. **BLOCK:** R07 is PREPARED, NOT ACCEPTED; no completion until separately authorized. |
| **T13 — canonical Payment and Receipt reread / NOT RUN** | Authorized completed Cash Trip and trusted Trip-to-Payment identity source; R05 reader available; R07 completion/receipt acceptance completed separately. | Obtain Payment ID only from the canonical Trip summary; reread exact Cash Payment and independently read Receipt evidence. | Use only authorized Driver-safe receipt read where applicable; do not query financial tables directly. | **PASS:** Trip/Payment/Receipt linkage, Rider/method/currency/amount/status/version all match; receipt issuance is independently verified. **FAIL:** Payment ID derived from Booking/Trip ID, paid inferred from completion, or receipt inferred from paid. **BLOCK:** no R07 accepted settlement/receipt evidence. |
| **T14 — no false financial success / NOT RUN** | Review build configured for the approved confirmation and payment-read states; no provider action is enabled. | Capture visible/accessibility copy at booking-confirmed, payment-unverified, and receipt-unverified states. | Observe matching Trip state but do not communicate payment success from Driver status. | **PASS:** booking confirmation remains a booking outcome; any paid/receipt wording is sourced only from its own canonical evidence; missing receipt is unverified. **FAIL:** confirmation/completion, timeout, or Realtime alone claims paid/captured/settled/receipt issued. |
| **T15 — Card/Stripe stays blocked / NOT RUN** | Default Card/Stripe dispatch-off build; no Card credentials or provider endpoint. Any Card test beyond disabled UI requires separate approval. | Select Card as draft intent and verify confirmation/entry remain unavailable; do not submit provider data. | No Card/Stripe action. | **PASS:** Card cannot confirm, Card does not convert to Cash, no Stripe SDK/session/provider request occurs. **FAIL:** Card authorizes/captures or displays financial success. **BLOCK:** R06/R08/Card activation is a hard stop and is not authorized. |
| **T16 — logout/account-switch isolation / NOT RUN** | Two distinct test identities and controlled delayed reads/events; approved R04 identity testing. | Logout or switch Rider while a read is pending; verify old booking/trip/payment view is hidden. | Logout/revoke Driver session during pending offer/Trip observation; verify old state/actions are retired. | **PASS:** late data/action is discarded, each device displays only its current principal's canonical data, and reauthentication is required. **FAIL:** stale result, offer, GPS, or financial detail crosses identities. |

## 6. Stop conditions

Stop the scenario immediately and preserve sanitized evidence if any of the
following occurs:

- Rider/Driver identity, role, namespace, owner, Booking, FareQuote, Offer, Trip,
  vehicle, method, or version is missing, foreign, stale, or conflicting.
- An RPC result is unknown, times out after possible dispatch, or disagrees with a
  canonical reread. Do not retry, replay, regenerate keys, or clear evidence;
  request authorized read-only reconciliation.
- Card/Stripe entry, credentials, authorization, capture, provider dispatch, or
  `RIDEX_ENABLE_TEST_DRIVER_CASH` activation appears without separate approval.
- Booking confirmation, mock/Driver Trip status, timeout, or Realtime notification
  implies Payment paid/captured/settled or Receipt issued/verified without its own
  canonical evidence.
- An unauthorized status transition, duplicate Booking/Offer/Trip/Payment/Receipt
  effect, stale state resurrection, or cross-session publication is observed.
- The test target/actor/fixture is not explicitly approved, an owner approval is
  missing, or any step requires direct table writes/service credentials in Flutter.

## 7. Owner acceptance checklist

No owner acceptance is claimed. Before the matching/two-device run, the owner must
explicitly approve and record:

- [ ] Resolution of the P6-R08 scope-label conflict and acceptance scope for the
      C06 Cash booking handoff; do not infer this from the R08 review report.
- [ ] Named non-production project/namespace, Rider and Driver test actors,
      allowed synthetic fixture lifecycle, and evidence-retention location.
- [ ] Reviewed trusted endpoint composition for A05; authentication, authorization,
      rate/abuse limits, service-secret custody, version handling, timeout, and
      unknown-outcome/read-only reconciliation policy.
- [ ] Integration review for Rider assignment/Trip consumers, Driver offer UI,
      Realtime invalidation, GPS freshness cadence, offer-expiry liveness, and
      session retirement. Resolve existing 60s/120s GPS freshness mismatch.
- [ ] Separate R07 approval for any completion, Cash settlement, Receipt issuance,
      lost-response, concurrency, or restart/recovery mutation test.
- [ ] Separate R06/R08/Phase 8 owner/security approval before any Card/Stripe
      account, credential, provider, authorization, or capture work. None is
      authorized by this handoff.
- [ ] Final two-device evidence review and explicit P7-C06 owner acceptance. Only
      after review should the appropriate owner update `Phase 7/Sanad.md`.

## 8. Current verdict

**LOCAL IMPLEMENTATION VERIFIED** — Slices 1 and 2 are committed at `bcc3eb2` and
`59d8404`; previously reported focused/widget/full-suite evidence is summarized
above. This documentation task did not rerun tests.

**LIVE / TWO-DEVICE ACCEPTANCE PENDING** — no C06 live matching endpoint/consumer,
P7-C02–C05 integration, hosted/device verification, R07 completion/settlement/
receipt acceptance, or owner approval is evidenced here. Phase 6 remains NOT
APPROVED. This handoff is not a declaration of integrated or release acceptance.

## Evidence index

- [P7 checkpoints / Sanad](../../../Phase%207/Sanad.md)
- [R08 Cash-only acceptance report](R08_CASH_ONLY_ACCEPTANCE_2026-11-02.md)
- [Phase 6 authoritative Sprint Tracker](../../parallel-development/phase-6/SPRINT_TRACKER.md)
- [Phase 6 post-merge roadmap](../../parallel-development/phase-6/P6_POST_MERGE_ROADMAP.md)
- [P6-R05 canonical Rider UI](../../parallel-development/phase-6/P6_R05_CANONICAL_TRIP_UI.md)
- [P6-R06 implementation](../../parallel-development/phase-6/P6_R06_IMPLEMENTATION.md)
- [P6-R06 durable preparation](../../parallel-development/phase-6/P6_R06_DURABLE_PREPARATION.md)
- [P6-R06 final closeout](../ops/R06_FINAL_CLOSEOUT.md)
- [P6-R07 fixture preparation](../../parallel-development/phase-6/P6_R07_TEST_FIXTURE_PREPARATION.md)
- [P6 canonical Driver Cash UI](../../parallel-development/phase-6/P6_CANONICAL_DRIVER_CASH_UI.md)
- [P7-A05 local integration verification](P7_A05_LOCAL_INTEGRATION_VERIFICATION_2026-11-04.md)
- [P7-A06 security/contract handoff](P7_A06_SECURITY_CONTRACT_HANDOFF_2026-11-04.md)
- [P7-A04 local database verification](P7_A04_LOCAL_DATABASE_VERIFICATION_2026-11-04.md)
- [P7-B01 Driver contract](../plans/P7_B01_DRIVER_FLOW_CONTRACT.md)
- [P7-B06 completion stop-gate plan](../plans/P7_B06_CASH_COMPLETION_GATE.md)
- [P7-B02 local verification](P7_B02_LOCAL_VERIFICATION.md)
- [P7-B03 local verification](P7_B03_LOCAL_VERIFICATION.md)
- [P7-B04 local verification](P7_B04_LOCAL_VERIFICATION.md)
- [P7-B05 local verification](P7_B05_LOCAL_VERIFICATION.md)
- [P7-B06 local verification](P7_B06_LOCAL_VERIFICATION.md)

The C06 code/test evidence paths are `lib/features/booking/presentation/screens/fare_estimate_screen.dart`,
`test/fare_estimate_screen_test.dart`, `lib/features/booking/presentation/screens/booking_confirmation_screen.dart`,
`test/booking_confirmation_handoff_test.dart`, and `lib/core/models/booking_handoff.dart`.
The Phase 7 contracts referenced above include
`supabase/functions/_shared/matching/cash_matching_adapter.ts`,
`lib/core/repositories/cash_booking_assignment_repository.dart`,
`lib/core/repositories/rider_trip_tracking_repository.dart`,
`lib/core/models/rider_trip_tracking_event.dart`,
`lib/features/driver_flow/domain/driver_flow_contract.dart`,
`lib/features/driver_flow/presentation/providers/driver_flow_repository_provider.dart`,
`lib/core/providers/driver_tracking_providers.dart`, and
`lib/core/services/driver_location/supabase_driver_tracking_connection.dart`.
