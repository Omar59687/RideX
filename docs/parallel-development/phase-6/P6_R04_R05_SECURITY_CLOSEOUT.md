# R04/R05 security acceptance closeout — 2026-10-26

Repository base: `86e67cb056c7b5b6049e0b41d84f2b3745a34bee`, latest main,
including merged PR #67. Target: owner-approved isolated graduation-project
Supabase backend `ykasivejjchupswqyxpm`. No production release approval is implied.

**R04: PARTIAL / blocked on disposable blocked and demoted Admin acceptance.**
**R05: ACCEPTED for the bounded canonical Cash Trip/payment/receipt read UI.**
Phase 6 remains NOT APPROVED. This does not accept Card discovery/execution,
Stripe, multi-Trip history, receipt restoration or a general financial release.

## Evidence provenance

- **U01 — owner-attested device evidence, supplied for this closeout:** authorized
  Admin displayed the persisted paid Cash Payment, JOD 16.00; Admin logout and
  Rider navigation isolation passed. These device steps were not repeated.
- **U02 — owner-attested device evidence after PR #67:** owning Rider saw Paid,
  JOD 16.00 and Receipt Verified; refresh and logout/login passed. The existing
  second Rider saw no foreign canonical Trip/payment information. These device
  steps were not repeated and are not claimed as agent-observed recordings.
- **H01 — preceding authenticated R04 run:** Rider/Driver Admin RPC calls returned
  HTTP 403 / SQLSTATE 42501, anonymous returned HTTP 401 / 42501. Direct Payment
  and Receipt SELECT returned empty under authenticated RLS despite verified
  fixture existence; anonymous received insufficient-privilege errors. Attempt/
  Refund representative row denial was not proven because no such fixture rows
  existed. This successful run was not repeated.
- **H02 — preceding fresh owning-Rider SDK acceptance:** official SDK password
  authentication and getUser passed; exact canonical Payment identity, owner,
  Trip linkage, Cash paid status, 16,000 fils/JOD and Payment version 2 passed.
  Trip version 5/completed, backend Trip-to-Payment lookup and independent issued
  receipt read passed. One Payment and one matching Receipt were verified. This
  successful run was not repeated.
- **M01 — new read-only deployed catalog inspection:** Admin RPC retains an
  explicit 12-column return contract, current-profile Admin authorization,
  created_at descending / ID ascending ordering and LIMIT 50. No currently
  blocked Admin profile exists (count zero). No approved disposable demoted-Admin
  identity/provenance is available; current role alone cannot prove demotion.
- **C01–C04 — new actor execution in this closeout:** fresh official Supabase Dart
  SDK authentication and getUser verified Admin-A and the existing Rider-B.
  Current nonblocked profiles/roles were checked. Rider-B's SDK user ID differed
  from the known Payment owner returned to the authorized Admin. Each client
  used its own actual SDK session, not service-role impersonation. Both helper
  process and SDK exit codes were 0. Only sanitized booleans/counts/status codes
  were retained; passwords, JWTs and raw financial responses were not persisted.
- **L01 — new focused Flutter run on this base:** 88 PASS / 0 FAIL, exit 0;
  `flutter analyze --no-pub`: No issues found. Files: Admin R04 security,
  Admin mapper, Admin live reader, Admin integration and Rider canonical Trip
  detail tests. These are local loopback/mock/fixture tests, not hosted races.
- **S01 — historical local SQL evidence:** the existing R04 record reports
  103 pgTAP assertions PASS across migrations 019/020/027, including the
  deterministic 55-record Admin limit/order fixture. These were isolated,
  rolled-back local records. No SQL fixture script was rerun or sent to hosted.

Local temporary execution artifacts are not a durable project evidence store.
This record preserves the sanitized outcomes and provenance without importing
machine paths, credentials, private account identities or financial payloads.
Actor labels are Admin-A (approved Admin), Rider-A (Payment owner), Rider-B
(existing second Rider) and Driver-A (approved Driver).

After execution the owner identified Rider-B as `laith@demo.com` (a non-sensitive
account label). Read-only metadata confirms that label belongs to an existing
nonblocked Rider distinct from the Payment owner. The execution artifact retains
only Rider-B, not the entered email or SDK user ID; its authentication/getUser
checks verified the operator-entered identity in memory. This metadata/owner
label corroboration is not a replacement SDK authentication or a repeated test.

## Acceptance matrix

