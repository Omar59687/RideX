# Phase 6 Payments — Reconciled Integration (Draft)

Base: main at b1f74c493d15a2fef6d62f761e29372805229571 (merged PR #50).
Sources: PR #47 at af5942730445feb2413e2bef611f323137f7ba7b; PR #51 at 180b0cc6073a113552c923b24afa7334c8254c27.

## Deliberate reconciliation
- Preserve current main Admin screen/widgets and session/Driver B1-B ownership.
- Bring forward #47's Cash completion/recovery composition, Stripe Test Mode interface, canonical payment repository and isolated regression coverage.
- Bring forward #51's migration-027 RPC Admin reader and matching production provider; no second production Admin reader.
- Do not bring forward #47's legacy CanonicalAdminPaymentReader composition, or overwrite main's sprint tracker.
- Preserve legacy canonical payment repository tests as *isolated* contract tests, not as tests of the production Admin provider. The production Admin path is solely the server-authorized RPC.
- Union the architecture allowlist for both core infrastructure adapters.

## Gates — NOT APPROVED
This is an integration candidate, not a release approval. No Flutter/TypeScript/DB tests were executed on this combined tree by the GitHub connector. The 1420 PASS / 2 SKIP / 0 FAIL evidence applies only to #51 before integration; #47's 1480 PASS / 2 SKIP evidence applies only to its prior branch. Neither result may be claimed for this new tree.

Before merge: independent financial/security and architecture review; run full Flutter suite, analyze, Stripe transport tests, relevant DB tests, diff/format checks. Hosted role/device checks remain deferred/not verified. Cash production wiring and Stripe financial operations remain disabled. No migrations, production secrets or hosted payment actions changed. Do not merge #47 or #51 as part of this operation.
