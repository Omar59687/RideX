# Phase 2 — Domain Architecture and Shared Contracts

Status: Approved — documentation complete; implementation not started

Lead: Yousuf

Reviewers: Yousuf and Omar

Implementation status: Documentation only; no functionality implemented

## 1. Purpose and Scope

This document defines the shared domain architecture required to replace RideX Mock and session-local behavior with persistent, authorized, and provider-independent functionality.

Rider UI V2 remains accepted as complete within its original UI-focused scope. Its illustrative map, deterministic fares, local Trip transitions, Mock history, Cash labels, and disabled Card behavior were intentional limitations of that milestone. They are not retroactive Rider UI V2 defects.

The next objective is to connect the existing Rider, Driver, and Admin screens to real behavior while preserving:

- Riverpod state ownership.
- GoRouter navigation and session guards.
- Supabase authentication and profiles.
- Existing repository boundaries.
- Existing screen structure and visual design.
- Provider-independent domain contracts.
- Explicit development and testing Mock modes.

This phase defines contracts only. It does not create Dart models, repositories, providers, Supabase migrations, Edge Functions, dependencies, tests, or configuration.

The architecture and final MVP decisions in this document are approved. Implementation starts only after a separate explicit instruction.

Later phases depend on this document:

- Phase 3: database tables, constraints, indexes, RPCs, and RLS.
- Phase 4: maps, GPS, place search, and routing.
- Phase 5: multi-stop booking and route-based fixed fares.
- Phase 6: Cash and Stripe Test Mode foundations.
- Phase 7: Driver availability, matching, and Realtime.
- Phase 8: Card authorization, Capture, cancellation, Refund, receipts, and history.
- Phase 9: profiles, notifications, ratings, help, and Admin workflows.
- Phase 10: end-to-end and release verification.

Git and actual project files are the source of truth when older documentation disagrees.

## 2. Architecture Principles

1. Flutter UI depends on provider-independent repository contracts.
2. Flutter may request operations and display canonical results, but it never makes trusted database, fare, matching, Trip-transition, payment, or Refund decisions.
3. Supabase is the permanent backend platform.
4. Trusted operations use database functions, RPCs, Edge Functions, or another explicitly approved backend boundary.
5. RLS protects every client-accessible persistent record.
6. Financial operations are server-authoritative.
7. Realtime subscriptions do not bypass RLS, participant authorization, or canonical state validation.
8. The existing Service → Repository → Provider/Controller → UI architecture remains in place.
9. Supabase- and Stripe-specific details stay behind concrete services or provider adapters.
10. Mock implementations remain available only in explicit development or testing modes.
11. Domain models and repository contracts do not depend on Flutter widgets, Riverpod, Supabase types, or Stripe types.
12. Persisted monetary amounts use integer minor units, never floating-point values.
13. Every amount includes an ISO 4217 currency code.
14. JOD uses three minor-unit decimal places.
15. All authoritative timestamps use backend UTC time.
16. Persisted aggregate records use backend-generated UUIDs unless they intentionally share a Supabase Auth user ID.
17. Trusted transitions validate previous state, actor, ownership, and aggregate version.
18. Repeated commands use idempotency keys or expected versions.
19. Historical Fare Quotes, Trip events, Payment Attempts, Refunds, and Receipts are retained rather than rewritten.
20. Client callbacks, redirects, and Realtime messages are state hints. Clients re-fetch canonical state after reconnects, version gaps, or ambiguous outcomes.
21. In-progress TripChangeRequest and FareAdjustment are Graduation MVP features for Cash Trips only.
22. Card Trips have one active authorized fare and one trusted Capture.
23. Card destination, stop, route, and fare changes after `inProgress` are deferred.
24. The Driver can never edit fares or add charges.
25. Card authorization is limited to two attempts in total for a Trip, including an initial or replacement authorization.
26. Card Capture permits the original attempt plus at most two retries.
27. Card Refund remains `refundPending` after a failed attempt and permits the original attempt plus at most two retries.
28. Booking and Trip command idempotency keys are retained for seven days.
29. Payment references are retained for the lifetime of the Payment.
30. Processed webhook event IDs are retained for 90 days.
31. Raw webhook payloads, when operationally required, are encrypted, server-only, stripped of prohibited card data, and retained for no more than 30 days.

## 3. Approved Domain Models

### Shared Conventions

- `...Id` values are opaque UUIDs.
- Fields ending in `Minor` are integer minor-unit monetary values.
- Distances use integer meters.
- Durations use integer seconds.
- Timestamps use UTC.
- `version` is an integer optimistic-concurrency token.
- Safe client-visible fields may be displayed or proposed through authorized commands. They are not automatically authoritative.
- Trusted backend-only fields are written only through approved backend operations.
- Mutable aggregates include `createdAt`, `updatedAt`, and `version`.
- Append-only records are not updated through ordinary client operations.

### 3.1 UserProfile

Purpose:

Canonical RideX identity connected one-to-one with a Supabase Auth user.

Required fields:

- `id`
- `role`
- `displayName`
- `email`
- `isBlocked`
- `createdAt`
- `updatedAt`
- `version`

Optional fields:

- `photoUrl`

Identifier strategy:

`id` is the Supabase Auth user UUID.

Ownership:

The user owns safe presentation fields. Supabase Auth owns email identity. Trusted Admin operations own role and blocked state.

Relationships:

- Zero or one RiderProfile.
- Zero or one DriverProfile.
- Referenced by all user-owned records.

Immutable fields:

- `id`
- `createdAt`

Mutable fields:

- `displayName`
- `photoUrl`
- Email through authenticated email-change flow
- Role through trusted role operations
- Blocked state through authorized Admin operations

Validation:

- Nonblank bounded display name.
- Valid normalized email.
- HTTPS or approved Supabase Storage photo URL.
- Role and profile subtype remain consistent.

Safe client-visible fields:

ID, role, display name, photo URL, own email, and own blocked state.

Trusted backend-only fields:

Role mutation, blocked-state mutation, email synchronization, timestamps, and version.

Audit requirements:

Role, blocked-state, and email changes preserve actor, reason, timestamp, and previous/new values.

### 3.2 RiderProfile

Purpose:

Rider-specific extension without duplicating canonical identity.

Required fields:

- `userId`
- `createdAt`
- `updatedAt`
- `version`

Optional fields:

None required for the current MVP contract.

Identifier strategy:

`userId` is the primary identifier and UserProfile foreign key.

Ownership:

The Rider owns the profile. Authorized Admin/support operations receive only a restricted view.

Relationships:

- Exactly one UserProfile with Rider role.
- Related BookingRequests, Trips, Ratings, Notifications, and HelpRequests.

Immutable fields:

- `userId`
- `createdAt`

Mutable fields:

Only future explicitly approved Rider attributes.

Validation:

The UserProfile must exist and have Rider role.

Safe client-visible fields:

All current fields.

Trusted backend-only fields:

Creation, role-driven deletion, timestamps, and version.

Audit requirements:

Profile creation, role conversion, and future profile changes are auditable.

### 3.3 DriverProfile

Purpose:

Driver-specific identity and approval state, separate from operational availability.

Required fields:

- `userId`
- `approvalStatus`
- `createdAt`
- `updatedAt`
- `version`

Optional fields:

- `rejectionReason`
- `ratingAverage`
- `ratingCount`

Identifier strategy:

`userId` is the shared primary key and UserProfile foreign key.

Ownership:

The Driver owns submitted information. Authorized Admin operations own approval decisions.

Relationships:

- Exactly one Driver UserProfile.
- Zero or more Vehicles.
- One DriverAvailability.
- Referenced by assigned Trips, DriverLocations, and Ratings.

Immutable fields:

- `userId`
- `createdAt`

Mutable fields:

- Approval through Admin operations.
- Rejection reason through Admin operations.
- Aggregate rating through trusted rating processing.

Validation:

- User role must be Driver.
- Rejected requires a bounded nonblank reason.
- Non-rejected states clear stale rejection reasons.
- Only approved, unblocked Drivers become available.

