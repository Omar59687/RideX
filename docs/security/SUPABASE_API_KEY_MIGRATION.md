# Supabase API key migration and retirement

Status: application and operator code is prepared for the new key format. The
legacy keys remain enabled until remote consumers and installed clients have
been migrated and verified.

## Repository inventory

| Surface | Finding | Required rollout |
| --- | --- | --- |
| Flutter clients | `EnvConfig` already reads `SUPABASE_PUBLISHABLE_KEY`; this change rejects legacy `anon` JWT values. No secret key is read by the app. | Build and distribute an APK containing an `sb_publishable_` key. Replace older APKs before disabling legacy keys. |
| Edge Functions | `places`, `fare`, and `cash-matching` are active remotely and their inspected deployed source still reads legacy key environment variables. `stripe-test-intent` is repository code but was not among the active deployed functions inspected. | Set the platform's new publishable/secret key environment, deploy the migrated functions, and verify authenticated calls before key retirement. |
| Local and CI tests | The isolated D05 Realtime harness and offline config tests now use publishable/secret terminology. Repository CI workflows do not declare legacy Supabase API-key variables; CI runs offline tests and local Supabase fixtures. | Add new GitHub secrets only if a hosted integration job is introduced; never put a secret key in Flutter defines. |
| Operator scripts | R06 card fixture, concurrency, retirement, and P6 R07 scripts now read `SUPABASE_PUBLISHABLE_KEY` and/or `SUPABASE_SECRET_KEY`. Privileged Data API requests send the secret only as `apikey`; actor requests send the user's access token as `Authorization: Bearer` and the publishable key as `apikey`. | Update operator-local secret stores and follow the updated phase-6 runbooks. Do not put secret values in command-line arguments. |
| Database jobs and SQL | `service_role` in grants, transaction-local `SET ROLE`, and SQL tests is a Postgres role boundary, not a legacy HTTP API-key dependency. No repo SQL outbound webhook/`net.http_*` consumer of the old API keys was found. | Leave database role grants and financial behavior unchanged. |
| Webhooks and hosted settings | Dashboard-configured webhooks/secrets are outside the repository and were not inspectable with available project access. | Project owner must inventory webhook destinations, database webhooks, and third-party integrations in Dashboard before deactivation. |
| APKs | The downloaded Yousuf APK is package `com.ridex.app`, versionCode 1, signed with the older Yousuf certificate. Its embedded Supabase key type was not established by the static scan. The installed Rider APK is versionCode 4016 and uses the current Rider debug signer; its embedded key type is also unverified by static scan. | Replace the v1 APK with a newly built publishable-key APK. Build and distribute a publishable-key successor to 4016 and verify its runtime configuration/provenance. Keep both installed acceptance devices unchanged until the owner schedules an update. |

## Edge Function authentication and key handling

The migrated handlers resolve the platform-injected `SUPABASE_PUBLISHABLE_KEYS`
and `SUPABASE_SECRET_KEYS` JSON maps by the `default` entry. Local development
may use `SUPABASE_PUBLISHABLE_KEY` and `SUPABASE_SECRET_KEY`. Missing or malformed
platform maps fail closed. Secret keys are used only in trusted Edge Function
and operator code, in the `apikey` header for privileged Data API requests;
they are never placed in `Authorization: Bearer`.

User-facing Edge Function requests continue to require the authenticated
user's JWT. The deployed user functions retain `verify_jwt = true`; handlers
that perform user-scoped reads also forward the caller's bearer token to
Supabase Auth/PostgREST. Do not disable JWT verification or replace the caller
JWT with the server secret. Payment-provider authorization headers are separate
provider credentials and are not Supabase API keys.

## Isolated D05 live-harness compatibility gate

The migrated D05 harness now requires **real opaque** local
`sb_publishable_` and `sb_secret_` keys; it does not accept the older
JWT-based `anon` / `service_role` keys simply renamed as environment
variables. Before running live D05 acceptance, confirm that the *isolated*
Supabase CLI/gateway version actually supports and issues these new key types.
Keep the existing Docker identity, loopback URL and port preflight unchanged.
Never paste hosted project keys into the local isolated stack.

If the isolated project cannot provide working opaque API keys, leave D05
live-isolated verification **BLOCKED** and do not use synthetic placeholder
keys as evidence of an end-to-end PASS. This limitation does not invalidate
the already completed offline unit tests or the separate hosted RideX Phase 7
live acceptance.

## Safe rollout and retirement gates

1. An owner with Supabase project Settings and API-key management access creates
   and stores a publishable key and a server-only secret key. Put the secret
   only in Edge Function secrets and trusted operator/CI secret stores.
2. Configure the new Edge Function environment and operator secret stores. Deploy
   `places`, `fare`, and `cash-matching` from this migration branch after merge.
   Keep JWT verification enabled. Verify deployment versions and sanitized
   function logs, then exercise only normal authenticated calls in a planned
   rollout; do not use privileged credentials as user authorization.
3. Replace all distributed APKs that may contain a legacy anon key. In
   particular replace the downloaded versionCode 1 APK and create a
   publishable-key successor to versionCode 4016. Confirm remaining app
   installations and release artifacts through the distribution inventory.
4. Inspect Supabase Dashboard webhooks, Auth hooks, scheduled integrations,
   external automation, GitHub Actions secrets, and any third-party consumers.
   Confirm every remaining consumer uses the new key type. Repository search
   cannot establish the state of hosted settings.
5. Confirm a tested rollback path and monitor the app/functions. Only then,
   with API-key management permission, deactivate the legacy `anon` and
   `service_role` API keys together. Supabase documents that disabling legacy
   API keys disables both keys; do not do this while any consumer remains.
6. Verify client and backend traffic after deactivation. Remove old values from
   local secret stores and CI only after identifying all consumers; never copy
   the disclosed key into replacement configuration.

This change does not deactivate keys, update hosted Edge Function secrets,
deploy functions, change the JWT signing secret, or touch installed apps.
Current project access does not expose API-key management, hosted secret
editing, or webhook inventory. These remain explicit rollout gates.

## JWT signing-secret revocation

The API `service_role` key and the legacy JWT signing secret are different
credentials. Deactivating legacy API keys is not the same operation as revoking
the JWT signing secret. Follow Supabase's current signing-key migration flow:
migrate to asymmetric signing keys, rotate so newly issued access tokens use the
new signing key, then wait at least the configured maximum JWT lifetime plus
the documented clock-skew buffer (the Supabase example is 1 hour 15 minutes
for a 1-hour token) before revoking the legacy signing secret. Immediate
revocation can invalidate still-live legacy-signed sessions. Treat revocation
as an incident-response decision if an active compromise requires immediate
containment; otherwise coordinate it after session lifetime and deployment
checks.

## References

- [Migrate to the new Supabase API keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys)
- [Rotate leaked API keys](https://supabase.com/docs/guides/security/rotate-leaked-api-keys)
- [Supabase Auth signing keys](https://supabase.com/docs/guides/auth/signing-keys)
- [Edge Function authentication](https://supabase.com/docs/guides/functions/auth)
- [Edge Function secrets](https://supabase.com/docs/guides/functions/secrets)
