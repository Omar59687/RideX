# Complete canonical payment read contract

## Resolution without a migration

The summary RPC is intentionally reduced and remains unchanged. The existing
`payments` table already contains `id`, `booking_request_id`, `trip_id`, `rider_id`,
`version`, method/status, integer `final_amount_fils`, currency and sanitized card
brand/last4. Its existing SELECT grant and `private.can_read_payment` RLS admit
Admins and the owning Rider, not Drivers (migrations 009/020).

`SupabaseCanonicalPaymentRepository` selects only those columns. It implements
the existing Cash and Card read-only contracts, rejects missing or malformed
identity/version, enforces method/status compatibility, and never guesses fields
from a booking, mock Trip, summary response or arithmetic version increment.
No provider references, secrets, payment attempts or raw payloads are selected.

The SDK session must be present and unexpired. A canonical `users` read checks
the actor's role and blocked flag before and after payment reads. The exact SDK
session object must still match after every await, including A→B→A replacement.
Rider single-record reads additionally validate returned ownership and payment ID.
Admin enumeration requires the canonical Admin role, returns at most 50 records
in deterministic order, and rejects duplicate identities. RLS remains the
server-side authority; UI checks do not replace it.

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

32 canonical parse/SDK/provider tests pass; the combined reader/Admin selection
passes 74 tests. Tests use an isolated loopback HTTP server and the real installed
Supabase SDK, with explicit fixtures and no hosted calls. These verify GET-only
transport, projection, role/session races, missing fields, identity mismatch and
sanitized output. They do not assert deployed schema/RLS state or live payments.

No migration, SQL contract, backend configuration, production record or financial
operation was changed. If a future environment lacks these existing columns or
grants, the reader fails closed; any schema remediation requires a separately
reviewed additive migration and safety plan before deployment.
