# P8-C06 — exact Driver integration handoff

Moath / Developer 3, issue #153. Local default-OFF package; **not hosted acceptance**.
Final verification and review: [C06 package](P8_C06_DRIVER_FINAL_INTEGRATION.md).
No shared router/provider, Rider/History, backend or financial file was changed.

## Omar: compose these existing seams

| Insertion point | Expected input / ownership |
|---|---|
| `lib/features/driver_flow/presentation/providers/driver_completion_interaction_provider.dart`: `driverCompletionInteractionGateProvider` | Default null. Override with one route/session-owned `CanonicalDriverCompletionInteraction`; register gate disposal. `driverCompletionInteractionControllerProvider` borrows and binds the existing `driverCashCompletionProvider.notifier` once. Do not construct a second command/coordinator/journal. |
| `lib/features/driver_flow/application/driver_completion_interaction.dart`: `DriverCompletionInteractionConfiguration` | Explicit `enabled: true` AND `reviewedNonproduction: true`, exact approved `DriverBackendIdentity` instance, Driver UUID and owned active vehicle UUID. Nonrelease builds only. Approval/configuration is trusted composition input, never route arguments, cached IDs or editable user metadata. |
| `CanonicalDriverCompletionInteraction(...)` | Matching `CanonicalDriverPort`, `loadContext: completion.recovery.source.load`, normal-user `readVehicle` selecting the configured vehicle's real `id,driver_id,is_active`, real `ValueListenable<bool> connected`, synchronous `sessionCurrent`. Pin the same verified client, SDK Session, backend object and authority epoch as the existing Cash composition. Dispose borrowed port/repository subscriptions with their owner. |
| `lib/core/providers/driver_cash_completion_providers.dart` (read-only in this branch) | Existing `driverCashRuntimeEnabledProvider`, approved-backend/provenance binding, `driverCashCompletionProvider` and store factory remain authoritative. The existing test Cash flag alone does NOT supply the new reviewed interaction gate. No new approved backend is supplied by P8-C. |
| `lib/features/trips/presentation/screens/driver_canonical_trip_screen.dart` | Existing `/driver/canonical-trip` entry consumes the interaction controller and mounts `DriverCashCompletionPanel` plus the optional handoff panel. Preparation only reads; explicit completion tap is one attempt. Do not auto-submit on mount/reconnect/resume. |
| `lib/features/driver_flow/presentation/providers/driver_active_trip_restoration_provider.dart`: `driverActiveTripRestorationProvider` | Default null. Override with a NEW `CanonicalDriverPresentationController` per auth/config/foreground lifetime: `enabled: true`, `restorationEnabled: true`, `offerActionsEnabled: false`. Its `CanonicalDriverRepository` must keep `offerCommandsEnabled: false`. The ChangeNotifier provider disposes the controller; `ref.onDispose` must separately release borrowed inputs. |
| `lib/features/driver_flow/presentation/screens/driver_active_trip_restoration_screen.dart` | Mount at the owner-approved Driver entry; there is intentionally no new global route here. Screen retires on background/route coverage; foreground/reload invalidates its provider. Factory must return a fresh owner, never the retired instance. It does not mount completion or enable offer commands. |
| `lib/features/driver_flow/presentation/providers/driver_completion_handoff_provider.dart`: `driverCompletionHandoffProvider` | Default null. Leave null until Yousuf's Driver-safe read contract and its adapter are reviewed. Then supply a separate read-only `DriverCompletionHandoffController`; never a financial command controller. |

### Authenticated inputs and delivery

- Use the application's existing initialization provenance to obtain
  `VerifiedSupabaseDriverAccess` against its reviewed backend registry, with the
  same normal-user client and `AuthService`. Existing
  `SupabaseCanonicalDriverPort.create(access: ..., auth: ...)` is in
  `lib/features/driver_flow/data/supabase_canonical_driver_port.dart`. It creates
  no client or login. Distinct authority binding wrappers must still observe the
  same backend object, auth epoch and SDK Session; UI role alone grants nothing.
- Restoration controller requires the application's real
  `ValueListenable<SessionState> session` and a synchronous
  `Listenable authorityInvalidations`. Watch auth, eligibility, configuration and
  client provenance dependencies in the provider factory. Logout, account switch,
  revocation/expiry, approval loss or SDK replacement must retire the old owners
  immediately and cancel their subscriptions. Returning A after A→B→A creates a
  new epoch/owner; it never rearms A's original command.
