# R05 bounded canonical Rider Cash detail integration

## Acceptance closeout — 2026-10-26

PR #67 merged at `86e67cb`. **ACCEPTED for this bounded Cash read/UI scope**:
owner-attested device Paid/JOD 16.00/Receipt Verified display, refresh/logout/login
and second-Rider UI isolation supplement prior owning-Rider SDK acceptance. Fresh
second-Rider SDK reads now reject the known foreign Payment (200/empty) and Trip
payment/receipt RPCs (403/42501). This closes the previously pending gates below;
those statements are historical. No successful device/owning-Rider test was
repeated. R04 remains PARTIAL and Phase 6 NOT APPROVED. See
[security closeout evidence and untested races](P6_R04_R05_SECURITY_CLOSEOUT.md).

Base: main `55b1320af402bc172b2694079f9ee8a901fa4785` (PR #66).
Status: Cash Trip-to-Payment/Receipt UI implemented locally; R05 remains PARTIAL
pending integrated hosted/device acceptance and the authorized foreign-Rider case.

## Existing discovery contract and scope

Migration 008 already grants authenticated participant SELECT on `public.trips`
through `trips_participant_select` / `private.can_read_trip(id)`. That helper
checks the current nonblocked profile and Rider ownership. The existing
`trips_rider_created_at_idx` supports the Rider/time lookup. This is a usable
backend discovery mechanism even though the old application Trip/history
repository returns `MockTrip`.

The new repository queries only the current Rider's latest **completed Cash**
Trip: explicit Rider, status and method filters; created_at descending plus ID
ascending for deterministic ordering; LIMIT 1; six allowlisted identity/status
fields. It accepts no caller-supplied Trip or Payment ID. This is one detail
surface, not a history list, matching service or Phase 8 history restoration.
No backend schema, policy, migration, index or RPC was changed.

## Trusted read chain

1. Use the application-owned Supabase client and trusted initialization
   provenance; require the authenticated, nonblocked app Rider and matching SDK
   Session. Pin that Session object and the application endpoint.
2. Validate the current backend Rider profile and discover the bounded Trip
   under existing participant RLS. Parse UUID identities, positive integer
   version, completed status, Cash method and exact Rider ownership.
3. Call `user_trip_payment_summary(target_trip_id)` for the discovered Trip.
   Its returned UUID is the Payment identity; require the same Trip and Cash.
4. Feed that UUID to the existing R05
   `SupabaseCanonicalPaymentRepository.readCashPayment`. Retain its current
   profile/ownership, strict financial parsing and SDK Session pinning. Require
   exact Payment, Trip and Booking linkage.
5. Independently call `user_trip_receipt_summary(target_trip_id)`. Only a single
   valid receipt UUID with matching Trip, Cash method, amount, currency and
   parseable issuance time establishes receipt issuance. Receipt errors/missing
   or mismatched evidence produce **receipt unverified**, not payment failure.
   Authorization denial invalidates the entire read. Unpaid Cash cannot acquire
   a receipt-issued display.
6. Reread the same Trip and exact Payment; reject changed Trip version/context
   or Payment snapshot. Revalidate the Rider profile before publication.

Only `trips` and the caller's profile are directly selected. No financial table
is selected from the client. The three payment/receipt RPCs are read-only.
Each asynchronous read is bounded to 15 seconds and checks the pinned owner
before/after; there is no retry or financial mutation. This is a point-in-time
snapshot, not an atomic cross-RPC transaction or instantaneous remote-revocation
guarantee. Refresh rereads all evidence.

## Navigation and UI

Rider home adds **Latest completed Cash Trip payment**, opening Rider-protected
`/rider/canonical-payment`. The route has no identity parameters; arbitrary query
IDs cannot influence discovery. Mock Trip/history/completion screens and their
unavailable financial cards are unchanged.

The surface shows loading, unavailable, authorization/read failure, unpaid,
persisted paid/cancelled Cash status, and independently verified/unverified
receipt issuance. It displays no raw backend errors, private identifiers or
receipt payload. Amount formatting preserves integer fils exactly (two decimal
places when exact, otherwise three), without rounding a canonical amount.

Auto-disposed Riverpod providers reuse the existing session owner. SDK session
replacement/logout invalidates loaded evidence as well as pending reads; an
unchanged initialSession replay does not restart the read. App session/client
changes replace the repository. FutureProvider generations discard out-of-order
results and loading hides prior success while refresh is pending. No new auth
client, lifecycle epoch manager or financial repository replaces R05's reader.

## Verification and remaining gates

Focused loopback/fixture tests cover scoped discovery, original Payment identity,
ownership/role/block checks, malformed IDs and amounts, changed Trip/Payment
versions, no financial-table SELECT or mutation, missing/mismatched/failed
receipt reads, exact JOD precision, logout, SDK A-B-A, invalidated backend owner,
loaded-provider invalidation, untrusted initialization, route identity isolation,
and loading/unpaid/paid/receipt-unverified/out-of-order UI behavior. Existing
payment/history/router regressions were run:

- New discovery/provider/widget/routing tests plus session guards: **47 PASS**.
- Existing canonical reader, Rider integration/provider/widget, mock history and
  router error regressions: **120 PASS**. Total: **167 PASS / 0 FAIL**.
- `flutter analyze --no-pub`: **No issues found**.
- Scoped formatting: **9 files, 0 changes**. `git diff --check`: passed.
- No full-suite rerun or hosted operation was performed for this change.

Prior authenticated hosted R05 acceptance independently verified the approved
fixture's exact paid Cash Payment (16,000 fils/JOD, version 2), completed Trip
version 5, Trip-to-Payment RPC and one issued receipt. This is historical evidence
from the preceding acceptance task, not a new hosted run of this UI/discovery
composition. No fixture identifiers are hardcoded in production code.

No backend discovery contract is missing for this **bounded Cash surface**.
Still required: review/merge, exercise the integrated surface with the approved
Rider in the configured app, verify device logout/account-switch behavior, and
execute foreign-Rider rejection with a separately authorized fixture. No new
account/fixture was created. Card Trip discovery, multi-Trip history/pagination,
Phase 7 matching and Phase 8 execution/receipt restoration remain outside this
slice. Phase 6 is NOT APPROVED. Driver activation and Stripe dispatch are unchanged.
