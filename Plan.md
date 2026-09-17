# RideX Development Plan

Last updated: 2026-09-14

## Purpose

This is the local source of truth for development discussions, decisions, reviews, and planned changes to RideX. Update it whenever a change is agreed on, implemented, reviewed, deferred, or cancelled.

## Working Rules

- Review this file before proposing or implementing a new change.
- Record agreed decisions and acceptance criteria before implementation.
- Mark assumptions clearly; do not present proposed work as implemented work.
- Keep only one main goal active at a time unless parallel work is explicitly agreed.
- Update task status and the change log after implementation and verification.
- Do not store secrets, API keys, passwords, or personal data here.

Task states: `[ ]` planned, `[~]` in progress, `[x]` completed, `[-]` cancelled or deferred.

## Current State

Verified from the repository, Git, automated tests, and read-only hosted Supabase
metadata through 2026-09-14:

- The audit was performed on `yousuf/supabase-env-audit` at `41dd2f5`, synchronized with `origin/yousuf/supabase-env-audit`.
- Rider UI V2 has already been merged into `main`.
- Git and the actual project files are the source of truth.
- Rider UI V2 remains accepted as complete within its original UI-focused scope.
- Flutter uses Riverpod for state ownership and GoRouter for navigation.
- Supabase permanently replaces Firebase as the backend platform.
- Real Supabase behavior currently covers email/password authentication, session restoration, profiles, roles, blocked state, and Driver approval state.
- Phase 3 migrations `005` through `022` provide the approved database foundations and remediation for security/audit/idempotency, Driver assets and availability, Booking/Fare/matching, Trips, Payments/Refunds/Receipts, Driver locations, Ratings, Notifications, and HelpRequests.
- Phase 3 is approved/completed after the documented remediation, clean isolated migration execution, and complete pgTAP verification.
- Flutter Booking, Driver matching, active trips, trip history, ratings, notifications, and Driver availability remain Mock-backed or session-local; Phase 3 added database foundations only.
- Checkpoint 4A commit `d65a58a` adds Google Maps to Rider and Driver Home plus one-shot foreground GPS and permission/fallback handling.
- Checkpoint 4B commit `2359a81` adds pickup/destination place search, geocoding, map selection, and routing-readiness validation. Fix commit `41dd2f5` blocks routing while map/GPS reverse geocoding is unresolved; this fix is pushed on the current branch but is not yet in `origin/main`.
- The hosted Supabase `places` function is active and the required `GOOGLE_MAPS_WEB_SERVICES_API_KEY` secret name exists. No secret value was read.
- Checkpoints 4A and 4B are approved. The project owner reports that Omar tested every previously remaining physical/live and configuration requirement successfully. The final 4B replacement-selection routing guard is implemented in the current working tree and passes focused and full regression verification.
- Real routing, route geometry/distance/duration, continuous Driver location tracking, and later Phase 4 work are not implemented.
- Multi-stop data can be represented in the booking draft, but stop management, routing, persistence, and fare integration are not implemented.
- Current fares are deterministic demo values rather than route-based fixed fares.
- Cash is displayed in the booking and completion UI, and Phase 3 defines trusted atomic Cash completion/settlement and persistent receipt foundations, but they are not connected to Flutter.
- Phase 3 defines approved Card Payment, attempt, Refund, Receipt, and webhook-ID foundations; provider integration, secure execution, and Flutter integration remain later-phase work.
- Current trip history and receipt content are Mock-backed and are not generated from completed persistent trips.
- Rider-Driver Realtime synchronization and two-device trip operation are not implemented.
- The existing automated tests validate the current UI, authentication, role, route, repository, and local lifecycle behavior. They do not establish Graduation MVP backend completeness.

## Active Goal

Checkpoints 4A, 4B, and 4C are approved. Checkpoint 4D is in progress: slice 1 is complete in implementation commit `4694a5e` and documentation commit `2a37abe`; slice 2 is next. Its approved scope and delivery slices are recorded in `docs/superpowers/specs/2026-09-17-checkpoint-4d-driver-location-tracking-design.md`.

### Problem

Project 1 requires a functional ride-hailing system with maps, location, Driver matching, persistence, cash and card payments, and operational Rider, Driver, and Admin workflows. The current application intentionally completed Rider UI V2 with Mock-backed or presentation-only implementations for many of these areas.

The Graduation MVP requires a new implementation sequence without treating the accepted Rider UI V2 scope as defective or redesigning existing architecture unnecessarily.

### Desired Outcome

RideX has an explicitly approved Graduation MVP scope, provider-independent payment contracts, compatible Trip and Payment lifecycles, measurable security boundaries, clear ownership, and a dependency-safe implementation roadmap.

### Acceptance Criteria

- [x] Supabase permanently replaces Firebase.
- [x] Cash and card payments are included in the Graduation MVP.
- [x] Stripe Test Mode is approved for the graduation card-payment demonstration.
- [x] Stripe is not approved as the final production payment provider for Jordan.
- [x] Payment architecture remains provider-independent so Stripe can later be replaced without redesigning Flutter UI, repository contracts, payment records, or Trip lifecycle.
- [x] Card entry uses Stripe PaymentSheet, Stripe Checkout, or another approved Stripe-hosted interface.
- [x] Raw card data and sensitive payment credentials are never collected or stored by RideX.
- [x] Stripe secrets and the Supabase service-role key remain server-side only.
- [x] Canonical payment results are verified server-side.
- [x] Payment method and payment status are stored separately.
- [x] Card authorization occurs only after successful Driver matching.
- [x] Card capture occurs only after trusted Driver completion.
- [x] Cash is not marked paid before trusted Driver completion.
- [x] Duplicate payment prevention and webhook replay protection are explicit.
- [x] Included and deferred Graduation MVP features are explicit.
- [x] Yousuf, Omar, and Shared ownership boundaries are explicit.
- [x] Rider UI V2 remains accepted within its original scope.
- [x] The dependency-safe implementation roadmap is approved.

### Out of Scope

The following are outside the Graduation MVP:

- Rewards and referrals.
- Promotions and promo codes.
- Chat and calling.
- Production phone OTP.
- AI chatbot.
- RideX wallet.
- Advanced Admin analytics.
- Advanced refund automation.
- Ride sharing.
- Demand prediction.
- Advanced route optimization.
- Cancellation fees.
- Partial captures.
- Partial trip charges.
- Complicated financial dispute rules.
- Production card-payment deployment in Jordan.

This planning step also excludes all implementation work. Do not add Flutter code, Supabase migrations, dependencies, tests, configuration, credentials, remote operations, or deployment changes as part of this step.

## Approved Graduation MVP Scope

The Graduation MVP includes:

- Supabase authentication, authorization, persistence, Realtime, and secure server-side operations.
- Real maps.
- GPS and location permissions.
- Place search.
- Real routing.
- Pickup and destination selection using geographical coordinates and provider place identifiers.
- Multi-stop booking with a maximum of three intermediate stops.
- Ordered stop persistence.
- Route distance and duration calculation.
- Route-based fixed fare calculation.
- Persistent and versioned fare quotes.
- Real Driver availability.
- Nearby Driver matching.
- Atomic Driver assignment and prevention of double acceptance.
- Supabase Realtime Rider-Driver synchronization.
- Live Driver location during active trips.
- Persistent Trips and Trip history.
- Persistent ratings.
- Persistent notifications.
- Persistent profiles and profile updates.
- Persistent help requests.
- Basic Admin Driver approval.
- Cash payments.
- Stripe Test Mode card payments.
- Persistent payment, refund, and receipt records.

## Fare Locking

Before Driver matching begins, RideX must persist and lock:

- Pickup location.
- Destination location.
- Ordered intermediate stops.
- Selected vehicle type.
- Route distance.
- Route duration.
- Fare breakdown.
- Currency.
- Fixed fare amount.
- Fare quote version.

The payment amount must come from this trusted fare quote. Flutter must not provide an authoritative payment amount.

If the route, ordered stops, vehicle type, fare breakdown, currency, or fixed fare changes, a new fare quote version is required. An existing authorization must not be reused for a changed amount without a secure backend decision.

## Provider-Independent Payment Architecture

The application payment domain must not expose Stripe-specific concepts as its primary Flutter or repository contracts.

Provider-independent responsibilities include:

- Flutter presents Cash or Card and canonical payment states.
- Payment repositories expose provider-neutral operations.
- Supabase stores canonical payment records and provider metadata separately.
- A secure backend adapter communicates with Stripe during the Graduation MVP.
- A future Jordan-supported provider can replace the Stripe adapter without redesigning Trip state, Flutter payment UI, receipts, or payment ownership rules.

Stripe-specific identifiers may be stored as provider metadata, but business logic must use RideX Trip, Fare Quote, Payment, Refund, and Receipt identifiers.

## Security Boundaries

- Card entry must use Stripe PaymentSheet, Stripe Checkout, or another explicitly approved Stripe-hosted interface.
- RideX must never directly collect or store a full card number, CVV, PIN, magnetic-stripe data, sensitive 3DS credentials, or card images.
- Stripe secret keys and the Supabase service-role key must exist only in a secure server-side environment such as a Supabase Edge Function.
- Secrets must never be stored in Flutter, public configuration, Git, client-accessible Supabase records, or logs.
- Flutter must never set a payment to succeeded, authorized, captured, cancelled, or refunded directly.
- Flutter callbacks and redirect results are advisory only.
- Canonical payment state must be verified server-side through Stripe webhooks and, when necessary, a server-to-server Stripe API query.
- Webhook signatures must be verified before processing.
- Payment amount, currency, Trip ID, Fare Quote ID, provider reference, and expected state must be compared before a canonical state transition.
- Sensitive raw Stripe payloads must not be persisted.
- Logs must not contain card information, secrets, or sensitive provider payloads.

## Payment Methods and States

Payment method and payment status are separate fields.

Approved payment methods:

- `cash`
- `card`

Approved card-payment states:

- `card_payment_pending`
- `card_payment_authorized`
- `card_payment_succeeded`
- `card_payment_failed`
- `payment_cancelled`
- `refund_pending`
- `refunded`

Approved cash behavior uses:

- `cash_selected` while selected but unpaid.
- A canonical paid/succeeded state only after trusted Trip completion.
- `payment_cancelled` when the Trip is cancelled without cash settlement.

Trip states and Payment states must remain separate. A completed Trip does not imply that a Card capture succeeded.

## Card Payment Lifecycle

1. The Rider selects Cash or Card before requesting the Trip.
2. The route, ordered stops, vehicle type, fare breakdown, currency, fixed fare, and Fare Quote are stored and locked.
3. Driver matching begins.
4. No Stripe authorization or capture occurs while matching is unresolved.
5. If no Driver is found, the booking ends without a Stripe financial operation.
6. After a Driver is assigned, the secure backend creates or confirms a Stripe PaymentIntent configured for manual capture.
7. The card amount is authorized only after Driver matching succeeds.
8. The Trip must not start until the backend verifies the authorization.
9. The assigned Driver completes the Trip through a trusted backend operation.
10. Trusted Trip completion requests Capture for the fixed authorized amount.
11. Stripe webhook verification or a server-to-server Stripe query confirms the canonical Capture result.
12. A successful verified Capture changes the payment to `card_payment_succeeded` and permits final receipt generation.
13. If Capture fails, the Trip remains completed and the payment becomes `card_payment_failed`.
14. Failed post-Trip Capture is visible to an authorized Admin for resolution.

## Cancellation and Refund Rules

- If no Driver is found, no card Authorization or Capture occurs.
- If the Rider cancels before Authorization, the booking is cancelled without a financial operation.
- If the Rider or Driver cancels after Authorization but before Trip start, the authorization is cancelled or released securely.
- The Graduation MVP does not apply cancellation fees or partial Trip charges.
- Refunds are initiated only by a secure backend operation or authorized Admin action.
- A requested Refund becomes `refund_pending`.
- The canonical payment becomes `refunded` only after Stripe verification.
- Flutter never creates or confirms a Refund directly.
- Advanced automatic refund policies remain outside the Graduation MVP.

## Duplicate Payment Protection

Duplicate and replay protection must include:

- One active payment attempt per Trip.
- Stripe idempotency keys.
- A unique provider transaction or PaymentIntent reference.
- A unique processed webhook event ID.
- Database constraints where applicable.
- Validated payment state transitions.
- Transactional or locked updates for financial state changes.
- Returning the existing payment session after repeated button taps.
- Treating duplicate, stale, or out-of-order webhook events as safe no-ops after validation.

## Cash Payment Lifecycle

1. The Rider selects Cash before requesting the Trip.
2. The Cash selection is stored persistently.
3. The payment remains `cash_selected` during Driver matching and the active Trip.
4. Cash is not displayed or stored as paid before Trip completion.
5. When the assigned Driver completes the Trip, one trusted backend operation:
   - Completes the Trip.
   - Marks the Cash payment paid.
   - Records the payment timestamp.
   - Generates a persistent receipt.
6. If the Trip is cancelled:
   - The Cash payment becomes cancelled.
   - No paid timestamp is stored.
   - No paid receipt is generated.

## Payment Metadata

Safe payment metadata may include:

- Provider name.
- Payment method.
- Stripe PaymentIntent or provider transaction reference.
- Card brand.
- Last four card digits.
- Amount.
- Currency.
- Canonical payment status.
- Sanitized failure code.
- Authorization reference.
- Capture reference.
- Refund reference.
- Idempotency key.
- Relevant timestamps.