- Supply `CanonicalDriverDelivery` from the reviewed authenticated source and
  actual source connection status, with monotonically ordered revisions per
  owner. A `CanonicalDriverConnectionHint(connected: true)` triggers a canonical
  restoration read, including cold start. An unconditional true notifier or
  Realtime row payload is not authorization. Do not label HTTP polling health as
  proof of a working Realtime subscription.
- Existing `TripRealtimeCanonicalDriverDelivery` in
  `lib/features/driver_flow/data/trip_realtime_canonical_driver_delivery.dart`
  needs an ALREADY verified exact Trip/Driver and the same authenticated source.
  It cannot discover a cold-start assignment. Discover via authenticated
  availability/reread first; do not seed it with a stored/mock/route ID as truth.
- Supply `DriverCompletionRestorationHints(completion.recovery)` from the SAME
  account/backend/session, and scoped `DriverRestorationLocationHint` values from
  the actual GPS source. GPS is health-only: exact Driver/backend/epoch/SDK/Trip,
  age 0..45 seconds; no coordinates or progression are invented by these widgets.
- Wire `retireCompletion: (defer) => completion.invalidateInteraction(
  deferNotification: defer)` on restoration, and retire any handoff owner from
  the same lifecycle/auth events. Preserve synchronous revocation and defer
  notifier publication when invoked during build/disposal. The canonical Cash
  screen currently retires its C02 owner, not a future C05 adapter: the host must
  also retire C05 on background, navigation/coverage and disposal.
- Authenticated source reads and every awaited boundary must check current
  ownership. Cancel old stream subscriptions; reconnect rereads only. Do not
  reset the durable journal, rotate the key or resubmit UNKNOWN while replacing
  a presentation owner. Recovery retained facts are historical, not current
  authorization; consumers must honor `authorizationRevoked` and revocable views.

### Shared `/driver/completed` protection — activation blocker

`lib/app/router/app_router.dart:220` still constructs
`TripCompletionScreen(isDriverView: true)` directly. The shared screen at
`lib/features/trips/presentation/screens/trip_completion_screen.dart` contains
generic success/fare presentation. The legacy Driver button was removed in C01,
but direct navigation remains possible in inherited shared code.

Omar must gate/replace this Driver route before enabling integration. Require
current authenticated approved Driver authority and an exact authorized canonical
completed Trip reread/version for this Driver. A boolean, MockTrip state, receipt,
RPC callback, journal record or route argument is insufficient. Render Trip,
Payment and Receipt facts separately; remove unverified hard-coded Driver success
and fare. Cover direct links, wrong role, expired session, unassigned Trip, stale
read, logout/A→B→A and missing finance evidence with shared-route tests. Do not
redirect to this shared screen from a journal callback alone. P8-C intentionally
does not edit Omar's shared files.

### Lifecycle progression is not implicitly enabled

C01 `DriverTripTransitionPolicy` and `CanonicalDriverRepository.inspectTransition`
are read-only preflight, not new RPC dispatchers. The existing adapter accepts an
offer with its OFFER ID/version; arrival/progress/completion require the canonical
TRIP ID/version. Keep strict accepted→driverArriving→driverArrived→inProgress→completed
edges. Any final UI wiring of intermediate canonical actions must use the existing
reviewed backend command contract and its own reviewed composition. The disabled
legacy MockTrip flow cannot supply canonical state. Card completion is not enabled
by C05's read-only Card examples; existing Cash-only completion is preserved.

## Yousuf: exact backend contract request

