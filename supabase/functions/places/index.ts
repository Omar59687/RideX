import { authorizeCaller, createPlacesHandler } from "./core.ts";
import { resolveDefaultApiKey } from "../_shared/api_keys.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const publishableKey = resolveDefaultApiKey(
  Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"),
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY"),
);
const googlePlacesApiKey = Deno.env.get("GOOGLE_PLACES_API_KEY") ?? "";
const googleRoutesApiKey = Deno.env.get("GOOGLE_ROUTES_API_KEY") ?? "";

Deno.serve(createPlacesHandler({
  apiKey: googlePlacesApiKey,
  googleRoutesApiKey,
  authorize: (request) =>
    authorizeCaller(request, {
      supabaseUrl,
      publishableKey,
    }),
}));