| Test | Actor | Expected | Actual evidence | Verdict | Reference |
|---|---|---|---|---|---|
| Authorized Admin UI | Admin-A | Canonical paid Cash display | Owner reports JOD 16.00 displayed on device | PASS, owner-attested | U01 |
| Admin list RPC denial | Rider-A / Driver-A | Denied | HTTP 403 / 42501 | PASS, prior hosted | H01 |
| Anonymous Admin list RPC | Anonymous | No execution privilege | HTTP 401 / 42501 | PASS, prior hosted | H01 |
| Direct Payment/Receipt SELECT | Rider-A / Driver-A | No finance rows | HTTP 200, empty under RLS for known existing rows | PASS, prior hosted | H01 |
| Anonymous direct finance SELECT | Anonymous | Insufficient privilege | HTTP 401 / 42501 for four financial tables | PASS, prior hosted | H01 |
| Admin list bounds/field redaction | Admin-A | At most 50, fixed fields, valid canonical values | HTTP 200, 1 row; exact field allowlist, financial validation and known-fixture presence passed | PASS for observed dataset/contract | C01 |
| Hard cap/order under more than 50 rows | Admin | Server-enforced LIMIT 50 and deterministic ordering | Deployed definition unchanged; historical local 55-record SQL fixture passed; no hosted over-limit dataset exercised | PASS contract/local; hosted boundary NOT RUN | M01, S01 |
| Admin UI redaction | Admin-A | Display DTO excludes IDs/provider payloads | Existing mapper/UI allowlist checks passed; no raw error payload display | PASS local; device display owner-attested | L01, U01 |
| Owning canonical Payment and independent Receipt | Rider-A | Exact owned persisted records | Fresh SDK read and receipt verification passed previously | PASS, prior hosted | H02 |
| Integrated Rider detail UI | Rider-A | Paid, correct amount, independently verified Receipt | Owner reports Paid, JOD 16.00, Receipt Verified; refresh/logout/login passed | PASS, owner-attested | U02 |
| Foreign canonical Trip discovery UI | Rider-B | No foreign information | Owner reports no foreign Trip/payment information | PASS, owner-attested | U02 |
| Foreign exact Payment ID RPC | Rider-B | No foreign Payment record | HTTP 200, 0 rows for the known existing Payment; actor is not its owner | PASS, new hosted | C02 |
| Foreign Trip-to-Payment RPC | Rider-B | Authorization denied | HTTP 403 / SQLSTATE 42501 | PASS, new hosted | C03 |
| Foreign Trip Receipt RPC | Rider-B | Authorization denied; no receipt details | HTTP 403 / SQLSTATE 42501 | PASS, new hosted | C04 |
| Logout / navigation isolation | Admin-A / Rider-A | Hidden protected data and isolated navigation | Owner-reported device checks passed | PASS, owner-attested | U01, U02 |
| SDK A-B-A, delayed reads, observed role/block changes, refresh ordering | Local fixtures | Reject stale publication | Focused local regressions passed | PASS LOCAL; hosted race NOT RUN | L01 |
| Blocked Admin hosted denial | Disposable blocked Admin | Denied by current-profile check | No blocked Admin exists; existing Admin was not changed | BLOCKED | M01 |
| Demoted Admin with stale session hosted denial | Disposable demoted Admin | Denied after role removal | No approved disposable demoted identity/retained session | BLOCKED | M01 |
| Representative direct Attempt/Refund row denial | Rider / Driver | No unauthorized rows | No representative records in approved fixture; prior empty responses alone are insufficient | BLOCKED for that representative case | H01 |

The foreign exact Payment response is intentionally empty, rather than an HTTP
authorization error. It is not mistaken for a missing fixture: authorized Admin
C01 verified the same known Payment existed, and the caller was a different
Rider. Conversely, C03/C04 are explicit authorization failures. No foreign
Payment or Receipt row/payload was exposed in any of these three responses.

The Admin RPC deliberately returns authorized canonical identities. Redaction
does not mean that authorized IDs disappear from the RPC: the UI mapper removes
them. The output excludes provider secrets, raw provider payloads, idempotency
keys, PAN/CVV and service credentials. One returned row proves the observed
bound, not stress behavior at 51+ hosted rows; the hard cap/order conclusion
also relies on the deployed source and historical local SQL contract test.

## Session-security limits and remaining work

Observed logout and normal logout/login/device navigation are accepted from the
owner's evidence. Deliberately delayed hosted RPC logout races, hosted SDK A-B-A
switching while a response is pending, cross-device/session concurrency, remote
Admin demotion/blocking during a hosted RPC and refresh-token/JWT-revocation
timing were not executed. Local regressions cover stale publication and observed
revocation; they are not substituted for hosted timing measurements. There is
no claim of instantaneous JWT invalidation, remote-profile detection or a
server-side freshness lease. Readers use bounded profile/session revalidation.

R05's stated bounded Cash read/UI gates are now supported by H02, U02, C02–C04
and the local security regressions. This closes its missing foreign exact-ID
case without expanding the scope into Card or Phase 8 history.

R04 cannot be formally accepted until separately authorized disposable blocked
and demoted Admin fixtures/sessions are available and their denial cases pass.
Do not modify the approved Admin or create identities under this closeout.
Representative Attempt/Refund and hosted over-limit/race evidence remain
explicit limitations; no fixture mutation is authorized to fill them here.
The next security task is owner-approved provisioning of the disposable Admin
acceptance identities, followed by their bounded read-only denial tests.

No implementation defect was found in the executed cases. This PR changes
documentation only. No hosted financial mutation, role change, account creation,
schema change, deployment, Stripe call, runtime-flag change or automatic merge.