Current source authority: migrations 019/020 expose the Driver-safe
`user_trip_receipt_summary`; 020/027 deny Driver Payment reads. The existing
`SupabaseCanonicalPaymentRepository` is Rider/Admin only. C06 reread
[issue #151](https://github.com/Omar59687/RideX/issues/151) and all comments: it is
open, has zero comments and no posted final versioned draft/fixtures. C06 adds no
presumed API.

Provide a reviewed versioned Driver-safe read projection/fixtures with:

1. Exact backend-issued Payment UUID, correlated Trip UUID, existing payment
   method and canonical Cash/Card status, positive monotonic Payment version.
2. Authenticated normal-user assigned-Driver, current role/approval/session and
   backend checks; clearly separate missing/hidden, unauthorized, transport error
   and UNKNOWN. A hidden record must never mean failed payment or no prior effect.
3. Receipt's real UUID, Trip UUID, method and nonblank backend-issued number from
   an authorized Driver summary. Current summary has no Payment ID or Receipt
   version; do not fabricate either. Define safe revocation/reissue semantics if
   they can occur; the present reader pins receipt identity/number per owner.
4. Reviewed Card failure-stage semantics if specific capture-failure wording is
   required. Existing generic `cardPaymentFailed` proves payment failure only;
   it does not identify the provider stage. Pending capture, successful capture,
   cancellation/refund and UNKNOWN must remain distinguishable.

No broad finance-table SELECT, Rider/Admin RPC reuse, privilege bypass, secret
client, capture/refund/void, Payment update or Receipt creation from Flutter.
Existing server Cash settlement/receipt atomicity remains unchanged. A completed
Trip is never client proof of independently read Payment success.

## Sanad and Omar: typed read-only consumer contract

Definitions: `lib/features/driver_flow/domain/driver_completion_handoff.dart` and
`lib/features/driver_flow/application/driver_completion_handoff_controller.dart`.

`DriverCompletionHandoffReader` exposes only `currentScope`, `readTrip(tripId)`,
`readPayment(tripId)`, `readReceipt(tripId)`; these are interface methods, not
invented backend RPCs. The trusted adapter supplies actual authenticated scope.

`DriverCompletionHandoffEvent` exposes:

- `scope`: `DriverAuthorityOwner` (Driver/backend/epoch/session ownership), exact
  opaque SDK identity and approved eligibility. Never serialize credentials.
- `tripState` plus verified `trip`: Trip UUID, assigned Driver UUID, canonical
  status, positive version, payment method. `tripCompleted` is true only after an
  authorized completed reread. It is not a command permission.
- `paymentState` plus optional verified `DriverHandoffCashPayment` or
  `DriverHandoffCardPayment`: independent Payment UUID/Trip/method/version/status.
- `receiptState` plus optional verified `DriverHandoffReceipt`: independent real
  Receipt UUID/Trip/method/number. Receipt presence never promotes Payment status.

Read states are `notChecked`, `loading`, `verified`, `missing`, `unknown`, `error`,
`unauthorized`; pending financial execution is the existing verified Cash/Card
status, not a new backend enum. Non-verified results carry no evidence.

Listen to the controller and consume its CURRENT event. Captured events expire
on publication/refresh/auth change; do not retain copied fields as new authority.
Foreign scope/Trip/method, stale version/identity and late callbacks are rejected.
Sanad may consume this event read-only without changing historical facts or
creating a second financial truth source. No History implementation is required
or modified here. The [C05 report](P8_C05_DRIVER_COMPLETION_HANDOFF.md) contains the
typed consumption example and Cash/Card/Receipt fixture cases.

## Safe integration order and rollback

1. Review the full unpublished stack and manifest. Integrate on Omar's isolated
   integration branch in ancestry order; obtain separate push/PR/merge approval.
   Do not cherry-pick only C06 or silently omit C01–C05. No upstream merge was
   attempted here.
2. Keep all Driver completion/offer/financial-read gates OFF; fix the shared
   success route first. Wire read-only restoration with actual identity and
   connection/lifecycle invalidation. Verify cold start, empty/terminal states,
   disconnect/reconnect and account switches using fakes/loopback first.
3. Wire C02 only with the reviewed nonproduction configuration and existing
   durable Cash composition; test flush/readback failures, original command
   identity, duplicate taps and UNKNOWN restart without replay. No hosted dispatch
   is authorized by this package.
4. After Yousuf's contract review, add the read-only C05 adapter and Sanad/Omar
   consumers. Keep Trip/Payment/Receipt success independent. Re-run focused and
   shared-route tests and compile checks under the chosen supported toolchain.
5. Obtain separate hosted fixture/device/operation authorization after discrepancy
   #149 and backend prerequisites are resolved. No current accepted Phase 7 Trip
   or existing emulator session may be used as an implicit fixture.

Rollback starts by disabling overrides/flags, retiring owners and cancelling
subscriptions. Restore/revert code only on an owner-approved integration branch;
never reset approved checkpoint branches. Preserve backend/account-scoped journal
bytes, UNKNOWN evidence and original keys. A stale writer lock fails closed;
do not delete it or clear app data merely to rearm dispatch. Canonical rereads
establish current observations, never permission to replay an uncertain command.
