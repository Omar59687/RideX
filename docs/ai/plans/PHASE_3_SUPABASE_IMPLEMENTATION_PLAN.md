# Phase 3 - Supabase Database, Constraints, RPCs, and RLS

Status: Approved for staged implementation

Branch: `codex/phase-3-supabase-foundation`

Phase 2 contract: `docs/ai/plans/PHASE_2_DOMAIN_ARCHITECTURE_AND_CONTRACTS.md`

## Purpose

Phase 3 creates the local Supabase database foundation for the approved Phase 2 domain contracts. It establishes durable tables, PostgreSQL enums, foreign keys, checks, unique constraints, indexes, trusted RPC boundaries, audit records, idempotency foundations, and Row-Level Security (RLS) for Rider, Driver, Admin, and backend operations.

Every Build-mode session completes exactly one checkpoint. Migrations are additive and ordered after existing migrations `001` through `004`. Flutter, provider, repository, payment-provider, mapping, matching, and remote-deployment work is outside this phase.

## Scope

- User-owned, Driver-owned, booking, fare, matching-foundation, Trip, Cash-change, payment-foundation, receipt, location, rating, notification, support, audit, and idempotency records.
- PostgreSQL enums and database validation for approved Phase 2 states.
- Backend-generated UUIDs, UTC timestamps, integer JOD fils, aggregate versions, append-only history, and safe state transitions.
- Narrow trusted `SECURITY DEFINER` RPCs with empty search paths and explicit grants.
- RLS and table/function privilege hardening.
- pgTAP security, schema, constraint, lifecycle, stale-version, and idempotency tests.
- Local Supabase Docker and CLI verification only.

## Exclusions

Phase 3 does not implement Google Maps, GPS/device permissions, map SDKs, mobile location publishing, heartbeat enforcement, reconnection, latest-location recovery, mobile Realtime subscriptions, Flutter repositories or screens, Stripe API calls, real Driver matching execution, Admin UI, production deployment, remote migration push, or remote Supabase changes.

Payment, matching, notification, rating, help, and location tables are secure provider-neutral foundations for later phases. Phase 4 owns mobile location behavior. Phase 6 owns Stripe integration. Phase 7 owns matching execution and Realtime. Phase 8 owns payment execution, capture, refunds, receipts, and history workflows. Phase 9 owns profiles, notifications, ratings, help, and Admin workflows. Phase 10 owns end-to-end and release verification.

## Compatibility Rules

- Migrations `001` through `004` are preserved and are not rewritten.
- Public Auth signup remains Rider-only.
- Existing `driver_profiles.is_online` and `driver_profiles.is_available` remain present and readable according to existing contracts. They are deprecated compatibility fields, not the Phase 3 source of truth.
- Checkpoint 3.2 adds `driver_availability`, safely backfills one canonical row per Driver, and updates trusted backend functions to prefer it.
- Legacy availability fields are not dropped until a later phase migrates Flutter repositories/providers and regression tests prove that production code no longer reads them.
- Existing Admin RPC names remain compatible while gaining audit behavior and canonical availability usage where applicable.
- Phase 2 separation of `booking_requests` and `trips`, Cash-only in-progress changes, fixed Card fare after `inProgress`, integer money, and server-authoritative decisions are preserved.

## Ordered Checkpoints

### Checkpoint 3.0 - Documentation and token-efficient resume workflow

Files created:

- `docs/ai/plans/PHASE_3_SUPABASE_IMPLEMENTATION_PLAN.md`
- `docs/ai/ops/PHASE_3_STATUS.md`
- `.opencode/commands/resume-phase-3.md`

Tables: none. RPCs: none. No migrations or database tests are created.

Definition of done: the three files agree on the checkpoint order, migration order, status, resume rules, and exclusions; `git diff --check` passes; only these three files exist as changes; no commit is made.

### Checkpoint 3.1 - Core security foundation

Migration: `supabase/migrations/005_phase3_core_security_foundation.sql`