RideX must never store:

- Full card number.
- CVV or PIN.
- Magnetic-stripe data.
- Stripe secret keys.
- Supabase service-role keys in client-accessible data.
- Sensitive 3DS credentials.
- Card images.
- Sensitive raw Stripe payloads.
- Debug logs containing card information.

## Receipt Rules

- Receipts are generated from trusted persistent Trip, Fare Quote, and Payment records.
- A paid Cash receipt is generated only during trusted Trip completion.
- A Card receipt is finalized only after verified Capture success.
- Cancelled unpaid Trips do not produce paid receipts.
- Refunds preserve the original receipt and create an auditable refund record.
- Receipt UI must not reconstruct authoritative fare components from display values.

## Architecture Responsibilities

### Flutter Payment UI

- Present Cash and Card selection.
- Open Stripe PaymentSheet, Checkout, or another approved Stripe-hosted interface.
- Display canonical loading, pending, authorized, success, failure, cancellation, and refund states.
- Never handle provider secrets.
- Never declare final payment success.

### Payment Repository

- Expose provider-independent payment operations and records.
- Return canonical RideX payment states.
- Keep Stripe-specific implementation details behind an adapter.

### Supabase Payment Records

- Store method, canonical status, amounts, currency, ownership, Trip and Fare Quote references, provider metadata, idempotency data, and timestamps.
- Enforce constraints, state transitions, and RLS.

### Secure Backend

- Calculate or validate the trusted payment amount.
- Create or confirm Stripe PaymentIntents.
- Request Authorization, Capture, cancellation, and Refund operations.
- Hold Stripe secrets and the Supabase service-role key.
- Perform provider queries and canonical database updates.

### Stripe Interface

- Securely collect card details.
- Perform 3DS and cardholder authentication.
- Return provider references and events without exposing card data to RideX.

### Webhook Handler

- Verify Stripe webhook signatures.
- Deduplicate webhook event IDs.
- Validate amount, currency, references, and expected state.
- Query Stripe when webhook data is insufficient or reconciliation is required.
- Update canonical records transactionally.

### Trip Completion

- Allow only the assigned Driver through a trusted backend operation.
- Complete the Trip independently from final Card Capture success.
- Trigger Cash settlement or Card Capture according to payment method.

### Admin Payment Visibility

- Show sanitized payment state, amount, currency, provider, card brand, last four digits, failure category, and operational references.
- Never expose secrets or raw sensitive payloads.

## Ownership

### Yousuf

- Supabase schema and migrations.
- RLS and authorization.
- Core models and repository contracts.
- Backend services and providers.
- Fixed-fare validation.
- Driver-matching transactions.
- Payment backend.
- Stripe PaymentIntent creation.
- Stripe webhook verification.
- Capture, cancellation, and Refund operations.
- Payment and receipt persistence.
- Admin security.
- Backend and security tests.

### Omar

- Maps and location UI.
- Permission states.
- Pickup, destination, and multi-stop interaction.
- Vehicle selection.
- Fare and booking-review UI.
- Rider and Driver Trip screens.
- Cash and Card selection.
- Stripe PaymentSheet or hosted-checkout UI.
- Payment loading, success, failure, and cancellation states.
- Receipt and history UI.
- Profiles, notifications, ratings, help, and basic Admin UI.
- Widget, navigation, accessibility, and responsive-layout tests.

### Shared

- Models and state definitions.
- Repository contracts.
- Trip and Payment lifecycle compatibility.
- Realtime integration.
- End-to-end testing.
- Two-device testing.
- Release verification.

## Decisions

| Date | Decision | Reason | Status |
| --- | --- | --- | --- |
| 2026-07-22 | Use this file as one living development plan. | Preserve discussion context and guide future reviews and changes. | Active |
| 2026-07-22 | Keep `Plan.md` local and out of Git. | The plan is private working context and should not be pushed to GitHub. | Active |
| 2026-07-22 | Require an explicit compile-time backend mode; never infer Mock mode from missing Supabase values. | Prevent silent Mock authentication and profile fallback, especially in Release. | Active |
| 2026-07-22 | Validate configuration centrally and sanitize all startup failure output. | Reject unsafe configuration before initialization without exposing values or raw exceptions. | Active |
| 2026-07-22 | Allow `developmentMock` only in Development and Testing; require `productionSupabase` in Release. | Make the release backend policy fail closed and testable. | Active |
| 2026-07-22 | Keep Booking and Trips Mock-backed during backend-mode hardening. | Preserve Case 2 scope without adding Supabase persistence prematurely. | Active |
| 2026-07-29 | Supabase permanently replaces Firebase. | Match the implemented backend foundation and approved Graduation MVP direction. | Approved |
| 2026-07-29 | Include Cash and Card in the Graduation MVP. | Satisfy Project 1 payment requirements and the approved demonstration scope. | Approved |
| 2026-07-29 | Use Stripe Test Mode only for the Graduation MVP demonstration. | Provide a real sandbox card flow without approving Stripe for Jordan production deployment. | Approved |
| 2026-07-29 | Keep the payment domain provider-independent. | Permit later replacement with a Jordan-supported provider without redesigning Flutter, repositories, records, or Trip lifecycle. | Approved |
| 2026-07-29 | Authorize Card payment only after Driver matching and capture only after Driver completion. | Avoid unnecessary holds and align financial settlement with trusted Trip state. | Approved |
| 2026-07-29 | Use only secure Stripe-hosted card entry and server-side canonical verification. | Keep RideX outside raw card-data handling and prevent client-authoritative payment results. | Approved |
| 2026-07-29 | Exclude cancellation fees, partial captures, and partial Trip charges. | Keep the Graduation MVP lifecycle measurable and appropriately scoped. | Approved |
| 2026-07-29 | Support a maximum of three intermediate stops. | Resolve the unspecified Project 1 stop limit with a testable MVP boundary. | Approved |
| 2026-07-29 | Preserve Rider UI V2 as complete within its original scope. | Real maps, persistence, matching, Realtime, and payments are later MVP milestones, not retroactive UI defects. | Approved |
| 2026-07-29 | Treat Git and actual project files as the source of truth for project status. | `CURRENT_STATUS.md` contains outdated branch and merge information. | Approved |

## Planned Work

The approved dependency-safe roadmap is:

### Phase 1: Requirements and Architecture

- [x] Approve and document the Graduation MVP requirements and payment architecture.

### Phase 2 — Domain Architecture and Shared Contracts

Status: Approved - documentation complete; Phase 3 database implementation followed and is under review

Scope:

Define the domain models, provider-independent repository contracts, Booking and Trip state machines, Fare Quote rules, Cash-only in-progress Fare Adjustments, separate Cash and Card payment lifecycles, error contracts, Realtime events, ownership, and measurable acceptance tests before database or Flutter functionality implementation.

Main deliverables:

- Approved domain models and validation boundaries.
- BookingRequest, Trip, Fare Quote, Cash Trip Change, Cash Payment, and Card Payment state machines.
- Provider-independent repository contracts.
- Fixed-fare protection and single-authorization Card payment rules.
- Trip, Fare, and Payment compatibility rules.
- Error, recovery, Realtime, ownership, and acceptance-test contracts.
- Future implementation file-group plan.

Ownership:

- Yousuf leads core models, repositories, backend authority, Fare, matching, payment, security, and backend-test contracts.
- Omar reviews UI-state mapping, map and booking interactions, Cash Trip Change UI, payment presentation, receipt/history behavior, and widget/navigation-test contracts.
- Yousuf and Omar share lifecycle, Realtime, compatibility, acceptance-test, and end-to-end approval.

Detailed design:

`docs/ai/plans/PHASE_2_DOMAIN_ARCHITECTURE_AND_CONTRACTS.md`

Approval state:

Approved by Yousuf and Omar for the Graduation MVP. The detailed design resolves the final Phase 2 decisions. Phase 3 or functionality implementation begins only after a separate explicit instruction.

### Phase 3: Database and Authorization

Status: **Approved / Completed**

Detailed references:

- `docs/ai/plans/PHASE_3_SUPABASE_IMPLEMENTATION_PLAN.md`
- `docs/ai/ops/PHASE_3_STATUS.md`

Completed implementation and frozen acceptance scope:

- [x] Driver lifecycle and canonical `driver_availability` consistency.
- [x] Driver, Vehicle, reservation, and active-Trip consistency.
- [x] Booking and Trip lifecycle correctness.
- [x] Current Card authorization-cycle correctness; historical successful Authorizations cannot authorize a newer cycle.
- [x] Payment cancellation consistency; active-Trip cancellation is blocked and an authorized Card requires verified current-cycle void/release.
- [x] Trusted Cash completion atomically completes the Trip, settles the Payment, and issues the Receipt; generic Payment RPCs cannot mark Cash paid.
- [x] Nonnegative remaining-route Cash FareAdjustment calculation and canonical Payment reconciliation.
- [x] Strict positive `expected_version` validation across versioned Phase 3 RPCs.
- [x] PaymentAttempt initial/replacement ordering, Capture retry ordering and limits, pending-attempt protection, and idempotency mismatch rejection.
- [x] Safe finance exposure through RLS and restricted summaries without provider-authoritative client fields.
- [x] HelpRequest payment-card-data rejection and Notification payload, destination, identifier, and recipient validation.
- [x] Focused pgTAP regression coverage for every Phase 3 approval blocker, including zero-value remaining-route adjustment and Admin HelpRequest card-data rejection.
- [x] Clean isolated migration execution from `001` through final migration `022`.
- [x] Complete pgTAP suite passing with no failures.

Final verification:

Omar manually verified that migrations `001` through `022` applied successfully in a clean isolated execution and that the complete pgTAP suite passed with no failures. All previously recorded Phase 3 contract, lifecycle, payment, security, and regression-coverage blockers are resolved.

At Phase 3 completion, Phase 4 had not started and required separate scope approval. Checkpoints 4A and 4B have since been implemented, verified, and approved under the evidence-based gates below.

## Phase 4 — Maps, GPS, Place Search, and Routing

- [~] Implement maps, GPS, location permissions, place search, and routing. Checkpoints 4A, 4B, and 4C are approved; Checkpoints 4D through 4G remain incomplete.

### Checkpoint 4A — Map + GPS Foundation

- [x] 4.1 Integrate the map service into both Rider and Driver applications.
- [x] 4.2 Implement safe location-permission handling:
  - Permission not requested yet.
  - Permission granted.
  - Permission denied.
  - Permission permanently denied.
  - Device location service disabled.
- [x] 4.3 Retrieve the user's current GPS location and display it accurately on the map.
- [x] 4.4 Do not block the application when GPS is unavailable. Provide a clear fallback allowing the user to search for or manually select a location.

Checkpoint goal:

Establish the basic Maps/GPS infrastructure without implementing booking, routing, matching, fare calculation, or later-phase business logic.

Approval gate:

- [x] Rider map loads on physical Android with the restricted Maps credential.
- [x] Driver map loads on physical Android with the restricted Maps credential.
- [x] Current location works accurately on physical Android.
- [x] Every permission state is handled.
- [x] App remains usable when GPS is unavailable.
- [x] Existing architecture boundaries are preserved.
- [x] Flutter analyze passes.
- [x] Relevant existing tests pass.

Platform scope note:

Checkpoint 4A acceptance is Android-only. iOS runtime map/GPS verification is excluded from this checkpoint because macOS/Xcode and an iOS test environment are not currently available. Existing iOS configuration is preserved for future verification but is not an approval requirement.

Credential security confirmation:

- [x] Android Maps key loading uses ignored `android/local.properties`; the path is ignored and no Maps key is Git-tracked.
- [x] Google Cloud restrictions for Android package `com.ridex.app`, the applicable signing SHA-1, and Maps SDK for Android only were included in Omar's completed verification reported by the project owner.

Checkpoint status:

- [x] CHECKPOINT 4A APPROVED

Checkpoint 4A is approved. Repository verification passed 23 focused automated cases, analysis, and the full regression suite. On 2026-09-14, the project owner additionally reported that Omar completed every previously remaining physical Android, Maps/GPS, permission/fallback, and configuration requirement successfully. No credential value was added to this plan.

### Checkpoint 4B — Place Search + Location Selection

- [x] 4.5 Implement map-based pickup and destination selection using markers.
- [x] 4.6 Implement place/address search with useful autocomplete results.
- [x] 4.7 Implement forward geocoding: searched address/place -> latitude and longitude.
- [x] 4.8 Implement reverse geocoding: latitude and longitude -> readable pickup/destination address.
- [x] 4.9 Keep coordinates as the authoritative location data while using readable addresses for presentation/UI.
- [x] 4.10 Validate selected pickup and destination locations before allowing them to be used for route calculation. All map/GPS, prediction-details, and forward-geocode replacement paths now clear the affected committed endpoint while unresolved.

Checkpoint goal:

Allow the Rider to reliably choose valid pickup and destination locations.

Approval gate:

- [x] Pickup search works.
- [x] Destination search works.
- [x] Map selection works.
- [x] Markers update correctly.
- [x] Forward geocoding works.
- [x] Reverse geocoding works.
- [x] Invalid or unresolved locations cannot progress to routing.
- [x] GPS-selected and manually selected locations remain consistent.
- [x] Relevant tests pass. Final local verification passed all 33 focused Flutter cases; Omar's remaining-requirements verification was reported successful by the project owner. Deno was unavailable for an independent local rerun.