Safe client-visible fields:

Approval status, subject-visible rejection reason, public profile, and public rating summary.

Trusted backend-only fields:

Approval mutation, aggregate rating calculation, timestamps, and version.

Audit requirements:

Every approval transition records Admin actor, previous/new state, reason, and timestamp.

### 3.4 Vehicle

Purpose:

Physical vehicle owned by a Driver and snapshotted into assigned Trips.

Required fields:

- `id`
- `driverId`
- `vehicleTypeCode`
- `make`
- `model`
- `color`
- `registrationPlate`
- `seatCapacity`
- `isActive`
- `createdAt`
- `updatedAt`
- `version`

Optional fields:

- `modelYear`
- `photoUrl`

Identifier strategy:

Backend-generated UUID. Registration plate is a normalized business key.

Ownership:

The Driver owns the vehicle. Admin may review it through approved Driver workflows.

Relationships:

- Belongs to one DriverProfile.
- Used by DriverAvailability.
- Snapshotted into Trips and Receipts.

Immutable fields:

- `id`
- `driverId`
- `createdAt`

Mutable fields:

Vehicle description, validated plate, active state, and photo.

Validation:

- Recognized vehicle type.
- Positive seat capacity.
- Normalized nonblank registration plate.
- Approved plate uniqueness policy.
- Vehicle belongs to authenticated Driver.
- Vehicle cannot change during an active Trip.

Safe client-visible fields:

Vehicle presentation and Driver-editable attributes.

Trusted backend-only fields:

Eligibility decisions, normalized uniqueness keys, timestamps, and version.

Audit requirements:

Ownership, plate, type, and active-state changes are recorded.

### 3.5 DriverAvailability

Purpose:

Canonical matching eligibility separate from approval and location.

Approved states:

- `offline`
- `available`
- `reserved`
- `onTrip`

Required fields:

- `driverId`
- `state`
- `updatedAt`
- `version`

Optional fields:

- `vehicleId`
- `reservedBookingRequestId`
- `activeTripId`
- `lastHeartbeatAt`

Identifier strategy:

One record per Driver using `driverId`.

Ownership:

Driver requests online/offline changes. Matching and Trip services own reservation and onTrip states.

Relationships:

DriverProfile, Vehicle, BookingRequest, and Trip.

Immutable fields:

- `driverId`

Mutable fields:

State and references through trusted version-checked operations.

Validation:

- Driver approved and unblocked.
- Available requires eligible active Vehicle and fresh heartbeat.
- Reserved requires one BookingRequest.
- OnTrip requires one Trip.
- No simultaneous reservations or Trips.

Safe client-visible fields:

Own availability, active Vehicle, and heartbeat summary.

Trusted backend-only fields:

Reservation, onTrip transition, eligibility, and version.

Audit requirements:

State transitions include source, actor, timestamp, and related BookingRequest or Trip. While available or reserved, the Driver publishes a location heartbeat every 20 seconds.

### 3.6 LocationPoint

Purpose:

Provider-independent geographical value.

Required fields:

- `latitude`
- `longitude`

Optional fields:

- `accuracyMeters`
- `formattedAddress`
- `label`
- `providerName`
- `providerPlaceReference`

Identifier strategy:

Immutable value object with no separate UUID.

Ownership:

Owned by its containing aggregate.

Relationships:

PlaceSelection, BookingRequest, BookingStop, FareQuote, Trip, and DriverLocation.

Immutable fields:

All fields once attached to locked or historical data.

Mutable fields:

Draft may replace the entire point before confirmation.

Validation:

- Latitude between -90 and 90.
- Longitude between -180 and 180.
- Finite values.
- Nonnegative accuracy.
- Bounded labels and addresses.

Safe client-visible fields:

Display and coordinate fields where participant authorization allows.

Trusted backend-only fields:

Canonical resolution, service-area result, and route snapping.

Audit requirements:

Historical snapshots are preserved; raw coordinates are excluded from ordinary logs.

### 3.7 PlaceSelection

Purpose:

Rider-facing search, map, GPS, saved, or recent place selection.

Required fields:

- `point`
- `source`
- `selectedAt`

Optional fields:

- `displayName`
- `formattedAddress`
- `providerName`
- `providerPlaceReference`

Identifier strategy:

Transient value object. Provider reference is external.

Ownership:

Selecting Rider.

Relationships:

Converts to pickup, destination, or BookingStop.

Immutable fields:

Each selection instance is immutable.

Mutable fields:

Draft may replace it.

Validation:

- Valid LocationPoint.
- Supported source.
- Provider reference where required.
- Point within service area.

Safe client-visible fields:

All fields.

Trusted backend-only fields:

Resolution verification and service-area acceptance.

Audit requirements:

Abandoned searches are not persisted. Confirmed snapshots are retained.

### 3.8 BookingRequest

Purpose:

Persistent request controlling confirmation, FareQuote locking, searching, matching, cancellation, expiration, and failure.

Required fields:

- `id`
- `riderId`
- `status`
- `pickup`
- `destination`
- `vehicleTypeCode`
- `paymentMethod`
- `fareQuoteId`
- `createdAt`
- `updatedAt`
- `version`

Optional fields:

- `confirmedAt`
- `searchingAt`
- `matchedAt`
- `cancelledAt`
- `expiredAt`
- `failedAt`
- `cancellationReasonCode`
- `failureReasonCode`
- `matchedDriverId`
- `matchedVehicleId`

Identifier strategy:

Backend-generated UUID. Confirmation uses an idempotency key.

Ownership:

Rider owns draft and confirmation. Matching service owns search and assignment results.

Relationships:

- One Rider.
- Zero to three BookingStops.
- One current FareQuote.
- Zero or one Trip.
- One canonical Payment.

Immutable after confirmation:

- ID and Rider.
- Pickup, destination, ordered stops.
- Vehicle type and payment method.
- Locked FareQuote reference, except an approved pre-start Card re-quote workflow.

Mutable fields:

Draft fields before confirmation and trusted lifecycle fields afterward.

Validation:

- Valid pickup/destination.
- Maximum three stops.
- Contiguous stop order.
- Recognized vehicle type.
- Cash or Card method.
- Matching requires locked FareQuote.
- Rider authenticated and unblocked.
- Valid state transition.

Safe client-visible fields:

Booking presentation, method, state, and safe reasons.

Trusted backend-only fields:

Canonical state, match result, lifecycle timestamps, and version.

Audit requirements:

Confirmation, cancellation, expiration, failure, matching, and pre-start requote are recorded.

### 3.9 BookingStop

Purpose:

Persist one intermediate stop and route order.

Required fields:

- `id`
- `bookingRequestId`
- `sequence`
- `location`
- `createdAt`

Optional fields:

- `label`
- `riderNote`

Identifier strategy:

Backend-generated UUID with unique `(bookingRequestId, sequence)`.

Ownership:

Parent BookingRequest Rider.

Relationships:

BookingRequest, FareQuote, and Trip snapshots.

Immutable after confirmation:

ID, parent, sequence, location, and created timestamp.

Mutable fields:

Draft stops before confirmation.

Validation:

- Contiguous sequence.
- Maximum three.
- No duplicate stop IDs.
- Route remains valid.

Safe client-visible fields:

All fields.

Trusted backend-only fields:

Confirmed ordering and route validation.

Audit requirements:

Submitted order remains historical. In-progress changes use TripChangeRequest only for Cash.

### 3.10 FareQuote

Purpose:

Trusted versioned fixed-fare offer and sole original payment authority.

Required fields:

- `id`
- `bookingRequestId`
- `riderId`
- `status`
- `pickup`
- `destination`
- `orderedStops`
- `routeDistanceMeters`
- `routeDurationSeconds`
- `vehicleTypeCode`
- `breakdown`
- `currency`
- `fixedFareMinor`
- `pricingVersion`
- `quoteVersion`
- `createdAt`
- `expiresAt`

Optional fields:

- `routeGeometryReference`
- `lockedAt`
- `supersededAt`
- `supersedesFareQuoteId`