Test: `supabase/tests/database/005_phase3_core_security_foundation.test.sql`

Tables created or extended: `audit_records`, `command_idempotency_keys`; existing `users`, `rider_profiles`, and `driver_profiles` receive compatible version/validation support where required.

RPCs: private `private.bootstrap_first_admin`; audited revisions of existing Admin role/approval RPCs; `admin_set_user_blocked`.

The checkpoint adds approved enums, bounded values, optimistic versions, immutable audit rows, seven-day command idempotency records, audit triggers for role/blocked/approval changes, and the one-time Admin bootstrap. The bootstrap is owner-only, private-schema, target-UUID based, reason-required, non-blocked-target only, succeeds only when no Admin exists, and fails closed thereafter.

Definition of done: schema assertions, bootstrap success/failure/security/audit tests, idempotency mismatch tests, and existing `004_role_authorization_boundary.test.sql` compatibility pass locally.

### Checkpoint 3.2 - Driver assets and canonical availability

Migration: `supabase/migrations/006_phase3_driver_assets_availability.sql`

Test: `supabase/tests/database/006_phase3_driver_assets_availability.test.sql`

Tables: `vehicles`, `driver_availability`.

RPCs: `driver_create_vehicle`, `driver_update_vehicle`, `driver_set_vehicle_active`, `driver_set_availability`.

The canonical availability table uses exactly `offline`, `available`, `reserved`, and `onTrip`. Existing Driver rows are backfilled safely. Availability transitions enforce approval, blocked state, vehicle ownership, and valid references. Legacy online/available columns remain deprecated compatibility fields.

Definition of done: vehicle ownership/plate constraints, canonical backfill, Driver/Admin reads, denied direct writes, and availability transition tests pass.

### Checkpoint 3.3 - Booking, fare, and matching foundations

Migration: `supabase/migrations/007_phase3_booking_fare_matching_foundation.sql`

Test: `supabase/tests/database/007_phase3_booking_fare_matching_foundation.test.sql`

Tables: `pricing_configurations`, `booking_requests`, `booking_stops`, `fare_quotes`, `driver_match_offers`.

RPCs: `rider_create_booking_draft`, `rider_update_booking_draft`, `rider_confirm_booking`, `rider_cancel_booking`; backend-only fare calculation, quote locking, and matching-offer functions.

The schema enforces maximum three contiguous stops, immutable confirmed inputs, quote version uniqueness, ten-minute calculated quote expiry, one active locked quote, supported vehicle/payment values, and offer expiry/uniqueness. It creates matching records only; it does not execute matching.

Definition of done: route, money, quote, booking lifecycle, participant RLS, idempotent confirmation, and no-client-authority tests pass.

### Checkpoint 3.4 - Trip and Cash-change foundations

Migration: `supabase/migrations/008_phase3_trip_cash_change_foundation.sql`

Test: `supabase/tests/database/008_phase3_trip_cash_change_foundation.test.sql`

Tables: `trips`, `trip_stops`, `trip_status_events`, `trip_change_requests`, `fare_adjustments`.

RPCs: `driver_transition_trip`, `rider_cancel_trip`, `admin_terminate_trip`, `rider_create_trip_change_request`, `rider_cancel_trip_change_request`, `rider_approve_trip_change_request`; backend-only Cash pricing and adjustment-application functions.

Trip assignment, event sequence, terminal-state protection, Card fixed-fare rules, Cash-only changes, unresolved-request completion rules, and expected-version checks are database foundations. No Card in-progress adjustment path exists.

Definition of done: authorized lifecycle transitions, append-only events, Cash adjustment invariants, Card rejection, participant access, and race/idempotency tests pass.

### Checkpoint 3.5 - Payment, refund, receipt, and webhook foundations

Migration: `supabase/migrations/009_phase3_payment_receipt_foundation.sql`

Test: `supabase/tests/database/009_phase3_payment_receipt_foundation.test.sql`

Tables: `payments`, `payment_attempts`, `refunds`, `receipts`, `processed_webhook_events`.

