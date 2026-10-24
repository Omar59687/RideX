# Complete canonical payment read contract

## Restricted RPC contract (PR #48; migration 027 remains undeployed)

The summary RPC is intentionally reduced and remains unchanged. The existing
`payments` table already contains `id`, `booking_request_id`, `trip_id`, `rider_id`,
`version`, method/status, integer `final_amount_fils`, currency and sanitized card
brand/last4. Migration 019 removed the earlier direct SELECT policies. The SELECT
grant does not bypass RLS: even Admins and owning Riders cannot read the raw table.
The parent PR's direct-table reader was therefore not hosted-operational.

Migration 027 adds `user_canonical_payment_record(uuid)` and
`admin_recent_canonical_payments()` with empty search paths and explicit canonical
finance authorization. Only authenticated callers receive EXECUTE; owning active
Riders and nonblocked Admins receive the limited projection. Drivers are denied.
No direct SELECT policy is introduced. The functions perform no financial writes.

`SupabaseCanonicalPaymentRepository` invokes those restricted RPCs. It implements
the existing Cash and Card read-only contracts, rejects missing or malformed
identity/version, enforces method/status compatibility, and never guesses fields
from a booking, mock Trip, summary response or arithmetic version increment.
No provider references, secrets, payment attempts or raw payloads are selected.

The SDK session must be present and unexpired. A canonical `users` read checks
the actor's role and blocked flag before and after payment reads. The exact SDK
session object must still match after every await, including A→B→A replacement.
Rider single-record reads additionally validate returned ownership and payment ID.
Admin enumeration requires the canonical Admin role, returns at most 50 records
in deterministic order, and rejects duplicate identities. The exact-record RPC
must return one list row (or a not-found outcome), never duplicate or invented data.
RLS plus the restricted server finance gate remain authoritative; UI checks do not
replace them. Missing RPCs report unavailable rather than a successful empty list.

## Composition

The guarded Admin reader borrows the existing application Supabase client and
maps records through the existing allowlisted display mapper before they reach
the provider/widget tree. Demo/unconfigured mode remains unavailable; no fake
repository is installed. Role loss or account replacement hides prior summaries.

The Rider payment presentation providers are unchanged. This read contract is not
a trusted completed-Trip/receipt linkage or permission to render financial success
from caller-built evidence. Receipt issuance and persistent History remain P8.
Drivers must continue using Driver-safe Trip/receipt contracts, never this reader.

## Evidence and limits

The original parent reader results do not verify the RPC repair. Current PR #48
results, local PostgreSQL/pgTAP environment and limitations are recorded in
`P6_PAYMENT_RLS_RPC_REMEDIATION.md`. SDK tests use loopback users GET and explicit
read-only RPC POST paths; direct payments requests are rejected. They verify role/
session races, missing RPCs/fields, identity mismatch and sanitized output.

Migration 027 is additive, proposed and locally tested only. Dev 1 numbering and
security review plus database-first rollout/hosted acceptance remain required.
No applied migration, hosted configuration, production record or financial
operation was changed. Independent approval is required before deployment.
