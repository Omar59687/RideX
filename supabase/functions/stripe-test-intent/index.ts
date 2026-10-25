import {
  authorizeStripeTestRider,
  createCanonicalIntentContextReader,
  createStripeTestIntentHandler,
} from "../_shared/payments/stripe_test_intent_handler.ts";
import {
  TestIntentError,
  type TestIntentProvider,
} from "../_shared/payments/test_intent_provider.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// R06 remains intentionally closed in production until an owner approves the
// JOD Test Mode account and a durable attempt claim/unknown-outcome contract.
// No Stripe credentials are read and no provider request can be dispatched here.
const disabledProvider: TestIntentProvider = {
  prepare: () => {
    throw new TestIntentError("not_configured");
  },
};

Deno.serve(createStripeTestIntentHandler({
  authorize: (request) =>
    authorizeStripeTestRider(request, {
      supabaseUrl,
      anonKey,
      serviceRoleKey,
    }),
  readAuthorizedContext: createCanonicalIntentContextReader({
    supabaseUrl,
    anonKey,
    serviceRoleKey,
  }),
  provider: disabledProvider,
  providerDispatchEnabled: false,
}));
