# R08 Cash Only acceptance report

Date: 2026-11-02

Branch: `feature/r08-cash-only`

Base: `origin/main` at `52840b10f266cf73bf4f5057633fda95933e0d71` (PR #87)

Status: **R08 CASH ONLY READY FOR REVIEW**

Phase 6 and Production are **NOT APPROVED**.

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

**R08-focused pgTAP: PASS (owner-supplied run evidence).** The reported isolated
local project is `ridex-r08-local-test`, PostgreSQL 17, with all 31 migrations
applied. Both
`20261028150000_cash_only_rider_booking_confirmation.test.sql` and
`20261028150001_cash_only_booking_confirmation_concurrency.test.sql` passed.
The exact raw output, command, and run timestamp were not available in the
worktree for independent log inspection; the project/version/migration/test
results above are recorded from the supplied evidence summary.

**Full database suite: FAIL (failures classified as unrelated to R08 from the
supplied summary).** The run reports 44 files, 1,242 tests, exit code 1. The
detailed terminal transcript was not attached, so this classification uses the
reported failing filenames, assertion numbers, and error excerpts.

1. `013_phase3_rls_rpc_hardening.test.sql`, test 11, expects exactly 20
   service-role-only `public.backend_*` functions and finds 21. R08 replaces
   `public.rider_confirm_booking`; it does not add a `backend_*` function. The
   R06 X2 migration adds
   `public.backend_record_stripe_test_preparation_fenced`, which accounts for
   the extra function. This is a stale inventory-count assertion following R06
   evolution, not a Cash-only authorization regression. Do not weaken the
   service-role privilege checks.
2. Tests 39, 51, and 75 in
   `20261028140221_r06_x2_reserved_recovery.test.sql` report a scalar subquery
   returning multiple rows. The failing file and tested recovery surface are
   R06 X2; the summary also reports that the test runner executed seed fixtures
   separately. Fixture contamination is a plausible cause, but the omitted
   assertion/SQL context prevents proving the exact link. This is an R06
   follow-up, not evidence of an R08 Cash confirmation defect.
3. `20261028140223_r06_x2_evidence_boundaries.test.sql` reports a duplicate
   `users_pkey`; the discovered fixture files report duplicate user/approval
   keys or `extensions` already existing. Fixture files under
   `supabase/tests/database/fixtures/` were erroneously discovered as tests and
   several report "No subtests run". This is incorrect recursive test
   discovery and R06 fixture/test isolation contamination.

No failure names either R08-specific pgTAP test. The focused reviewer found no
R08 code defect. The older
`007_phase3_booking_fare_matching_foundation.test.sql` confirmation fixture
uses Cash, so its confirmation expectation remains compatible with the Cash-only
guard.

The preceding local tooling attempt in this worktree could not fetch the
PostgreSQL image, but the supplied run now provides separate isolated PG17
evidence. No database migration was deployed from this worktree; no hosted
project was linked or contacted, and no Production request occurred.

## Remaining device and hosted checks

- **Physical device:** no R08-specific physical-device gate is required for this
  Cash-only scope; the original R08 task allows scope/widget acceptance without
  a device. Native Stripe PaymentSheet checks do not apply while Stripe is
  deferred. Broader app restart, Rider/Driver, and trip-flow device acceptance
  remains with its existing release gates.
- **Full-suite follow-up:** repair/classify the stale R06 backend-function
  inventory count and restrict pgTAP discovery to actual test files so fixture
  SQL is not executed as a standalone test. Investigate the three R06 X2
  scalar-subquery failures in their intended fixture-isolated runner. These are
  outside R08; do not weaken the privilege assertion or alter R06 code as part
  of this closeout. The supplied failure summary lacks the full assertion
  context, so retain the exact scalar-subquery causal link as unproven.
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
   database. **Met by owner-supplied evidence** for `ridex-r08-local-test` on
   PostgreSQL 17 with 31 migrations applied; raw log inspection remains pending.
5. Establish that no full-suite failure is an unresolved Cash-only security
   regression. **Met based on the supplied failing-file/test summary and focused
   independent review.** The remaining failures are an R06 function inventory
   count drift and R06 X2 fixture/discovery/test-isolation failures; their
   cleanup is a separate R06/database-harness follow-up.
6. Record explicit owner approval of the bounded Cash-only disposition. Approval
   evidence is not present in this work.

**Recommended owner decision:** explicitly accept the bounded R08 Cash Only
scope and record that approval. The focused Flutter evidence and both isolated
R08 pgTAP tests pass, independent review found no R08 defect, and the reported
full-suite failures are in an outdated R06 function-count assertion and R06 X2
fixture/discovery/test-isolation cases. Keep the full-suite failure and R06
follow-up visible; a green full database suite is not represented as achieved.
Do not label R08 accepted until the owner's approval is recorded. Hosted
non-Production checks are a separate, explicitly authorized follow-up only if
the owner requires them; Production, Stripe, migrations deployment, and
financial operations remain out of scope.

R09 planning and code/integration review may proceed in parallel. Record the
R06 full-suite test-harness failures separately; do not treat this bounded R08
decision as Phase 6 acceptance. R08 remains READY FOR REVIEW until the owner
records acceptance. Direct main integration was authorized for this
documentation only; it does not authorize product changes, Phase 6 approval, or
Production activity.
