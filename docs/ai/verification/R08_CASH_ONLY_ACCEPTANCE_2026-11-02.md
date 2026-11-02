# R08 Cash Only acceptance report

Date: 2026-11-02

Branch: `feature/r08-cash-only`

Base: `origin/main` at `52840b10f266cf73bf4f5057633fda95933e0d71` (PR #87)

Status: **R08 CASH ONLY READY FOR REVIEW**

## Scope decision

R08 is bounded to the existing Cash booking flow. Cash remains the only
confirmable method. Card can be selected on a draft for persisted-state
compatibility, but is marked unavailable, cannot be converted after fare lock,
and cannot be confirmed. Stripe, hosted card entry, provider configuration,
authorization/capture, and Production are explicitly deferred. No backend
deployment, hosted request, payment operation, or financial state change was
performed.

The existing Cash/Card review behavior was inspected and the reported
selection/state inconsistency is not reproducible on current `origin/main`:
the review screen reads the canonical booking and locked FareQuote, displays the
persisted booking method instead of session-local selection, and revalidates
the same booking before continuation. A Card-locked booking remains blocked.
No implementation defect was found, so no code change or additional regression
test was warranted.

## Verified locally

- Cash is the default selection; selection is session-local UI intent and the
  method captured for the canonical quote/draft request matches the request key.
- The payment review reads by canonical booking ID and Rider ID, checks the
  booking/FareQuote lineage, and re-reads before continuing.
- Cash review hands off to booking confirmation without claiming that a payment
  occurred. Confirmation revalidates the canonical locked lineage and is
  idempotent; canonical Card is rejected and prior confirmed Card bookings can
  be recovered without mutation.
- Recovery tests cover exact booking/quote identity, stale or changed method,
  session changes, and ambiguous/replayed operations.
- The Cash-only confirmation migration preserves authenticated authorization,
  version/lock/idempotency/audit checks, rejects new Card confirmation, and
  returns historical confirmed bookings unchanged. Its pgTAP suite includes
  direct Card RPC rejection and checks that the booking status/version and audit
  state remain unchanged.

Reused local Flutter evidence from the preceding R08 audit on this same base
commit (HEAD remains `52840b10f266cf73bf4f5057633fda95933e0d71`). Preflight
confirmed no product-code or test changes since those runs:

- Focused payment/booking/recovery/selection suite: **108 passed, 0 failed**.
- Full non-live Flutter suite: **1,664 passed, 0 failed, 2 intentional live
  skips**.
- `flutter analyze --no-pub`: **No issues found**.

Evidence covers `test/payment_method_screen_authority_test.dart`,
`test/payment_method_screen_test.dart`,
`test/booking_confirmation_handoff_test.dart`,
`test/fare_lock_recovery_test.dart`, and
`test/rider_payment_selection_test.dart`; the full suite adds all project
non-live and Driver regressions. No test was rerun during this fast closeout.

## Independent review

Focused independent review: **PASS**. The reviewer inspected the Cash
selection/canonical authority, existing Card-locked recovery, Cash-only
confirmation and ownership guards, relevant pgTAP assertions, and this report.
No product defect or additional test gap was found. The reviewer did not run
tests or database operations.

## Database verification outcome

**NOT VERIFIED — ENVIRONMENT BLOCKED.** Docker Engine is available (`28.3.2`),
but the required local database image
`public.ecr.aws/supabase/postgres:17.11.0.006` is not cached. In the preceding
attempt, Docker registry TLS handshakes timed out while pulling Supabase images;
a Postgres-only local start then stalled before creating a container and was
stopped. The minimal preflight rechecked Docker/image availability once and did
not retry downloads. No database container, migration replay, pgTAP run, hosted
project link, or Production request occurred.

## Remaining device and hosted checks

- **Physical device:** no R08-specific physical-device gate is required for this
  Cash-only scope; the original R08 task allows scope/widget acceptance without
  a device. Native Stripe PaymentSheet checks do not apply while Stripe is
  deferred. Broader app restart, Rider/Driver, and trip-flow device acceptance
  remains with its existing release gates.
- **Local database (mandatory before R08 acceptance):** when the Postgres image
  is available, start an isolated local stack and run the R08 Cash confirmation
  pgTAP tests against a fresh local migration sequence, including the preceding
  R06 X2 migration and
  `20261028150000_cash_only_rider_booking_confirmation.sql`:
  `20261028150000_cash_only_rider_booking_confirmation.test.sql` and
  `20261028150001_cash_only_booking_confirmation_concurrency.test.sql`.
  Confirm Cash succeeds; new Card is rejected without status/version/audit
  mutation; the pre-existing confirmed Card recovery is unchanged; ownership,
  blocked-Rider, stale-version, and locked-quote guards remain effective; and
  the concurrent Cash idempotency case has one canonical outcome.
- **Hosted non-Production:** no hosted check was run or is authorized by this
  R08 work. If separate hosted acceptance is required, first name and authorize
  a non-Production project and isolated synthetic Rider/booking fixtures. Verify
  the same RPC positive/negative matrix and retain project identity, migration
  versions, run logs, and resulting canonical booking/version/audit evidence.
  Do not use Production, protected R06 actors/fixtures, Stripe, or financial
  operations.

## Deferred dependencies

Real matching and accepted Trip identity belong to Phase 7. The complete Trip
lifecycle and Phase 8 payment authorization/capture, receipts, refunds, and
history remain later work. R08 does not establish a matched ride or settled
payment.

## Review and approval

### Explicit acceptance criteria

1. Keep all new confirmation Cash-only; Card remains unavailable, with no
   client-declared payment success or financial action.
2. Preserve canonical booking/Rider/FareQuote identity, ownership, optimistic
   version, locked-quote, idempotency, and session checks.
3. Preserve read-only recovery for historical confirmed Card bookings.
4. Run both named Cash-only pgTAP tests successfully against an isolated local
   database. This criterion is **not met** because the environment could not
   obtain the Postgres image.
5. Record explicit owner approval of the bounded Cash-only disposition. Approval
   evidence is not present in this work.

**Recommended owner decision:** retain **R08 CASH ONLY READY FOR REVIEW**; do not
mark R08 accepted yet. Approve the bounded scope disposition, then require the
two local pgTAP suites to pass and record the owner's explicit approval before
changing the status to accepted. Hosted non-Production checks are a separate,
explicitly authorized follow-up only if the owner requires them; Production,
Stripe, migrations deployment, and financial operations remain out of scope.

R09 planning and code/integration review may proceed in parallel, but R09 must
record R08's database blocker and must not treat R08 as accepted until its
mandatory pgTAP evidence and owner approval exist. No commit beyond this closeout
documentation, push, merge, or deploy is authorized.
