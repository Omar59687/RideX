# P6-04 executable Test Mode preparation interface

This slice implements the owner-authorized interface/fake boundary from Issue #38.
It supersedes the design-only restriction only for unconfirmed intent preparation.
It is a server-only shared module, with no deployed handler or Flutter dependency.

The service accepts an existing payment identity, expected Payment version and
original operation key. A mandatory trusted server reader supplies the canonical
matched/accepted Card Trip, assigned Driver, pending payment and exact JOD fils.
Missing/foreign identity, changed keys, stale versions and invalid lifecycle states
fail before provider dispatch. The reader is an explicit injection boundary, not
an implemented public authentication or financial authorization endpoint.

The Stripe adapter accepts only server-injected Test Mode secret/restricted keys
and explicit JOD account approval. It sends one fixed-endpoint request with manual
capture, manual confirmation and confirm=false. It never attaches a payment method,
authorizes, captures, refunds, verifies a webhook, writes a payment row, or returns
a client secret. Only a matching unconfirmed, zero-received, zero-capturable,
non-live response is accepted. The result always requires canonical verification.
Errors are closed codes; timeouts remain unknown and are never automatically retried.
The original provider idempotency key is retained unchanged.

JOD fils are not converted or rounded. Nonmultiples of ten fils are conservatively
rejected pending account-specific currency verification. Stripe's account/currency
support must be independently confirmed before supplying the explicit approval.

Validation: `node --test supabase/functions/_shared/payments/test_intent_provider_test.ts`
passes 32 tests, using injected HTTP responses only. Production modules also pass
strict TypeScript checking. No network request to Stripe was executed.

External blockers: no Stripe Test Mode secret/account currency approval is configured
in this environment, and no trusted canonical attempt/actor composition is deployed.
Therefore real Test Mode preparation is NOT VERIFIED. P8 authorization, capture,
webhooks, refunds and hosted card entry remain separate, unimplemented execution scope.

Primary references checked 2026-10-24:
- https://docs.stripe.com/api/payment_intents/create (confirm=false; manual modes)
- https://docs.stripe.com/keys (server-only Test Mode key prefixes)
- https://docs.stripe.com/api/idempotent_requests (stable operation key)
- https://support.stripe.com/questions/which-payments-methods-and-products-are-available-in-the-uae
  (JOD three-decimal account support; this is not approval of Jordan production Stripe)
