import { authorizeCaller, createBackendQuoteCaller, createFareHandler } from "./core.ts";
import { resolveDefaultApiKey } from "../_shared/api_keys.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const publishableKey = resolveDefaultApiKey(
  Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"),
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY"),
);
const secretKey = resolveDefaultApiKey(
  Deno.env.get("SUPABASE_SECRET_KEYS"),
  Deno.env.get("SUPABASE_SECRET_KEY"),
);
const googleRoutesApiKey = Deno.env.get("GOOGLE_ROUTES_API_KEY") ?? "";

Deno.serve(createFareHandler({
  authorize: (request) =>
    authorizeCaller(request, {
      supabaseUrl,
      publishableKey,
    }),
  calculateFare: createBackendQuoteCaller({
    supabaseUrl,
    secretKey,
    googleRoutesApiKey,
  }),
}));
