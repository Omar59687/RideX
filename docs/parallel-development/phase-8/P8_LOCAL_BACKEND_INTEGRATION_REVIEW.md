# P8 local backend integration — independent review

Reviewed candidate: `feature/p8-local-backend-integration-preview` at `187bc49e7150d2b054d146a8f6a9018374ea9459`. This record is documentation-only; obtain its commit with `git rev-parse HEAD`. No hosted operation, provider dispatch, Card activation, financial transition, merge or deployment was performed.

## Disposition

- **Integration source:** READY for independent team review of the local candidate; not a merge or deployment approval.
- **Security:** READY for review of the tested local scope; not a hosted security assessment. The read-only security reviewer found no actionable defect in the reviewed gates, ACLs, session boundary, quarantine, read privacy or R06-X2 source protections.
- **Financial lifecycle acceptance:** BLOCKED. Real provider credential/account provenance, authorization-to-capture identity, verified provider evidence, atomic reconciliation, UNKNOWN recovery and financial race acceptance remain incomplete. Local fake evidence is not financial authority.
- **Hosted deployment:** BLOCKED. R06-X2 hosted parity and backup/restore evidence remain unverified; target-specific owner approvals and independent financial/staging acceptance remain necessary. See `P8_A06_DEPLOYMENT_READINESS.md`.

## Integration review and verification

The 42 imported committed A02/A03 backend source blobs match A03 commit `48511c3446f563fc46f6a122bee01ca57e27ac18`; all 46 committed migration versions are unique. A04 migration/contract files are unchanged, and A05/A06 are ancestors of the candidate. A02's four migration versions and content match A03 despite divergent branch ancestry. No uncommitted A03 provenance draft was imported. The independent integration reviewer found no migration ordering, duplicate-version or RPC-wiring defect; the Cash adapter retains its Cash default.

Fresh network-isolated PostgreSQL replay: **46 migrations**, exact history, zero recovery approvals; **184/184 pgTAP**: A02 gate 4, A03 admission 10, integration safety 12, A04 privacy 25, A04 reads 29, legacy security 15 + 36, Cash 32 + 7, fake identity 14. One local fake-identity race passed with a real lock waiter. Deno tests with fake dependencies and no network permissions: **78/78** Cash/matching/authorization handler, **31/31** fake/webhook/observer, and **4/4** selected R06-X2 fences. `git diff --check` passed. The exact commands are in `P8_LOCAL_BACKEND_INTEGRATION_EVIDENCE.md`.

The A02 gated lifecycle and matching races, broad A03 quarantine/HTTP and concurrency fixtures, and historical `009` suite were excluded because they enable Card or execute financial transitions. Successful durable webhook reconciliation and full R06-X2 recovery/concurrency were not verified. These are coverage gaps, not passing results.

## Consumer dependencies

Omar must handle `user_trip_financial_read_v1` receipt `unverified` and legacy `P0002` as unverified, not proof of absence. Sanad must map `user_trip_history_v1` keyset results to authorized additional fields required by the history model, and independently verify Receipt linkage. The existing Driver adapter labels `P0002` as `missing`; its semantics need coordinated consumer work. See `P8_A04_FINANCIAL_READ_CONTRACT.md`. These are integration dependencies, not changes made in this review.
