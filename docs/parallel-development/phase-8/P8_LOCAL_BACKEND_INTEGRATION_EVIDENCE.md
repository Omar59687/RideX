# P8 local backend integration preview — evidence

Status: **READY for independent local source review; NOT financial or hosted acceptance**. No hosted Supabase, live Stripe, Card activation, provider dispatch or financial transitions were performed. Preview branch `feature/p8-local-backend-integration-preview` starts at A06 `7ae33f3e03cc46c6ee7208386abb575308bb7146`; the evidence commit is `git rev-parse HEAD`.

## Sources and integration

- A02 local `feature/p8-a02-trusted-payment-lifecycle`: `77654881d9fc8a440b13ad50452cd78c8796c590`.
- A03 committed local `feature/p8-a03-provider-webhook-recovery`: `48511c3446f563fc46f6a122bee01ca57e27ac18`.
- A04 published `364b63edb267e47c8795b34d20302f526e85845e`; A05 published `46f76e8176274b0f32a7930668337c5f1d698b9f`; A06 published `7ae33f3e03cc46c6ee7208386abb575308bb7146`.

A02 is not an ancestor of A03; their four A02 migration files have the same version and content. This preview imports the reviewed committed A02/A03 backend tree as a local integration commit, not a branch merge. It retains A04/A05/A06 files and the A04 privacy-hardening tests, including their expected errors. Only A02/A03 additions and the reviewed `supabase/config.toml` and Cash matching adapter changes were selected. No A03 uncommitted provenance draft was imported. No schema conflict or integration-only production fix was observed; the new files in this checkpoint are the safety test and reproducible runner. No UI or R06-X2 migration was changed.

## Fresh combined verification

`python supabase/tests/ops/p8_local_integration_test.py` creates a fresh PostgreSQL Docker container with no network, mounts or published ports; verifies isolation; applies **46 migrations**, with exact migration history, unique versions and zero recovery approvals; then uses disposable database clones. The complete chain includes A02, A03 and A04 in lexical order. A second independent fresh run after adding the fake concurrency test produced:

| Test | Passed |
| --- | ---: |
| A02 gate/ACL | 4 |
| A03 admission | 10 |
| Integration gate/quarantine/R06 access safety | 12 |
| A04 legacy privacy / canonical reads | 25 / 29 |
| Existing legacy security `019` / `020` | 15 / 36 |
| Cash booking / Cash booking race | 32 / 7 |
| Local fake identity | 14 |

Total **184 pgTAP**, zero failures, plus **1** local fake-identity race with a real lock waiter and one durable fake identity. The fake gate is enabled only inside the isolated fake fixture; the Card gate remains OFF. Test fixtures insert initial synthetic rows but execute no financial transition RPC. Admission leases operate only on the test limiter. No production financial table is reached by the fake identity fixture.

Deno commands used no network permissions and use in-memory fake dependencies:

```powershell
deno test --no-config --no-lock supabase/functions/cash-matching/core_test.ts supabase/functions/cash-matching/security_test.ts supabase/functions/_shared/matching/cash_matching_adapter_test.ts supabase/functions/_shared/matching/cash_matching_auth_acceptance_test.ts supabase/functions/card-authorization/core_test.ts
deno test --no-config --no-lock supabase/tests/fakes/local_fake_identity_test.ts supabase/functions/_shared/payments/provider_evidence_test.ts supabase/functions/_shared/payments/stripe_test_evidence_test.ts supabase/functions/_shared/payments/stripe_webhook_quarantine_test.ts supabase/functions/_shared/payments/stripe_webhook_verifier_test.ts supabase/functions/stripe-test-webhook/admission_test.ts supabase/functions/stripe-test-webhook/core_test.ts
deno test --no-config --no-lock --filter 'R06-X2 permanent fence stops' supabase/functions/_shared/payments/test_intent_reservation_test.ts
```

Results: **78/78**, **31/31**, and **4/4** selected R06-X2 tests respectively. The R06-X2 tests are selected dispatch fences, not full recovery acceptance. The Card database gate is OFF; test webhook intake is default OFF and provider dispatch is hard OFF in `stripe-test-intent/index.ts`. The fake provider is under `supabase/tests/fakes/`, is not a production endpoint, and its observer output is non-authoritative. Privileged quarantine and identity operations retain server-role restrictions; the checks here do not prove an independently verified real-provider trust boundary.

## Exclusions and remaining blockers

- Historical `009_phase3_payment_receipt_foundation.test.sql`, `p8_a02_gated_card_matching.test.sql`, A02 matching races, A03 broad quarantine/HTTP fixtures and their concurrency setup were **not run**: they enable Card or invoke synthetic authorization, capture, refund, or financial transitions. No blanket R06-X2 recovery run was performed. No hosted or real-provider tests were run.
- Durable provider account/environment provenance, authorization-to-capture identity, verified real-provider evidence, atomic reconciliation, financial concurrency and safe UNKNOWN resolution remain incomplete. There is no Stripe account or credential. No financial success is inferred from fake evidence.
- Historical hosted R06-X2 parity is **NOT VERIFIED**; see issue #149 and the A06 readiness record. Existing Driver `P0002`/`missing` semantics and Omar/Sanad read-model integration require separate consumer coordination. Backup/restore and staging approvals remain outside this preview.

Next: independent security and integration review of the exact candidate and conflict/privilege semantics, followed by owner-approved work on the remaining trust boundary and a separately authorized acceptance plan. This preview does not authorize merging, deployment, financial execution or activation.