RPCs: `admin_request_refund`; backend-only payment-attempt, payment-state, receipt-issuance, and webhook-idempotency functions.

The schema enforces separate Cash/Card statuses, one active Card authorization, one Capture, attempt limits, full-refund rules, receipt-number format/uniqueness, amount/currency reconciliation, and ninety-day processed webhook retention. It stores no prohibited card data and makes no Stripe calls.

Definition of done: payment compatibility constraints, append-only attempts, duplicate operation handling, receipt prerequisites, refund state, participant-safe reads, and service-only writes pass.

### Checkpoint 3.5H - Verified authorization and Refund-state hardening

Migration: `supabase/migrations/010_phase3_payment_state_verification_hardening.sql`

Test: `supabase/tests/database/010_phase3_payment_state_verification_hardening.test.sql`

This corrective checkpoint requires verified, timely trusted authorization completion before a Card Payment can become authorized. It associates every Refund attempt with its canonical Refund, routes Refund operations through dedicated backend-only lifecycle functions, retains failed Refunds as pending for up to two retries, and permits `refunded` only after verified Refund completion.

### Checkpoint 3.6 - Driver-location database foundation

Migration: `supabase/migrations/011_phase3_driver_location_foundation.sql`

Test: `supabase/tests/database/011_phase3_driver_location_foundation.test.sql`

Table: `driver_locations`.

RPCs: `driver_record_location`; backend-only expired-location purge function.

The table includes Driver and optional active-Trip foreign keys, per-Driver monotonic sequence protection, duplicate/out-of-order rejection, latitude/longitude/accuracy/heading/speed validation, recorded/received timestamp validation, participant-safe RLS, retrieval indexes, and a seven-day precise-location retention foundation. It does not implement GPS, publishing cadence, heartbeats, Realtime, reconnection, or map presentation.

Definition of done: unauthorized read/write, ownership, assigned-Rider visibility, stale/future timestamp, duplicate/out-of-order sequence, invalid value, index, and retention tests pass.

### Checkpoint 3.7 - Support, feedback, and notification foundations

Migration: `supabase/migrations/012_phase3_support_feedback_notification_foundation.sql`

Test: `supabase/tests/database/012_phase3_support_feedback_notification_foundation.test.sql`

Tables: `ratings`, `notifications`, `help_requests`.

RPCs: `rider_create_rating`, `user_create_help_request`, `user_mark_notification_read`, `admin_assign_help_request`, `admin_resolve_help_request`; backend-only notification creation.

The schema enforces completed-Trip Rider-to-Driver ratings, one rating per Trip, bounded HelpRequest content, linked-record ownership, no card data, recipient-owned notification read state, deduplication, and Admin resolution controls.

Definition of done: participant ownership, moderation visibility, valid rating/help transitions, notification read isolation, deduplication, blocked-user denial, and backend-only content creation tests pass.

### Checkpoint 3.8 - Cross-cutting RLS and RPC hardening

Migration: `supabase/migrations/013_phase3_rls_rpc_hardening.sql`

Test: `supabase/tests/database/013_phase3_rls_rpc_hardening.test.sql`

Tables: none. RPCs: no new domain RPCs; all Phase 3 function privileges, search paths, security-definer properties, grants, revokes, and RLS enablement are finalized and verified.

Definition of done: the complete matrix below is asserted for every Phase 3 table and function, all non-live local database tests pass, and no direct client write bypass remains.

## Migration Dependencies

`005` depends on the identity and role boundary established by `001`-`004`. `006` depends on `005` enums, versions, and audit support. `007` depends on user/Driver/vehicle foundations. `008` depends on booking, FareQuote, Driver availability, and Trip-assignment foundations; it does not reference a Payment table. `009` depends on booking, FareQuote, and Trip structures, creates Payment records, and adds any required Payment-to-Trip relationship after both sides exist. `010` depends on `009` Payment, PaymentAttempt, and Refund records to harden verified authorization and Refund lifecycles. `011` depends on Driver and Trip identifiers. `012` depends on Trip, payment, and user records. `013` depends on every prior Phase 3 object. There is no circular migration dependency.