Checkpoint status:

- [x] CHECKPOINT 4B APPROVED

Checkpoint 4B is approved. Commit `41dd2f5` covers unresolved map/GPS reverse geocoding, and the current working-tree correction extends the same fail-closed behavior to prediction details and forward geocoding. Final local verification passed 33 focused 4B Flutter cases, analysis, and the full 132-pass/2-skip suite. On 2026-09-14, the project owner reported that Omar completed every remaining physical Android, authenticated live Google, Edge Function, and Cloud configuration requirement successfully. Public Terms/Privacy surfaces remain a separate pre-release requirement.

### Checkpoint 4C — Routing Engine

- [x] 4.11 Calculate a valid route between pickup and destination.
- [x] 4.12 Retrieve and expose trusted route information:
  - Route geometry/polyline.
  - Distance.
  - Estimated duration.
  - Origin.
  - Destination.
- [x] 4.13 Render the calculated route clearly on the map.
- [x] 4.14 Ensure route distance and duration come from the routing service rather than being estimated only from straight-line GPS distance.
- [x] 4.15 Handle route recalculation when the Rider changes pickup or destination before booking confirmation.
- [x] 4.16 Design the routing layer so Phase 5 can add intermediate stops without replacing the Phase 4 routing architecture.

Checkpoint goal:

Create a trusted routing foundation reusable by later RideX phases.

Approval gate:

- [x] Valid route is returned through authenticated live Google routing.
- [x] Polyline renders on physical Android.
- [x] Service-backed distance is available.
- [x] Service-backed estimated duration is available.
- [x] Route updates correctly after endpoint changes.
- [x] Stale route responses cannot overwrite newer route requests.
- [x] Routing provider is abstracted behind RideX contracts.
- [x] Architecture can later support ordered intermediate stops.
- [x] No Phase 5 fare or multi-stop business logic is implemented.
- [x] Relevant Flutter and Deno Edge Function tests pass.

Implementation evidence:

- [x] Focused Checkpoint 4C and booking-flow command passed 15 tests.
- [x] `flutter analyze --no-pub` reported no issues.
- [x] Full non-live Flutter suite passed 144 tests with 2 intentional skips.
- [x] `git diff --check` passed.
- [x] Deno `places` Edge Function suite passed 23 tests with 0 failures.
- [x] Routes API enablement and separate server-side key configuration verified.
- [x] Updated `places` Edge Function deployed and authenticated live route verified.
- [x] Temporary route diagnostics removed and the cleaned `places` function redeployed.
- [x] Route polyline, metrics, endpoints, and recalculation verified on physical Android.

Checkpoint status:

- [x] CHECKPOINT 4C APPROVED

Checkpoint 4C is approved. Automated verification passes, the authenticated live
Google route returns trusted geometry and service metrics, and physical Android
verification confirms polyline rendering and endpoint-change recalculation. Trip
History remains Mock-backed and displays static sample endpoints; that known
booking/history persistence limitation is outside Checkpoint 4C.

### Checkpoint 4D — Driver Location Tracking

- [ ] 4.17 Implement Driver GPS tracking with controlled location updates while location tracking is required.
- [ ] 4.18 Store/update DriverLocation through the approved architecture:

  ```text
  Service
    ->
  Repository
    ->
  Provider / Controller
    ->
  UI
  ```

- [ ] 4.19 Attach an authoritative timestamp to Driver location updates so current and stale locations can be distinguished.
- [ ] 4.20 Prevent an old/stale Driver GPS position from being treated as the Driver's current location.
- [ ] 4.21 Recover the latest valid Driver location after:
  - Temporary network loss.
  - Realtime disconnection.
  - App background/foreground transition.
  - App restart where supported.
- [ ] 4.22 Implement reconnection logic without producing duplicate or conflicting Driver location streams.
- [ ] 4.23 After ambiguous connection/reconnection states, re-fetch the canonical latest Driver location instead of relying only on missed Realtime events.

Checkpoint goal:

Create the reliable Driver-location foundation required by later Driver matching and live-trip tracking.

Approval gate:

- [ ] Driver location updates successfully.
- [ ] DriverLocation follows Service -> Repository -> Provider/Controller -> UI.
- [ ] Stale updates cannot overwrite newer valid locations.
- [ ] Duplicate tracking streams are prevented.
- [ ] Reconnection works.
- [ ] Latest canonical location can be recovered.
- [ ] App lifecycle transitions do not create conflicting subscriptions.
- [ ] No Driver matching logic is implemented in Phase 4.
- [ ] Relevant tests pass.

#### Checkpoint 4D Slice 1 — Contracts and adapters

Status: Completed and committed locally as `4694a5e` on 2026-09-17.

Implemented files:

- `lib/core/errors/driver_location_exception.dart`
- `lib/core/models/driver_availability.dart`
- `lib/core/models/driver_location.dart`
- `lib/core/providers/repositories_providers.dart`
- `lib/core/repositories/driver_location_repository.dart`
- `lib/core/repositories/mock_driver_location_repository.dart`
- `lib/core/services/driver_location/driver_location_service.dart`
- `lib/core/services/driver_location/supabase_driver_location_service.dart`
- `test/driver_location_repository_test.dart`

Slice 1 adds provider-neutral availability, timestamped sample, and saved-location
models; strict mapping and sanitized failures; canonical availability/latest-location
reads; RPC-only publishing through `driver_record_location`; and a deterministic
Mock implementation. It does not edit committed migrations.

Verification: `dart format` completed on all changed Dart files; `flutter test
test/driver_location_repository_test.dart` passed 6 tests; `flutter analyze`
reported no issues; `git diff --check` and staged `git diff --cached --check`
passed before the commit.

Limitations: no GPS stream, tracking controller, Driver Home UI, Realtime
subscription, matching, background behavior, lifecycle/reconnect recovery, or live
Supabase verification is included. The Checkpoint 4D items above remain incomplete
until the later slices provide those behaviors.

Slice 2A then added only the foreground GPS stream boundary and fake-driven
tests. Slice 2B next adds the Riverpod tracking controller with ordering,
lifecycle, reconnect, and canonical recovery tests. This split keeps each
OpenCode implementation prompt small.

#### Checkpoint 4D Slice 2A — Foreground GPS stream boundary

Status: Completed and committed locally as `3669a4d` on 2026-09-17.

Implemented files:

- `lib/core/models/driver_location.dart`
- `lib/core/services/driver_location/driver_gps_stream_service.dart`
- `lib/core/services/driver_location/geolocator_driver_gps_stream_service.dart`
- `test/driver_gps_stream_service_test.dart`

