# P8-A05 local backend verification evidence

Date: 2026-11-22. Local verification only; no hosted acceptance, provider dispatch, financial transition, Card activation, push or deployment. A05 is PARTIAL.

## Component inventory and decisions

| Component | Status | Local decision and boundary |
| --- | --- | --- |
| A01 | IMPLEMENTED; consumer approval pending | GO for contract review, not financial rollout. Published `feature/p8-a01-payment-contracts`, `93d17481fc341590c9ff97d3c60e966106c9c511`. |
| A02 | IMPLEMENTED; PARTIALLY TESTED | GO for gate/ACL review; NO-GO for financial acceptance. Local branch `feature/p8-a02-trusted-payment-lifecycle`, `77654881d9fc8a440b13ad50452cd78c8796c590`. Card lifecycle and concurrency acceptance blocked by no-transition/no-activation restriction. |
| A03 | IMPLEMENTED; PARTIALLY TESTED | GO for local fake/read-only review; NO-GO for real-provider acceptance or recovery. Local branch `feature/p8-a03-provider-webhook-recovery`, `48511c3446f563fc46f6a122bee01ca57e27ac18`. The uncommitted provenance draft is excluded. |
| A04 | IMPLEMENTED and locally TESTED | GO for team integration review; NO-GO for hosted or production acceptance. Published `feature/p8-a04-financial-read-apis`, `364b63edb267e47c8795b34d20302f526e85845e`. |
| A05 | PARTIAL | Selected tests passed; full financial state, recovery and integrated acceptance remain blocked. No A06 work. |

A05 was created at A04 `364b63e`; fetched `origin/main` was `3be1aa67eecb49ce95ea77077b63964eb3cbc62c`, an ancestor of A04. This report is committed with A05 test-only changes; use `git rev-parse HEAD` for the evidence commit.

## Environment and results

Fresh disposable PostgreSQL containers used `--network none`, no host ports or mounts; the runner asserts these properties. Bootstrap and each worktree's own migration chain were replayed in new databases. These are **separate runs**, not integrated A02/A03/A04 acceptance. Read fixtures insert synthetic initial records; no payment or Trip transition, authorization, capture, refund, or provider dispatch is invoked. Deno tests use fake transports without network permissions.

| Run | Result |
| --- | --- |
| A04/A05 `364b63e` plus A05 test assertion | 38 migrations; A04 legacy privacy **25**, A04 reads **28** initially and **29** after the service-role history-grant assertion; legacy security **15 + 36**; Cash booking **32**, Cash booking race **7** pgTAP. |
| A04/A05 Cash Deno | **65/65** matching core, security, adapter and auth acceptance. |
| A02 `7765488` | 40 migrations; A05 read-only A02 gate/ACL probes **4/4**. Gate remained OFF. |
| A03 clean verification worktree `48511c3` | 44 migrations; webhook admission **10/10** pgTAP. |
| A03 fake-only suite `48511c3` | 44 committed migrations; fake identity **14/14** pgTAP; **1** real lock-waiter race; Cash booking **32/32**, race **7/7**. Untracked provenance migration was excluded. |
| A03 Deno on original checkout | **23/23** webhook/admission, fake observer and fake Stripe-read unit tests; the four pre-existing draft files were not imported by those tests or edited. |
| R06-X2 | **4/4** filtered dispatch-fence Deno tests on A05 and **4/4** on clean A03; not full recovery coverage. |

Independent SQL review found no actionable migration-order, grant, RLS or isolation defect. It identified a missing explicit service-role history EXECUTE assertion; A05 adds it, and **29/29** A04 read assertions pass. Selected tests cover foreign/nonexistent and blocked actor privacy, cross-link rejection, malformed identifiers, deterministic pagination and direct financial RLS; this is not a hosted audit. An existing Driver adapter calls a `P0002` receipt result `missing`; it must remain unverified, as documented in `P8_A04_FINANCIAL_READ_CONTRACT.md`.

## Reproduction commands

Set `$env:PYTHONDONTWRITEBYTECODE='1'` to avoid worktree caches. From A05:

```powershell
python supabase/tests/ops/p8_a04_financial_reads_local_test.py
deno test --no-config --no-lock supabase/functions/cash-matching/core_test.ts supabase/functions/cash-matching/security_test.ts supabase/functions/_shared/matching/cash_matching_adapter_test.ts supabase/functions/_shared/matching/cash_matching_auth_acceptance_test.ts
deno test --no-config --no-lock --filter 'R06-X2 permanent fence stops' supabase/functions/_shared/payments/test_intent_reservation_test.ts
```

From A02, create an A02-only isolated database and load the A05 read-only probe (the Python command creates a new container and database):

```powershell
python -c "import sys; from pathlib import Path; sys.path.insert(0,'supabase/tests/ops'); import r06_x2_local_test as h; c=h.create_cluster(); b=h.build_database(c); h.tap(c,h.clone(c,b),Path('../RideX-Phase8-Yousuf-A05/supabase/tests/database/p8_a05_a02_gate_read.test.sql'))"
```

From clean `RideX-A03-fake-verification` at `48511c3`, the admission test uses a fresh A03-only cluster:

```powershell
python -c "import sys; from pathlib import Path; sys.path.insert(0,'supabase/tests/ops'); import r06_x2_local_test as h; c=h.create_cluster(); b=h.build_database(c); h.tap(c,h.clone(c,b),Path('supabase/tests/database/p8_a03_webhook_admission.test.sql'))"
python supabase/tests/ops/p8_a03_local_fake_identity_test.py
deno test --no-config --no-lock --filter 'R06-X2 permanent fence stops' supabase/functions/_shared/payments/test_intent_reservation_test.ts
```

The following A03 unit command was run in the original A03 checkout, with its unrelated uncommitted provenance draft preserved:

```powershell
deno test --no-config --no-lock supabase/tests/fakes/local_fake_identity_test.ts supabase/functions/_shared/payments/provider_evidence_test.ts supabase/functions/_shared/payments/stripe_test_evidence_test.ts supabase/functions/_shared/payments/stripe_webhook_quarantine_test.ts supabase/functions/stripe-test-webhook/admission_test.ts supabase/functions/stripe-test-webhook/core_test.ts
```

## Exclusions and dependencies

- Historical `009_phase3_payment_receipt_foundation.test.sql` invokes successful authorization, capture, Payment transitions and refunds: **BLOCKED**, not executed. A02 `p8_a02_gated_card_matching.test.sql` and lifecycle races enable Card and perform synthetic financial transitions: **BLOCKED**, not executed. A03 broad quarantine/HTTP fixture includes that setup: **BLOCKED**, not executed. Live and hosted tests were not run.
- A02/A03 migration histories were not combined with A04. A03 unapproved provenance draft remains uncommitted and is not accepted evidence. No Stripe credentials exist; provider account provenance, capture identity, real-provider evidence, atomic financial reconciliation, UNKNOWN recovery and integration remain incomplete.
- A04 can proceed to team integration review only. Omar needs explicit unverified Receipt handling; Sanad needs authorized additional fields/mapping for the history model. The Driver `P0002`/`missing` mismatch needs coordinated consumer work. A04 RPCs are not hosted.