Applied migrations are never edited. Any correction after local application uses a new compensating migration. Existing data is preserved; backfills are idempotent and use conflict-safe inserts.

## Complete RLS Matrix

`S`, `I`, `U`, and `D` mean direct table Select, Insert, Update, and Delete. `-` means no direct permission. A listed `S` is limited by row policy and safe columns/views. The Backend/database owner column represents `postgres` and explicitly trusted service operations. Blocked users fail all Phase 3 row policies and all command RPC authorization checks.

| Table | Anonymous S/I/U/D | Rider S/I/U/D | Driver S/I/U/D | Admin S/I/U/D | Blocked user S/I/U/D | Backend/database owner S/I/U/D | Required trusted RPC | Direct client writes denied |
|---|---|---|---|---|---|---|---|---|
| `audit_records` | `-/-/-/-` | `-/-/-/-` | `-/-/-/-` | `-/-/-/-` | `-/-/-/-` | `S/I/U/D` | Internal audit writer | Yes |
| `command_idempotency_keys` | `-/-/-/-` | `-/-/-/-` | `-/-/-/-` | `-/-/-/-` | `-/-/-/-` | `S/I/U/D` | Command RPCs | Yes |
| `vehicles` | `-/-/-/-` | `S/-/-/-` authorized assigned-Trip view | `S/-/-/-` own vehicles | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Vehicle RPCs | Yes |
| `driver_availability` | `-/-/-/-` | `-/-/-/-` | `S/-/-/-` own row | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Availability RPCs | Yes |
| `pricing_configurations` | `-/-/-/-` | `S/-/-/-` active safe config | `S/-/-/-` active safe config | `S/-/-/-` | `-/-/-/-` | `S/I/U/D` | Backend config writer | Yes |
| `booking_requests` | `-/-/-/-` | `S/-/-/-` own rows | `S/-/-/-` authorized offer/Trip | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Rider booking and backend matching RPCs | Yes |
| `booking_stops` | `-/-/-/-` | `S/-/-/-` own Booking | `S/-/-/-` assigned Trip | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Draft and backend booking RPCs | Yes |
| `fare_quotes` | `-/-/-/-` | `S/-/-/-` own Booking/Trip | `S/-/-/-` assigned Trip | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Backend quote RPCs | Yes |
| `driver_match_offers` | `-/-/-/-` | `S/-/-/-` own Booking status | `S/-/-/-` own offers | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Backend matching RPCs | Yes |
| `trips` | `-/-/-/-` | `S/-/-/-` own Trips | `S/-/-/-` assigned Trips | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Trip lifecycle RPCs | Yes |
| `trip_stops` | `-/-/-/-` | `S/-/-/-` own Trip | `S/-/-/-` assigned Trip | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Backend Trip/change RPCs | Yes |
| `trip_status_events` | `-/-/-/-` | `S/-/-/-` participant-safe | `S/-/-/-` participant-safe | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Trip lifecycle functions | Yes |
| `trip_change_requests` | `-/-/-/-` | `S/-/-/-` own Trip | `S/-/-/-` assigned Trip read-only | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Rider Cash-change RPCs | Yes |
| `fare_adjustments` | `-/-/-/-` | `S/-/-/-` own Trip | `S/-/-/-` assigned Trip read-only | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | Backend Cash pricing/application | Yes |
| `payments` | `-/-/-/-` | `S/-/-/-` safe own fields | `-/-/-/-` | `S/-/-/-` restricted finance view | `-/-/-/-` | `S/I/U/D` | Backend payment functions | Yes |
| `payment_attempts` | `-/-/-/-` | `S/-/-/-` safe own summary | `-/-/-/-` | `S/-/-/-` restricted finance view | `-/-/-/-` | `S/I/U/D` | Backend payment functions | Yes |
| `refunds` | `-/-/-/-` | `S/-/-/-` safe own status | `-/-/-/-` | `S/-/-/-` restricted finance view | `-/-/-/-` | `S/I/U/D` | `admin_request_refund` | Yes |
| `receipts` | `-/-/-/-` | `S/-/-/-` own receipts | `S/-/-/-` assigned Trip view | `S/-/-/-` restricted finance view | `-/-/-/-` | `S/I/U/D` | Backend receipt issuance | Yes |
| `processed_webhook_events` | `-/-/-/-` | `-/-/-/-` | `-/-/-/-` | `-/-/-/-` | `-/-/-/-` | `S/I/U/D` | Backend webhook idempotency | Yes |
| `driver_locations` | `-/-/-/-` | `S/-/-/-` assigned Trip samples | `S/-/-/-` own samples | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | `driver_record_location`, retention purge | Yes |
| `ratings` | `-/-/-/-` | `S/-/-/-` own submitted/allowed received summary | `S/-/-/-` own received ratings | `S/-/-/-` moderation view | `-/-/-/-` | `S/I/U/D` | `rider_create_rating` | Yes |
| `notifications` | `-/-/-/-` | `S/-/-/-` own notifications | `S/-/-/-` own notifications | `S/-/-/-` restricted view | `-/-/-/-` | `S/I/U/D` | `user_mark_notification_read`; backend notification creation | Yes |
| `help_requests` | `-/-/-/-` | `S/-/-/-` own requests | `S/-/-/-` own requests | `S/-/-/-` assignment/resolution view | `-/-/-/-` | `S/I/U/D` | `admin_assign_help_request`; `admin_resolve_help_request`; user creation RPC | Yes |