Identifier strategy:

Backend UUID with unique `(bookingRequestId, quoteVersion)`.

Ownership:

Trusted Fare service. Rider requests calculation and locking.

Relationships:

BookingRequest, Trip, Payment, FareAdjustment, and Receipt.

Immutable fields:

All route, stop, vehicle, amount, currency, and version values.

Mutable fields:

Status and status timestamps only.

Validation:

- Integer minor units.
- Supported currency.
- Breakdown reconciles.
- At most three stops.
- Monotonic version.
- Calculated quote expires ten minutes after creation.
- Lock verifies current route and vehicle.
- One active locked quote.

Safe client-visible fields:

All display fields and status.

Trusted backend-only fields:

Amounts, route metrics, pricing version, canonical state, and timestamps.

Audit requirements:

Every version retained. No in-place edits.

### 3.11 FareBreakdown

Purpose:

Immutable explanation of FareQuote.

Required fields:

- `baseFareMinor`
- `distanceChargeMinor`
- `durationChargeMinor`
- `intermediateStopChargeMinor`
- `subtotalMinor`
- `roundingMinor`
- `fixedFareMinor`
- `currency`

Optional fields:

- `minimumFareAdjustmentMinor`

Identifier strategy:

Value object within FareQuote.

Ownership:

Trusted Fare service.

Relationships:

FareQuote and Receipt.

Immutable fields:

All fields.

Mutable fields:

None.

Validation:

- Integer minor units.
- Matching currency.
- Exact arithmetic.
- No rewards/promotions.
- Deterministic server rounding.

Safe client-visible fields:

Read-only breakdown.

Trusted backend-only fields:

All calculations.

Audit requirements:

Retained with quote and pricing version.

### 3.12 FareAdjustment

Purpose:

Trusted Cash-only Graduation MVP financial result of an in-progress TripChangeRequest.

Required fields:

- `id`
- `tripChangeRequestId`
- `tripId`
- `originalFareQuoteId`
- `requestingRiderId`
- `originalDestination`
- `originalOrderedStops`
- `requestedDestination`
- `requestedOrderedStops`
- `originalRemainingDistanceMeters`
- `originalRemainingDurationSeconds`
- `newRemainingDistanceMeters`
- `newRemainingDurationSeconds`
- `originalRemainingRoutePriceMinor`
- `newRemainingRoutePriceMinor`
- `additionalAmountMinor`
- `originalFixedFareMinor`
- `newFinalFareMinor`
- `currency`
- `reasonCode`
- `status`
- `createdAt`

Optional fields:

- `riderApprovedAt`
- `appliedAt`
- `relatedPaymentAttemptId` reserved for future Card support

Identifier strategy:

Backend UUID. One canonical FareAdjustment per TripChangeRequest.

Ownership:

Trusted Fare service. Rider approves the related request.

Relationships:

Cash Trip, TripChangeRequest, original FareQuote, and future optional PaymentAttempt.

Immutable fields:

Every calculation input and amount.

Mutable fields:

No independent canonical status. `status` reflects the related TripChangeRequestStatus.

Validation:

- Trip payment method is Cash for Graduation MVP application.
- Trip is inProgress.
- Currency matches original FareQuote and Payment.
- Additional amount is the remaining-route difference.
- Additional amount is nonnegative.
- Stops do not exceed three.
- Completed route is not charged again.
- New final fare reconciles.
- Client cannot set distances, durations, or amounts.

Safe client-visible fields:

Route comparison, additional amount, new total, status, and timestamps.

Trusted backend-only fields:

Route metrics, prices, calculation version, and status projection.

Audit requirements:

Original/requested route, pricing inputs, Rider approval, and application are retained.

### 3.13 TripChangeRequest

Purpose:

Cash Trip Rider request to change destination or intermediate stops while inProgress.

Required fields:

- `id`
- `tripId`
- `requestingRiderId`
- `status`
- `requestedDestination`
- `requestedOrderedStops`
- `createdAt`
- `updatedAt`
- `version`

Optional fields:

- `fareAdjustmentId`
- `failureReasonCode`
- `rejectedReasonCode`
- `riderApprovedAt`
- `appliedAt`
- `cancelledAt`

Identifier strategy:

Backend UUID.

Ownership:

Only the Trip Rider creates and approves it.

Relationships:

Cash Trip and FareAdjustment.

Immutable fields:

Trip, requester, proposed route, and creation time.

Mutable fields:

Canonical status and lifecycle timestamps.

Validation:

- Trip method is Cash.
- Trip is inProgress.
- Requester is Trip Rider.
- Maximum three intermediate stops.
- One unresolved request per Trip.
- Approved change requires trusted FareAdjustment.
- Card Trip request is rejected as unsupported for MVP.

Safe client-visible fields:

Requested route, price difference, new total, status, and safe failure reason.

Trusted backend-only fields:

Pricing and application decisions.

Audit requirements:

Every transition and Rider decision is recorded.

### 3.14 Trip

Purpose:

Canonical operational ride created after one Driver wins assignment.

Required fields:

- `id`
- `bookingRequestId`
- `riderId`
- `driverId`
- `vehicleId`
- `fareQuoteId`
- `paymentId`
- `status`
- `pickup`
- `destination`
- `orderedStops`
- `originalFixedFareMinor`
- `approvedAdjustmentsMinor`
- `finalFareMinor`
- `currency`
- `createdAt`
- `updatedAt`
- `version`

Optional fields:

- `acceptedAt`
- `driverArrivingAt`
- `driverArrivedAt`
- `startedAt`
- `completedAt`
- `cancelledAt`
- `cancelledByUserId`
- `cancellationReasonCode`
- `failedAt`
- `failureReasonCode`

Identifier strategy:

Backend UUID with unique BookingRequest relationship.

Ownership:

Shared by Rider and assigned Driver. Trusted Trip service owns state.

Relationships:

BookingRequest, Rider, Driver, Vehicle, FareQuote, Payment, events, locations, Cash adjustments, Receipt, Ratings, Notifications, and HelpRequests.

Immutable fields:

- IDs and participants.
- Original assigned Vehicle snapshot.
- Created time.
- For Card, route, stops, destination, FareQuote, and fare become immutable at `inProgress`.
- For Cash, original FareQuote remains immutable while current route/final fare may change through applied adjustments.

Mutable fields:

- Canonical status and timestamps.
- Pre-start FareQuote replacement through an approved backend workflow.
- Cash current route and final fare through applied FareAdjustment.

Validation:

- Booking matched.
- Driver approved and reserved.
- Only assigned Driver progresses.
- Card cannot progress until authorized.
- Card has no in-progress route/fare mutation.
- Final Cash fare equals original plus applied adjustments.
- Terminal states cannot reopen.

Safe client-visible fields:

Participant-authorized Trip state, route, fare, and timestamps.

Trusted backend-only fields:

Assignment, state, FareQuote replacement, adjustment totals, cancellation attribution, and version.

Audit requirements:

Every transition and authorized route/fare replacement is recorded.

### 3.15 TripStatusEvent

Purpose:

Append-only evidence of Trip transitions.

Required fields:

- `id`
- `tripId`
- `fromStatus`
- `toStatus`
- `actorType`
- `sequence`
- `occurredAt`

Optional fields:

- `actorUserId`
- `reasonCode`
- `sanitizedNote`
- `idempotencyKey`

Identifier strategy:

Backend UUID with unique `(tripId, sequence)`.

Ownership:

Trusted Trip service.

Relationships:

Trip and optional user actor.

Immutable fields:

All fields.

Mutable fields:

None.

Validation:

Allowed transition, matching previous state, authorized actor, monotonic sequence, required reason.

Safe client-visible fields:

Participant-safe timeline.

Trusted backend-only fields:

Canonical attribution and idempotency data.

Audit requirements:

Append-only lifecycle audit.

### 3.16 DriverLocation

Purpose:

Timestamped Driver telemetry for matching and active tracking.

Required fields:

- `id`
- `driverId`
- `point`
- `recordedAt`
- `receivedAt`
- `sequence`

