# P7-B06 - Cash completion stop gate and integration handoff

Owner: Moath. Issue: [#111](https://github.com/Omar59687/RideX/issues/111).
Branch: feature/p7-b04-driver-offer-actions.
Base: 085823a3dce9de61424d766de49e5c5271c662bb (committed B05).
Local implementation only; no staging or commit pending independent review.

## Contract inspection and scope

Issue #111 was read through the GitHub connector without mutation. Its acceptance
requires no fake payment success, green local UI tests with explicit blockers,
recorded limitations, no unapproved financial/hosted operations and no cross-owner
changes. The issue and older Phase 7/Moath.md repeat outdated R08 Cash-handoff
wording. The authoritative Phase 6 tracker/roadmap defines R08 as secure Stripe UI;
that wording cannot authorize Cash completion.

The selected implementation adds a closed stop policy to the existing B05 owner.
Extending the canonical financial composition or legacy mock completion screens
was rejected: each would cross authority/ownership boundaries without acceptance.
No new controller, payment owner, receipt repository or backend API is introduced.

Exact ownership, two modified and four new files:

- lib/features/driver_flow/presentation/providers/driver_trip_presentation_controller.dart
- lib/features/driver_flow/presentation/screens/driver_trip_preview_screen.dart
- test/driver_cash_completion_gate_test.dart
- test/driver_cash_completion_gate_screen_test.dart
- docs/ai/plans/P7_B06_CASH_COMPLETION_GATE.md
- docs/ai/verification/P7_B06_LOCAL_VERIFICATION.md

## Stop policy and UI

DriverTripCompletionGate has a private const constructor, immutable requirements
and canComplete permanently false. There is no gate provider, evidence-approval
boolean, activation setter or injectable completion transport. Its requirement
enum is a read-only integration checklist, never verified authority.

DriverTripPresentationController.requestCompletion synchronously returns
DriverFlowOutcome.unsupported. It never accesses a repository, stages intent,
generates a token, publishes state, navigates or modifies a pending/UNKNOWN
attempt. Direct, repeated, stale or revoked calls cannot dispatch. B01's command
contract is unchanged: DriverFlowProgressTrip still permits only driverArriving,
driverArrived and inProgress. Calling progress with completed is rejected too.

The Local Trip preview includes an explicitly disabled Complete Cash Trip control,
a visible accessible reason and required P6-R01/R02/R03/R07 acceptance references.
It separately labels simulated progression, canonical completion, Cash settlement,
payment confirmation and receipt issuance. The latter four remain unverified even
when a simulated Trip reports completed. No mock receipt or financial result is
read/displayed. Completion is not automatically enabled after an approval record;
separately reviewed integration through the existing canonical composition is needed.

The finite preview content uses a SingleChildScrollView/Column so status/access
explanations stay mounted as the new section extends scroll range. This preserves
the existing B05 widget assertions without changing tests or owning new Trip state.
Large text remains scrollable and actions retain native disabled semantics.

B05's pinned identity, entity/event version barriers, session retirement,
authorization hiding, read-only recovery, single-flight and UNKNOWN protections
are unchanged. B04 remains the offer-decision owner. B06 cannot release its pending
or UNKNOWN barrier. The route sheet still observes the same owner and hides details
on revocation. No navigation to mock completion or the canonical financial panel
is introduced, and neither panel is instantiated by this preview.

## Current authoritative Phase 6 evidence and blockers

Sources at the inspected local base:

- docs/parallel-development/phase-6/SPRINT_TRACKER.md (dated overrides take precedence)
- docs/parallel-development/phase-6/P6_POST_MERGE_ROADMAP.md
- docs/parallel-development/phase-6/P6_CANONICAL_DRIVER_CASH_UI.md
- docs/parallel-development/phase-6/P6_R01_R02_IMPLEMENTATION.md
- docs/parallel-development/phase-6/P6_R03_IMPLEMENTATION.md

No hosted state was queried. These are repository-recorded dispositions, not fresh
hosted acceptance. Older statements about an empty/unapproved registry or an
unmounted canonical panel are superseded by the later tracker/runtime record.

| Gate | Existing evidence | Still missing for real activation/acceptance |
| --- | --- | --- |
| P6-R01 | Canonical source, SDK/client/backend/epoch binding, approved isolated namespace and default-off canonical composition exist; PARTIAL acceptance | Accepted runtime Driver/session/role/Trip ownership evidence and current canonical context/version; this preview has no canonical assignment binding. A UUID or local DriverFlowSession is insufficient. |
| P6-R02 | Durable file journal, create-or-load staging and one-attempt coordinator, distinct canonical UI mounted behind default-off gate; PARTIAL acceptance | Native storage/process lifecycle and durability acceptance, preservation of existing/conflicting/corrupt/uncertain intent, original-key coordination and authorized hosted completion acceptance. App-data rollback, cross-device coordination and universal power-loss durability are not established. |
| P6-R03 | Read-only journal/Trip/receipt recovery and unresolved UI exist; PARTIAL acceptance | Owner-approved retention/export/operator-resolution policy, runtime restart/session/role acceptance and R07 recovery evidence. No automatic replay, deletion or retirement is approved. |
| P6-R07 | PREPARED, NOT ACCEPTED. Historical fixture setup reached inProgress/version 4 with unpaid Cash and no receipt | Separately authorized fresh fixture checks and controlled completion proving canonical completed Trip, one Cash settlement and one immutable issued receipt; original-key duplicate/concurrency, stale/foreign/blocked Driver, lost reply, receipt-read failure, revocation and read-only restart/resume recovery matrix. Setup is not financial acceptance. |

R05's bounded Rider Cash read acceptance is not Driver financial approval. R04
remains partial for separate role/fixture cases. R06 remains PARTIAL; provider
dispatch stays OFF and expired fixture/concurrency/sandbox/account/JOD acceptance
gaps are not waived. R08 remains secure Stripe UI scope. Phase 6 overall is NOT
APPROVED. None of these conditions blocks the isolated B06 stop gate itself.

Physical hardware is not required for local UI tests or every R07 SDK/emulator
case. Native storage/process evidence and broader physical-device release tails
remain separate requirements; this checkpoint supplies neither.

## Read-only integration handoff

Reuse the following EXISTING contracts in future reviewed integration; B06 does
not connect them to DriverFlow or accept them as evidence supplied by UI:

| Requirement | Existing boundary and required proof |
| --- | --- |
| Authenticated owner | DriverAuthorityOwner, verified initialization/backend registry and AuthService.driverBinding; exact SDK user/client/backend/epoch with current eligible Driver, before and after awaits; local SessionState alone is not canonical proof. |
| Canonical Trip | CanonicalDriverCompletionSource/Context and SupabaseDriverCompletionSource; owning Driver's canonical Cash inProgress Trip ID and independent Trip version, not offer/booking revision or UUID shape. Legal adjacent lifecycle must already have been observed. |
| Durable intent | DriverCompleteTripCommand and DriverCompletionStagingGateway; one original Trip ID/version/key persisted and positively acknowledged before first dispatch. StagingExistingEvidence is reconciliation-only. No key/version rotation or uncertain replay. |
| Unknown recovery | Existing DriverCompletionCoordinator, recovery coordinator/controller and canonical reconciliation repository; retain exact evidence across loss/restart, read only, never infer failure from absence/timeout and never auto-replay or clear journal. |
| Payment truth | Canonical payment reader/model bound to the correct Trip/payment/Driver/session; Cash paid is trusted backend evidence, never simulated status or completion-only JSON. |
| Receipt truth | Existing user_trip_receipt_summary/user_receipt_summary reader path and immutable receipt/payment/Trip identity; only authorized driver-safe canonical reads can verify issuance. Missing receipt is unverified, not proof of failed payment. |
| Realtime | Notifications are invalidation/re-read triggers only. Fresh authorized canonical reads must revalidate owner, ID/version and lineage; no notification or realtime payload can settle a financial command by itself. |
| Acceptance | Explicit R01/R02/R03/R07 disposition, authorized controlled hosted matrix and applicable native/device evidence, independent review and owner activation. UI flags cannot substitute for this evidence. |

Backend source contract: public.driver_transition_trip(target_id uuid,
requested_status public.trip_status, expected_version integer, idempotency_key text)
returns JSONB. Acceptance uses an offer target; completion uses canonical Trip
ID/version with completed. Migration 017 delegates Trip transition and invokes
private.settle_cash_trip_and_issue_receipt for completed Cash; settlement and
receipt creation are trusted backend consequences. Flutter must not call those
private functions or set financial status itself. Receipt-summary reads remain
separate authorization/correlation steps. No financial RPC was executed here.

The checklist exposes requirements without inventing a Phase 6 authorization API.
Existing-interface tests show missing source/session/durable acknowledgement and
pre-existing journal evidence prevent financial dispatch. They are local contract
characterization, not a new activation API or hosted end-to-end evidence.

## Test matrix and acceptance mapping

- A-E: all nine lifecycle statuses have a disabled UI control and blocked direct
  completion/progress(completed); actual repository command count stays zero.
- F/G/H/S: simulated completed UUIDs and fake receipt objects do not grant authority;
  no canonical source is mounted; required gates include R07 with no bypass input.
- I/J: completion calls preserve B05 UNKNOWN/original token and B04 pending/UNKNOWN;
  only the existing explicitly simulated nonfinancial command is recorded.
- K: logout hides summary and an already-open route sheet; revoked direct calls
  cannot restore data or mutate a Trip.
- L/M/N: refresh/resume/remount and rapid taps/calls do not replay completion.
- O/P/Q: disabled semantics/no tap action, visible gate explanation, exact integer
  fils and three decimals, five separate authority labels, no success fabrication.
- R/T: actual default-off/null/unavailable configuration and a canonical UI flag
  override cannot activate this preview; a poison canonical-provider override
  proves the UI does not mount the financial owner.
- Future handoff: existing canonical command validation, no-context/session,
  unacknowledged staging and reconciliation-only evidence tests verify zero
  completion-repository calls. These fixtures never contact hosted services.

Issue #111's local acceptance criteria are implemented and remain subject to
independent review. Current commit SHA is the B05 base; B06 is intentionally
uncommitted. Exact executed counts, SDK, earlier failures and final hashes are
recorded in ../verification/P7_B06_LOCAL_VERIFICATION.md.

No SQL, Rider, canonical financial provider or other-owner file is changed.
No live matching/completion, settlement, payment, receipt, Card/Stripe, migration,
deployment, journal repair/retirement, push, PR or issue closure is performed.

Final local execution: B06 42 PASS (26 controller/contract, 16 widget), existing
B01-B05 439 PASS, integration-sensitive 280 PASS, full suite 2234 PASS / 0 FAIL /
2 intentional live SKIP. Counts overlap. Scoped analysis and formatting pass.
Full analysis exits 1 with two unchanged inherited infos; global formatting
exits 1 with the same 15 inherited findings. Tracked/untracked whitespace checks
pass. Flutter 3.41.2 / Dart 3.11.0 was used; the older prescribed SDK was not tested.
These are implementation-agent results, not CI, hosted acceptance or independent
review. Final-source hashes and earlier failures are in the verification record.
