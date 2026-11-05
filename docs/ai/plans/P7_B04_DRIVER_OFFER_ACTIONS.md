# P7-B04 - safe simulated Driver offer decisions

Owner: Moath. Issue: #109. Branch: `feature/p7-b04-driver-offer-actions`.
Base: `6a9485b352710f185296753d62437d26d08f06d1` (PR #121).
The approved conversation plan is implemented locally; independent review is pending.

## Ownership and reuse

Modify only the existing incoming-offer controller/screen, B01 contract commentary,
B01 plan correction, test fake and its tests. Add B04 controller/widget tests and
this plan plus the local verification record. B03 remains the sole offer-state
owner. No second repository/controller, shared session/router/GPS/Rider change,
Driver Home change, dependency, migration or backend adapter is introduced.

## Admission and commands

`driverOfferSimulationEnabledProvider` defaults to false. Only deliberate local
test/demo overrides can enable controls, alongside a simulated repository and
local scope. The production repository and null scope defaults are unchanged.
Every action validates inside the controller after dependency flushing: active
lifetime/session, full displayed offer equivalence, simulated source, actionable
status, positive remaining time, no observed Trip and no retired/uncertain attempt.
The widget callback captures the displayed offer, preventing stale callbacks from
acting on a replacement. Reserved/onTrip availability is never synthesized here.

A synchronous attempt lock precedes scheduling/dispatch. Admission is rechecked
after pending-state publication and scheduler setup, so synchronous host listeners
cannot revoke scope or advance expiry and still allow dispatch. The P2 correction
also checks observation readiness independently of our own pending decision lock:
latest simulated/session-matching ready snapshot, no Trip, identical full captured
offer, actionable observation view, and unchanged operation ownership. A local
pending decision does not change the observed ready phase. A reentrant observed
pending/loading/error/Trip/payload/version/gate change prevents execution.
The immutable attempt
captures the original DriverFlowDecideOffer, full offer, repository/scope epoch,
observation revision and operation identity. A secure controller nonce plus an
operation counter creates one token per admitted attempt. Rebuilds, reads, timers,
remount and resume cannot regenerate it. No retry or replay API is added.

## State and result policy

Decision state is independent of B03 observation/expiry state: idle, pendingAccept,
pendingDecline, simulatedAccepted, simulatedDeclined, rejected, stale, expired,
unknown or unauthorized. A pending or unknown attempt blocks both decisions.
Definite negative results retire the original ID/version. A genuinely new offer
can become actionable after a definite result, never after unknown. Simulated
acceptance blocks subsequent decisions for that scope without owning a canonical
Trip or routing to B05.

A simulated result requires the captured session/source, ready snapshot, newer
revision and no offer. Acceptance additionally requires accepted Trip vocabulary
and exact original journey; decline permits no Trip. Same-revision event-before-
reply results must match the complete publication, including availability and
Trip identity/version/journey. After dispatch, incompatible publications,
version/payload changes, observation failures, response exceptions,
unavailable/unsupported/malformed results and timeouts remain unknown.
Before dispatch, the attempt's explicit dispatched flag remains false: blocked
attempts cancel their timers and finish locally stale (expired at the deadline),
without transient lost-response UNKNOWN or replay. Scope/authorization retirement
keeps its existing semantics. A fresh eligible observation may admit a new attempt
following a definitely unsent cancellation, subject to all B03 memory barriers.
Retired timeout callbacks cannot affect that newer attempt. Authorization loss hides details and wins over uncertainty.

The injected one-shot scheduler bounds response waiting to 15 seconds, independently
of the offer deadline. Expiry while pending establishes neither success nor
rejection. Widget removal/backgrounding does not retire the persistent controller.
Scope/repository replacement or disposal retires the wait, cancels its timer and
rejects old completions. Old cleanup cannot release a replacement attempt.
Unknown remains latched for the active scope: ordinary reads, notification events,
new offers, higher revisions and late success cannot reconcile it. B01 has no
reviewed command-correlated reconciliation API. Scope retirement clears local
presentation only and does not establish the old command's real-world outcome.

B03 first-frame clock projection, monotonic expiry, per-ID version high-water,
equivalence memory and lifecycle handling remain in use. Original route/fare are
retained while an attempt is unresolved even if an observation omits the offer.
The test fake now retains uncertainty for decline as well as acceptance; its
existing explicit acceptance-outcome fixture API cannot resolve decline attempts.

## Screen

Default controls retain disabled labels. The explicit override exposes Simulate
accept / Simulate decline. Both disable synchronously on either decision. Semantic
live-region messages identify pending, rejection and unknown states; simulation
success never claims real assignment or payment. The existing route/stops, exact
integer-fils Cash formatting, deadline and limitation copy remain. Buttons wrap
and use at least 48 logical pixels height. No unsupported Rider contact is added.

## A04 source contracts and integration gates

Verified locally in `20261104100311_p7_a04_offer_lifecycle_atomic_acceptance.sql`:

- `driver_decline_match_offer(target_offer_id uuid, expected_offer_version integer,
  idempotency_key text)` returns `public.driver_match_offers`.
- `driver_transition_trip(target_id uuid, requested_status public.trip_status,
  expected_version integer, idempotency_key text)` returns `jsonb`.

Both have authenticated execute grants, use auth.uid(), require approved/nonblocked
Driver identity and validate owner offer access. Accept uses offer ID/version and
status accepted; later transitions use Trip ID/version. A04 revalidates expiry,
booking/search state, Rider eligibility and competing Trips under locks. Decline
claims actor/payload-bound idempotency and may return an expired row. A future
adapter must inspect canonical results, not assume decline succeeded.

No RPC is wired here. Live command delivery/session binding, canonical IDs and
lineage, authoritative unknown reconciliation, GPS freshness alignment (120-second
available-mode publishing versus 60-second matching freshness), expiry scheduler,
and hosted actor/device acceptance remain separate work. P6-R01/R02/R03/R07 still
gate Cash completion/settlement/receipts; P6-R06/R08 Card/Stripe and R09 phase exit
remain gated. The authoritative R08 scope is secure Stripe UI, not the historical
Cash label in the Moath brief. Phase 6 is not approved by this checkpoint.

## Acceptance and verification

Issue #109's local description requires single flight, no optimistic assignment,
stale-action protection and original-token handoff, with double-click, late,
rejected and lost-response fake tests. The approved detailed matrix additionally
covers expiry, versions/payloads, A-B-A and repository retirement, authorization,
remount/background/resume/disposal, stale callbacks, event-before-reply ordering,
unknown latching, default-off behavior and absence of financial/canonical authority.
An unfiltered controllable repository tests controller safety independently of the
fake. P2 tests inspect every transient decision publication and actual execute
calls for both decisions, including reentrant loading/pending, stream errors,
accepted Trip, authorization, full payload/version regression/replacement,
gate/scope/repository replacement, equivalent ready data and later recovery.
Tests read the real default gate without an override, assert widget live-region
properties, and reject mismatched result source/session/payload. Commands use deterministic completers/clocks/manual scheduler callbacks;
widget tests use Flutter's virtual timers. Actual results belong in the B04
verification record. The GitHub issue itself was not accessed during implementation.

No commit, push, merge, PR, issue mutation, hosted operation, financial action,
B05/B06 implementation or live activation is authorized by this local checkpoint.
