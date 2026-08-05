# Phase 3 Contract Remediation Verification

Date: August 5, 2026

## Scope

- Branch: `codex/phase-3-contract-remediation`
- Original implementation commit: `fd154fcab466f154d26490a440b046f81c7bfc6f`
- Corrective implementation commit: `5564bc8`
- Local only. No Supabase project linking, remote query, remote SQL, migration
  deployment, `db push`, deployment, push, merge, or Pull Request occurred.

## Environment

- Docker Engine: `28.3.2`
- Supabase CLI: `2.111.0`
- PostgreSQL: `17.6`

## Commands And Results

| Command | Result | Exit status |
|---|---|---|
| `npx supabase@latest db reset --local` | Applied migrations `001` through `020` in order | `0` |
| `npx supabase@latest test db --local supabase/tests/database/020_phase3_driver_finance_exposure_correction.test.sql` | `Files=1, Tests=36, Result: PASS` | `0` |
| `npx supabase@latest test db --local` | `Files=17, Tests=825, Result: FAIL`; immutable test `019` exited `3` after its obsolete assigned-Driver Payment expectation | `1` |

The reset emitted the existing informational `supabase/seed.sql` no-match warning.
It did not affect migration application or test results.

## Second Contract And Security Review

Reviewed the Phase 2 contract, remediation design and implementation plan, full
RLS/grant/function matrix, migration `020`, focused regression coverage, and the
clean-reset results above.

- Finance tables retain no authenticated `SELECT` RLS policies. Whole-row
  client queries therefore return no rows, while stable participant-authorized
  RPC summaries expose only approved Payment, PaymentAttempt, Refund, and
  Receipt fields. Provider references and idempotency keys remain backend-only.
- Direct client writes remain denied. Anonymous access remains denied. Blocked
  users fail closed; an assigned Driver can read only the restricted Receipt
  summary for the assigned Trip and cannot read Payment, PaymentAttempt, or
  Refund summaries.
- HelpRequest subject, message, and Admin resolution reject PAN-like digit
  sequences and CVV/CVC disclosures before persistence or audit logging.
- Notification payloads remain recursively safety-checked and now permit only
  an explicit destination allowlist with the corresponding UUID identifier.
- The authorized 3R.4 compatibility updates to tests `009`, `010`, and `013`
  replace their direct finance-read expectations with the safe-summary boundary.
- The confirmed Driver finance authorization defect is corrected by `020`, and
  focused role/resource coverage passes. The required complete-suite pass is
  blocked because immutable test `019` still expects the now-forbidden assigned
  Driver Payment summary. Preserving that expectation would weaken the approved
  boundary, so no bypass was added.

## Completion

Checkpoint 3R.4C implementation is committed, but Phase 3 backend-foundation
remediation is not complete. Local Supabase must be stopped after the
documentation commit and final worktree inspection. Phase 4 remains out of scope
and blocked pending an approved resolution of the immutable-test conflict, review,
push, and merge approval on a separate branch.
