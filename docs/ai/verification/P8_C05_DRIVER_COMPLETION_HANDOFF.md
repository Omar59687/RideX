# P8-C05 - Driver Trip/Payment/Receipt handoff

Moath / Developer 3, issue #153. Local implementation only. C06 has not started.

## Baseline and stack

Branch: `feature/p8-c05-driver-completion-handoff`, separate worktree based on
approved C04 `c630ecc7f592f4b58063bff3a8514583b4fac881`.
Fetched origin/main remains `3be1aa6`. Required unpublished stack above main:
C01 implementation `2c52bc35708dd719168db051107113c7a9e87916`, reviewed C01 fix
`30a27aaa31eddfd6ece4ea6736d30582e54fcba6`, C02
`1bd8a9659e04a0ca88f2fcee20bee6b00432d3fa`, C03
`c152f44acc7372deb3d3928f06a0f6f671f265c3`, C04, then this checkpoint.
Ancestry was verified; earlier worktrees are preserved. No merge/rebase/cherry-pick.

## Contract availability and source authority

Read Phase 8/Yousuf.md and Phase 8/Moath.md from the documentation branch.
[Issue #151](https://github.com/Omar59687/RideX/issues/151) was read through the
GitHub connector, including comments: the issue contains the assignment, with
zero comments and no posted versioned financial draft/fixtures. The named early
branch feature/p8-a01-payment-contracts was not advertised by origin. No finalized
Driver financial contract was found in these sources; local work therefore uses
an explicitly fake-backed typed interface, not a fabricated endpoint.

Source authority inspected:

- Existing CashPaymentStatus: cashSelected, paid, cancelled.
- Existing CardPaymentStatus: cardPaymentPending, cardPaymentAuthorized,
  cardPaymentSucceeded, cardPaymentFailed, paymentCancelled, refundPending, refunded.
- Migrations 019/020: Driver-safe user_trip_receipt_summary exists; 020 removes
  Driver finance-reader permission. Receipt summary includes id, trip_id,
  payment_method and receipt_number, but no receipt version or Payment ID.
- Migration 027 and SupabaseCanonicalPaymentRepository: versioned Payment reads
  are Rider/Admin only. They must NOT be repurposed for Driver access.
- Existing completion repository/coordinator already separates canonical Trip
  reread and receipt verification. Cash settlement is a trusted server consequence
  in 017; Flutter must still not infer its success from an acknowledgement/Trip.

No backend, shared payment model, canonical completion engine, journal, recovery,
Card gate or shared provider/router was changed. Card support added here is strictly
read-only presentation/fixtures, not Card completion or financial execution.

## Exact typed handoff

DriverCompletionHandoffReader exposes only currentScope, readTrip(tripId),
readPayment(tripId), readReceipt(tripId). These are Dart read seams, not RPC names.
There is no capture/refund/void/settlement/update capability or SDK adapter.

Every result is DriverHandoffRead<T>, carrying the actual authenticated scope,
requested canonical Trip ID and one terminal read outcome: verified, missing,
unknown, error or unauthorized. Verified requires typed evidence; other outcomes
cannot carry it. notChecked/loading are presentation-only states, not database enums.
Missing/hidden reads never prove payment failure, cancellation or no prior effect.

| Type | Required independently read facts |
|---|---|
| DriverHandoffScope | DriverAuthorityOwner (Driver UUID, approved backend identity/namespace, epoch, valid-session ownership), exact opaque SDK Session identity, approved/nonblocked Driver eligibility |
| DriverHandoffTrip | Exact Trip UUID, assigned Driver UUID, canonical lifecycle status, positive int32 Trip version, existing PaymentMethod |
| DriverHandoffCashPayment | Backend-issued Payment UUID, exact Trip UUID, positive Payment version, existing CashPaymentStatus; method fixed cash |
| DriverHandoffCardPayment | Backend-issued Payment UUID, exact Trip UUID, positive Payment version, existing CardPaymentStatus; method fixed card |
| DriverHandoffReceipt | Backend-issued Receipt UUID, exact Trip UUID, payment method and genuine receipt number; no invented version/Payment ID |

The controller exposes a revocable DriverCompletionHandoffEvent for Omar/Sanad:

```dart
final handoff = controller.event;
if (handoff.tripCompleted && handoff.scope != null) {
  final canonicalTripId = handoff.trip!.tripId;
  final verifiedTripVersion = handoff.trip!.version;
  final driverId = handoff.scope!.owner.driverId;
  // These are separate facts; neither implies the other.
  final independentlyReadPayment = handoff.payment; // null unless verified
  final independentlyReadReceipt = handoff.receipt; // null unless verified
  final paymentReadState = handoff.paymentState;    // pending comes from its enum
  final receiptReadState = handoff.receiptState;    // missing != issued
}
```

Consumers listen to the controller and fetch its current event. A captured event
expires on publication, refresh or auth replacement; its getters hide stale fields.
Do not persist/serialize the opaque SDK identity or treat a copied display fact
as permission for any operation. The event has no public constructor accepting
a completion callback or journal result. Trip completion requires readTrip to
return a current authorized canonical completed record. Financial reads occur
only after that gate. Restart starts unverified and rereads all evidence.

A fake example is completed Card Trip@5, independently verified Payment@7 with
cardPaymentAuthorized, receipt missing. Its UI is Trip completion verified,
Card authorized/Capture pending, Receipt not available. No capture was dispatched
and no Payment was advanced by Flutter. Completed Cash plus cashSelected similarly
shows settlement pending; that fixture demonstrates boundary handling and does not
claim the current atomic Cash backend partially commits settlement.

## Isolation and presentation behavior

Reader replies must come from the SAME normal-user SDK/backend/session/epoch as
currentScope, with server authorization/role/approval and assigned Trip checks on
every read. The controller verifies returned scope, Driver/Trip/payment-method
correlation and canonical versions. Payment ID is pinned per Trip; lower versions,
same-version status changes and invalid terminal regressions are rejected. Receipt
identity/number cannot silently change for the same Trip. Read uncertainty clears
current financial claims while preserving private high-water checks.

Duplicate refreshes share one read sequence. Disconnect clears current evidence;
reconnect performs read-only verification. Generation checks discard late responses
from old connections. Logout/revocation/A-B-A permanently retires the owner and
revokes captured events. The host supplies synchronous authority invalidations;
no instantaneous remote-revocation guarantee is invented by local state.

Trip, Payment and Receipt text are independent. Pending Cash/Card, generic Card
failure, UNKNOWN, read error, missing/delayed receipt and verified receipt are
separate. Generic cardPaymentFailed is not falsely claimed to identify a provider
capture-attempt failure stage. Only cardPaymentSucceeded can show verified capture,
and only an independently read paid Cash state can show verified settlement.
Receipt availability never promotes a Payment to paid/succeeded. No amount/fare,
provider reference, raw error, card data or secret is exposed.

DriverCompletionHandoffPanel is placed alongside the existing gated canonical Cash
panel. Its Driver-owned provider defaults null, so the current app only reports
Payment status unavailable. The separate panel can be consumed by future Card
read composition without enabling Card completion. C01-C04 guards remain intact.

## Verification and independent review

- New controller/contract/widget tests: 52 passed.
- Final focused regression suite: 619 passed, zero failures across 14 test files.
- Changed-file analysis: clean in seven Dart files.
- Android debug APK: passed. Existing platform/toolchain warnings remain.
- Full analyzer: 21 inherited diagnostics (three warnings, 18 info); all ten
  diagnostic-bearing files match the approved C04 blobs. No new diagnostics.
  Whole-repository analysis exits nonzero and is not reported as passing.
- Independent review: APPROVED, no critical/high/medium findings. Reviewer also
  independently ran the first 45 handoff tests successfully. Seven additional
  negative scope/Trip regression cases pass after that review; production behavior
  did not change while adding those cases/formatting test conditionals.

Coverage: Cash settlement pending, Card authorization/capture pending, failed Card,
UNKNOWN/error/unauthorized financial read, missing/delayed receipt, genuine receipt
with still-UNKNOWN payment, foreign/mismatched Payment/Receipt/Trip/scope, stale
versions/terminal resurrection, logout/A-B-A at each awaited read, duplicate
callbacks, reconnect with late paid response, restart, and no false Paid/Receipt
issued UI. Existing C01-C04/session/native journal/process-exit tests are included.
Tests use fakes and existing loopback fixtures only; no hosted Trip/financial calls.

## Exact dependencies

Yousuf: publish a reviewed, versioned Driver-safe financial read projection and
fixtures, including canonical Payment ID/Trip/method/status/version and per-request
auth/session/error/UNKNOWN semantics. Current 020/027 deny this access. Keep Driver
privacy limits explicit; do not grant broad finance-table SELECT or reuse the
Rider/Admin RPC. Define any safe capture-failure-stage indicator if finer text is
required; current generic CardPaymentStatus does not identify that stage. Existing
Driver receipt summary may supply its real ID/Trip/method/number, but no Payment
or receipt version may be fabricated to fit another contract.

Omar: keep driverCompletionHandoffProvider null until that contract/adapter is
reviewed. Then supply a read-only controller using the same verified application
client, authority epoch, SDK identity, approved Driver and canonical Trip locator.
Wire real connection status and synchronous auth/lifecycle invalidations; retire
on background/navigation/disposal and construct a fresh owner on replacement.
No constructor/adapter may label cached UI metadata as authenticated scope. C04's
retirement callback can retire both C02 and this read owner, forwarding notification
deferral during build/disposal. Sanad can consume the revocable event without
changing History state or creating a separate financial truth path.

Existing C02 nonproduction completion gate and shared /driver/completed protection
remain required. Hosted acceptance, discrepancy #149 and durable power-loss limits
remain open. C05 does not activate any financial read or write endpoint.

Toolchain: Flutter 3.41.2 / Dart 3.11.0 (existing CI). Tests/build use temporary SDK
resolution. The committed lockfile remains unchanged, blob
bb6148d20da9613013f01aa25dfefe82566360f1. Exact enforcement on this SDK still fails:
`flutter pub get --offline --enforce-lockfile` exits 65 without changing the lock.
The required temporary SDK-pinned differences are
characters 1.4.0->1.4.1, matcher 0.12.17->0.12.18, material_color_utilities
0.11.1->0.13.0, meta 1.16.0->1.17.0, test_api 0.7.6->0.7.9. The original lockfile
already requires Dart >=3.8 despite the older 3.27.3/3.6.1 guide. No dependency,
generated plugin, platform or machine-specific configuration change is committed.

## Changed files

- lib/features/driver_flow/domain/driver_completion_handoff.dart
- lib/features/driver_flow/application/driver_completion_handoff_controller.dart
- lib/features/driver_flow/presentation/providers/driver_completion_handoff_provider.dart
- lib/features/driver_flow/presentation/widgets/driver_completion_handoff_panel.dart
- lib/features/trips/presentation/screens/driver_canonical_trip_screen.dart
- test/helpers/fake_driver_completion_handoff_reader.dart
- test/driver_completion_handoff_test.dart
- This report and docs/ai/ops/CURRENT_STATUS.md.

No hosted mutations, Stripe calls, migrations, Edge Functions, shared router/provider
changes, Rider/History edits, accepted Phase 7 Trip changes, emulator operations,
push, PR, merge or deployment. C05 awaits owner approval; C06 is not started.