Slice 2A adds the provider-neutral `DriverLocationFix` containing the point,
device timestamp, and optional heading/speed values; a separate foreground GPS
stream interface; and a Geolocator adapter. Invalid coordinates are dropped,
invalid optional measurements are omitted, provider stream errors are sanitized,
and subscription cancellation reaches the provider stream. The existing
one-shot Rider location service is unchanged. No controller, UI, backend
publishing, Realtime, background permissions, or matching was added.

Verification: changed Dart files formatted; `flutter test
test/driver_gps_stream_service_test.dart` passed 4 tests; `flutter analyze`
reported no issues; `git diff --cached --check` passed before the commit.

#### Checkpoint 4D Slice 2B1 — Tracking controller foundation

Status: Completed and corrected in follow-up commit `49d7702` after the
original implementation commit `c3e85ee` on 2026-09-17.

Implemented files:

- `lib/core/providers/driver_tracking_providers.dart`
- `test/driver_tracking_controller_test.dart`

Slice 2B1 adds a Riverpod Driver tracking controller with explicit start/stop,
canonical availability and latest-location reads before stream ownership,
single foreground stream ownership, sequential publication, sequence values
greater than the saved maximum, and filtering for missing-accuracy or older
device-timestamp fixes. Only one publish is in flight; publish failures stop
tracking without blindly retrying a rejected sequence. The correction carries
the canonical active Trip ID into `onTrip` samples and invalidates unfinished
starts and queued work across Stop, disposal, and later sessions. No UI,
lifecycle, reconnection, Realtime, background tracking, or matching was added.

Verification: changed Dart files formatted; `flutter test
test/driver_tracking_controller_test.dart` passed 9 tests covering eligibility,
start/stop, `onTrip` publishing, pending-start invalidation, duplicate starts,
sequence ordering, invalid/stale fixes, publish failure, and queued-work
invalidation across restart; `flutter analyze` reported no issues;
`git diff --cached --check` passed before the correction commit.

#### Checkpoint 4D Slice 2B2A — Foreground lifecycle handling

Status: Completed and committed locally as `1a2bad3` on 2026-09-17.

Slice 2B2A adds a testable lifecycle boundary. Background entry cancels the
foreground GPS stream and invalidates pending tracking work while preserving
deliberate tracking intent. Foreground return resumes only requested tracking
after fresh canonical availability and latest-location reads. Explicit Stop and
sign-out clear the resume intent. Repeated resume events remain coalesced to one
stream. No network/realtime reconnection, UI, background location permission,
or matching was added.

Verification: changed Dart files formatted; `flutter test
test/driver_tracking_controller_test.dart` passed 13 tests; `flutter analyze`
reported no issues; `git diff --cached --check` passed before the commit.

Next step: Network and Realtime reconnect/recovery handling is next. Do not
start that step as part of Slice 2B2A.

#### Checkpoint 4D Slice 2B2 — Network recovery entry point

Status: Completed and committed locally as `7ddc3f3` on 2026-09-17.

Slice 2B2 adds the testable `recoverAfterConnectivity()` entry point. After a
publish or network failure it cancels the old stream while preserving deliberate
tracking intent, re-fetches canonical availability and latest saved location,
derives the next sequence from the canonical row, and opens exactly one new
foreground stream. Failed samples are never replayed. Repeated recovery calls
and recovery after Stop, sign-out, backgrounding, or disposal are ignored. No
connectivity package, Realtime subscription, UI, background tracking, or
matching was added.

Verification: changed Dart files formatted; `flutter test
test/driver_tracking_controller_test.dart` passed 16 tests; `flutter analyze`
reported no issues; `git diff --cached --check` passed before the commit.

Next step: Wire an actual network/reconnection signal to the recovery entry
point. Do not start that wiring as part of Slice 2B2.

#### Checkpoint 4D Reconnection signal wiring

Status: Completed and committed locally as `610835f` on 2026-09-17.

Added a disposable, testable connection-status boundary with a no-op Mock
implementation and a Supabase adapter. While Driver tracking is requested in
Supabase mode, the controller owns one lightweight Realtime channel. Initial
subscription is not treated as recovery; a disconnect/error followed by a
successful resubscription invokes `recoverAfterConnectivity()` once. The
channel is removed on Stop, sign-out, backgrounding, and disposal. The adapter
does not subscribe to `driver_locations` changes, and no dependency was added.

Verification: changed Dart files formatted; `flutter test
test/driver_tracking_controller_test.dart` passed 21 tests; `flutter analyze`
reported no issues; `git diff --cached --check` passed before the commit.

Review finding before Driver Home UI: an intentional channel close during Stop,
backgrounding, or disposal can set the controller's reconnect-pending flag.
The next normal subscription may then trigger an unnecessary recovery. Correct
the signal/session ownership race with focused tests before starting UI.

### Checkpoint 4E — GPS Effectiveness + Efficiency

- [ ] 4.24 Make GPS updates efficient:
  - Avoid unnecessary location requests.
  - Avoid unnecessary database/network writes.
  - Avoid unnecessary map rebuilds.
  - Avoid multiple simultaneous GPS subscriptions.
- [ ] 4.25 Configure location-update behavior according to RideX state so high-frequency tracking is used only when operationally necessary.
- [ ] 4.26 Stop unnecessary Driver location tracking when the Driver is in a state that does not require active tracking.
- [ ] 4.27 Ensure GPS tracking does not unnecessarily consume:
  - Battery.
  - Mobile data.
  - Backend resources.
- [ ] 4.28 Make location updates resilient to temporary GPS inaccuracies and prevent obviously stale/invalid updates from replacing a newer valid location.
- [ ] 4.29 Provide clear application states for:
  - Loading.
  - GPS unavailable.
  - Permission denied.
  - Location not found.
  - Route unavailable.
  - Network failure.
- [ ] 4.30 Never expose raw map-provider/GPS errors directly to the user.

Checkpoint goal:

Make RideX GPS effective, efficient, resilient, and suitable for continuous smart-mobility use.

Approval gate:

- [ ] No duplicate GPS subscriptions.
- [ ] Update frequency is controlled.
- [ ] Tracking stops when not required.
- [ ] Unnecessary network/database writes are minimized.
- [ ] Unnecessary map rebuilds are minimized.
- [ ] Stale/out-of-order location updates are handled.
- [ ] Temporary GPS/network failures do not break canonical state.
- [ ] User-facing errors are clear and safe.
- [ ] Relevant tests pass.

### Checkpoint 4F — Architecture + Smart City Readiness