Client-facing RPCs still enforce actor ownership, role, blocked state, lifecycle, and expected version. `SECURITY DEFINER` does not grant authority by itself; every function performs explicit authorization. Anonymous callers receive no Phase 3 table or RPC privileges.

## First-Admin Bootstrap

`private.bootstrap_first_admin(target_user_id uuid, audit_reason text)` is created in Checkpoint 3.1.

- Public signup remains Rider-only; email addresses and patterns never create Admins.
- The Flutter application cannot call or bootstrap an Admin.
- The function accepts an existing target UUID and a required, bounded audit reason.
- It is executable only by the database owner or equivalent trusted operator; `public`, `anon`, and `authenticated` receive no execute privilege.
- It succeeds only when no Admin exists, the target exists, and the target is not blocked.
- It locks the relevant role state, changes the target through the trusted boundary, and preserves profile consistency.
- It writes an immutable audit record containing actor/context, target, reason, previous role, new role, and UTC timestamp.
- It fails closed for a second bootstrap, blocked target, nonexistent target, invalid reason, or unauthorized caller.
- It is tested locally and never executed against remote Supabase during Phase 3.

## Driver-Location Foundation

`driver_locations` is created in Checkpoint 3.6. It has Driver and optional active-Trip foreign keys; monotonic per-Driver sequence protection; duplicate/out-of-order rejection; coordinate, accuracy, heading, speed, and timestamp checks; indexes for Driver/Trip sequence retrieval and retention; participant-safe RLS; and a backend-only seven-day precise-sample purge foundation. Phase 4 supplies device GPS, permissions, publishing, heartbeat enforcement, Realtime, reconnection, latest-location recovery, and maps.

## Payment and Matching Boundaries

Payment tables, attempts, refunds, receipts, and processed webhook IDs are schema foundations only. Phase 3 performs no Stripe API calls, provider verification, authorization, capture, or refund execution. Matching offers and availability are schema foundations only. Phase 3 performs no Driver selection, offer dispatch, atomic acceptance worker, or Realtime matching operation.

## Audit, Idempotency, and Retention

