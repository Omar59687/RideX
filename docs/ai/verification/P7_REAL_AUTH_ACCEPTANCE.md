# P7 real local Auth acceptance

Baseline: `9aab49971d6d21358c61908f6574b3dc35243f2b`.

Run `python supabase/tests/ops/p7_real_auth_http_acceptance.py` from the repository root. It creates new uniquely named/labeled containers and a new internal network, checks a free explicit subnet (Docker default pools are exhausted on this machine), publishes no ports and uses no existing stack or keys. PostgreSQL uses a fresh /tmp cluster; its trust rule is restricted to that private subnet. Cleanup verifies ownership labels before removing only resources from that invocation. No hosted calls or Cron activation.

Images: PostgreSQL 17.11 (`public.ecr.aws/supabase/postgres:17.11.0.006`), GoTrue v2.197.0, PostgREST v16.5. Cached image digests can be inspected with `docker image inspect`; target production versions remain a separate catalog preflight. GoTrue creates real users, identities and sessions via its own migrations. Only standard API roles/Auth helper functions/extensions are bootstrapped by the harness; no synthetic auth.users or auth.sessions table is substituted. GoTrue DB search_path=auth and default JWT group authenticated are explicit test configuration.

## Actual result

**26 PASS / 0 FAIL / 0 SKIP** after a full 36-application-migration replay on the real Auth schema. The final run proves:

- GoTrue-owned session table; two real signups and two password sign-ins.
- Authoritative /user identity, real JWT session_id association, positive PostgREST session/admission RPCs.
- Missing, invalid and expired JWT rejection at PostgREST.
- Real Rider profile and Booking isolation, including positive own-Booking read and empty foreign-Booking read.
- Read-only deployment preflight executes against this real Auth schema.
- Blocked Rider session/admission rejection.
- Actual HTTP requests through admission 30 succeed, then the 31st fails the budget (RPC returns false; the Edge maps false to HTTP429 in separately passing Deno tests).
- Rider cannot invoke privileged expiry or batch scheduler RPCs.
- Real GoTrue global logout succeeds and deletes the session; its still-unexpired JWT fails the database session check and matching admission.

The harness's early iterations found local test-stack configuration issues (Docker pool exhaustion, missing subnet pg_hba entry, GoTrue search_path and default group, and empty 204 response parsing). These were fixed in the harness, not by weakening application permissions or replacing real Auth with fixtures. No application security defect was inferred from those configuration failures.

## Precise limitations and hosted acceptance procedure

This is real local GoTrue/PostgREST HTTP evidence, not a deployed Edge Function gateway test, hosted verification, Realtime delivery, device E2E or atomic revocation guarantee. The direct local services have no Kong/API-key gateway; production public-key routing and JWT gateway configuration require target acceptance. The fixed-minute rate test pins the private budget window in the disposable DB to avoid a minute-boundary flake. Existing independent-session tests verify serialization/rollback. Deno tests separately verify HTTP429/Retry-After and malformed Auth/profile/session responses fail closed without privileged matching writes.

After explicit owner approval of one nonproduction project and named Rider/Driver accounts, repeat the positive /user, cash-matching, own/foreign Booking and 30/31 admission cases through the deployed gateway. Confirm session_id linkage read-only using the approved operator connection, log out through GoTrue, and prove the still-unexpired token is denied by cash-matching. Repeat blocked/expired/missing/invalid cases, record sanitized status/error codes and canonical rows, and never record tokens/passwords/keys. Use the deployment runbook for grants/preflight and the Moath handoff for Cash Booking/Driver fixtures. Hosted evidence remains NOT RUN.

A session check and a subsequent service-role matching mutation remain separate transactions. Logout after a check can race an in-flight operation; this work does not claim rollback or atomic revocation across that boundary. Time-box/inactivity/single-session policy semantics also require the actual target Auth configuration.