- [ ] 4.31 Keep the map/GPS provider behind RideX service/repository contracts so UI and domain logic are not tightly coupled to a specific provider.
- [ ] 4.32 Keep API keys and map-service configuration out of source code and protect them according to existing RideX environment/config rules.
- [ ] 4.33 Ensure GPS integration supports RideX's Smart City objective of connecting Rider and Driver location information through digital mobility services.
- [ ] 4.34 Ensure routing supports RideX's objective of accurate local routing rather than relying only on generic coordinate distance.
- [ ] 4.35 Ensure GPS and routing outputs can later support:
  - Accurate ETA.
  - FareQuote/fare calculation.
  - Driver matching.
  - Live Driver tracking.
  - Trip navigation.

  These later-phase business rules are not implemented in Phase 4.

Checkpoint goal:

Ensure Phase 4 becomes reusable RideX infrastructure instead of provider-specific Flutter code.

Approval gate:

- [ ] UI is not unnecessarily coupled directly to provider APIs.
- [ ] Provider-specific models do not leak into domain contracts.
- [ ] API keys are not hardcoded.
- [ ] Configuration follows existing RideX environment rules.
- [ ] Routing architecture can support Phase 5.
- [ ] GPS architecture can support Phase 7.
- [ ] Route outputs can support later fare and ETA logic.
- [ ] Phase boundaries remain intact.

### Checkpoint 4G — Testing + Final Phase 4 Approval

- [ ] 4.36 Add unit tests for:
  - Location.
  - Geocoding.
  - Routing.
  - Stale-location handling.
  - Repositories.
  - Providers/controllers.
- [ ] 4.37 Add widget/integration tests for:
  - Permission states.
  - Current-location loading.
  - Place search.
  - Map selection.
  - Route rendering.
  - GPS failure.
  - Network failure.
  - Reconnection.
- [ ] 4.38 Test GPS behavior on at least two physical devices or equivalent Rider/Driver environments before approving Phase 4.
- [ ] 4.39 Verify temporary GPS/network failures do not corrupt:
  - BookingRequest.
  - Trip.
  - DriverLocation.
  - Canonical RideX state.
- [ ] 4.40 Complete the Phase 4 approval gate.

Final approval gate:

- [ ] Flutter formatting passes.
- [ ] Flutter analyze passes.
- [ ] Relevant unit tests pass.
- [ ] Relevant widget tests pass.
- [ ] Relevant integration tests pass where applicable.
- [ ] Existing regression tests pass.
- [ ] Rider GPS flow works.
- [ ] Driver GPS flow works.
- [ ] Place search works.
- [ ] Forward/reverse geocoding works.
- [ ] Route calculation works.
- [ ] Route geometry renders correctly.
- [ ] Distance works.
- [ ] Estimated duration works.
- [ ] Driver tracking works.
- [ ] Reconnection works.
- [ ] Latest-location recovery works.
- [ ] No known Phase 4 blocker remains.

Phase status:

- [ ] PHASE 4 APPROVED

Only after approval:

Phase 5 — Multi-Stop Booking and Fixed Fare may begin.

### OpenCode Execution Workflow

Every Phase 4 checkpoint must be implemented separately using this workflow:

1. **INSPECT**
   Read the existing RideX implementation and relevant architecture/docs.
2. **PLAN**
   Explain exactly what files/contracts/components require modification. Do not modify anything yet.
3. **SCOPE CHECK**
   Confirm the proposed work belongs only to the current Phase 4 checkpoint. Do not implement later-phase functionality.
4. **IMPLEMENT**
   Implement only the approved checkpoint.
5. **TEST**
   Add/update tests required by that checkpoint.
6. **VERIFY**
   Run:
   - Formatting.
   - Flutter analyze.
   - Relevant unit/widget/integration tests.
   - Existing regression tests.
7. **REVIEW**
   Review:
   - Architecture boundaries.
   - Security/configuration.
   - Application lifecycle.
   - Stale/concurrent state.
   - Error handling.
   - Resource efficiency.
8. **REPORT**
   Mark each checkpoint item:
   - `[x]` Completed.
   - `[ ]` Not completed.

   Explain exactly why any item remains incomplete.
9. **STOP**
   Do not automatically begin the next checkpoint. Wait for explicit approval before proceeding.

Phase 4 documentation constraints:

- Preserve existing completed Phase 1, Phase 2, and Phase 3 information.
- Do not falsely mark Phase 4 items as completed.
- Do not claim tests have passed unless they are actually executed later during implementation.
- Keep the Phase 4 acceptance scope explicit and measurable.
- Preserve the RideX architecture: Service -> Repository -> Provider/Controller -> UI.
- Do not move Phase 5, Phase 6, Phase 7, or Phase 8 functionality into Phase 4.
- Phase 4 prepares infrastructure for later phases but must not implement their business logic.

### Phase 5: Multi-Stop and Fixed Fare

- [ ] Implement ordered multi-stop booking with a maximum of three intermediate stops.
- [ ] Implement route distance, duration, persistent Fare Quotes, and route-based fixed fares.

### Phase 6: Payment Foundations

- [ ] Implement persistent Cash payment foundations.
- [ ] Implement provider-independent Card payment contracts.
- [ ] Implement Stripe Test Mode PaymentIntent and secure UI foundations.

### Phase 7: Matching and Realtime

- [ ] Implement Driver availability.
- [ ] Implement nearby Driver matching and atomic assignment.
- [ ] Implement Supabase Realtime Rider-Driver Trip and location synchronization.

### Phase 8: Payment Completion and History

- [ ] Complete Card Authorization, Capture, cancellation, Refund, webhook verification, receipts, and payment history.
- [ ] Complete persistent Trip history and active Trip restoration.

### Phase 9: Secondary and Admin Workflows

- [ ] Complete persistent profiles, notifications, ratings, and help requests.
- [ ] Complete basic Admin Driver approval, Trip visibility, and sanitized payment visibility.

### Phase 10: Verification and Release

- [ ] Run Flutter, database, payment, and security verification.
- [ ] Run Rider and Driver two-device end-to-end testing.
- [ ] Run responsive, accessibility, platform, and release verification.

## Review Checklist

Use this checklist when asking for a review or before starting implementation:

- [x] The problem and desired outcome are clear.
- [x] Acceptance criteria are observable and testable.
- [x] Current behavior was verified in code and tests.
- [x] Security, privacy, data migration, and failure cases were considered.
- [x] The change follows existing architecture and avoids unrelated refactoring.
- [x] Required unit, widget, integration, and manual tests are identified.
- [ ] Static analysis and relevant tests pass after each future implementation phase.
- [x] Documentation and this plan reflect the final behavior.

## Discussion Notes

Add concise notes here while discussing the active goal. Convert final conclusions into the Decisions and Planned Work sections.

