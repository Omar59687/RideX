import { SupabaseWebhookAdmission } from "./admission.ts";
import { SupabaseWebhookQuarantineStore } from "../_shared/payments/stripe_webhook_quarantine.ts";
import { resolveDefaultApiKey } from "../_shared/api_keys.ts";
import { createStripeTestWebhookHandler } from "./core.ts";

const enabled = Deno.env.get("RIDEX_TEST_WEBHOOK_INTAKE_ENABLED") === "true";
const secret = Deno.env.get("STRIPE_TEST_WEBHOOK_SECRET") ?? "";
const account = Deno.env.get("STRIPE_TEST_WEBHOOK_ACCOUNT") ?? "";
const url = Deno.env.get("SUPABASE_URL") ?? "";
const serverKey = resolveDefaultApiKey(
  Deno.env.get("SUPABASE_SECRET_KEYS"),
  Deno.env.get("SUPABASE_SECRET_KEY"),
);
let handler: (request: Request) => Promise<Response> = () =>
  Promise.resolve(new Response(null, { status: 503, headers: { "cache-control": "no-store" } }));
try {
  if (enabled && secret && account && url && serverKey) {
    handler = createStripeTestWebhookHandler({
      enabled: true,
      secret,
      account,
      now: () => Math.floor(Date.now() / 1000),
      store: new SupabaseWebhookQuarantineStore(url, serverKey),
      admission: new SupabaseWebhookAdmission(url, serverKey),
    });
  }
} catch { /* Fail closed on missing or invalid server configuration. */ }
Deno.serve(handler);