- Role, blocked-state, approval, lifecycle, financial, support, and Admin actions record actor/context, reason where applicable, prior/new state, and UTC time.
- Audit records are immutable and backend-written.
- Booking and Trip command keys are retained seven days and are payload-fingerprint checked.
- Payment/provider references remain for the Payment retention period.
- Processed webhook event IDs remain for ninety days.
- Precise Driver locations are retained for seven days before backend purge or approved irreversible aggregation.
- Raw webhook payloads are not stored in Phase 3 because encrypted restricted storage is not yet approved.

## Failure and Rollback Strategy

- Each migration is transaction-safe and includes preflight checks for required predecessor objects.
- Backfills are idempotent and preserve existing profiles/state with conflict-safe inserts.
- No applied migration is edited and no destructive reset is used against remote databases.
- Failed local migrations are diagnosed with `npx supabase@latest db reset --local`; corrections are new compensating migrations.
- Trusted commands lock aggregates, validate prior state/actor/version, and fail closed on ambiguity or duplicate payload mismatch.
- Append-only audit, event, payment-attempt, quote, and receipt facts are never rewritten by client operations.
- Remote deployment is a separate approved activity and is not part of Phase 3 implementation.

## pgTAP Strategy

Each migration has one matching test file. Tests run transactionally and cover:

- enums, columns, defaults, foreign keys, checks, unique constraints, partial indexes, and retention indexes;
- valid lifecycle operations and invalid actor, role, blocked-user, state, amount, currency, timestamp, sequence, and expected-version inputs;
- anonymous, Rider, Driver, Admin, blocked-user, and backend/database-owner visibility and mutation boundaries;
- direct table writes, function grants, `SECURITY DEFINER`, empty `search_path`, and private bootstrap isolation;
- duplicate idempotency keys, matching payload replay, mismatched payload rejection, and terminal-state replay;
- audit creation and immutability;
- Driver-location unauthorized access and stale/out-of-order samples;
- preservation of existing migration `004` tests.

## Local Verification

Checkpoint 3.0 uses documentation-only verification and does not run Supabase, Docker, Flutter, or database commands.

From Checkpoint 3.1 onward, focused local verification uses:

```powershell
npx supabase@latest start
npx supabase@latest db reset --local
npx supabase@latest test db
npx supabase@latest stop
```

The current Supabase CLI test command runs the complete database test directory; no unsupported single-test path is prescribed. Focused development uses the complete local database suite, followed by the same suite before completing each migration checkpoint. No `supabase link`, remote migration push, production command, or remote database reset is permitted without explicit approval.

## Future-Phase Dependencies

- Phase 4 consumes location records through provider-independent contracts and adds device GPS, permissions, maps, publishing, heartbeats, recovery, and Realtime behavior.
- Phase 5 extends booking stops and route/fare workflows without changing historical quote facts.
- Phase 6 consumes payment foundations for Cash and Stripe Test Mode; Phase 3 does not contact Stripe.
- Phase 7 consumes availability, offers, Trips, and location foundations for matching and Realtime.
- Phase 8 consumes payment attempts, refunds, receipts, and webhook foundations for trusted financial execution and history.
- Phase 9 consumes profile, notification, rating, HelpRequest, and Admin foundations for user-facing workflows.
- Phase 10 validates complete integration, security, failure recovery, retention, and release readiness.

## Phase 3 Definition Of Done

Phase 3 is complete when:

- Checkpoints 3.0 through 3.8 are individually completed in order.
- Migrations `005` through `012` apply cleanly after `001` through `004`.
- Every Phase 3 table has appropriate keys, checks, indexes, RLS, grants, and pgTAP coverage.
- Trusted RPCs enforce approved actor, state, ownership, version, money, idempotency, and audit rules.
- Legacy availability fields remain compatible and are documented as deprecated.
- Driver-location persistence and retention foundations pass unauthorized/stale/out-of-order tests.
- Payment and matching records remain schema-only with no external integrations.
- Local Supabase Docker/CLI verification passes, including the existing database tests.
- No Flutter code, dependency, configuration, credential, MCP, remote Git, branch, or remote Supabase state is changed.
- Remote deployment remains explicitly separate and has not occurred.