Optional fields:

- `tripId`
- `accuracyMeters`
- `headingDegrees`
- `speedMetersPerSecond`

Identifier strategy:

Backend UUID. Latest projection may use Driver ID.

Ownership:

Driver produces; location service accepts and authorizes.

Relationships:

Driver and optional active Trip.

Immutable fields:

All samples.

Mutable fields:

None.

Validation:

Valid point, monotonic sequence, plausible timestamp, valid heading/speed/accuracy, eligible Driver, authorized visibility, and the approved publishing interval. Driver location updates every 5 seconds during a Trip and every 20 seconds while available or reserved.

Safe client-visible fields:

Latest authorized point and movement data.

Trusted backend-only fields:

Receipt time, Trip binding, retention, and disclosure.

Audit requirements:

Precise Driver location samples are retained for seven days and then removed or irreversibly aggregated according to the approved retention process. Location data is excluded from ordinary application logs.

### 3.17 Payment

Purpose:

Canonical provider-independent business payment.

Required fields:

- `id`
- `bookingRequestId`
- `riderId`
- `method`
- `fareQuoteId`
- `authorizedAmountMinor`
- `finalAmountMinor`
- `currency`
- `createdAt`
- `updatedAt`
- `version`

Optional fields:

- `tripId`
- `cashStatus`
- `cardStatus`
- `providerName`
- `cardBrand`
- `cardLastFour`
- `authorizedAt`
- `paidAt`
- `cancelledAt`
- `refundedAt`
- `sanitizedFailureCode`

Identifier strategy:

Backend UUID. One canonical Payment per booking/Trip attempt.

Ownership:

Rider is payer. Trusted Payment service owns state.

Relationships:

BookingRequest, optional Trip until matching, FareQuote, Attempts, Refund, and Receipt.

Immutable fields:

- ID, BookingRequest, Rider, method, currency, created time.
- FareQuote and amount become immutable at Trip start.
- Cash original amount remains immutable while final amount may increase through applied Cash adjustments.

Mutable fields:

- Trip reference assigned once.
- Pre-start Card FareQuote and amount replacement after old authorization release.
- Cash final amount through applied adjustment.
- Compatible canonical status.
- Safe provider summary and timestamps.

Validation:

- Cash requires cashStatus and no cardStatus.
- Card requires cardStatus and no cashStatus.
- Amount matches active FareQuote.
- Card has one active authorization amount.
- Card Capture uses that single amount.
- Cash paid only at trusted completion.
- Card fields cannot change after inProgress.

Safe client-visible fields:

Method, canonical status, amount, currency, brand, last four, safe failures, timestamps.

Trusted backend-only fields:

Amounts, provider references, canonical transitions, verification, and idempotency data.

Audit requirements:

Every status and active FareQuote/amount replacement references PaymentAttempts and retains prior history.

### 3.18 PaymentAttempt

Purpose:

Auditable financial/provider operation.

Required fields:

- `id`
- `paymentId`
- `type`
- `status`
- `requestedAmountMinor`
- `currency`
- `idempotencyKey`
- `createdAt`

Optional fields:

- `providerName`
- `providerTransactionReference`
- `fareAdjustmentId` reserved for future Card adjustment support
- `sanitizedFailureCode`
- `sanitizedFailureMessage`
- `completedAt`

Identifier strategy:

Backend UUID, unique idempotency scope, unique provider reference.

Ownership:

Trusted Payment service.

Relationships:

Payment and future optional FareAdjustment.

Immutable fields:

Payment, type, amount, currency, key, and creation time.

Mutable fields:

Attempt status and sanitized result.

Validation:

Operation valid for current Trip/Payment; amount trusted; one active equivalent operation; provider result verified.

Safe client-visible fields:

Safe operation status and failure category.

Trusted backend-only fields:

Provider reference, communication, raw diagnostics, and result.

Audit requirements:

All attempts retained.

### 3.19 Refund

Purpose:

Canonical full Card Refund.

Required fields:

- `id`
- `paymentId`
- `amountMinor`
- `currency`
- `status`
- `reasonCode`
- `createdAt`
- `updatedAt`
- `version`

Optional fields:

- `requestedByAdminId`
- `providerName`
- `providerRefundReference`
- `sanitizedFailureCode`
- `completedAt`

Identifier strategy:

Backend UUID.

Ownership:

Authorized Admin or trusted backend.

Relationships:

Succeeded Card Payment and Receipt.

Immutable fields:

Payment, amount, currency, reason, requester, creation time.

Mutable fields:

Provider-verified status and completion.

Validation:

Succeeded Card Payment, full refundable amount, matching currency, one active Refund, provider verification.

Safe client-visible fields:

Amount, status, safe reason, and timestamps.

Trusted backend-only fields:

Provider reference and transitions.

Audit requirements:

Requester, reason, attempts, provider result, and state transitions.

### 3.20 Receipt

Purpose:

Immutable financial document from trusted Trip, Fare, Payment, and Refund data.

Required fields:

- `id`
- `receiptNumber`
- `tripId`
- `fareQuoteId`
- `paymentId`
- Rider, Driver, and Vehicle snapshots
- Pickup, destination, and ordered stops
- FareBreakdown snapshot
- Applied Cash FareAdjustment snapshots
- `amountPaidMinor`
- `currency`
- `paymentMethod`
- `issuedAt`

Optional fields:

- `cardBrand`
- `cardLastFour`
- `safeProviderReference`
- `refundId`

Identifier strategy:

Backend UUID plus a unique server-generated receipt number in the format `RDX-YYYYMMDD-XXXXXXXX`, where the date is the UTC issue date and `XXXXXXXX` is an uppercase server-generated uniqueness suffix.

Ownership:

RideX issues it. Rider owns access; Driver/Admin get restricted views.

Relationships:

Completed Trip, active FareQuote, succeeded Payment, Cash adjustments, optional Refund.

Immutable fields:

All original receipt facts.

Mutable fields:

None.

Validation:

- Cash only after settlement.
- Card only after one verified Capture.
- Amount reconciles.
- Cancelled/unpaid Trip has no paid Receipt.
- Receipt number matches `RDX-YYYYMMDD-XXXXXXXX` and is globally unique.

Safe client-visible fields:

Authorized Receipt presentation.

Trusted backend-only fields:

Number, source snapshots, and issuance.

Audit requirements:

Generation records source versions and correlation ID.

### 3.21 Rating

Purpose:

Persistent Rider-to-Driver post-Trip feedback.

Required fields:

- `id`
- `tripId`
- `raterUserId`
- `rateeUserId`
- `score`
- `createdAt`

Optional fields:

- `comment`
- `feedbackTags`
- `updatedAt`

Identifier strategy:

Backend UUID with unique participant/Trip relationship.

Ownership:

Rater owns feedback; Admin owns moderation.

Relationships:

Completed Trip and participants.

Immutable fields:

Trip, rater, ratee, creation time.

Mutable fields:

Only through a future approved edit policy.

Validation:

Score 1–5, completed Trip, authenticated Rider is the Trip Rider, ratee is the assigned Driver, and one Rider-to-Driver rating per Trip. Driver-to-Rider ratings are outside the Graduation MVP.

Safe client-visible fields:

Score, comment, tags, aggregate.

Trusted backend-only fields:

Participant derivation and aggregate calculation.

Audit requirements:

Submission and moderation retained.

### 3.22 Notification

Purpose:

Persistent recipient-owned notification.

Required fields:

- `id`
- `recipientUserId`
- `typeCode`
- `title`
- `body`
- `createdAt`

Optional fields:

- Domain references
- Safe navigation target
- Safe payload
- `readAt`
- `expiresAt`
- `deduplicationKey`

Identifier strategy:

Backend UUID.

Ownership:

Recipient owns read state; trusted services own content.

Relationships:

User and optional authorized records.

Immutable fields:

Recipient, content, references, creation.

Mutable fields:

Read timestamp.

Validation:

Bounded content, authorized references, allowlisted navigation, no sensitive payload.

Safe client-visible fields:

Presentation data.

Trusted backend-only fields:

Creation, recipient, deduplication, delivery metadata.

Audit requirements:

Creation and read time.

### 3.23 HelpRequest

Purpose:

Persistent basic request-and-resolution record for ordinary and exceptional Trip/service issues. Chat threads and attachments are outside the Graduation MVP.

Required fields:

- `id`
- `requesterUserId`
- `categoryCode`
- `subject`
- `message`
- `status`
- `createdAt`
- `updatedAt`
- `version`

Optional fields:

- `tripId`
- `paymentId`
- `assignedAdminId`
- `resolutionSummary`
- `resolvedAt`

Identifier strategy:

Backend UUID with creation idempotency key.

Ownership:

Requester owns submission/visibility; Admin owns assignment/resolution.

Relationships:

Requester and optional requester-visible Trip/Payment.

Immutable fields:

Requester, original message/context, creation.

Mutable fields:

Status, assignment, resolution.

Validation:

Bounded nonblank content, recognized category, ownership of linked records, no card data, no attachments, no threaded messages, and a valid request-and-resolution transition.

Safe client-visible fields:

Request, status, resolution.

Trusted backend-only fields:

Assignment and internal diagnostics.

Audit requirements:

Creation, assignment, transitions, and resolution.

## 4. BookingRequest and Trip Separation

BookingRequest and Trip remain separate.

BookingRequest handles:

- Rider confirmation.
- FareQuote locking.
- Driver search.
- Atomic assignment.
- Cancellation.
- Expiration.
- Matching failure.

Trip handles:

- Assigned Driver and Vehicle.
- Driver arrival.
- Start.
- Active route.
- Cash-only in-progress Trip changes.
- Trusted completion.
- Operational cancellation/failure.

One BookingRequest creates zero or one Trip.

Trip is created atomically when one Driver wins assignment.

Cancelled, expired, or failed BookingRequest creates no operational Trip.

This prevents fake Driver data during searching, separates no-driver outcomes from Trip history, and allows participant RLS only after assignment.

## 5. BookingRequest Lifecycle

```dart
enum BookingRequestStatus {
  draft,
  confirmed,
  searching,
  matched,
  cancelled,
  expired,
  failed,
}
```

| From | To | Actor | Preconditions | Trusted operation | Side effects | Realtime | Timestamp | Idempotency | Reason |
|---|---|---|---|---|---|---|---|---|---|
| draft | confirmed | Rider | Valid route, ≤3 stops, vehicle/method, unexpired quote | Confirm and lock | Payment created; inputs locked | `booking.confirmed` | confirmedAt | Key | No |
| draft | cancelled | Rider | Own draft | Cancel | No matching/payment operation | `booking.cancelled` | cancelledAt | Repeat safe | Optional |
| confirmed | searching | Backend | Locked quote, no conflict | Start matching | Match attempt | `booking.searching` | searchingAt | Key | No |
| confirmed | cancelled | Rider | Match not started | Cancel | Payment cancelled | Booking/payment events | cancelledAt | Atomic | Required |
| confirmed | expired | Backend | Preparation timeout/policy | Expire | No Trip | `booking.expired` | expiredAt | No-op repeat | Required |
| confirmed | failed | Backend | Unrecoverable setup failure | Fail | No Trip | `booking.failed` | failedAt | Key | Required |
| searching | matched | Matching service | Atomic eligible Driver acceptance | Assign/create Trip | Reserve Driver, link Payment, close offers | Match/Trip events | matchedAt | Unique assignment | No |
| searching | cancelled | Rider | Assignment not won | Cancel search | Close offers, cancel Payment | Booking/payment events | cancelledAt | Race-safe | Required |
| searching | expired | Matching service | Timeout | Expire search | Close offers, no Trip | `booking.expired` | expiredAt | Timeout key | Required |
| searching | failed | Matching service | Terminal search failure | Fail | Close offers, no Trip | `booking.failed` | failedAt | Key | Required |

Matched, cancelled, expired, and failed are terminal.

### Approved Driver Matching Policy

- Search radius expands through `3 km`, `5 km`, then `8 km` steps.
- At most three Driver offers are active simultaneously for one BookingRequest.
- Each offer expires after 15 seconds.
- Total matching time is limited to 90 seconds from `searchingAt`.
- The matching service may issue additional offer batches within the active radius step while respecting the three-offer limit and total timeout.
- The first valid atomic acceptance wins.
- The winning operation locks the BookingRequest and Driver availability records, verifies Driver approval, block state, availability, Vehicle compatibility, offer expiry, and BookingRequest status, then creates the Trip.
- Losing or duplicate acceptance attempts return `duplicate_driver_acceptance` and do not create or modify a Trip.
- If no Driver wins before 90 seconds, the BookingRequest becomes expired with a matching-timeout reason and no Trip is created.

## 6. Trip Lifecycle

```dart
enum TripStatus {
  accepted,
  driverArriving,
  driverArrived,
  inProgress,
  completed,
  cancelledByRider,
  cancelledByDriver,
  cancelledByAdmin,
  failed,
}
```

| From | To | Actor | Preconditions | Trusted operation | Side effects | Realtime | Reason | Payment dependency |
|---|---|---|---|---|---|---|---|---|
| accepted | driverArriving | Assigned Driver | Cash selected or Card authorized | Begin approach | Timestamp | Trip event | No | Card authorization required |
| accepted | cancellation states | Authorized Rider/Driver/Admin | Not started | Cancel | Release Driver/payment | Trip/payment events | Required | Release Card auth |
| accepted | failed | Backend | Unrecoverable setup | Fail | Release resources | Trip/payment events | Required | Cancel/release |
| driverArriving | driverArrived | Assigned Driver | Valid current state | Mark arrived | Timestamp | Trip event | No | Existing valid payment |
| driverArriving | cancellation/failed | Authorized actor | Not started | Cancel/fail | Release resources | Events | Required | Release Card auth |
| driverArrived | inProgress | Assigned Driver | Card authorized or Cash selected | Start Trip | Availability onTrip | Trip event | No | Card authorization required |
| driverArrived | cancellation/failed | Authorized actor | Not started | Cancel/fail | Release resources | Events | Required | Release Card auth |
| inProgress | completed | Assigned Driver | No blocking Cash change; fare valid | Complete | Cash settle or one Card Capture | Trip/payment/receipt events | No | Cash atomic; Card Capture follows |
| inProgress | cancelledByAdmin | Admin | Exceptional safety/service case | Exceptional cancel | Help/audit and payment handling | Events | Required | Explicit approved handling |
| inProgress | failed | Backend/Admin | Cannot continue safely | Fail | Help/audit and payment handling | Events | Required | Explicit approved handling |

Only assigned Driver progresses the normal lifecycle. Terminal states do not reopen.

## 7. FareQuote Lifecycle

```dart
enum FareQuoteStatus {
  calculated,
  locked,
  expired,
  superseded,
}
```

| From | To | Actor | Rule |
|---|---|---|---|
| calculated | locked | Rider through backend | Younger than ten minutes; inputs unchanged |
| calculated | expired | Backend | Ten minutes elapsed unconfirmed |
| calculated | superseded | Fare service | Route/vehicle/pricing changed |
| locked | superseded | Trusted pre-start replacement or applied Cash change | New immutable version created |

Original FareQuote locks immediately before matching.

For Card pre-start revisions, a replacement FareQuote must be locked before a replacement authorization and before Trip progression resumes.

Locked quotes are immutable and do not expire during matching or Trip operation.

### Approved JOD Pricing Formula

All pricing is configurable and stored in integer Jordanian fils:

- Base fare: `500` fils.
- Distance charge: `300` fils per kilometer.
- Duration charge: `50` fils per minute.
- Intermediate-stop charge: `200` fils per stop.
- Minimum fare: `1000` fils.
- Final fare rounding: nearest `50` fils.

The trusted Fare service prorates distance from integer meters and duration from integer seconds using deterministic integer arithmetic. It calculates the unrounded subtotal as:

`baseFare + distanceCharge + durationCharge + stopCharge`

The service then applies the `1000` fils minimum and rounds the resulting final amount to the nearest `50` fils. Exact half-way results round upward. Flutter displays the resulting FareBreakdown but does not reproduce or authoritatively perform this calculation.

Pricing values are configuration records controlled by a trusted backend boundary. Every FareQuote stores the pricing version used so later configuration changes do not alter historical fares.

## 8. Fixed-Fare Protection

Original fixed fare does not increase due to traffic, GPS error, road closure, Driver navigation error, longer Driver route, or minor provider differences.

Driver cannot edit fare or add charges.

Cash fare may increase only through approved in-progress TripChangeRequest and FareAdjustment.

Card fare cannot increase after inProgress.

## 9. TripChangeRequest and FareAdjustment

```dart
enum TripChangeRequestStatus {
  requested,
  pricing,
  awaitingRiderApproval,
  authorizationPending,
  approved,
  rejected,
  cancelled,
  applied,
  failed,
}
```

`authorizationPending` is reserved for possible future Card support and is unreachable in the Graduation MVP.

FareAdjustment status is derived from TripChangeRequestStatus.

MVP Cash transitions:

| From | To | Actor | Rule |
|---|---|---|---|
| requested | pricing | Backend | Cash Trip, inProgress, Rider owns Trip |
| requested | cancelled | Rider | Request unresolved |
| pricing | awaitingRiderApproval | Backend | Valid nonnegative FareAdjustment |
| pricing | failed | Backend | Routing/pricing failure |
| pricing | cancelled | Rider | Request unresolved |
| awaitingRiderApproval | approved | Rider | Approves displayed additional amount |
| awaitingRiderApproval | rejected | Rider | Declines amount |
| awaitingRiderApproval | cancelled | Rider | Withdraws request |
| approved | applied | Backend | Route and state remain valid |
| approved | failed | Backend | Safe application fails |

Formula:

`additionalAmount = newRemainingRoutePrice - originalRemainingRoutePrice`

No completed route portion is charged again. Negative amount is not supported.

Card TripChangeRequest creation after inProgress is rejected.

## 10. Cash Trip Change Rules

- Rider requests longer destination or additional stop.
- Backend calculates only remaining-route difference.
- Rider sees additional amount and new total.
- Rider approves or rejects.
- Approved adjustment changes current route and final fare.
- Cash remains unpaid.
- Driver cannot edit fare.
- Trusted completion marks Cash paid.
- Receipt contains original quote and applied adjustments.
- At completion, unresolved requests in `requested`, `pricing`, or `awaitingRiderApproval` are cancelled before the original route completes.
- Completion is blocked when a Cash TripChangeRequest is `approved` but its FareAdjustment is not yet `applied`.

## 11. Card Route and Fare Rules

### Before Trip Start

Any route, stop, destination, vehicle, or fare change requires:

1. Pause Trip progression.
2. Create a new FareQuote.
3. Supersede the previous active FareQuote.
4. Cancel/release any previous authorization where required.
5. Record a `voidAuthorization` PaymentAttempt.
6. Update Payment to the replacement FareQuote and amount through a trusted operation.
7. Create one replacement authorization attempt.
8. Verify the new authorization.
9. Allow Trip progression only after verification.

No two Card authorizations remain active.

A pre-start route, stop, destination, vehicle, or fare change is allowed only when the assigned Driver and Vehicle remain compatible with the replacement request. If compatibility fails, the trusted backend cancels the current Trip, releases any Card authorization, releases the Driver, and requires a new BookingRequest and matching operation.

The Rider has two minutes to complete each required Card authorization or reauthorization flow. Expiration cancels the pre-start Trip and releases the Driver and any active authorization.

A Card Trip permits at most two authorization attempts in total. The limit includes the initial authorization, retries, and any replacement authorization required by a pre-start FareQuote change. Once both attempts are consumed without a verified active authorization, the Trip is cancelled and the Driver is released.

### After Trip Start

After `inProgress`:

- Original authorized route and fare remain fixed.
- No destination changes.
- No stop additions/removals/reordering.
- No Card FareAdjustment.
- Rider uses HelpRequest for exceptional safety/service issues.
- Driver cannot modify route price or add charges.

### Capture

- Exactly one active authorized amount.
- Exactly one trusted Capture after completion.
- Capture verified server-side.
- Capture failure leaves Trip completed.
- After the original Capture fails, at most two `captureRetry` attempts are allowed, for a maximum of three Capture attempts in total.
- No successful Receipt until Capture succeeds.
- Every Capture attempt uses the same single approved authorized amount and idempotent operation scope.

## 12. Separate Payment Enums

```dart
enum PaymentMethod { cash, card }
enum CashPaymentStatus { cashSelected, paid, cancelled }
enum CardPaymentStatus {
  cardPaymentPending,
  cardPaymentAuthorized,
  cardPaymentSucceeded,
  cardPaymentFailed,
  paymentCancelled,
  refundPending,
  refunded,
}
```

Cash requires cashStatus and null cardStatus.

Card requires cardStatus and null cashStatus.

Dart contracts, database constraints, and trusted backend validation enforce this.

## 13. Cash Payment Lifecycle

| From | To | Trigger | Preconditions | Operation | Receipt | Idempotency |
|---|---|---|---|---|---|---|
| cashSelected | paid | Trusted completion + collection | Trip inProgress; assigned Driver | Complete Trip, settle Cash, issue Receipt atomically | Paid Receipt | Completion key |
| cashSelected | cancelled | Booking/Trip terminal unpaid state | Not paid | Cancel Payment | None | Repeated cancel safe |

## 14. Card Payment Lifecycle

| From | To | Trigger | Preconditions | Stripe/trusted operation | Trip result | Receipt |
|---|---|---|---|---|---|---|
| pending | authorized | Post-match secure flow | Trip accepted, quote/amount match | Manual-capture authorization + verification | Accepted may progress | None |
| pending | failed | Authorization failure | Verified result | Record failure | Cannot progress | None |
| pending | cancelled | Pre-start cancellation | No successful auth | Cancel provider object if needed | Cancelled | None |
| authorized | pending | Approved pre-start re-quote | Trip not inProgress; old auth released | Void old auth; start one replacement auth | Progress paused | None |
| authorized | succeeded | Trusted completion | Trip completed | One Capture + verification | Remains completed | Issue Receipt |
| authorized | failed | Capture failure | Trip completed | Verify failure | Remains completed | None |
| authorized | cancelled | Pre-start cancellation | Trip not started | Release authorization | Cancelled | None |
| failed | pending | Pre-start authorization retry | Trip accepted; fewer than two authorization attempts used | Create second and final authorization attempt | Progress remains paused | None |
| failed | succeeded | Verified Capture retry | Trip completed; no successful paid Receipt; no more than two Capture retries used | Capture the same single authorized amount and verify | Remains completed | Issue Receipt after success |
| failed | failed | Capture retry fails | Trip completed; Capture retry limit not exceeded | Retain failed canonical state and PaymentAttempt | Remains completed | None |
| succeeded | refundPending | Authorized Refund | Full Refund allowed | Create Refund | Completed | Original retained |
| refundPending | refundPending | Refund attempt fails | No more than two Refund retries used | Retain pending state and failed PaymentAttempt | Completed | Original retained |
| refundPending | refunded | Verified Refund | Provider confirms | Finalize Refund | Completed | Original + Refund |

No Card adjustment authorization exists in the MVP.

Authorization attempt rules:

- Maximum two authorization attempts in total.
- A replacement authorization consumes one of those two attempts.
- Driver progression remains blocked until one attempt is verified as authorized.
- Authorization timeout is two minutes per attempt.

Capture attempt rules:

- One original Capture attempt plus at most two `captureRetry` attempts.
- Trip remains completed while retries are pending or failed.
- Card becomes succeeded only after a verified successful Capture.
- No paid Receipt is issued before verified success.

Refund attempt rules:

- One original Refund attempt plus at most two retries.
- A failed Refund attempt leaves the canonical Card status as `refundPending`.
- No `refundFailed` Card status is added.
- `refunded` requires provider verification.

## 15. Payment and PaymentAttempt

One Payment per BookingRequest/Trip attempt.

Multiple attempts preserve authorization, replacement authorization, void, Capture, retry, Refund, and verification history.

```dart
enum PaymentAttemptType {
  initialAuthorization,
  replacementAuthorization,
  adjustmentAuthorization,
  capture,
  captureRetry,
  voidAuthorization,
  refund,
  providerStatusVerification,
}
```

`adjustmentAuthorization` is reserved future work and unused in the MVP.

```dart
enum PaymentAttemptStatus { pending, succeeded, failed, cancelled }
```

### Approved Idempotency and Provider-Record Retention

- Booking and Trip command idempotency keys are retained for seven days.
- Payment and provider transaction references are retained for the lifetime of the Payment and its required financial retention period.
- Processed webhook event IDs are retained for 90 days to prevent replay.
- Raw webhook payloads are retained for no more than 30 days, only when operationally required, encrypted at rest, restricted to server-side access, and stripped of prohibited card data.
- Expired command keys do not permit replay of terminal or otherwise invalid aggregate transitions because canonical state and version validation still apply.
- A repeated request with a retained matching key returns the existing canonical operation result.
- Reuse of the same idempotency key with a different payload fails closed and is security-logged.

## 16. Repository Contracts

The repository contracts from the approved proposal remain provider-independent with these revisions:

### FareRepository

- `calculateFareAdjustment` accepts only an in-progress Cash TripChangeRequest in the MVP.
- Card Trip input returns a stable unsupported-operation failure.

### TripRepository

- `createTripChangeRequest` accepts only Cash + inProgress.
- Card + inProgress is rejected.
- Pre-start Card changes use a separate trusted FareQuote replacement workflow.
- `completeTrip` triggers one Card Capture or atomic Cash settlement.

### PaymentRepository

Required methods:

| Method | Purpose |
|---|---|
| `getPayment` | Read canonical Payment |
| `watchPayment` | Subscribe to authorized canonical updates |
| `createCardAuthorizationSession` | Start/resume post-match authorization |
| `replacePreStartCardAuthorization` | Release old authorization and prepare one replacement authorization |
| `cancelPayment` | Cancel/release pre-start payment |
| `capturePayment` | Perform one Capture after completion |
| `requestRefund` | Authorized full Refund |
| `verifyProviderStatus` | Server-side provider reconciliation |

No primary contract exposes Stripe PaymentIntent types.

All other Profile, Driver, Vehicle, Location, Routing, Booking, Matching, DriverLocation, Receipt, Rating, Notification, HelpRequest, and Admin contracts remain as defined in the original Phase 2 proposal.

### Approved Repository Migration Strategy

The current combined `TripsRepository` and `MockTrip` contract is replaced gradually rather than through one broad rewrite:

1. Introduce provider-independent `BookingRepository`, `MatchingRepository`, `TripRepository`, `FareRepository`, `PaymentRepository`, and `ReceiptRepository` contracts.
2. Keep existing UI working through controllers and temporary mapping adapters while each real contract becomes available.
3. Move request/search/no-driver behavior from `MockTrip` to Booking and Matching contracts.
4. Move accepted/arriving/arrived/inProgress/completed behavior to TripRepository.
5. Move scalar/mock fare behavior to FareRepository and immutable FareQuote contracts.
6. Move payment labels and fabricated receipt behavior to PaymentRepository and ReceiptRepository canonical records.
7. Remove production-facing dependencies on `MockTrip` only after every consumer is migrated and regression-tested.
8. Keep Mock implementations only for explicit development and tests.
9. Production Supabase mode must never silently fall back to Mock repositories.

## 17. Compatibility Matrix

| Combination | Result |
|---|---|
| Searching + Cash selected | Valid |
| Searching + Card pending | Valid; no authorization yet |
| Searching + Card authorized | Invalid |
| Matched/accepted + Card pending | Valid transiently |
| Accepted + Card authorized | Valid |
| InProgress + Card authorized | Valid |
| InProgress + Cash selected | Valid |
| InProgress Cash + awaiting approval | Valid; original route active |
| InProgress Cash + applied FareAdjustment | Valid |
| InProgress Card + TripChangeRequest | Invalid/deferred |
| InProgress Card + FareAdjustment | Invalid/deferred |
| Completed + Card succeeded | Valid |
| Completed + Card failed | Valid; no paid Receipt |
| Completed + Cash paid | Valid |
| Cancelled + cancelled Payment | Valid |
| InProgress Card without authorization | Impossible |
| Completed Cash still selected | Impossible after trusted completion |
| Cancelled Trip with active authorization | Invalid; the trusted cancellation workflow must release or cancel it and verify the provider state |
| Cash with cardStatus | Impossible |
| Card with cashStatus | Impossible |
| Applied Cash adjustment without Rider approval | Impossible |
| Card adjustment PaymentAttempt in MVP | Impossible |
| More than one active Card authorization | Impossible |
| More than one Card Capture | Impossible |
| Paid Receipt for unpaid/cancelled Payment | Impossible |

## 18. Cancellation Rules

Pre-start cancellation releases Card authorization where required.

In-progress Rider/Driver cancellation is not a normal MVP action.

Exceptional in-progress Card service/safety issues use a basic HelpRequest and authorized Admin handling. No partial charge is captured. The Trip is terminated only through the trusted exceptional operation, the original authorization is released or cancelled, and the action is audited. If provider release remains pending, the Payment remains in a safe non-succeeded state until verified.

Completed Trips cannot be cancelled. Refund remains separate.

## 19. Error Contracts

Existing stable errors remain, with these additions/clarifications:

| Code | Meaning | UI |
|---|---|---|
| `card_trip_change_not_supported` | In-progress Card route/fare changes are deferred | Keep original route; offer Help |
| `card_reauthorization_required` | Pre-start Card change invalidated previous authorization | Open secure authorization |
| `authorization_release_pending` | Old Card authorization release is not verified | Wait; Trip cannot start |
| `multiple_active_authorizations` | Invariant violation detected | Fail closed; Admin/security logging |
| `capture_failed` | Single Capture failed after completion | Trip completed; Admin review |

`additional_authorization_failed` remains reserved for future Card adjustment support and is not emitted by MVP paths.

## 20. Failure and Recovery

| Failure | Behavior |
|---|---|
| Cash adjustment calculation fails | Original Cash route/fare remain |
| Cash adjustment approval interrupted | Restore pending request |
| Completion with Cash request in requested/pricing/awaiting approval | Cancel the unresolved request, then complete the original route |
| Completion with approved but unapplied Cash adjustment | Block completion until the adjustment is applied or the trusted operation fails it safely |
| Card in-progress change requested | Reject with stable deferred error |
| Compatible Card pre-start route change | New FareQuote; release old authorization; one replacement authorization within the two-attempt limit |
| Incompatible Card pre-start route/vehicle change | Cancel current Trip, release authorization and Driver, then require a new BookingRequest |
| Old Card release pending | Trip progression blocked |
| Authorization attempt times out after two minutes | Mark attempt failed/cancelled; retry only if the two-attempt total is not exhausted |
| Replacement authorization fails | Trip stays pre-start; no old authorization reused; cancel when two total attempts are exhausted |
| Duplicate authorization | Return existing active attempt/session |
| Duplicate Capture | Return existing Capture result |
| Capture failure | Trip completed; Card failed; no paid Receipt; Admin visibility; at most two retries after the original attempt |
| Refund attempt fails | Keep refundPending; allow at most two retries after the original attempt |
| Exceptional in-progress Card termination | Create/associate HelpRequest, perform audited Admin termination, capture no partial charge, and verify authorization release |
| Realtime disconnect | Reconnect and refetch |
| App restart | Restore Booking, Trip, Payment, and Cash TripChangeRequest |
| Payment pending | Wait/query backend; never infer result |

## 21. Realtime Contracts

Required events remain:

- Booking state.
- Driver assignment.
- Trip state.
- Driver location.
- Cash TripChangeRequest.
- Cash FareAdjustment.
- Payment state.
- Receipt availability.
- Notifications.

Card in-progress TripChange/FareAdjustment events are not produced in the MVP.

Pre-start Card replacement events include safe FareQuote and Payment canonical-state changes.

Driver location events are accepted every 5 seconds during an active Trip and every 20 seconds while the Driver is available or reserved. Clients discard stale sequences, and precise samples are retained for seven days.

## 22. Ownership

Yousuf additionally owns:

- Pre-start Card re-quote and authorization-replacement contracts.
- Enforcement of one active Card authorization.
- Enforcement of one Card Capture.
- Cash-only FareAdjustment backend validation.

Omar additionally owns:

- Cash-only TripChangeRequest UI.
- Card fixed-route explanatory state after Trip start.
- Pre-start Card reauthorization UI.
- HelpRequest path for exceptional Card service/safety issues.

Shared review confirms no Card in-progress adjustment path is exposed.

## 23. Acceptance Tests

Revised/new tests:

| Test | Expected result |
|---|---|
| Cash FareAdjustment | Rider-approved adjustment applies |
| Cash completed-route protection | Only remaining-route difference charged |
| Cash completion | Original quote + adjustments settled and receipted |
| Cash completion with unresolved unapproved change | Request cancelled; original route completes |
| Cash completion with approved unapplied adjustment | Completion blocked |
| Card in-progress destination change | Rejected as deferred |
| Card in-progress stop addition | Rejected as deferred |
| Driver Card fare edit | Rejected |
| Card pre-start route change | New FareQuote required |
| Card pre-start authorized change | Old authorization released |
| Card replacement authorization | One new authorization verified |
| Card authorization timeout | Attempt ends after two minutes |
| Third Card authorization attempt | Rejected because total limit is two |
| Multiple active Card authorizations | Prevented |
| Card completion | One Capture only |
| Duplicate Card Capture | No duplicate financial operation |
| Card Capture failure | Trip remains completed; no paid Receipt |
| Capture retry limit | Original attempt plus at most two retries |
| Refund retry limit | Status remains refundPending; original attempt plus at most two retries |
| HelpRequest during Card Trip | Exceptional issue recorded without FareAdjustment |
| Driver availability states | Only offline, available, reserved, and onTrip accepted |
| Driver Trip location interval | New accepted sample every five seconds |
| Available/reserved location interval | New accepted sample every 20 seconds |
| Location retention | Precise sample unavailable after seven-day retention processing |
| Receipt number | Matches RDX-YYYYMMDD-XXXXXXXX and is unique |
| Configured base fare | Uses 500 fils |
| Configured distance charge | Uses 300 fils per kilometer |
| Configured duration charge | Uses 50 fils per minute |
| Configured stop charge | Uses 200 fils per stop |
| Minimum and rounding | At least 1000 fils and rounded to nearest 50 fils |
| Matching radius expansion | Uses 3 km, then 5 km, then 8 km |
| Matching offer limit | Never exceeds three active simultaneous offers |
| Matching offer expiry | Offer expires after 15 seconds |
| Matching timeout | Booking expires after 90 seconds without a winner |
| Atomic acceptance | First valid acceptance wins |
| Idempotency retention | Command, Payment, webhook ID, and raw payload periods match approved rules |

All previously proposed Booking, matching, lifecycle, Cash/Card validation, Realtime, restoration, cancellation, Receipt, duplicate webhook, and authorization tests remain required.

## 24. Future File Plan

Future model, repository, service, provider, migration, Edge Function, test, and integration-test groups remain as previously proposed.

Implementation must clearly separate:

- Cash TripChange/FareAdjustment MVP paths.
- Card fixed-fare MVP paths.
- Future deferred Card adjustment contracts.

No implementation files are created in Phase 2 documentation.

## 25. Contradiction and Complexity Review

Resolved simplification:

- Card in-progress FareAdjustment is deferred.
- Additional Card authorization is unused in the MVP.
- Card has one active authorization.
- Card has one Capture.
- Cash retains TripChangeRequest and FareAdjustment.
- Partial Card settlement caused by multiple Captures is removed.

Approved implementation constraints:

- Pre-start Card re-quote is allowed only while Driver/Vehicle compatibility remains valid.
- Incompatible changes cancel the Trip and require a new BookingRequest.
- Authorization timeout is two minutes with two attempts total.
- Capture allows the original attempt plus two retries.
- Refund remains pending through failures and allows the original attempt plus two retries.
- Exceptional in-progress Card termination uses HelpRequest and audited Admin handling with no partial charge.
- Fare uses the approved configurable JOD fils formula.
- Matching uses the approved radius, offer, expiry, atomic-acceptance, and timeout policy.

Current-code conflicts remain:

- MockTrip combines Booking and Trip.
- Rider can author Driver transitions.
- Cash is hardcoded.
- Card is disabled.
- Receipt data is fabricated.
- Money uses `double`.
- History is static.
- No persistence contracts exist.

The approved architecture avoids UI redesign by mapping existing screens to canonical providers and keeping provider-specific payment details behind PaymentRepository.

## 26. Definition of Done

Phase 2 documentation is complete only when:

- Plan.md has a concise Phase 2 summary and link.
- Detailed architecture is approved.
- Models and repositories are provider-independent.
- BookingRequest and Trip remain separate.
- FareQuote locks before matching.
- Cash supports approved in-progress FareAdjustment.
- Card rejects in-progress route/fare changes.
- Card has one active authorization and one Capture.
- Payment and PaymentAttempt remain separate.
- Cash and Card use separate statuses.
- Fixed-fare and cancellation rules are explicit.
- Capture failure does not undo completion.
- Error, recovery, Realtime, ownership, and tests are measurable.
- Deferred Card adjustments are explicit.
- All 16 final MVP decisions are recorded as approved rules rather than unresolved questions.
- No implementation file changed.

## 27. Final Approved MVP Decisions

1. Pre-start Card route, stop, destination, vehicle, or Fare changes are allowed only when the assigned Driver and Vehicle remain compatible. Otherwise the Trip is cancelled and the Rider must create a new BookingRequest.
2. Card authorization and reauthorization timeout is two minutes per attempt.
3. A Card Trip permits two authorization attempts in total.
4. After the original Capture fails, two Capture retries are allowed, for three total Capture attempts.
5. Refund failure does not add `refundFailed`. The Card remains `refundPending`, and two retries are allowed after the original Refund attempt.
6. Exceptional in-progress Card termination uses a basic HelpRequest and audited Admin handling with no partial charge.
7. Completion cancels unresolved Cash change requests in `requested`, `pricing`, or `awaitingRiderApproval`, but blocks while an approved adjustment remains unapplied.
8. Graduation MVP Ratings are Rider-to-Driver only.
9. DriverAvailability uses exactly `offline`, `available`, `reserved`, and `onTrip`.
10. Driver location updates every five seconds during a Trip and every 20 seconds while available or reserved. Precise samples are retained for seven days.
11. HelpRequest is a basic request-and-resolution workflow with no threads or attachments.
12. Receipt numbers are server-generated as `RDX-YYYYMMDD-XXXXXXXX`.
13. Configurable JOD pricing uses 500 fils base fare, 300 fils per kilometer, 50 fils per minute, 200 fils per intermediate stop, a 1000 fils minimum, and final rounding to the nearest 50 fils.
14. Driver matching uses 3 km, 5 km, and 8 km radius steps; at most three simultaneous offers; 15-second offer expiry; a 90-second total timeout; and first valid atomic acceptance wins.
15. Booking/Trip command keys are retained seven days, Payment references for the Payment lifetime, webhook event IDs for 90 days, and raw webhook payloads for at most 30 days under the documented security restrictions.
16. `TripsRepository` and `MockTrip` are replaced gradually by separate BookingRepository, MatchingRepository, TripRepository, FareRepository, PaymentRepository, and ReceiptRepository contracts. Mock implementations remain only for explicit development and tests.
