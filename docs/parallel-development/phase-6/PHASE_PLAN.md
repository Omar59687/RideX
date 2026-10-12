# Phase 6 — Detailed Execution Plan (Payment Foundations)

Baseline `6bae92e`. Status authority: `SPRINT_TRACKER.md`.
Phase 4/5 remain unapproved; their verification is tracked separately (V-tasks).

## 1. Scope (from Plan.md)

- Persistent Cash payment foundations.
- Provider-independent Card payment contracts.
- Stripe Test Mode PaymentIntent + secure UI foundations.
- Out of Phase 6: authorization/capture execution, webhooks, refunds, persistent
  history restoration (Phase 8); matching/Realtime (Phase 7); secondary/admin
  persistence (Phase 9); release (Phase 10).

## 2. Starting facts (verified)

- `TripsRepository`/`BookingRepository` are Mock-backed (`MockTripsRepository`,
  `MockBookingRepository`); `FareRepository` has `SupabaseFareRepository` (RPC
  `rider_create/update_booking_draft`, `rider_lock_fare_quote`, `rider_confirm_booking`;
  Edge `fare` quote op). Drafts already carry `paymentMethod`.
- Phase 3 (`005`–`022`) provides payment/attempt/refund/receipt/webhook-ID foundations;
  P5 (`025`/`026`) provides pricing/quote-lock. Cash display exists; trusted Cash
  settlement is not yet Flutter-connected. No `payment_repository.dart` exists yet.
- No dedicated admin feature folder exists (TO VERIFY exact admin surface before P6-08).

## 3. Task decomposition

| ID | Title | Owner | Depends | Branch (suggested) |
|----|---|---|---|---|
| P6-01 | Cash payment domain contract | Dev 1 | none | `feature/p6-cash-contract` |
| P6-02 | Cash settlement backend wiring | Dev 1 | P6-01 | `feature/p6-cash-backend` (Sprint 3+) |
| P6-03 | Card payment domain contract | Dev 1 | P6-01 | `feature/p6-card-contract` |
| P6-04 | Stripe Test Mode intent interface | Dev 1 | P6-03 | `feature/p6-stripe-intent` (Sprint 3+) |
| P6-05 | Rider payment selection + fare-lock handoff | Dev 2 | P6-01 draft (cash; card placeholder until P6-03) | `feature/p6-rider-payment-ui` |
| P6-06 | Rider payment states + receipt presentation | Dev 2 | P6-01, P6-03 | `feature/p6-rider-payment-states` |
| P6-07 | Driver cash-completion hook | Dev 3 | P6-01, P6-02 draft | `feature/p6-driver-cash-completion` |
| P6-08 | Admin sanitized payment visibility | Dev 3 | P6-01 (cash scope Sprint 1; card columns after P6-03) | `feature/p6-admin-payment-visibility` |
| P6-09 | Contract compatibility harness | Dev 1 | P6-01…P6-08 | `feature/p6-contract-harness` (Sprint 3+) |
| V4-01 | Two-device verification (4.38) | Dev 3 | devices | no code branch |
| V4-02 | Blank-map diagnosis | Dev 3 | device logs/certs | no code branch (fix branch only if needed) |
| V5-01 | Hosted Rider-RLS recovery/confirm checks | Dev 2 | hosted access | no code branch |
| V5-02 | Android confirm + repeat-booking (B1/B2) | Dev 2 | hosted + device | no code branch |
| V5-03 | Multi-stop physical verification | Dev 3 | device | no code branch |
| V5-04 | Lost-response/restart recovery checks | Dev 2/3 | device | no code branch |

Sprints 1–2 implement P6-01, P6-05, P6-08, P6-03, P6-06, P6-07.
P6-02/P6-04/P6-09 are Sprint 3+ (high-level; re-plan from latest repo state).

## 4. Contract-first order

1. Dev 1 publishes P6-01 draft interface early Day 1; Dev 2/3 build against fakes.
2. Dev 1 publishes P6-03 draft early Sprint 2; UI stays mock-backed.
3. P6-09 compatibility tests gate P6-02/P6-04/P8 integration. No production wiring
   against unreviewed contracts.

## 5. Ownership and shared files

- P6-01/P6-03: NEW `lib/core/models/payment*.dart`, `lib/core/repositories/payment_repository.dart`,
  `test/payment_*_test.dart`. `repositories_providers.dart`: read-only in Sprints 1–2
  (wiring deferred to P6-09); any edit needs Dev 1 + Integration Owner approval.
- P6-05: `lib/features/booking/**`, fare screens; tests beside them.
  Reuses `/rider/fare`; no `app_router.dart` production change.
- P6-06: `lib/features/history/**`, `lib/features/trips/**` presentation only;
  no `MockTripsRepository` rewrite (Phase 8 owns it).
- P6-07: `lib/features/driver_home/**`, `driver_application/**`, trip completion
  presentation; calls existing trusted completion path only; never sets paid client-side.
- P6-08: new read-only widgets + tests; no guard/router/RLS change; exact admin
  surface TO VERIFY before implementation.
- Migrations/Edge: no new files in Sprints 1–2. Any later migration is additive,
  Dev 1-numbered, separately authorized.

## 6. Acceptance + tests (per task)

- Each P6 task: acceptance in its DEVELOPER file; required focused tests listed there;
  `flutter analyze` clean; full non-live suite at sprint boundary.
- Blocked labels: P6-02/P6-04/P6-07 financial-execution claims blocked until hosted
  evidence (V5-01/V5-04) exists; UI/contract work is not blocked.
- Carry-over V-tasks never reimplement completed functionality; evidence only.