- 2026-07-22: Created the local living-plan workflow.
- 2026-07-22: Audited Supabase environment loading, Mock mode selection, startup behavior, ignore rules, documentation, and safe test boundaries. The existing `.gitignore` environment and signing rules are pre-existing work and will be preserved unchanged.
- 2026-07-22: Implemented centralized, offline Supabase configuration validation. HTTPS custom domains and plausible Publishable or legacy anon key formats remain supported; recognized secret or service-role credentials are rejected. The focused test initially exposed a synthetic JWT fixture defect, which was corrected before all eight cases passed.
- 2026-07-22: Added bootstrap failure containment and a minimal RideX startup error app. Normal users receive fixed non-technical text, while debug diagnostics contain only a fixed failure category. The isolated widget test passed without backend access.
- 2026-07-22: Replaced the starter README with compile-time Supabase setup, intentional Mock mode, and client-key safety guidance. Added missing Apple signing-file patterns to the existing uncommitted `.gitignore` hardening; no runtime `.env` loader or example file was introduced.
- 2026-07-22: Final review tightened legacy JWT validation to require the anonymous role and rejected unknown `sb_` key families. All 11 selected local tests passed. Formatting completed on task-owned Dart files. `flutter analyze` completed with two pre-existing role-selection deprecation infos and no task-file findings.
- 2026-07-22: Case 2 audit found that missing Supabase values selected Mock Auth/Profile in Release and that UI mode decisions bypassed test-overridable providers. Agreed to require explicit backend mode in all app runs, keep Booking/Trips mocked temporarily, and fail closed in Release.
- 2026-07-22: Implemented centralized backend-mode resolution, bootstrap injection, repository and UI mode alignment, safe test overrides, and removal of hardcoded demo credentials/profile values. All local tests passed, focused backend tests passed after final cleanup, formatting completed, and `flutter analyze` reported no issues.
- 2026-07-29: Completed a read-only Graduation MVP audit against Project 1, project-status documentation, actual Git state, dependencies, models, repositories, providers, migrations, payment UI, maps, Trip flows, and tests.
- 2026-07-29: Confirmed that Rider UI V2 is merged and remains accepted within its original UI-focused scope. Real maps, persistence, matching, Realtime, and payment integrations are later Graduation MVP milestones.
- 2026-07-29: Approved Supabase as the permanent Firebase replacement and approved Cash plus Stripe Test Mode Card payments for the graduation demonstration.
- 2026-07-29: Approved provider-independent payment boundaries, manual Card capture, backend-only secrets, webhook verification, Cash settlement on Trip completion, duplicate prevention, explicit ownership, included/deferred scope, and the ten-phase implementation roadmap.
- 2026-08-02: Reviewed the completed Phase 3 repository implementation against the Phase 2 contract, detailed Phase 3 plan/status, migrations `005`-`013`, SQL tests, database objects, lifecycle rules, and security boundaries. The implementation and reported 628-test pass were confirmed as present, but contract, security, and test-evidence blockers prevent approval. Phase 4 has not started.
- 2026-09-14: Final Checkpoint 4A/4B audit confirmed commits `d65a58a`, `2359a81`, and `41dd2f5`; reran 23 focused 4A Flutter cases, 25 focused 4B Flutter cases, analysis, and the full 124-pass/2-skip Flutter suite in a detached temporary worktree; and confirmed the hosted `places` function is active with the required secret name. Neither checkpoint is approved because physical/live evidence is absent, Deno tests were not rerun, and 4B still permits the old committed endpoint during unresolved prediction-details or forward-geocode replacement.
- 2026-09-14: The project owner reported that Omar completed every remaining 4A/4B physical, live-service, and configuration test successfully. The 4B prediction-details/forward-geocode replacement guard was then implemented locally with eight new regression cases; all 33 focused 4B Flutter cases, analysis, and the full 132-pass/2-skip suite passed. Checkpoints 4A and 4B are approved; Phase 4 remains in progress because 4C through 4G are incomplete.

## Change Log

| Date | Change | Verification | Result |
| --- | --- | --- | --- |
| 2026-07-22 | Initialized the RideX living development plan. | Reviewed repository structure, routes, repositories, dependencies, and tests. | Completed |
| 2026-07-22 | Supabase environment hardening completed: centralized validation, safe startup failure handling, secure ignore additions, documentation, and local regression coverage. | All 11 selected mock/local tests passed. Task-owned Dart files were formatted. `flutter analyze` completed with 2 pre-existing deprecation infos outside this scope and no task-file findings. No migration or remote operation was performed. | Completed with pre-existing analyzer notices |
| 2026-07-22 | Secured backend mode selection with explicit Development Mock, Development Supabase, and Production Supabase policies; aligned bootstrap, repositories, UI, tests, and documentation. | Full local suite passed with 30 tests and 2 live tests skipped; 12 focused backend tests passed after final cleanup; `flutter analyze` reported no issues; formatting and `git diff --check` completed. | Completed |
| 2026-07-29 | Approved and documented the Graduation MVP scope, ownership, provider-independent payment architecture, Stripe Test Mode lifecycle, Cash settlement rules, security boundaries, deferred features, and dependency-safe roadmap. | Read-only audit and stakeholder approval. No Flutter code, migrations, dependencies, tests, configuration, credentials, branches, or remote operations were changed. | Approved for documentation |
| 2026-08-02 | Reviewed the Phase 3 Supabase implementation and recorded verified scope, blockers, and exact remediation actions. | Static inspection of Phase 3 plans/status, migrations `005`-`013`, all matching pgTAP files, constraints, indexes, functions, RPCs, triggers, grants, and RLS. Existing 628-test result is documented and count-consistent but was not independently rerun under the safe-local-check restriction. | Review blocked - not approved |
| 2026-09-14 | Performed final repository verification for Checkpoints 4A and 4B and reconciled their documentation. | At `41dd2f5`: 23 focused 4A Flutter cases passed; 25 focused 4B Flutter cases passed; `flutter analyze` found no issues; full `flutter test` passed 124 tests with 2 intentional skips and known non-failing SVG warnings. Read-only Supabase CLI metadata confirmed active `places` function version 1 and the required secret name. Deno, physical Android, live Google API, credential-restriction, and authenticated end-to-end evidence remain incomplete; static audit found the unresolved prediction/forward-geocode replacement guard. | Implemented but not approved |
| 2026-09-14 | Closed the final 4B replacement-selection routing guard and approved Checkpoints 4A/4B using local automation plus project-owner-reported Omar verification. | Eight new replacement regression cases passed; all 33 focused 4B Flutter cases passed; `flutter analyze` found no issues; full `flutter test` passed 132 tests with 2 intentional skips and known non-failing SVG warnings. The project owner reported every remaining physical/live/configuration requirement passed. Deno was not available for independent local rerun. | Checkpoints 4A and 4B approved; Phase 4 remains in progress |
